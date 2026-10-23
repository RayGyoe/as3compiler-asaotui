# 探针：原生窗口的**确定性像素取证**（2026-10-22）

## 问题

`air-check/README.md` 记了一条硬约束：Windows 上 `adl.exe` 没有控制台，AIR 侧的证据**必须写文件**。
那么反过来问：**我们自己的 AOT 原生窗口程序，能不能也把「屏幕上应该出现的像素」写成文件？**

能写，就能把「弹窗截图确认」从**肉眼判断**升级成**两台工具链逐像素 diff**。这是本探针要回答的唯一问题。

## 结论

**能，而且逐像素精确。** 完整链路：
`new Stage()` → `addChild(Shape)` → `stage.showWindow()`（阻塞在真实事件循环）→
`setTimeout` 回调里 `BitmapData.draw(stage)` → `getPixels()` → 手写 32-bit BMP → `FileStream.writeBytes` → 退出。

一次跑通的实测输出：

```
pixdump: opening window
pixdump: wrote .../temp/pixdump/dump.bmp (200x120, 96054 bytes)
pixdump: done, exiting
pixdump: window closed
EXIT=0
```

落盘 BMP 的采样（`probe-output.bmp`，用 Node 直接解 32-bit BMP 读回）：

| 采样点 | 期望（源码里画的） | 实测读回 |
|---|---|---|
| `(5,5)` 背景 | `0x203040` | `#203040ff` ✅ |
| `(20,20)` 红块 | `#FF0000` | `#ff0000ff` ✅ |
| `(110,70)` 绿块 | `#00FF00` | `#00ff00ff` ✅ |
| `(90,20)` 两块的缝 | 背景色 | `#203040ff` ✅ |

⇒ 光栅化 → 读回 → 落盘这条链**没有偏移、没有通道错序、没有底色污染**。

## 几个关键事实（都是实测出来的，写下来省下一次重复踩）

1. **`BitmapData.getPixels()` 是 ARGB、逐行自上而下**（`emit.ts` 的 `BitmapData_getPixels` 写
   `A,R,G,B` 四字节）。BMP 要的是**自下而上 BGRA**，所以落盘前必须**翻转行序 + 重排通道**。
   直接照抄会得到一张上下颠倒、红蓝互换的图 —— 而且它「看起来像那么回事」，最容易被当成通过。
2. **`stage.showWindow()` 会阻塞**，所以取证必须挂在 `setTimeout` 回调里（事件循环此时在跑），
   做完取证再 `NativeApplication.nativeApplication.exit()`。这与 `examples/window.as` 的结构一致。
3. **不需要窗口真的上屏即可取证**：`BitmapData.draw(stage)` 是**重新光栅化**显示列表，
   与窗口是否被遮挡、是否已经 present 无关。
4. **本机（Windows）原生窗口可编可跑**：`vendor/{skia,sdl2,curl}/lib/windows-x64` 齐备，
   `node src/index.ts <f>.as --manifest examples/window.build.example.json` 直接出 `.exe`。

## 对「截图确认」的意义

| 手段 | 强度 | 用途 |
|---|---|---|
| Computer Use 截图 | 中（受窗口位置/缩放/遮挡影响） | 给人看：**界面真的弹出来了** |
| **本探针的 BMP 落盘** | **强（逐像素确定）** | 给机器看：**布局算出来的矩形真的画在了这个位置** |

两者互补。**AOT 与 AIR 两侧都用同一条 BMP 落盘**，就能把「同一份 `.as` 源码、两条工具链」
的对照从**布局数字**（`GOT` 的 105 行）一路钉到**像素**。

---

## 追加实测：AOT 原生 × 真 AIR **逐字节相同**（同日）

同一段绘制序列（深蓝底 + 红块 `(10,10,60,40)` + 绿块 `(100,60,50,30)`，画布 200×120），两条工具链各自
落盘一张 32-bit BMP：

| 臂 | 工具链 | 落盘 |
|---|---|---|
| AOT | 我们的 AOT → C → clang → **native**（Skia + SDL2） | `as3compiler/temp/pixdump/dump.bmp` |
| **AIR** | **`mxmlc` → `adl`（AIR SDK 51.4.1）** | [`air-dump.bmp`](pixel-dump/air-dump.bmp) |

```
AOT bytes=96054   AIR bytes=96054
differing bytes = 0
*** THE TWO IMAGES ARE BYTE-IDENTICAL ***
```

⇒ **同一份绘制语义，我们的 AOT 与真 AIR 产出完全相同的像素。**

这条把「能不能在 AIR 上跑」从**数字层**（布局 `GOT` 105 行逐字符一致）**推进到像素层**，
也让「弹窗截图确认」有了机器可判的版本：不是「看着像」，而是 **0 个不同字节**。

### 探到的三个 AIR 专属差异（都不是缺陷，但会让 AIR 侧编不过）

1. **mxmlc 只接受 `package { }` 包裹的类形态**。一个只有顶层语句的 `.as`（我们的 AOT 接受）会报
   「**无法解析 SWF 的根类**」。⇒ AIR 侧驱动必须写成文件同名的类（`air-check/AirMain.as:33-36` 已记过）。
2. **`ByteArray` 必须显式 `import flash.utils.ByteArray`**：AIR 报「找不到类型或类型不是编译时常量: ByteArray」
   并连带「所调用的方法 ByteArray 可能未定义」；**我们的 AOT 不写 import 也能过**。⇒ 写跨端源码时显式 import 更安全。
3. **AIR 描述符里 `<content>` 指 SWF 文件名**（`pixeldump.swf`）最稳；给类名（`PixelDump`）时
   `adl` 直接 **exit 8**，且**不给任何解释**。

## 文件

| 文件 | 是什么 |
|---|---|
| [`probe.as`](pixel-dump/probe.as) | AOT 侧探针源码（同时留一份在 `as3compiler/temp/pixdump/Dump.as`，temp 是 gitignore 的草稿区） |
| [`probe-output.bmp`](pixel-dump/probe-output.bmp) | AOT 侧落盘产物（200x120 32bpp BMP） |
| [`air-dump.bmp`](pixel-dump/air-dump.bmp) | **AIR 侧落盘产物 —— 与上面那张 0 字节差异** |
| `../../air-check/PixelDump.as` | AIR 侧探针源码（`package{}` 类形态，Sprite 根） |
| `../../air-check/app-pixel.xml` | AIR 描述符（`node run-adl.cjs app-pixel.xml`） |
