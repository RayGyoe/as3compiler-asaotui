# GPUI 借鉴映射表（每一条都指到 `gpui-src` 的具体文件）

**规则**：本工作区任何「借鉴 GPUI」的说法，都必须能落到下表的某一行，并给出 `gpui-src/`
里的**具体文件（尽量带行号）**。没有出处的不写；写出处却对不上的，删掉。

> `gpui-src/` 是 Zed 的 `gpui` crate 浅克隆（`crates/gpui/src/`，约 80 个 `.rs`）。
> 我们**只借设计与语义，不借实现**：GPUI 是 Rust + 保留式元素树的即时模式混合体，
> 我们是 AS3 + **retained 显示树**（`flash.display.DisplayObject` 就是节点身份），
> 两者的落地形态必然不同。凡是「形态不同」的行，最后一列都必须写清**为什么不照搬**。

---

## 1. 借了，且已落地

| # | 借什么 | GPUI 出处 | 拿过来变成什么 | 我们落在哪 |
|---|---|---|---|---|
| B1 | **扁平的 `Style` + `StyleRefinement` 覆盖机制**：一个结构体承载全部 flexbox 属性，`refine` 做「部分覆盖」（未设的字段保持继承值），而不是 C SS 那样的级联解析 | `crates/gpui/src/style.rs:180`（`pub struct Style`）、`style.rs:324-330`（`StyleRefinement` + `impl Styled`）、`style.rs:296`（`text: TextStyleRefinement`） | `asaot.ui.style.Style`（扁平）+ `StyleRefinement`（只存「作者显式设过的字段」）+ `refine()` 逐字段覆盖；`TextStyle` 单独一层 | `kit/asaot/ui/style/Style.as`、`StyleRefinement.as`、`TextStyle.as` |
| B2 | **布局属性用「值 + 单位」三元组表达**（长度不是裸数字，必须带单位） | `crates/gpui/src/style.rs`（`DefiniteLength` / `Length` 系列）、`taffy.rs:439-483`（`impl ToTaffy<taffy::style::Style>`：把 `Style` 逐字段翻译成布局引擎的 Style） | `Length`（值 + `Unit`），与 `LayoutConstants.UNIT_*` **同一套整数枚举**，直接喂 `As3LayoutEngine` | `kit/asaot/ui/style/Length.as`、`seam/asaot/ui/LayoutConstants.as` |
| B3 | **布局引擎是可替换的接缝，控件层不认识具体引擎** | `crates/gpui/src/taffy.rs:31`（`pub struct TaffyLayoutEngine`）、`taffy.rs:187`（`compute_layout`）、`taffy.rs:385`（`LayoutId` 是不透明句柄） | `asaot.ui.LayoutEngine` 纯 AS3 接口 + 30 个方法；句柄是 `Object`（不透明）；`As3LayoutEngine` / （已搁置的）`NativeLayoutEngine` 可互换 | `seam/asaot/ui/LayoutEngine.as`、`seam/asaot/ui/as3/As3LayoutEngine.as` |
| B4 | **元素身份（`ElementId`）用于「同一个元素跨帧保持状态」** | `crates/gpui/src/element.rs:52-99`（`trait Element`、`GlobalElementId` 被传进 `request_layout`/`prepaint`/`paint`）、`element.rs:66`（`fn id()`） | `Node` 的 keyed 身份：`Reconciler` 按 key 匹配新旧节点，**复用**（而不是重建）已存在的显示对象与布局节点 | `kit/asaot/ui/Node.as`、`kit/asaot/ui/Reconciler.as` |
| B5 | **测量（prepaint）与绘制（paint）分离**：两趟，第一趟可以改自己的尺寸并向上汇报 | `crates/gpui/src/element.rs:76-99`（`request_layout` / `prepaint` / `paint` 三段签名）、`elements/div.rs:1863`（`impl Div` 同时实现三者） | `View` 的 `render()` 产出 `Node` 树；先整棵算布局（`calculate`），再整棵绘制——**一趟布局、一趟绘制** | `kit/asaot/ui/View.as`、`kit/asaot/ui/UiApp.as` |
| B6 | **数据流：`Entity` + `notify`/`observe`，模型变更驱动重绘** | `crates/gpui/src/app/entity_map.rs:435`（`pub struct Entity<T>`）、`app/entity_map.rs:267`（`AnyEntity`）、`_ownership_and_data_flow.rs:1`（所有权与数据流的官方说明） | `Observable`（可观察值）+ `Subscription`（订阅句柄）；变更 → 标脏 → 下一个 tick 重绘 | `kit/asaot/ui/Observable.as`、`Binding.as`、`Subscription.as`、`Dirty.as` |
| B7 | **Tab 序是显式的、可排序、可分组** | `crates/gpui/src/tab_stop.rs:19`（`TabStopOperation`）、`tab_stop.rs:92-98`（`begin_group`/`end_group`）、`tab_stop.rs:472`（`tab_group`） | 每个控件声明自己的 `tabIndex`；Tab 遍历按 `tabIndex` 排序（**不是**扁平扫描） | `kit/asaot/ui/UiApp.as`（Tab 序）、`kit/asaot/ui/Control.as` |
| B8 | **瞬态 UI 状态与业务状态分离**（hover/active/focus 不属于模型） | `crates/gpui/src/elements/div.rs:92`（`Interactivity`）、`div.rs:1803`（`HoverListenerMode`）、`div.rs:1927`（`impl InteractiveElement for Div`） | `ElementState`（hover / active / focus / disabled），由 `UiApp` 维护，**不写进作者的状态对象** | `kit/asaot/ui/ElementState.as`、`UiNode.as` |
| B9 | **控件 = 一个有 `render()` 的可复用单元，而不是一棵要手搭的树** | `crates/gpui/src/view.rs:208`（`pub trait View`）、`view.rs:266`（`ViewElement`）、`element.rs:164`（`pub trait Render`）、`element.rs:180`（`RenderOnce`） | `View` 基类（`render()` 返回 `Node`）；`Box`/`Button`/`Label`/`Checkbox`/`TextInput` 都是 `View` 子类 | `kit/asaot/ui/View.as`、`Box.as`、`Button.as`、`Text.as`、`Checkbox.as`、`TextInput.as` |
| B10 | **样式用链式/工厂函数拼装，而不是一堆构造函数参数** | `crates/gpui/src/style.rs:330`（`impl StyleRefinement` 的 setter 群）、`elements/div.rs:1921`（`impl Styled for Div`） | `Factories`（`row()`/`column()`/`label()` 等）+ `Style` 上的链式 setter | `kit/asaot/ui/Factories.as` |
| B11 | **主题/配色集中一处，不散落在控件里** | `crates/gpui/src/colors.rs`、`color.rs` | `Theme`（颜色 / 圆角 / 间距 / 字号 一组 token） | `kit/asaot/ui/Theme.as`、`style/{Fill,Corners,Edges,Size}.as` |
| B12 | **绘制层只认矩形与颜色，可读回** | `crates/gpui/src/scene.rs`（`Scene` 是绘制命令列表） | 控件 → `flash.display.Graphics` 的 `drawRect` 等；可 `BitmapData.draw(stage)` 读回成像素做断言 | `kit/asaot/ui/UiNode.as`（→ DisplayObject 桥）、`layout-check/visual-check.cjs` |

