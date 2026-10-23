# U1 布局接缝原型 — 验收记录（`asaotui/u1-prototype/`）

> **状态：验收通过。** `yoga_glue` 接缝可编、可链、可真跑；六个用例（外加 NULL 容错）全绿，
> native（clang++ / lld-link）与 wasm（em++ 3.1.44，node 运行）**结果逐项一致**。
> 本文件记录**实际值 vs 手算期望**、**原始运行输出**、以及开发中踩到、且**只能靠实测定口径**的坑。
> 凡本机测不了的项一律写「未测」；所有数字都是本机实测，不是估算。

---

## 0. 一句话结论

同一棵 flex 树在 Yoga 下算出的矩形与手算期望**逐项相等**（17 项断言 0 失败，容差 `EPS = 0.01`）。
百分比基准口径**实测 = 父的 content box**（padding 与 border 都不计入），与 CSS/flexbox 标准一致。
接缝最终 **30 个函数**（草案 24 行 / 28 个函数，+2：`overflow`、`box_sizing`）。

---

## 1. 环境与口径

| 项 | 值 |
|---|---|
| 宿主 / 工具链 | Windows；clang 23.1.3（`x86_64-pc-windows-msvc`，lld-link）；emcc/em++ 3.1.44；node v24.15.0 |
| Yoga 源 | `asaotui/measurements/yoga-src`，commit `843dba8619420992e492bbb4b3d2f63d9ad6c683`（复用 U1 前置测量，未重新 clone） |
| 布局配置 | `point_scale = 0`（关像素对齐，取原始 float）、`use_web_defaults = 1`（flex-direction=row / align-content=stretch / flex-shrink=1 / flex-basis 正 flex 时为 auto，对齐 CSS 与 GPUI `style.rs` 的 `Default for Style`） |
| 容差 | `EPS = 0.01f`。理由：本用例里最小可分辨差是 1.0，而 float 累计误差在 1e-5 量级；0.01 既远低于有意义差异，又远高于浮点舍入。**不允许为了通过而放宽 EPS。** |

**产物与命令入口**

- 交付物：`yoga_glue.h`（不透明头）、`yoga_glue.cc`（唯一 include `<yoga/Yoga.h>` 的 TU）、`test_layout.c`（纯 C 验收测）、`build.sh`、本文件。
- 一键：`cd asaotui/u1-prototype && bash build.sh`（native）/ `bash build.sh --wasm`（emscripten）。
- 原始日志：`native.log`、`wasm.log`；临时探针 `probes/{probe,raw,mixed}.c`（见 §5）。

---

## 2. 接缝函数清单（实际 30 个 vs 草案）

草案见 `asaotui/measurements/u1-yoga-precheck.md` §6.3（24 行）。实际函数集：

| 组 | 函数 | 对应 Yoga API | 承载 `Style` 字段（api-design §2.1） |
|---|---|---|---|
| Config(2) | `config_new(point_scale, use_web_defaults)` / `config_free` | `YGConfigNew/Free`, `YGConfigSetUseWebDefaults/PointScaleFactor` | —（**签名相对草案 +1 参数** `use_web_defaults`） |
| Node(5) | `node_new` / `node_free` / `node_free_recursive` / `node_insert` / `node_remove` | `YGNodeNewWithConfig` / `YGNodeFree` / `YGNodeFreeRecursive` / `YGNodeInsertChild` / `YGNodeRemoveChild` | — |
| Style(19) | `set_flex_direction` | `YGNodeStyleSetFlexDirection` | `flexDirection` |
| | `set_flex_wrap` | `…SetFlexWrap` | `flexWrap` |
| | `set_justify` | `…SetJustifyContent` | `justifyContent` |
| | `set_align_items` | `…SetAlignItems` | `alignItems` |
| | `set_align_self` | `…SetAlignSelf` | `alignSelf` |
| | `set_align_content` | `…SetAlignContent` | `alignContent` |
| | `set_flex(grow, shrink, basis, basis_unit)` | `…SetFlexGrow/Shrink/FlexBasis{,Percent,Auto,…}` | `flexGrow`/`flexShrink`/`flexBasis` |
| | `set_size(axis, value, unit)` | `…SetWidth{,Percent,Auto,…}` / `…Height…` | `size` |
| | `set_minmax(axis, is_max, value, unit)` | `…SetMin{,Percent,…}` / `Max…` | `minSize`/`maxSize` |
| | `set_margin(edge, value, unit)` | `…SetMargin{,Percent,Auto}` | `margin` |
| | `set_padding(edge, value, unit)` | `…SetPadding{,Percent}` | `padding` |
| | `set_border(edge, value)` | `…SetBorder` | `borderWidths` |
| | `set_gap(gutter, value, unit)` | `…SetGap{,Percent}` | `gap` |
| | `set_position(edge, value, unit)` | `…SetPosition{,Percent,Auto}` | `inset` |
| | `set_position_type` | `…SetPositionType` | `position` |
| | `set_display` | `…SetDisplay` | `display` |
| | `set_overflow` | `…SetOverflow` | `overflowX`/`overflowY`（Yoga 只留一个值） |
| | `set_aspect_ratio` | `…SetAspectRatio` | `aspectRatio` |
| | `set_box_sizing` | `…SetBoxSizing` | （设计未列，见下） |
| Measure(1) | `set_measure(fn, ctx)` | `YGNodeSetMeasureFunc` + `YGNodeSet/GetContext` | 内在尺寸（文本/图片） |
| Compute/Query(3) | `calculate(...)` / `set_dirty` / `layout_get(out[4])` | `YGNodeCalculateLayout` / `YGNodeMarkDirty` / `YGNodeLayoutGet{Left,Top,Width,Height}` | — |

