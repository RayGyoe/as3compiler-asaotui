# U1 范围一页纸：布局底座（LayoutEngine 接缝，画在 AS3 interface 层）

> **一句话**：给 `asaot.ui` 接上**自动布局**——接缝画在**纯 AS3 接口** `asaot.ui.LayoutEngine` 上，
> **唯一实施路径 = 纯 AS3 实现 `As3LayoutEngine`**（flexbox 子集，**已实现**且**三端逐值一致**：
> 自家 AOT / Yoga(C，差分对手) / AIR）。接口是纯 `.as` ⇒ 整库 `mxmlc`→`adl` 可跑，拿到
> 「同一份 `.as`、双端逐值对照」的杠杆。
>
> **native（Yoga 内建类）路径：已评估、暂不实施**。它需要改编译器（`emit.ts`/`symbols.ts`/`build.ts`），
> 按用户 **2026-10-22** 指示**搁置**——UI 库走纯 AS3，缺的底层支持只**登记**在
> [`compiler-gaps.md`](compiler-gaps.md)，**不动编译器代码**。native 的评估备查见
> [`u1-implementation-plan.md`](u1-implementation-plan.md)。
> 前置测量（供将来决策）：**Go（条件）**：[`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md)。

---

## 做（IN）

- **AS3 侧接缝是纯 `.as` 接口**：`asaot.ui.LayoutEngine`（30 个方法）+ 冻结枚举
  `asaot.ui.LayoutConstants`。契约见 [`seam/`](seam/)。
- **`As3LayoutEngine`：纯 AS3 flexbox 子集（本阶段唯一实现，已落地）**——见
  [`seam/asaot/ui/as3/As3LayoutEngine.as`](seam/asaot/ui/as3/As3LayoutEngine.as)。**零 `flash.*` 依赖**，
  只用内部 `asaot.ui.*`；自家 AOT 能编能跑。
- **验收物（全在 `asaotui/` 工作区内，不进编译器仓库）**：
  - [`layout-check/`](layout-check/)：用**自家 AOT** 编成原生程序，16 项手算断言全绿 + 两次变异测试；
  - [`diff-check/`](diff-check/)：同一份冻结规格喂 Yoga 与纯 AS3 引擎逐行比对（含**单侧变异**证明 harness 有牙）；
  - [`air-check/`](air-check/)：`mxmlc` 编整库 + `adl` 运行 → 16/16，与另两臂**逐字符一致**。
- **验收基准是 W3C flexbox / 浏览器，不是 `adl`**（AIR 无 flexbox 概念，布局属增强，无 AIR 参照物）。
- **不静默**：子集未实现的语义一律 `throw`，**绝不给出错误矩形**（缺口表见 [`seam/README.md`](seam/README.md) §4）。
- **缺口登记**：若 dogfood 过程中撞到编译器缺的底层支持，登记在 [`compiler-gaps.md`](compiler-gaps.md)。

## 不做（OUT）

- **不做 native（Yoga）路径**——`vendor/yoga/`、不透明 C 接缝 `as_ui_yg_*`、内建类
  `NativeLayoutEngine`、`usesAsaotUi` 引用才链、`--package web` 接线：**全部搁置**（需改编译器，
  用户 2026-10-22 指示）。评估与 file-by-file 步骤仅**备查**于 [`u1-implementation-plan.md`](u1-implementation-plan.md)。
- **不改编译器仓库**：不占阶段号、不升版本、不改 `TODO.md`、不动 `src/**` 与 `examples/**`。
  若将来要把这套库作为编译器的**增强面**正式发布（`examples/ui-layout.as` + 单元组 + 版本号），
  那是**另一次项目级决定**，须先取得项目负责人同意。
- **不做控件**（`Box`/`Button`/`Text`/`List`…）——那是 U4。U1 只交**布局引擎接缝**。
- **不做元素身份/reconcile、数据流、`notify`、重绘调度、键盘/焦点**——那些是 U2/U3/U5。
- **不做 `flash.accessibility`**（U6）；**不新增 GPU 渲染管线**；**不换文本引擎**。
- **不碰 `flash.*`**：新 API 一律 `asaot.ui.*`，不改写任何 AIR 已定义行为。
- **不做「通用控件集」**，不预造用不到的 API 面。

## 完成的定义（DoD）

1. **纯 AS3**：`seam/*.as` 全部**不经 codegen**（零 `flash.*` 依赖）；**不动编译器仓库任何文件**
   （`src/**`、`examples/**`、`test/**`、`TODO.md`、`package.json` 一律不改）。
2. **不静默**：未实现的语义一律 `throw`，并如实维护 [`seam/README.md`](seam/README.md) §4 的缺口表。
3. **验收（三层，均在 `asaotui/` 内）**：
   - [`layout-check/`](layout-check/)：自家 AOT 跑 16 项手算断言 → 全绿（`RESULT: PASS`，exit 0）；
   - [`diff-check/`](diff-check/)：Yoga 臂与 AS3 臂读**同一份** `spec/cases.txt`，逐行一致；
   - [`air-check/`](air-check/)：`mxmlc` → `adl`，16/16，与前两臂**逐字符一致**。
4. **防假绿**：至少一次**单侧变异**（改一侧引擎）证明差分 harness 真会红；至少一次期望值变异证明
   `layout-check` 真会红。
5. **缺口登记**：dogfood 撞到的编译器缺口已写入 [`compiler-gaps.md`](compiler-gaps.md)（含证据与状态）。
6. **工作区文档同步**：`asaotui/README.md` 目录表 + 本文与 `seam/README.md` 的状态行。
7. **不动 `flash.*`、不占阶段号、不升版本**（版本号与阶段号属编译器项目，未获授权不碰）。

## 已知边界（不在 U1 承诺内）

- 文本/图片的 **intrinsic measure 回调**先做固定/空桩；真正的文本度量归 U2/U4。
- RTL / grid / baseline / 嵌套百分比等**不在本子集已证范围内**——完整缺口表见 [`seam/README.md`](seam/README.md) §4。

> **native（Yoga）路径的旧边界，仅备查、当前不适用**（该路径已搁置）：严格 `--target wasm --package raw`
> 对 C++ 源直接 throw（`build.ts:1322`，即 G6）；`__EMSCRIPTEN__` 下 `YG_EXPORT` 的 `used` 使 web 侧 DCE
> 弱于 native（wasm 增量已计入 ≈120 KiB）；两实现差分一致（`EPS=0.01`）的硬要求。
> native 所依赖的「**内建类 implements 用户 `.as` 接口**」已 **2026-10-22 实测成立**
> （[`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md)）。
