# 探针：demo 底色消失事件 —— 四次假设、三次被自己否证，最后是**过期产物**

**日期**：2026-10-22
**性质**：**没有编译器缺陷可登记**（这条结论本身是实测得来的，不是推断）
**留下的资产**：`tools/pngread.cjs`（无依赖 PNG→RGBA，像素级读图）、`probes/kit-crash/asan.cjs`（ASan 取证法）、
`tools/clean-probes.cjs`；以及一条**新的流程陷阱**（过期产物会造**假红**，不只是假绿）。

---

## 0 为什么要写这份文档

这次调查里我错了三次，每一次都是**被我自己的测量推翻**的，而不是被我自己的推理推翻的。
把三次都写下来，是因为「如何证伪自己」比「最后结论是什么」更可复用——
而且它反过来证明了一条老规矩：**没有测量就没有结论**。

最终结论一句话：**`asaot.ui` 工具链的绘制链路完全正确；两个吓人的现象都出自过期/未重建的产物。**

---

## 1 事件一：`CheckUiDbg.exe` 段错误 —— 假红

### 现象
`ui-demo/CheckUiDbg.exe`（另一个 worker 为了加日志临时做的变体）实测：

```
status=3221225477  (0xC0000005, EXCEPTION_ACCESS_VIOLATION)   elapsed 39 ms
stdout = 0 bytes      stderr = 0 bytes      落在盘上的日志只有一行 "START"
```

进程**瞬间**以访问违例死亡、且**一个字都没打印**——这是 codegen 级故障的样子，值得钉最小复现。

### 我先做了什么（次序很重要）
不是读代码猜，而是**二分**：
1. `probes/kit-crash/Step.as` —— 走完工具链整条管线（`new View` → `new Stage` → `new UiApp` →
   `mount`（含 describe→reconcile→measure→solve→arrange→paint）→ `attachRoot` → `findByKey` → 稳态 reflow），
   **9 步全过、布局 `a=0,0,100,40` 正确、`status=0`**。工具链无罪。
2. `probes/kit-crash/StaticInit{,2}.as` —— 逐级复刻 `CheckView` 的 `static const = 另一类的静态工厂`、
   五个 const 一起、字符串+数字+数组混排字面量，**全部 `status=0`**。
3. `probes/compiler-crash/StmtBeforeClass.as` —— 复刻「类声明之前先执行顶层语句」这个唯一的结构差异，
   **`status=0`**。

### 真正的定位方式
改用 **AddressSanitizer**：`probes/kit-crash/asan.cjs` 让 AOT 先产出 `.c`，再用我们自己的 clang
把**同一份 `.c`** 加 `-fsanitize=address` 重编一遍再跑。结果：

```
CHECKUI: 23 checks, 0 failures
RESULT: PASS                                    status=0
```

**同一份 `.c`，ASan 下全绿。** 于是做严格 A/B：把 AOT 刚产出的 `.c` 分别用 `-O0/-O1/-O2/-Os` 编：

| 优化档 | 结果 |
|---|---|
| `-O0` / `-O1` / `-O2` / `-Os` | 全部 `status=0`，25 行输出 |

⇒ **不是编译器崩溃，也不是优化档问题**；那个崩掉的 `.exe` 是**没被重建的旧产物**。
直接跑正式交付物：`ui-demo/CheckUi.exe` → `status=0`、25 行、末行 `RESULT: PASS`；
`node ui-demo/run-check.cjs` → **`EXIT 0`**。

**事件一结案：`CheckUi` 24 项断言（23 检查 + 汇总）全绿，由我独立复跑确认。**

### 顺带记录：取证工具箱
- 崩溃时**磁盘文件是活的**（每行 open/write/close），**stdout 不是**——所以探针要把步进日志写文件，
  不能只 `trace()`。`Step.as` 就是这么写的，一行一个语句，最后一行即崩溃点。
- Windows 的崩溃码要按 `0x%08X` 看：`3221225477 = 0xC0000005`（访问违例）、
  `3221225781 = 0xC0000135`（DLL 缺失，我第一次跑 ASan 就撞上——ASan 运行时不随 `clang.exe` 放，
  在 `lib/clang/<major>/lib/windows/`，要显式加进 `PATH`）。