**与草案的差异及原因**：

1. **+2 个函数**（28→30）：`set_overflow` 与 `set_box_sizing`。
   - `overflow`：`Style.overflowX/overflowY` 是真实字段，影响裁剪/命中，暴露成本极低。
   - `box_sizing`：**Yoga 默认 `border-box`，与 CSS 默认 `content-box` 相反**（源码 `style/Style.h:935`）。
     这是个「引擎默认 vs 标准默认」的分叉，必须能**显式选**，不能靠继承一个引擎巧合。
2. **measure 回调签名改了**（草案 §6.3 #21 写成 `float (*fn)(ctx,aw,awm,ah,ahm)`）：
   回调要返回**宽和高两个数**，单个 `float` 返回值表达不了。改成
   `void (*fn)(void* ctx, float aw, int wm, float ah, int hm, float out_wh[2])`——
   用出参数组，接缝仍只有纯 C 标量，不引入任何共享结构体类型。
3. **`config_new` 多一个 `use_web_defaults`**：草案说「web defaults 内部固定」，但
   `Style.flexDirection` 的默认值是 `row`（GPUI `style.rs:799`），需要 web defaults 才对得上；
   做成显式参数而不是隐式固定，便于对照实验。
4. 其余：`position`/`display`/`aspect_ratio` 在草案里是合并行，这里各占一个函数（数目不变，只是行数计数不同）。

---

## 3. 六个用例：实际值 vs 手算期望

统一 `EPS = 0.01`，`point_scale = 0`。**矩形 = (left, top, width, height)**。

### a) 单节点固定宽高 — `root: width=100, height=50`

| 节点 | 实际 | 期望 | 手算公式 |
|---|---|---|---|
| root | (0, 0, 100, 50) | (0, 0, 100, 50) | 叶子显式宽高，放在父原点，尺寸即所设 ✅ |

### b) column + padding(16) + row-gap(10) — `root 200×300, 3 子 100×40`

| 节点 | 实际 | 期望 | 手算公式（主=竖轴） |
|---|---|---|---|
| root | (0, 0, 200, 300) | (0, 0, 200, 300) | 显式尺寸，内容高 40*3+2*10+2*16=172 < 300，无溢出 ✅ |
| child0 | (16, 16, 100, 40) | (16, 16, 100, 40) | left=padding.left=16；top=padding.top=16 ✅ |
| child1 | (16, 66, 100, 40) | (16, 66, 100, 40) | top=16+(40+gap10)=66 ✅ |
| child2 | (16, 116, 100, 40) | (16, 116, 100, 40) | top=16+2*(40+10)=116 ✅ |

**口径**：gap **只加在相邻项之间**（首尾不加），padding 在两端各加一次，二者叠加。row-gap 在 column 容器里就是竖向间隙（实测证实）。

### c) row + 三个 flexGrow 1:2:3，`flex-basis=0` — `root 300×100`

| 节点 | 实际 | 期望 | 手算公式 |
|---|---|---|---|
| child0 | (0, 0, 50, 100) | (0, 0, 50, 100) | free=300-0=300；grow 和=6；w=300*1/6 ✅ |
| child1 | (50, 0, 100, 100) | (50, 0, 100, 100) | w=300*2/6；x=前项累计=50 ✅ |
| child2 | (150, 0, 150, 100) | (150, 0, 150, 100) | w=300*3/6；x=50+100=150 ✅ |

