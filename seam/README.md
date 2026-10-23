# `asaot.ui` 布局接缝（AS3 interface 形态）

> **状态：契约已定；纯 AS3 实现 = 唯一实施路径，已实现并通过三端验收（native 侧搁置、仅备查）**。
> 本目录是「把布局接缝画在
> **AS3 interface 层**」这一决定的**契约**：一份可被 `mxmlc` 编译的纯 AS3 接口 + 一份**已实现**的
> 纯 AS3 实现（101 项手算验收全绿，三臂 105 项差分逐字符一致，见 [`../layout-check/`](../layout-check/)）+ 一份 native 内建类的
> 形态说明。它对应 `u1-implementation-plan.md` 的 U1，是 [`ui-toolkit-api-design.md`](../ui-toolkit-api-design.md)
> §0.3/§9.2 与 [`ui-toolkit-feasibility.md`](../ui-toolkit-feasibility.md) §6 里那条接缝的**落地形态**。

---

## 1. 接缝形状

接缝**不再画在 C 函数层**，而是画在 **AS3 interface 层**：`asaot.ui.LayoutEngine` 是一个**纯 `.as`
接口**（[`asaot/ui/LayoutEngine.as`](asaot/ui/LayoutEngine.as)），方法集与原来 `u1-prototype/yoga_glue.h`
里 **30 个 `as_ui_yg_*`** C 函数的能力**一一对应**（每个方法都有 `// <-> as_ui_yg_*` 标注）。

```
        asaot.ui 控件层（纯 AS3，只依赖接口）
                    │  LayoutEngine（纯 .as 接口）
        ┌───────────┴─────────────────────────────┐
        │                                         │
  As3LayoutEngine                          NativeLayoutEngine
  （纯 AS3 flexbox 子集）                    （内建类，implements 同一接口）
  mxmlc→adl 可跑                             方法体 → as_ui_yg_*（不透明 C 接缝）→ Yoga
                                                  ↑
                                        30 个 C 函数（仅 native 内建可见）
```

- **接口层（纯 AS3）**：`asaot/ui/LayoutEngine.as` + `asaot/ui/LayoutConstants.as`（冻结枚举，
  与 C 头 `AS_UI_*` 逐值相同）。
- **纯 AS3 实现（adl 可跑）**：[`asaot/ui/as3/As3LayoutEngine.as`](asaot/ui/as3/As3LayoutEngine.as)
  + 辅助记录 [`asaot/ui/as3/As3LayoutNode.as`](asaot/ui/as3/As3LayoutNode.as)。
- **native 实现（内建类，只有它能碰 C）**：
  [`asaot/ui/native/NativeLayoutEngine.as.doc`](asaot/ui/native/NativeLayoutEngine.as.doc)
  ——**不是真源码**，是「内建类形态说明」。
- **内层 C 接缝（不透明，沿用原型）**：`u1-prototype/yoga_glue.h` / `.cc` 的 30 个 `as_ui_yg_*`
  （节点是 `void*`，枚举值自有，`<yoga/Yoga.h>` 只在 `.cc` 里 include）。它现在只是
  `NativeLayoutEngine` 的**实现细节**，不再是对 AS3 可见的接缝。

### 为什么这样切

AS3 **目前没有 FFI**（`enhancements.md` E11 未排期），纯 AS3 源调不到 C 函数 ⇒ 原生实现只能做成
「**内建类 implements 纯 AS3 接口**」。而一旦接口是纯 `.as`，控件层就**只依赖接口** ⇒

- 整个库（NodeTree、Style、控件、**含布局**）都能用 `mxmlc` 编译并在 `adl` 上跑；
- 由此得到本项目**最值钱的验收杠杆**：「同一份 `.as` 源码，`mxmlc`→`adl` 与我们的 AOT→native
  双端逐值对照」。

---

## 2. 两条实现路径与注入点