- **`--opt` 只接受单个旗标**：`--opt "-O1 -fsanitize=address"` 会被 clang 当成一个畸形参数；
  命令行直接给 `-g` 则报 `unknown argument: -g`。所以注入 ASan 只能「自己重编 AOT 留下的 `.c`」。

---

## 2 事件二：demo 的卡片与按钮「没有底色」—— 假红

### 现象（用像素量出来的，不是看出来的）
我先给这件事造了一个工具：`tools/pngread.cjs`（零依赖，`zlib` 解 PNG，输出 RGBA）。
把 UI 截图当**测量对象**，并加了一个 `runs` 模式：把某一行/列压成**颜色游程**，
这样图片与布局坐标是否 1:1 **不必假设**，直接从图里读几何。

对 `ui-demo/UiDemo-shot-3.png`（当时最新）测：

```
col x=280:  y 92 = #e5e7eb (卡片边框)  y 93..110 = #ffffff   <- 卡片内部应是 #f9fafb
row y=284:  x 47 = #1d4ed8 (按钮边框)  x 48..512 = #ffffff   <- 按钮内部应是 #2563eb
```

边框在、底色不在。**注意：肉眼当时「看到」卡片是浅灰的——是错觉，像素说它是纯白。**
这就是「读图不做假设」的现场价值。

### 假设一（错）：「`lineStyle` 在 `beginFill` 之后会丢掉填充」
依据是同一文件里两类画法的差异：能画出蓝块的 `UiNode.paintCheckbox` 是
`lineStyle → beginFill`，而没画出底色的 `UiNode.drawBox` 是 `beginFill → lineStyle`。

**实测否证** —— `probes/graphics-order/Order.as`（一个窗口、两个只差调用顺序的方块，落盘 BMP 逐像素读回）：
两个方块**中心都是 `#2563eb`**，两次顺序都保住了填充。

### 假设二（错）：「是 `drawRoundRect`（`cornerRadii`）」
依据是 demo 两个坏块都带圆角、我的对照组用的是 `drawRect`。

**实测否证** —— `probes/graphics-order/Order2.as` 把两个变量叉积成四块（`drawRect`/`drawRoundRect` ×
`beginFill` 先/后），落盘 BMP 读回：

```
A rect      fill-first:  centre=#2563eb  left=#1d4ed8
B roundRect fill-first:  centre=#2563eb  left=#1d4ed8
C rect      line-first:  centre=#2563eb  left=#1d4ed8
D roundRect line-first:  centre=#2563eb  left=#1d4ed8
```

**四种组合全对。Graphics 无罪。**

### 假设三（错）：「`Fill.alpha()` 把 24 位色号当 ARGB，alpha 取到 0」
依据很有说服力：`Fill.alpha()` 读的是 `0xAARRGGBB` 的最高字节，所以 `background: 0xF9FAFB`
的 alpha 会是 0；而**唯一画得出底色的地方**（复选框）是 `beginFill(0x2F80ED, 1.0)`，**硬编码 1.0**
绕过了 `alpha()`；页面 `0xFFFFFFFF` 的 alpha 正好 255 ⇒ 白页看不出问题。三条现象全部吻合。

**实测否证** —— `probes/silent-null/AlphaValue.as` 逐级打印 `.argb / .rgb() / .alpha()`：

```
Fill.solid(0xF9FAFB).argb  = 0xfff9fafb  rgb 0xf9fafb  alpha 1
CARD.background            = 0xfff9fafb  rgb 0xf9fafb  alpha 1
SIGNIN.background          = 0xff2563eb  rgb 0x2563eb  alpha 1
```

`argb` 在进 `Fill` 时就被补成不透明（`0x00RRGGBB → 0xFFRRGGBB`），alpha 恒为 1。假设不成立。

### 假设四：不再是假设，而是**造复现**
`probes/kit-fill/Cards2.as` —— 用**真工具链**（`View` → `UiApp` → `Reconciler` → `UiNode`）画六张只差样式的卡，
其中 `c5`/`c6` 是 demo 的 `CARD`/`SIGNIN` 字面量**逐字复制**（含 `Length.pct`），落盘 BMP 后在
**引擎自报的矩形**上采样：

```
c1 centre=#f9fafb border=#e5e7eb      c5 centre=#f9fafb border=#e5e7eb
c2 centre=#2563eb border=#1d4ed8      c6 centre=#2563eb border=#1d4ed8
```

**六张全对。**