**口径**：浮点按 grow 比例分剩余空间，宽度和恰为 300（无舍入残差）。

### d) 百分比宽高 vs 父 padding(20)+border(10) — `root width=200,height=100,padding=20,border=10`；`child width=50%,height=50%`

| 节点 | 实际 | 期望（CSS 标准） | 手算公式 |
|---|---|---|---|
| root | (0, 0, 200, 100) | (0, 0, 200, 100) | border-box：显式尺寸即 border box ✅ |
| child | **(30, 30, 70, 20)** | (30, 30, 70, 20) | **见下** ✅ |

**这是本原型唯一「口径只能靠实测定」的用例**，实测结论：

- **百分比基准 = 父的 content box**（padding 与 border 都扣除），**不是 border box**。
  - content 宽 = 200 − 2·padding(20) − 2·border(10) = **140** → child 宽 = 50%·140 = **70**。
  - content 高 = 100 − 2·20 − 2·10 = **40** → child 高 = 50%·40 = **20**。
  - child 位置 = border.left + padding.left = 10 + 20 = **30**（top 同理）。
- 反证：若基准是 border box → child 宽会是 **100**；若只扣 padding 不扣 border → **80**。
  实测 **70**，故两者都被扣除 = content box。**这与 CSS 标准一致**（CSS 2.1 §10.2 / Flexbox §4：
  子件 `width` 百分比相对 containing block 的 width，而 containing block 是父的 content box）。
- **附注（必须记住）**：Yoga 的 `box-sizing` 默认是 **border-box**（源码 `style/Style.h:935`），
  与 CSS 默认 **content-box 相反**。所以本用例里 `width=200` 指的是 border box。
  设计 §2.1 把 `box-sizing` 列在「暂不引入」，于是我们**继承了引擎默认**——为避免这个「引擎巧合」被当成标准，
  接缝特地暴露了 `set_box_sizing`（§2 差异 1）。

### e) min/max 宽对 flex 长度的压缩

| 子例 | 树 | 实际 | 期望 | 手算公式 |
|---|---|---|---|---|
| e1 min 赢过 shrink | root row 宽 100；child `flex-basis=200, shrink=1, min-width=150` | (0,0,**150**,50) | (0,0,150,50) | 单项从 200 收缩到 content 100，但 min-width 夹到 150（溢出 50）✅ |
| e2 max 赢过 grow | root row 宽 300；child `flex-basis=100, grow=1, max-width=150` | (0,0,**150**,50) | (0,0,150,50) | free=200，grow 想涨到 300，但 max-width 夹到 150 ✅ |

**口径**：min/max 在 flex 求解后仍对最终尺寸生效（min 与 shrink、max 与 grow 都如此）。

### f) measure 回调（内在尺寸）— 假文本 `宽 = 字符数×7，行高 = 16`

| 子例 | 树 | 节点 | 实际 | 期望 | 手算公式 |
|---|---|---|---|---|---|
| f1 一行 | root column 宽 100，10 字符(70) | root | (0,0,100,**16**) | (0,0,100,16) | 根高=auto=内容高 ✅ |
| | | text | (0,0,**70**,16) | (0,0,70,16) | measure(AtMost 100) → 宽 min(70,100)=70，行数 1 ✅ |
| f2 换行 | root column 宽 40，10 字符(70) | root | (0,0,40,**32**) | (0,0,40,32) | 根高=auto=内容高 ✅ |
| | | text | (0,0,**40**,32) | (0,0,40,32) | lines=ceil(70/40)=2 → 高 2×16=32，宽 min(70,40)=40 ✅ |

**口径 + 坑**：`calculate` 的 available 是**根在无显式尺寸那一轴上被拉伸到的尺寸**。
传 `(1000,1000)` 会把 auto 高的根撑成 1000，**不会**变成内容高；要观察内在尺寸必须传**未定义(NaN)**。
本用例因此传 `(NAN, NAN)`（见 §5 坑 ②）。

### g)（附加）NULL 句柄容错

| 调用 | 实际 | 期望 |
|---|---|---|
| `layout_get(NULL, r)` | (0,0,0,0) | 全 0 ✅ |
| 其余 (config_free/free/free_recursive/insert/remove/各 setter/set_measure/calculate/set_dirty)(NULL,…) | 不崩，走完全程 | 不崩 ✅ |

**理由**：AS3 侧对象生命周期不由 C 保证，接缝每个函数都容忍 `NULL` 句柄，返回安全默认值而非解引用。

---

## 4. 原始运行输出

### native（`bash build.sh`，节选——完整见 `native.log`）