| 路径 | 类 | 何时用 | 布局来源 |
|---|---|---|---|
| **纯 AS3（当前唯一实施路径）** | `asaot.ui.as3.As3LayoutEngine` | **一切情况**：AOT 构建、`mxmlc`→`adl` 对照、差分测试基准。**已实现** | 自研 flexbox 子集（见 §4 缺口） |
| **native（已搁置，仅备查）** | `asaot.ui.native.NativeLayoutEngine`（内建） | **仅当将来获准 native 化**（需改编译器，属项目级决定）；当前**不实施** | Yoga（不透明 C 接缝） |

**注入点（`UiApp` 怎么选实现）**：

- `UiApp` 持有一个 `LayoutEngine` 字段（**接口类型**），`mount()` 时构造一次。
- **当前恒用 `As3LayoutEngine`**——不需要任何编译期开关，也不需要改动编译器。
- 若将来获准 native：选择规则才是「有 native 内建就用 native，否则回退 AS3」（`ASC_HAVE_LAYOUT` 两态 + `usesAsaotUi` 引用才链）；native 缺失时**不静默**（按 AGENTS.md §1.5 报明）。
- **两条路径共用同一 `LayoutEngine` 接口**，控件层对「走进了哪条」无感知——这正是接缝的意义。

> 具体 `UiApp`/工厂的 AS3 形状见 `ui-toolkit-api-design.md` §1（作者模型）与 §3（三趟管线）。
> 本目录只交**接缝契约**，不交 `UiApp`。

---

## 3. 两条硬要求

### 3.1 布局的验收基准**不是 `adl`**，而是 W3C flexbox / 浏览器

**AIR 里根本没有 flexbox 概念** ⇒ 布局层的「正确矩形」没有 AIR 参照物，`adl` 也不是基准。
基准是 **W3C flexbox 规范 / 一个浏览器**（Yoga 本身就是按 web 标准实现的）。

这不违反 AGENTS.md §1.5：布局属**增强**（AIR 无对应物），**增强本来就没有 AIR 参照物**。
`adl` 在布局上的价值只是「把 AS3 编排层与 `As3LayoutEngine` 子集跑起来、验 AS3 语义」，
**不**用来验布局数字。

### 3.2 两后端必须**差分测试**一致（drift 护栏）

维护**两套**实现（纯 AS3 子集 + Yoga）就要付 **drift 风险**：子集引擎与 Yoga 会在边界上分岔。
因此**硬要求**：

> 对**同一份**「节点树 + 样式」输入，`As3LayoutEngine` 与 `NativeLayoutEngine`（Yoga）产出的
> 每个节点矩形必须**逐项相等**（容差同 `u1-prototype/check-layout.md` 的 `EPS = 0.01`），
> 否则测试红。

落法：在 **native 构建**里同时链接两套实现（native 内建 + 纯 AS3 子集），对同一输入各跑一遍、
逐项比对。`examples/ui-layout.as` 与单元组 `test/unit/ui-layout.ts` 把这条钉成不变量。
**不允许**为了让差分测试过而放宽 `EPS` 或裁剪用例（同原型 §1 的口径）。

---

## 4. 纯 AS3 子集的**已实现**范围与缺口清单

已实现的范围 = **被验收钉住的那一片**：[`../layout-check/`](../layout-check/) **101 项全绿**，
[`../diff-check/`](../diff-check/) **105 项与 Yoga 差分逐字符一致**，[`../air-check/`](../air-check/)
在 AIR 上复现同一批 105 项。逐项如下（改 `As3LayoutEngine.as` 后必须同步这一节）：

- **方向**：`row` / `column` / `row-reverse` / `column-reverse`；`DIR_RTL`（row ↔ row-reverse，
  column 的交叉轴变 row-reverse；`DIR_INHERIT` 拒收）
- **主轴**：显式尺寸（**border-box 默认**）+ 百分比（基准 = **父的 content box**）；
  `flex grow/shrink/basis`；`min/max` 夹取；
  `justify-content` = flex-start / center / flex-end / space-between / space-around / space-evenly
- **交叉轴**：`align-items` / `align-self`（`auto` 继承父的 align-items）= flex-start / center /
  flex-end / stretch；auto 尺寸 stretch