于是只剩最后一个变量：**demo 自己的装配 / 那张截图本身是不是新的**。

### 结论
重新测量当时的**最新**截图 `ui-demo/UiDemo-shot.png`（比 `shot-3` 晚 3 分钟）：

```
col x=280:  y 92 = #e5e7eb   y 93..110 = #f9fafb   <-- 卡片底色回来了
            y 261 = #1d4ed8  y 262..306 = #2563eb  y 307 = #1d4ed8
row y=284:  x 47 = #1d4ed8   x 48..258 = #2563eb
            x 259..305 = 白/蓝抗锯齿混色 —— 这就是 "Sign in" 的字形
```

**底色在，按钮文字也在。** `UiDemo-rects.txt` 现在还会自报 `bg=`/`border=`：

```
box key=card   (28,92,504,234)   bg=f9fafb  border=e5e7eb
button key=signin (47,261,466,46) bg=2563eb border=1d4ed8
```

⇒ **`shot-3` 是过期截图**（拍在一次重建之前）。事件二与事件一**同源**：都是拿旧产物当现状。

---

## 3 这条流程陷阱值得单独记一笔

我们以前记的是「**过期文件造成假绿**」（漏传 `AIRSDK_HOME` 用到过期 SWF）。这次遇到的是镜子那一面：

> **过期产物同样造成假红。** 你会花时间去修一个**已经不存在**的缺陷，而且它的表现
> （段错误 / 少了一半绘制）**看起来像编译器缺陷**，比假绿更耗时间。

可复用的做法，只有两条，都很便宜：
1. **先重建，再测**：拿到现象的第一件事是把产物从源码重新生成一遍（`run-check.cjs`、
   `visual-check.cjs` 这类「一条命令闭环」的脚本就是干这个的，它们的价值在这里第二次体现）。
2. **把变量钉到只剩一个**：当产物可疑时，不要改源码，而是把**同一份 `.c`** 用不同旗标/不同入口重跑
   （本次是 `-O0/-O1/-O2/-Os` 与 ASan）。同一份输入两种表现 ⇒ 问题在构建；同一种表现 ⇒ 问题在源码。

---

## 4 本次新增的可复用资产

| 资产 | 用途 |
|---|---|
| [`tools/pngread.cjs`](../tools/pngread.cjs) | 零依赖 PNG→RGBA；`info` / `top`（区域颜色直方图）/ `scan` / `runs`（**行/列颜色游程**，用来从图里读几何而不假设 1:1）。**截图从此可当测量对象**，不必再靠肉眼 |
| [`probes/kit-crash/asan.cjs`](../probes/kit-crash/asan.cjs) | ASan 取证：AOT 出 `.c` → 自己重编加 `-fsanitize=address` → 跑。自动找 LLVM 的 ASan 运行时目录加进 `PATH` |
| [`tools/clean-probes.cjs`](../tools/clean-probes.cjs) | 清 `probes/` 下的 `.c/.exe/.pdb`（本次 32 个、106.8 MB），保留源码与测量证据（`.bmp`/`.rects.txt`/`.log`） |
| [`probes/graphics-order/`](../probes/graphics-order/) | Graphics 调用顺序 × 形状的四格叉积（`Order.as` 否证「顺序」，`Order2.as` 否证「圆角」） |
| [`probes/silent-null/`](../probes/silent-null/) | 样式取值链（`FillFromAny.as` / `AlphaValue.as`）——**否定**「alpha=0」那个假设的证据就在这里 |
| [`probes/kit-fill/`](../probes/kit-fill/) | 六卡样式叉积 + `DemoRepro.as`（拉别人的 `DemoView` 跑自己的落盘管线） |
| [`probes/kit-crash/`](../probes/kit-crash/) | 步进探针（`Step.as`/`StaticInit{,2}.as`）——工具链与静态初始化的无罪证据 |

---

## 5 与编译器仓库的边界

全程 `as3compiler/` **零改动**，已用开工指纹复核（11 个脏文件逐字节相同，HEAD 仍 `92a1239`）。
本事件**没有**产生新的编译器缺口，因此 [`compiler-gaps.md`](../compiler-gaps.md) 的 G7/G8 是本次
真正的编译器侧产出（另见 [`probe-asmdef-and-name-collision-2026-10-22.md`](probe-asmdef-and-name-collision-2026-10-22.md)）。