```
== [4/4] link (C++ driver pulls libcpmt; /OPT:REF = COFF dead-strip) ==
+ clang++ -O2 .../test_layout.o .../yoga_glue.o .../libyoga.a -Wl,/OPT:REF -Wl,/OPT:ICF -o .../test_layout.exe
   -> 280064 bytes : .../build/native/test_layout.exe

== run ==
U1 layout seam acceptance -- yoga_glue vs hand-computed rectangles
tolerance EPS = 0.010, point_scale = 0 (no pixel snapping), web defaults

=== a) single node, fixed width=100 height=50 ===
  root       got (l=   0.000 t=   0.000 w= 100.000 h=  50.000)  want (... same ...)  OK
=== b) column + padding(16) + row-gap(10), 3 children 100x40 ===
  root       got (l=   0.000 t=   0.000 w= 200.000 h= 300.000)  want (... same ...)  OK
  child0     got (l=  16.000 t=  16.000 w= 100.000 h=  40.000)  want (... same ...)  OK
  child1     got (l=  16.000 t=  66.000 w= 100.000 h=  40.000)  want (... same ...)  OK
  child2     got (l=  16.000 t= 116.000 w= 100.000 h=  40.000)  want (... same ...)  OK
=== c) row + grow 1:2:3, basis 0, root 300x100 ===
  child0     got (l=   0.000 t=   0.000 w=  50.000 h= 100.000)  want (... same ...)  OK
  child1     got (l=  50.000 t=   0.000 w= 100.000 h= 100.000)  want (... same ...)  OK
  child2     got (l= 150.000 t=   0.000 w= 150.000 h= 100.000)  want (... same ...)  OK
=== d) percent width/height vs parent padding(20)+border(10) ===
  root       got (l=   0.000 t=   0.000 w= 200.000 h= 100.000)  want (... same ...)  OK
  child      got (l=  30.000 t=  30.000 w=  70.000 h=  20.000)  want (... same ...)  OK
=== e) min/max width clamp flex-basis (e1 min, e2 max) ===
  e1 child   got (l=   0.000 t=   0.000 w= 150.000 h=  50.000)  want (... same ...)  OK
  e2 child   got (l=   0.000 t=   0.000 w= 150.000 h=  50.000)  want (... same ...)  OK
=== f) measure callback: text wrap height (7pt/char, 16pt/line) ===
  f1 root    got (l=   0.000 t=   0.000 w= 100.000 h=  16.000)  want (... same ...)  OK
  f1 text    got (l=   0.000 t=   0.000 w=  70.000 h=  16.000)  want (... same ...)  OK
  f2 root    got (l=   0.000 t=   0.000 w=  40.000 h=  32.000)  want (... same ...)  OK
  f2 text    got (l=   0.000 t=   0.000 w=  40.000 h=  32.000)  want (... same ...)  OK
=== g) NULL-handle tolerance (must not crash) ===
  layout_get(NULL) -> (0.0,0.0,0.0,0.0)  want zeros  OK
  survived all NULL calls  OK

---- 17 checks, 0 failures ----
RESULT: PASS
(exit code 0)
```

（上面每处 `want (... same ...)` 均为 `want` 与 `got` 逐值相同；原样文本见 `native.log`。）

### wasm（`bash build.sh --wasm`，node 运行）

19 个 Yoga `.cpp` 全部编过，**0 error**；`test_layout.wasm` **134,149 B** + `test_layout.js` **50,647 B**；
`node build/wasm/test_layout.js` **输出与 native 逐字节相同，17 checks 0 failures，exit 0**。
（共 126 条 `-Wignored-attributes` 警告，全部来自 emscripten 下 `YG_EXPORT` 的 `used` 属性，
与前置测量 §5.3 的发现一致，无害。）

| 产物 | 字节 |
|---|---|
| `build/native/libyoga.a` | 509,762 |
| `build/native/test_layout.exe` | 280,064 |
| `build/wasm/libyoga.a` | 234,470 |
| `build/wasm/test_layout.wasm` | 134,149 |
| `build/wasm/test_layout.js` | 50,647 |

---

## 5. 踩到的坑（尤其 d 用例那种「口径靠实测定」的）

**① case d 的百分比基准——只能实测定。** 设计文档从没写清「% 相对 content box 还是 border box」。
靠实测（70 vs 反证 100/80）定为 **content box**，与 CSS 标准一致。这里若不实测、凭直觉写「50%·200=100」，
就会做出一个「看着对」的错布局。**结论已写进 §3d。**