---

## 2. 明确**不借**的

| # | 不借什么 | GPUI 出处 | 为什么不 |
|---|---|---|---|
| N1 | **每帧重建整棵元素树**（`Div` 每次 render 都是新对象，靠 `AnyElement` 装箱/打量） | `crates/gpui/src/element.rs:146`（`IntoElement`）、`arena.rs`（每帧 arena 分配） | 我们的红线是「**禁止在每帧/每循环的热路径里产生进 arena 的临时分配**」（`AGENTS.md` 内存管理红线；历史上 `as_disp_key` 的每帧分配造成过 ~39 KB/s 静默泄漏）。而且我们的 `DisplayObject` 树本来就是 **retained** 的 ⇒ 改成 **keyed reconcile**：只重建 key 变了的节点。 | 
| N2 | **Rust 的 `Entity`/借用检查器驱动的所有权模型** | `crates/gpui/src/app/entity_map.rs`、`_ownership_and_data_flow.rs` | AS3 没有生命周期/借用；`EntityMap` 的存在是 Rust 所有权约束的产物。我们只需「值 + 订阅」两件事，多了是负担。 |
| N3 | **`taffy` 作为布局引擎本身** | `crates/gpui/src/taffy.rs` | 我们**已有** Yoga 的 C 接缝与纯 AS3 实现（三方逐字符一致，105 项差分）。再引一个 Rust 布局引擎等于把已验证的接缝推倒重来。**借的是接口形状（B3），不是引擎。** |
| N4 | **actions + JSON keymap 的完整机制** | `crates/gpui/src/action.rs:24`（`actions!` 宏）、`keymap.rs`、`keymap/binding.rs`、`keymap/context.rs:10`（`KeyContext`）、`key_dispatch.rs` | 这是 U4 的量级（actions、context 谓词、keymap 解析、冲突消解）。**本轮不做**；等 U2 的控件层稳定、真的需要快捷键时再按同一张表另开一节。现在写进去只是猜。 |
| N5 | **a11y（无障碍）子系统** | `crates/gpui/src/_accessibility.rs`、`window/a11y.rs:304`（`pub struct A11ySubtreeBuilder`）、`window/a11y/debug.rs` | 我们连 `flash.accessibility.*` 整包都还没有（[`compiler-gaps.md`](compiler-gaps.md) **G2**）。底层不存在时谈控件层 a11y 是空话。 |
| N6 | **平台弹层/系统菜单/`layer_shell`** | `crates/gpui/src/platform/popup.rs`、`platform/app_menu.rs`、`platform/layer_shell.rs` | 属窗口后端能力，不是 UI 工具链；我们要做的话是 `flash.display` 层的事。 |

---

## 3. 与 `ui-toolkit-api-design.md` 的关系

`ui-toolkit-api-design.md` 是**先写的 API 草案**（~1344 行，2026-10-21）。
本表是它落地之后的**回溯核对**：草案里哪些设计实际来自 GPUI 的哪个文件、
哪些在落地时被改掉了（改掉的原因写在 §2）。

**核对口径**：草案里凡出现「借 GPUI」字样的段落，若在本表 B1~B12 里找不到对应行，
则该段落**作废**——要么补出处，要么删掉。

---

## 4. 与本表的自检

```bash
# 本工作区里所有提到 GPUI 的地方（应全部落在上表）
grep -rn "GPUI\|gpui" asaotui --include=*.md --include=*.as
```

> 注：本机 bash 无 coreutils（无 `grep`），实际用内置 grep 工具或 `node` 脚本执行。
> 每次改动本表后跑一遍，确认没有**无出处**的借鉴声明。
