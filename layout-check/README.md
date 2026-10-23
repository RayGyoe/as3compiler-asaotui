# layout-check —— 纯 AS3 布局子集的验收 harness

把 `asaot.ui.as3.As3LayoutEngine`（纯 AS3 flexbox 子集）**用我们自己的 AOT 编译器**编成原生
可执行文件，逐项对照 `u1-prototype/check-layout.md` §3 的**手算**用例 a~e（加上 f/g 默认值两例，共 16 项）
以及本阶段新增的 **P1~P8 扩展用例**（h~q 组，共 85 项），再加**样式面字段对照**（r~aa 组，共 32 项，
把 `kit/asaot/ui/style/Style.as` 新增的 `justifyContent/alignItems/alignSelf/alignContent/flexWrap/
margin/inset/position/overflow/display/aspectRatio` 各自映射到的 seam setter 各钉一个手算用例；
纯 AS3 子集不实现的 `baseline`/`static`/`display`/`aspect-ratio`/`auto margin` 用 `chkThrows` 钉为**大声报错**）。
`EPS = 0.01`。合计 **133 项**。

存在的意义：布局接缝是纯 AS3 接口，native 实现（Yoga）与 AS3 实现必须**逐值一致**。这个 harness 是
AS3 实现这一侧的基准；两侧都钉在**同一份手算期望**上，差分测试才有共同锚点。

**期望值一律手算**（公式写在 `CheckMain.as` 每组上方），**绝不「跑一遍抄输出当期望」**：
一个从输出回抄的期望永远不可能红，等于没有断言。

## 怎么跑

```bash
cd as3compiler
node src/index.ts ../asaotui/layout-check/CheckMain.as \
  ../asaotui/seam/asaot/ui/LayoutConstants.as \
  ../asaotui/seam/asaot/ui/LayoutEngine.as \
  ../asaotui/seam/asaot/ui/as3/As3LayoutNode.as \
  ../asaotui/seam/asaot/ui/as3/As3LayoutEngine.as \
  --run --cc clang -I ./vendor/curl/include -L ./vendor/curl/lib/windows-x64 -l zlib
```

`exit 0` = 全过。任何一项不符 → 打印 `FAIL` 行、`throw`、**非零退出**，且**不打印** `RESULT: PASS`
（`trace('RESULT: PASS')` 在 `throw` 之后）。`run.stdout` / `run.stderr` 留档。

### 视觉半边：弹出真窗口 + 读回帧缓冲复核

```bash
node asaotui/layout-check/visual-check.cjs     # 建 → 弹窗 → 读帧缓冲 → 断言 → 关窗
```

一条命令做完：用**我们自己的 AOT**（窗口清单，Skia+SDL2）编出 `VisualDemo.exe`，detached 启动
（窗口是阻塞的，不能 await），等它把帧缓冲写成 `visual-demo.bmp`，再用 `verify-visual.cjs`
**把图读回来对着手算矩形断言**，最后关窗。`exit 0` = 全过。

**为什么视觉半边不是重复**：`CheckMain.as` 断言的是 `layoutGet` **返回**什么；
`verify-visual.cjs` 断言的是**真的画在了哪里**。一个「算对了但画错位置」的 bug
（paint 递归的坐标累加写错、DPI 缩放、被裁剪）能过前者、必被后者抓住。
这和「拿我们的输出对 `adl`」是同一种思路：**在用户能观察到的层面上断言，而不是在我们碰巧能控制的层面上**。

**读图刻意不做任何假设**：`visual-demo.bmp` 是窗口帧缓冲的 1:1 拷贝（**没有 DPI 缩放、没有窗口边框**，
与截图不同）；每个盒子都用**不透明 1px 描边**绘制，描边色按深度决定 ⇒ 「边框在哪」用
**整数颜色精确相等**回答，不涉及 alpha 混合、预乘或 gamma 假设。

首个实现里我自己写错了 3 处预期（gap=0 时相邻边共享 1 像素、gap>0 时左右边都在、
描边落在 `left+width`/`top+height` 而非 `-1`）——**引擎全对，是检查器错了**。
这三条是**从实测帧缓冲读出来的**，不是推的，已作为已知事实注释在 `verify-visual.cjs` 里。

## 当前状态（实测）

```
---- 133 checks, 0 failures ----       CheckMain.as（文本半边）
RESULT: PASS

12 checks, 0 failures                  verify-visual.cjs（视觉半边，读 visual-demo.bmp）
RESULT: every scanned border matches the hand-computed rectangle
        -- the engine both COMPUTED and DREW them in the right place
```

### 视觉半边钉住什么（`VisualDemo.as` 六块面板）