**② 根节点的拉伸语义（case f 第一次就红）。** `calculate(root, 1000, 1000, …)` 时，auto 高的根会被
**撑成 1000**（available 是根待填充的尺寸），不是内容高。第一版我期望根高 16/32 却得到 1000。
查证方式：给根传 `(NAN, NAN)` → 根高变为内容高 16/32。**这跟 Yoga 无关、是 flex「根=视口」的既有语义**，
但接缝必须让调用方知道：要内在尺寸就传未定义。已写进 test 注释与 §3f。

**③ 我自己的 glue 有 bug，被 case e 抓出（没有放宽断言）。** 第一版 `set_minmax` 与 `set_size`
共用一个 `isMax` 布尔，导致「min 宽」被写成了「普通 width」，min-width 静默失效（实测 child 宽 100 而非 150）。
用 `probes/raw.c`（纯 Yoga，得 150）与 `probes/mixed.c`（glue 建、Yoga 读回，`YGNodeStyleGetMinWidth=nan`）
双向定位后，把模式改成三态 `SLOT_SIZE/SLOT_MIN/SLOT_MAX` 修复。**先证「谁错了」再改代码**——这正是
「实测与手算不符是发现，不许放宽断言」的价值。

**④ 草案的 measure 签名表达不了返回两个维度。** 见 §2 差异 2。

**⑤ 每节点一次 malloc（measure 记录）。** Yoga 每节点只有一个 user-data 槽；我们的 measure 回调需要
同时拿到「回调函数」与「调用方的 ctx」，于是把两者放进一条小记录、存进该槽，并在 `node_free*` 里回收
（Yoga 自己不会释放我们的记录，递归释放前先自己遍历子件）。这是**结构性时刻**的一次分配，不是每帧分配，
不违反设计 §7。风险见 §7。

---

## 6. 未测项（如实登记，不估算）

| 项 | 为什么没测 |
|---|---|
| macOS arm64 上原地编/链/跑 | 本机是 Windows，无 macOS |
| `-Wl,-dead_strip`（macOS）对本接缝产物的剪枝 | 同上（本机 COFF 用 `/OPT:REF`，已用） |
| 严格 `clang --target=wasm32-wasip1`（项目 `--target wasm` 的真实形状） | 本机无 WASI SDK sysroot；emcc 路径已覆盖 wasm「可编可跑」 |
| 与真实 Skia / SDL 窗口后端联合链接、真实文本引擎接入 measure | 超出本原型范围（U1 前置测量的 §8 同款） |
| 渲染正确性（本原型只看矩形，不看像素） | U1 只验布局接缝 |
| `point_scale != 0` 的像素对齐行为 | 本原型固定 0 取原始 float；对齐口径属渲染阶段 |

---

## 7. 实现中发现的最大两个设计风险

**风险 1：接缝是「只写不报」的——所有 setter 都是 `void`，没有任何错误/校验通道。**
一旦样式设错（拼错枚举、给 min/max 设成 `auto`、给不支持的 combo），引擎**不会报错**，
只会给出一个合法但错误的矩形。更隐蔽的是 **measure 陈旧**：Yoga 缓存测量结果，
只有 `set_dirty` 才失效；若 AS3 侧文本内容变了却忘了标脏，接缝**无法察觉**，会静默返回旧尺寸。
⇒ U1 的 AS3 层必须**自己拥有脏传播与样式校验**（对应设计 §3.3 的脏传播表），不能指望引擎兜底。
接缝能做到的只是「宁可不设、不设错」，做不到「报错」。

**风险 2：长度与盒模型的参照系是一大片「静默语义面」。**
三件事都能悄悄偏离直觉：① 百分比基准是 content box（本原型实测），② `box-sizing` 默认 border-box
（与 CSS 相反），③ 父尺寸未定时的百分比会退化成 undefined/0 而非报错（「嵌套百分比」）。
接缝用 `(value, unit)` 承载三态，但**区分不了「显式设了 undefined」与「从没设过」**，也**报告不了
「这个百分比没能解析」**。⇒ 设计 §6 明确把「嵌套百分比」「box-sizing 的完整语义」列为**不支持须响亮报明**；
本原型据此把 `box_sizing` 显式暴露（§2 差异 1），把「不支持」交给 AS3 层报明，而不是让引擎默认冒充标准。

> 次要风险（登记备查）：measure 记录是每节点一次 `malloc`，接缝在 `node_free*` 里回收；若将来 AS3 侧也要
> 在 Yoga 节点上挂自己的 `UiNode*`，这个唯一 user-data 槽会被争用（需要把记录扩成
> `{fn, ctx, void* user}` 并统一生命周期管理）。