- **换行**：`flex-wrap` = nowrap / wrap / wrap-reverse（wrap-reverse 是**事后沿交叉轴镜像**）；
  `align-content` = flex-start / center / flex-end / stretch / space-between / space-around
- **间距**：`padding` / `border`（point）+ **百分比 padding**；`row-gap` / `column-gap` **分离存储**
  （row 容器用 column-gap、column 容器用 row-gap）+ 百分比 gap；
  `margin`（point / percent，支持 `EDGE_ALL/H/V/TOP/RIGHT/BOTTOM/LEFT/START/END`）
- **定位**：`position-type` = relative（默认）/ absolute；`inset`（point / percent，含 START/END）
- **盒模型**：`box-sizing` = border-box（默认）/ content-box
- **overflow**：只**存标志位**（visible / hidden / scroll），**绝不改变矩形**

**其余一律 `throw new Error('… 未实现 …')`，绝不静默给出错误矩形。**

| 缺口（继续 `throw`） | 方法 / 取值 | 备注 |
|---|---|---|
| display | `setDisplay`（任一取值） | flex 之外的盒生成/移除未做 |
| aspect-ratio | `setAspectRatio` | — |
| 内在尺寸 | `setMeasure` | auto 沿主轴只做 max-content 近似 |
| auto margin | `setMargin(..., UNIT_AUTO)` | Yoga 会用它吸收主轴空余 |
| 定位 static | `setPositionType(STATIC)` | 需 `layoutAbsoluteDescendants` 的 containing-block 推演 |
| BASELINE | `setAlignItems` / `setAlignSelf(ALIGN_BASELINE)` | 需真实文本基线（column 容器的降级分支保留在 `childAlign`，但接口层不放行） |
| align-content START/END | `setAlignContent(ALIGN_START/END)` | Yoga 视作 no-op；我们**拒绝**而不是静默 |
| align-content space-evenly | `setAlignContent(ALIGN_SPACE_EVENLY)` | 引擎内部有该分支，接口层未放行（P4 未列） |
| justify START/END | `setJustifyContent(JUSTIFY_START/END)` | Yoga 视作 flex-start；我们拒绝 |
| 非 point/percent 长度 | `setSize` / `setMinMax`(AUTO/MAX_CONTENT/…)；`setFlex` 的 basis 单位 | 仅 point / percent /（尺寸与 basis 还收）undefined |
| gap 的 undefined | `setGap(..., UNIT_UNDEFINED)` | 「无 gap」用 point 0 表达 |
| inset auto | `setPosition(..., UNIT_AUTO)` | — |
| 自动尺寸下的嵌套百分比 | 父 auto 时子件百分比的基准 | 近似，见 `As3LayoutEngine.as` 注释 |

> **`overflow` 为什么不算缺口**：P8 的口径就是「存标志位，矩形不受影响」。`overflow:hidden` 是
> **裁剪**，属绘制层职责；用例 `q1` 把「矩形与 `visible` 逐值相同」钉住，所以这是**已实现**，不是缺口。

> **百分比基准（与直觉不同的点）**：padding / margin / gap 的百分比**一律按 containing block 的
> WIDTH** 解析（竖向也是）；**inset 例外**，水平按 owner 宽、竖向按 owner 高
> （`Style::computeMarginForAxis` 硬编码 widthSize / `computeFlexStartPosition` 按轴）。
> `gap` 的百分比基准是 `availableInnerMainDim` / `availableInnerCrossDim`。

> **默认 flex-direction 由 config 决定**：`use_web_defaults = 1` → **row**，且 **align-content 默认 = stretch**
>（对齐 CSS / GPUI `style.rs`）；`= 0` → Yoga 自带的 **column** / align-content 默认 flex-start，
> 与 `YGConfigSetUseWebDefaults` 同语义（`u1-prototype/yoga_glue.h:246-249`）。子集**曾经收下这个标志却忽略它**
>（恒 column），已修，并由 `layout-check/` 的 **f/g 成对断言**与 spec 的 **k2**（不调 `setAlignContent`，
> 靠 config 默认）钉住——a~e/k3~k6 全都显式设值，只看它们会漏掉默认值写错。