| 面板 | 画什么 | 读回来钉什么 |
|---|---|---|
| 1 | column + padding 16 + row-gap 10 | （视觉；数值由 b 组钉） |
| 2 | row + `flex-grow 1:2:3`（basis 0） | **宽 46/92/138，边在 352/398/490/628** |
| 3 | `justify-content` 四取值各一条 | center 744/788/832/876、between 672/716/788/832/904/948、evenly 708/752/788/832/868/912、flex-end 816/860/904/948 |
| 4 | `align-items` 四取值各一条 | **同一个盒子（高 30）在四种对齐下的上下边**：偏移 0 / +5 / +10 / +0 |
| 5 | row + `flex-wrap`（7 个 60×36） | 第 1 行 4 个、第 2 行 3 个，pitch 70 宽 60 |
| 6 | margin + `position:absolute` | （视觉；数值由 l/n 组钉） |

窗口尺寸也钉住（`960x660`）：帧缓冲若被缩放，页面底色就不会落在预期像素上。

| 组 | 钉住什么 |
|---|---|
| a | 单个显式尺寸节点 |
| b | column + `padding(all)=16` + `row-gap=10`；也钉住 **gap 只加在相邻项之间**（首尾不加） |
| c | row + `flexGrow 1:2:3` + `basis 0` |
| d | 百分比基准 = **父的 content box**（减父 padding **与 border**）；子件起点 = border + padding；**显式尺寸按 border-box** |
| e1 / e2 | `min`/`max` 在 flex 求解**之后**仍生效 |
| f / g | **config 的默认方向**：`use_web_defaults=1` → 未设方向的节点默认 **row**；`=0` → **column** |
| h | **P1** `justify-content` 六取值（flex-start/center/flex-end/space-between/space-around/space-evenly）；space-evenly 的 32.5 是手算的，不是取整出来的 |
| i | **P1** justify **与 gap 共同**参与分布（gap 被折进 between，不是额外叠加） |
| j | **P2** `align-items` 四取值 + `align-self`（含 `auto` 继承、显式高胜过 stretch） |
| k | **P4** `flex-wrap` + `align-content` 五取值 + **wrap-reverse 的事后镜像** + column wrap 换行点 |
| l | **P3** margin point/percent（竖向也按**宽度**解析）/ EDGE_H·V / START·END |
| m | **P5** `position:relative` + inset（right/bottom 为**负向**偏移） |
| n | **P5** `position:absolute` + inset（containing block = **padding box**；right/bottom、percent、无 inset 时随父 justify/align 居中） |
| o | **P6** 百分比 padding / 百分比 gap（主轴基准 = content 尺寸） |
| p | **P7** `row-reverse` / `column-reverse` / RTL / START·END 在 RTL 下映射到右/左 |
| q | **P8** `overflow:hidden` **不改变**任何矩形 |
| r | 样式面 `justifyContent` —— column 下 center / space-between 的手算 top |
| s | 样式面 `alignItems` —— column 下 center / flex-end 的手算 left；`baseline` 钉 `chkThrows` |
| t | 样式面 `alignSelf` —— center / flex-end / auto-width stretch；`baseline` 钉 `chkThrows` |
| u | 样式面 `alignContent` —— 无 gap 3 行 flex-start 的逐行 top |
| v | 样式面 `flexWrap:nowrap` —— 单行不换行、`flex 0 0 60` 溢出也保持 60 |
| w | 样式面 `margin` —— point all 6 / percent-left 10% / `auto` 钉 `chkThrows` |
| x | 样式面 `position`/`inset` —— relative left 15 / absolute left·top（containing block=padding box）；`static` 钉 `chkThrows` |
| y | 样式面 `overflow` —— hidden / scroll **不改变**任何矩形 |
| z | 样式面 `display` —— flex / none 在纯 AS3 子集**均** `chkThrows`（native-only） |
| aa | 样式面 `aspectRatio` —— ratio>0 在纯 AS3 子集 `chkThrows`（native-only） |

f/g 是**成对**钉的：a~e 全都显式设了方向，仅靠它们，默认方向写错也看不出来。
k 组还额外钉住 **column wrap 的换行点**（主轴 = 高）。

## 防假绿：走过的变异测试

| 变异 | 结果 |
|---|---|
| `b.child1` 期望 66 → 67 | `FAIL b.child1 got 66 want 67`、`1 failures`、**不打印 PASS**、exit 1 |
| `createNode` 的方向钉死为 column（抹掉 config 效果） | **f.child1 FAIL**（got `(0,40)` want `(50,0)`），g 仍 OK、`1 failures`、exit 1 |
| 新组变异：`h2.justifyCenter0` 期望 55 → 56 | `FAIL h2.justifyCenter0 got (55,…) want (56,…)`、`1 failures`、**不打印 PASS**、exit 1 |
| 引擎级变异：`As3LayoutEngine.as` 把 `space-evenly` 的 lead 篡改为 `space-around` 公式 | **4 项 FAIL**（`h6.justifySpaceEvenly0/2`、`i3.justifyGapEvenly0/2`）、`4 failures`、**不打印 PASS**、exit 1 |
| 引擎级变异（样式面新增组）：`As3LayoutEngine.as` 的 `justify center` lead 篡改为 `remainingMain/2 + 1` | **4 项 FAIL**（`h2.justifyCenter0/2`、`r1.justifyCenter0/1`）、`4 failures`、**不打印 PASS**、exit 1 ⇒ **r 组（column 的 centre）真的承重、且对引擎 bug 有牙**；还原后复跑 133/133 |

第二项证明 f/g **方向特异且真的承重**，不是碰巧绿；第三项证明**新增的 h~q 组也真的在断言**；
第四项证明**harness 对引擎自身的 bug 也有牙**（不只是对「写错的期望值」）。
四项都做完即还原，还原后复跑回 101/101。

| **视觉半边**：把 `visual-demo.bmp` 里 justify-center 那条色带的盒子整条**右移 5px**（其余不动） | **只有 `p3 strip 0` 一项 FAIL**（got `749,793,837,881`）、其余 11 项 PASS、`1 failures`、exit 1 ⇒ **只是画偏 5px 就能被逐像素抓住**，且定位精确到那一条 |

## 边界（本 harness **不**覆盖）

仍然 `throw` 的（缺口表见 `seam/README.md` §4，本段与该表**逐项一致**）：
`setDisplay`、`setAspectRatio`、`setMeasure`、`setMargin(..., UNIT_AUTO)`（auto margin）、
`setPositionType(STATIC)`、`ALIGN_BASELINE`（align-items/self）、`setAlignContent(ALIGN_START/END)`、
`setAlignContent(ALIGN_SPACE_EVENLY)`、`setJustifyContent(JUSTIFY_START/END)`，
以及 size/minmax/basis 的 `AUTO`/`MAX_CONTENT`/`FIT_CONTENT`/`STRETCH` 单位与 `setGap(..., UNIT_UNDEFINED)`。

**`overflow` 不在缺口里**：它只**存标志位**，裁剪属绘制层；q 组把「矩形与 `visible` 相同」钉住。
native 路径走 Yoga，不依赖这个子集。

## dogfooding 发现（用自家编译器编自己的库时会撞到的）

> **以下均已登记在 [`../compiler-gaps.md`](../compiler-gaps.md)**（该文件是这些缺口的唯一登记处；
> 按用户 2026-10-22 指示，**不直接改编译器代码、不改 `TODO.md`**）。

1. **`System.exit(...)` 不支持**。`System` 是 `emit.ts` 里的手写伪类，只认 `gc` / `output` /
   `pauseForGCIfCollectionImminent` / `setClipboard` / `disposeXML` / `useCodePage` 与内存常量，
   **没有 `exit`**；且落到通用路径后**报错文案误导**——`undefined variable 'System' in class Main`，
   而不是「System 无 exit 成员」。**已用真 AIR（51.4.1）判清**：AIR **有** `System.exit(code:uint):void`
   ⇒ 这是**遗留欠账**（AIR 有我们无），登记为 **G1**。
   **但注意（用户 2026-10-22 纠正）**：惯用退出路径不是 `System.exit`，而是
   `import flash.desktop.NativeApplication; NativeApplication.nativeApplication.exit();` ——
   这条**我们已支持且实测跑通**（AOT `EXIT=0`），所以 G1 **不影响程序能否正常退出**。
   取证：[`../reviews/probe-exit-paths-2026-10-22.md`](../reviews/probe-exit-paths-2026-10-22.md)。
2. **`-w` 无法透传给 C 编译器**：`unknown argument: -w`。生成的 C 会带来 clang 的 deprecated 噪音，
   且没有标准开关能压掉（纯噪音，不影响正确性）。登记为 **G4**。
3. 其余所用写法**全部原生支持、无需绕路**：接口 `implements` + 经接口变量分派、`Boolean(obj.prop)`
   动态属性读、`Math.*`、`isNaN`、`toFixed`、数组字面量 / `push` / 下标、`switch`、`for`/`while`、
   `?:`、`&&` 值语义、字符串 + 数字拼接、`as` 转换、顶层脚本、多文件编译。（正面清单见
   [`../compiler-gaps.md`](../compiler-gaps.md) §3。）