---

## 5. native 路径的前提（**已实测，2026-10-22；当前搁置，仅备查**）与回退

> 本节与当前实施无关（UI 库走纯 AS3），保留给「若将来要 native 化」的决策人。

**前置依赖**：native 路径成立的前提，是编译器支持一条**此前无先例、现已实测通过**的模式——
**内建类 `implements` 一个用户 `.as` 接口**（即 `NativeLayoutEngine` 声明
`implements: ['asaot_ui_LayoutEngine']`，引用用户接口 `asaot.ui.LayoutEngine` 的 classMap key）。
机制上可通（`emit.ts:3962` 的接口 vtable 与 `symbols.ts:7383` 的一致性检查都遍历全部类，含内建类），
**已实测通过**（2026-10-22：正例 `x=120`/`is` 为真，反证报 `does not implement`；
确切命令与原文见 [`../reviews/probe-builtin-implements-user-iface-2026-10-22.md`](../reviews/probe-builtin-implements-user-iface-2026-10-22.md)）
⇒ 本模式**不再是无先例的未知项**，架构无需回退。

**回退方案（实测已通过，以下仅备查）**（详见 [`asaot/ui/native/NativeLayoutEngine.as.doc`](asaot/ui/native/NativeLayoutEngine.as.doc) §4）：

1. **适配器模块（优先）**：内建类不再 implements 接口，改发一组内建**静态**方法；另写只在 AOT
   构建里编译的纯 AS3 适配器 `implements LayoutEngine` 转发到内建。adl 侧仍用 `As3LayoutEngine`，
   控件层仍只依赖接口。代价：多一层转发、多一个只在 AOT 存在的模块。
2. **回到原设计（最后手段）**：放弃纯 `.as` 接口，`emit.ts` 直接发射内建类，控件层引用内建类。
   代价：整个库不能在 `adl` 上跑，adl↔native 对照只覆盖非布局层。

---

## 6. 文件清单

| 文件 | 是什么 | 可否被 mxmlc 编译 |
|---|---|---|
| [`asaot/ui/LayoutEngine.as`](asaot/ui/LayoutEngine.as) | 接缝 AS3 接口（30 个方法 ↔ 30 个 `as_ui_yg_*`） | ✅ |
| [`asaot/ui/LayoutConstants.as`](asaot/ui/LayoutConstants.as) | 冻结枚举常量（与 C 头 `AS_UI_*` 逐值相同） | ✅ |
| [`asaot/ui/as3/As3LayoutEngine.as`](asaot/ui/as3/As3LayoutEngine.as) | 纯 AS3 flexbox 子集（**已实现**，验收见 [`../layout-check/`](../layout-check/)） | ✅ |
| [`asaot/ui/as3/As3LayoutNode.as`](asaot/ui/as3/As3LayoutNode.as) | `As3LayoutEngine` 的节点记录（不透明句柄） | ✅ |
| [`asaot/ui/native/NativeLayoutEngine.as.doc`](asaot/ui/native/NativeLayoutEngine.as.doc) | native 内建类**形态说明** | ❌（**不是源码**） |

## 7. 参考

- 内层 C 接缝（权威）：[`../u1-prototype/yoga_glue.h`](../u1-prototype/yoga_glue.h) /
  [`../u1-prototype/check-layout.md`](../u1-prototype/check-layout.md)（30 函数清单、9 用例口径、`EPS`）。
- 主文档：[`../ui-toolkit-feasibility.md`](../ui-toolkit-feasibility.md) §6（三条接缝、U1 行、风险表）。
- API 草案：[`../ui-toolkit-api-design.md`](../ui-toolkit-api-design.md) §0.3（接缝图）、§9.2（新 API）、§10（未决）。
- U1 计划与回退：[`../u1-implementation-plan.md`](../u1-implementation-plan.md) §3.5~§3.7、§4。
- FFI 未排期：[`../../as3compiler/docs/zh-cn/enhancements.md`](../../as3compiler/docs/zh-cn/enhancements.md) E11。
