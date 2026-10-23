# 自研 UI 库：GPUI 借鉴评估

> **状态：评估（未实施、无版本号）**。先例同 [`rust-text-backend.md`](as3compiler/docs/zh-cn/rust-text-backend.md)：先算清楚
> 该做什么、不该做什么，再决定要不要排期。本文只做技术裁决，不落实现；`TODO.md` 里只追加了一段
> **未排期待定项**（不占阶段号、不升版本）。
>
> （文档位置：工作区根目录，与 `talkmed-meeting-aot-*.md` 几份分析报告同族。）
>
> **一句话结论：可以借鉴，但目标不是"再做一遍 GPUI"。** 借它的**作者模型**与四件事
> ——布局、元素身份、数据流、键盘与焦点**形态**；**不借**它的"每帧重建整棵元素树"（那会正面撞上本项目
> 的 GC 内存红线），也不借它的渲染与文本两层（我们已有的那两层是逐值对着 `adl` 校准出来的，
> 换掉＝把校准重做一遍）。
>
> **实施路径口径（2026-10-22 用户决定）**：本线的 UI 库走**纯 AS3 实现**（已落地并三端验收，见
> [`seam/`](seam/)、[`layout-check/`](layout-check/)、[`diff-check/`](diff-check/)、[`air-check/`](air-check/)）。
> 凡需要改动主机编译器（`as3compiler/`）的 native 路径（如把布局换成内联 Yoga）**已搁置**；
> 缺的底层支持一律登记在 [`compiler-gaps.md`](compiler-gaps.md)，**不动编译器代码**。
> 因此本文件下方涉及 Yoga 内建类与 `emit.ts`/`build.ts` 改动的部分，请一律按「**备查选项**」阅读。

---

## 1. 先把问题问对：我们缺的是"哪一层"

"UI 库"这个词盖住了三个可独立拆卖的层。GPUI 三层都有，我们只有下两层半：

| 层 | 内容 | GPUI | 我们 | 裁决 |
|---|---|---|---|---|
| **L1 渲染后端** | 光栅化 / GPU 管线、图元、图层、遮罩、字体图集 | 自研 GPU 管线（Metal / D3D / Blade）+ `scene.rs` 图元表 | **已有两条**：`flash.display` → Skia（CPU/GPU）、`flash.display3D` → Metal / D3D12 / WebGL（Starling 2.x 端到端可跑） | **不借**。再加第三条管线是重复建设 |
| **L2 显示树与输入** | retained 树、变换、命中测试、事件分发、文本排版 | element tree（`gpui-src/crates/gpui/src/element.rs:315-348` 的 `Drawable`/`ElementDrawPhase` 状态机）+ Taffy + `text_system.rs` | **已有**：`DisplayObject` 树、三阶段事件、按绘制区域的命中测试、焦点与 Tab 遍历（AIR 对齐）、SkParagraph 文本 | **只缺自动布局**；焦点/Tab 已有但**形态受限**（扁平扫描、64 个上限、每次按键从零重扫、无分组），快捷键仍是 `keyCode` 直投 |
| **L3 控件与作者模型** | 声明式 API、状态提升、主题、控件集、actions/keymap、无障碍 | **核心价值所在** | **完全没有**（219 个示例里没有一个 Button/Slider/List） | **借这一层，并按 AS3 重写** |

所以真正的问题不是"要不要抄 GPUI"，而是：

> **把 L3 补上；L1/L2 复用现有的，只在 L2 的一处空白（自动布局）与两处形态（Tab 序、快捷键）上做增补。**

---

## 2. GPUI 实际长什么样（事实，带出处）

### 2.1 生命周期：每帧重建整棵元素树

`gpui-src/crates/gpui/src/element.rs:10-14` 写得很直白（英文原文逐字见英文版 §2.1）：

> Elements 由根 view 的 `Render::render()` 递归构造；交给 Taffy 布局；再按各自
> `Element::paint()` 画到屏幕。**"Before the start of the next frame, the entire element
> tree and any callbacks they have registered with GPUI are dropped and the process repeats."**
> （原句起于 `element.rs:13` 末尾、接 `:14`；这正是 GPUI README 自称的 `hybrid immediate and
> retained mode`——`gpui-src/crates/gpui/README.md:3`。）

这是 GPUI 自称 "hybrid immediate and retained" 里的 **immediate 一半**：树是"每帧重新描述的"。
**retained 的一半**有两个：① `App` 拥有的 **entity**（业务状态，跨帧存活）；
② `Element::PrepaintState`（`element.rs:17` 的模块说明、`:59` 的关联类型定义）——那些"太小太多、不值得塞进业务对象"的**瞬态 UI 状态**
（是否处于 hover、滚动偏移），由元素自己挂在树上跨帧保留。

### 2.2 四趟管线

`Element`(`element.rs:52-105`；`request_layout`/`prepaint`/`paint` 分别在 `:74`/`:84`/`:96`) 只有四件事，界限很清楚：

| 趟 | 干什么 | 我们今天的对应物 |
|---|---|---|
| `Render::render()` | 从当前状态**描述**出元素树 | 无（用户手写 `new Sprite()` + `addChild`） |
| `request_layout` | 把样式交给布局引擎（Taffy），拿回 `LayoutId` | **无** |
| `prepaint` | 布局已知后的第二趟：计算 **measure**、收集瞬态状态、建命中区域 | 无（`getBounds` 是事后算的） |
| `paint` | 把图元记录进 `Scene` | `as_render_object` / `as_render_object_content`（`src/emit.ts:22235`/`:22477`） |

**`prepaint` 这一趟是最值得抄的**：它把"测量与暂存"从"绘制"里分出来。Flash 生态里
反复出现的"先 measure 再摆放"的丑陋循环（改一次属性触一次布局、再读回尺寸），根子就是没有这一趟。

### 2.3 `Style` 与 Taffy

- `Style`(`style.rs:180-322`) 是一张 **38 项的扁平值表**（逐字段数过）：`display` / `visibility` /
  `overflow` + `scrollbar_width` + `allow_concurrent_scroll` + `restrict_scroll_to_axis` / `position` + `inset` /
  `size` + `min_size` + `max_size` + `aspect_ratio` / `margin` + `padding` + `border_widths` /
  `align_items` + `align_self` + `align_content` + `justify_content` + `gap` /
  `flex_direction` + `flex_wrap` + `flex_basis` + `flex_grow` + `flex_shrink` /
  `background` + `border_color` + `border_style` + `corner_radii` + `box_shadow` + `text` + `mouse_cursor`，
  以及面板未单列的 `opacity` / `grid_cols` / `grid_rows` / `grid_location` / `debug` / `debug_below`。
  其中 **11 个字段标了 `#[refineable]`**（`overflow` / `inset` / `size` / `min_size` / `max_size` / `margin` /
  `padding` / `border_widths` / `gap` / `corner_radii` / `text`），它们参与**继承式 refine**
  （父级样式 → 子级精化，`derive(Refineable)`）——这就是主题机制。
- 布局引擎是 **Taffy**（`taffy.rs:31` `TaffyLayoutEngine`，`:62` `request_layout`，`:187`
  `compute_layout`，`:345` `layout_bounds`），实现的是 **web 标准的 flexbox（以及 grid）**：
  `Style → taffy::style::Style` 的转换在 `taffy.rs:439` 起，逐字段对应，不掺私货。
- 尺寸有明确的三分法：`AbsoluteLength` / `DefiniteLength` / `Length`（auto），并带 `rem_size`
  与 `scale_factor`（`:436`）——**逻辑单位与设备像素是同一个换算链上的两件事**，这点我们的
  `ASC_render_scale` / `as_bake_scale`(`src/emit.ts:21797`) 与设备倍率的教训是同构的。

### 2.4 数据流：`App` 拥有状态，`Context` 里 `notify`

`_ownership_and_data_flow.rs` 的开篇即："每个 model 或 view 实际上都由一个顶层对象 `App` 拥有"。
链条是 `App` → `Entity<T>` → `Context<T>`，而 `Context<T>`（`gpui-src/crates/gpui/src/app/context.rs`）提供：

- `notify()`：告诉窗口"我变了，重画"（**不是**直接调 paint）——`context.rs:221`（`App` 侧同名方法在 `app.rs:3164`）；
- `observe()` / `subscribe()`：别的 entity 变了通知我（跨对象订阅）——`context.rs:64` / `:94`；
- `emit(event)`：向外广播自定义事件——`context.rs:780`。

要点是 **notify 是最小粒度、由被改动的对象自己发起**，不是"谁改了什么就整树重绘"。

### 2.5 输入：actions / key contexts / keymap / focus / tab 序

- **鼠标**：`div().on_click(...)`；**键盘**：必须绑 **action**（`docs/key_dispatch.md`）。
  action 是一个类型，keymap 是 **JSON**，按 **key context**（`div().key_context("menu")`）
  匹配上下文，再落到 action。**键盘映射因此是数据、不是代码**——可运行时改、可用户自定义、
  可随焦点上下文切换。（GPUI 的 `key_dispatch.rs` **2216 行 / 约 85 KB**、`keymap.rs` **1135 行 / 约 44 KB**——后者连同
  子模块 `keymap/context.rs`(891 行)、`keymap/binding.rs`(143 行) 合计约 2169 行。**注意**：它并**不是**
  GPUI 第二大的模块——同目录下 `window.rs` 9979 行、`elements/div.rs` 5789 行、`geometry.rs` 4020 行
  都比它大，它大约排在第十（`window.rs` 9979 > `elements/div.rs` 5789 > `geometry.rs` 4020 > `platform.rs` 3907 >
  `app.rs` 3888 > `elements/list.rs` 3638 > `profiler/journal.rs` 3540 > `gestures.rs` 2331 > `profiler.rs` 2225 > `key_dispatch.rs` 2216）。
- **焦点**：`FocusHandle` / `FocusId`（`window.rs:543` / `:339`）；**Tab 序**是 `TabStopMap`(`tab_stop.rs:11-23`)：
  `insertion_history: Vec<TabStopOperation>`（`Insert` / `Group` / `GroupEnd`）+ 一棵 `SumTree`
  维护顺序（`tab_stop.rs:11-23`：`TabStopMap` 在 `:11`、三个 op 在 `:19-23`）。注意 **`Group`**：
  Tab 序可以**分组限定**（对话框里循环），不是一条全局链。

### 2.6 无障碍：AccessKit

`_accessibility.rs` 明说集成 [AccessKit]（`_accessibility.rs:15`），两大能力（`:22-24`）：把当前 UI 状态暴露给辅助技术、
响应辅助技术发来的动作（语音控制"按下那个按钮"）。身份用 `ElementId` / `GlobalElementId`（`_accessibility.rs:30`；
`GlobalElementId` 定义在 `element.rs:220`）。

### 2.7 渲染：`Scene` 是一张图元表

`scene.rs:222-230`：`Primitive` 枚举成员 = `Shadow` / `Quad` / `Path` / `Underline` /
`MonochromeSprite` / `SubpixelSprite` / `PolychromeSprite` / `Surface`；
`:478-495` 是 `PrimitiveBatch`——按类型分段的 Range（`Shadows(Range)`、`Quads(Range)`、`Paths(Range)`…）——
外加 `Scene.primitive_bounds: BoundsTree<ScaledPixels>`（`scene.rs:43`，索引模块 `bounds_tree.rs`）做空间索引。
**注意**：`StartLayer(Bounds)` 属 `PaintOperation`（`scene.rs:214-216`），不是 `Primitive` 的成员；
另有 `PrimitiveKind`（`:202-211`）。**"GPU 只认图元表、不认元素树"** 是它的渲染后端 seam。

---

## 3. 我们这一侧的家底（逐条带证据）

| 能力 | 我们有没有 | 证据 |
|---|---|---|
| retained 显示树（父子、深度、变换矩阵、遮罩、九宫格） | **有** | `DisplayObjectContainer_addChild` `src/emit.ts:10607`；渲染遍历 `as_render_object` `:22235` / `as_render_object_content` `:22477`；轴对齐包围盒特化 `as_do_extents` `emit.ts:21464`（非轴对齐回落 `as_bounds_xform` `:21168`） |
| 上屏链路（一句话） | **有** | `Stage_showWindow`(`src/emit.ts:23979`) → `as_skia_surface_show_window[_gpu]`(`src/runtime.ts:9194`) → `sk_pump_frame`(`vendor/window_glue.cc:758`) / `sk_window_show`(`:1751`) → 每窗口 `on_redraw` = `ASC_window_on_redraw`(`src/emit.ts:23621`) → `ASC_window_render`(`:23197`) → `as_render_object(canvas, stage)`(`:23304`) → Skia → `present_frame`(`vendor/window_glue.cc:496`) |
| 每帧重绘的代价控制 | **有**（比 GPUI 更细） | `ASC_AUTO_BAKE_FRAMES 3` + 递归**内容指纹**把稳定子树自动烘焙进 `_cache_image`，`emit.ts:21749-21764`；`cacheAsBitmap` 走同一条烘焙路；烘焙分辨率按目标 CTM 1:1（`as_bake_scale` `emit.ts:21797`），上限 4M px（`AS_BAKE_MAX_PIXELS` `:21769`） |
| 窗口级失效 | **有** | `WinCtx.dirty` `vendor/window_glue.cc:387`；**只重绘 dirty 窗口** `:809-820`；一次应用级帧时钟把**所有可见窗口**标脏 `:775-800` |
| 像素级脏矩形 | **无** | `as_show_redraw_regions` 只记录不画，注释直说"this render walk has no AIR-style region list"（`src/runtime.ts:177-188`，关键注释在 `:178`） |
| 事件三阶段（捕获/目标/冒泡） | **有**，且逐个对 `adl` 校准 | `as_disp_target` `src/emit.ts:10043-10070`（定义在 `:10052`，含"目标自身的 capture 监听器 AIR 从不执行"这条实测口径） |
| 命中测试 | **有**，按**绘制区域**而非子件包围盒 | `as_pick_hit_local` `src/emit.ts:15998` → `as_obj_region_hit_local` `:16043` → `as_obj_hit_local` `:15961`（前置声明 `:15872`/`:15873`） |
| GPU 渲染路径 | **有** | `vendor/stage3d_glue.mm` / `stage3d_d3d.cc` / `stage3d_webgl.cc` / `metal_glue.mm` / `d3d_glue.cc`；Starling 2.x 端到端（`examples/air-starling-demo/`，外部夹具） |
| 文本排版（含度量） | **有** | SkParagraph 路线（[`flash-text.md`](as3compiler/docs/zh-cn/flash-text.md)/[`skia.md`](as3compiler/docs/zh-cn/skia.md)）；度量 `as_tf_paragraph` `src/emit.ts:18493` → `TextField_get_textWidth`→`as_skia_textlayout_max_width` `:18796` / `TextField_get_textHeight`→`as_skia_textlayout_height` `:18808`；最底层字宽原语 `sk_text_measure` `vendor/skia_text_glue.cc:308` |
| **自动布局（flexbox/grid/约束）** | **无** | `grep -riE "flexbox\|yoga\|taffy\|layout_engine"` 在 `src/*.ts` 零命中；x/y/width/height 一律由用户代码写 |
| **焦点 / Tab 遍历** | **有，且对 `adl` 校准过** | `as_focus_obj`（永久 GC 根，`gc_mark_ptr` 于 `emit.ts:5686`）`src/emit.ts:10782`；`as_set_focus` `:10827`（focusOut/focusIn 冒泡 + 重启光标闪烁）；`as_tab_scan` `:10860` + `as_focus_tab` `:10881`（Tab/Shift+Tab 双向环绕、`tabEnabled` 过滤、无焦点时取首/末、keyUp 投给新焦点） |
| ↑ 但 Tab 序的**形态**受限 | **是** | ① 每次 Tab **从零重扫整棵树**（`as_tab_scan` 深度优先、记显示序数）；② 硬上限 **64 个可聚焦对象**，越限「Tab 就不再移动」（代码注释自述 `emit.ts:10857`；`tabs[64]` 与 cap 参数在 `:10884-10886`）；③ **无分组**（没有对话/模态内循环的概念）；④ `tabIndex` 只被初始化为 `-1`、不参与排序（`emit.ts:10548`），序就是显示列表前序 |
| **actions / keymap（可配置快捷键）** | **无** | 键盘只有 `SDL_KEYDOWN` → `keyCode` 直投事件（`vendor/window_glue.cc:1360`）；无 context、无绑定表、无用户自定义 |
| **触摸 / 手势** | **类有、输入没有** | `TouchEvent` 类完整（`src/emit.ts:11987-12018`，阶段九十三），但窗口后端**不转发任何触摸事件**（`grep FINGER\|TOUCH` 于 `window_glue.cc` 零命中），`Multitouch.maxTouchPoints` 恒 `0`（`:10333`） |
| **无障碍** | **无**（整个 `flash.accessibility` 包缺失） | `grep -rn "flash.accessibility\|AccessibilityProperties\|AccessibilityImplementation" src/*.ts` **零命中**；`grep -rin "accessibility" src/*.ts` 只命中一处无关注释（`src/emit.ts:26272` 讲可见性测试的 `ACCESSIBILITY` 标记）；`Keyboard.isAccessible`（`emit.ts:14848`）与 `SoundMixer.areSoundsInaccessible`（`:12981`）拼写不同、且都是单点实现，不构成 `flash.accessibility` 面 |
| **控件集** | **无** | 219 个 `examples/*.as` 中无 Button/Slider/List/ScrollBar/Tooltip 等；`lib/` 下也没有 `.as` 库（只有 ANE host 的 C/H） |
| IME/合成输入 | **有** | `SDL_TEXTEDITING` / `SDL_TEXTINPUT` → marked text 通道（`vendor/window_glue.cc:1421`/`:1440`），阶段一百三十五 |
| **窗口能力面** | **有**，面很宽 | `NativeWindow` 共 **43** 个成员（23 个 getter 属性 + 16 个实例方法 + 4 个静态常量，`src/symbols.ts:1783-1894`；另有 11 个 setter，与 getter 同名成对）：activate/minimize/maximize/restore/orderInFrontOf/globalToScreen/listOwnedWindows… |
| 与显示/交互/事件相关的示例 | **有 39 个**顶层 `.as`（另有 `textfield/`、`air-starling-demo/`、`shmup-stage3d/` 等 **12 个**子目录） | `examples/` |

**一句话概括家底**：L1/L2 的"重活"已经做完了，而且做得比 GPUI 更贴 AS3 语义（命中按绘制区域、
事件的捕获口径、烘焙的 1:1 像素口径、Tab 遍历都对着 `adl` 校准过）；**我们缺的正好是
L3 全部，加上 L2 的一处空白（自动布局）与两处形态欠账（Tab 序、快捷键）。**

---

## 4. 逐项裁决

> 本节括注里的 GPUI 源码位置均相对工作区 `asaotui/`；为简洁，重复出现的 `style.rs`/`element.rs` 等省略前缀，
> 全路径即 `gpui-src/crates/gpui/src/<file>`（子模块如 `app/context.rs` 亦然）。

### 4.1 值得**直接借**（概念与形态照搬，实现换 AS3）

| # | GPUI 的东西 | 为什么值得借 | 落到我们这边 |
|---|---|---|---|
| B1 | **声明式 `render()` 描述树**（`gpui-src/crates/gpui/src/element.rs:10-14`） | 消灭"手工 addChild/removeChild 时漏一处就内存/视觉泄漏"这一类 bug | AS3 侧 `render():Node`，节点树进 `asaot.ui` 命名空间 |
| B2 | **`Style` 扁平值表 + `refine` 继承**（`style.rs:180-322`，11 个 `#[refineable]` 字段驱动继承） | 主题/样式复用；避免 AIR 里"每个控件自己读一遍 theme 静态表" | `Style` 类 + `refine(parent)`；值的粒度与 `AbsoluteLength`/`Length`(auto) 三分法照抄 |
| B3 | **`prepaint` 这一趟（测量与暂存独立于绘制）**（`element.rs:84-95`） | 唯一能根治 Flash 式 measure/arrange 循环的结构性办法 | `measure()` → `arrange()` → `paint()` 三趟 |
| B4 | **瞬态状态与业务状态分离（`PrepaintState`）**（`element.rs:59`） | hover/滚动/按下态属于**控件**，不该塞进业务对象 | `ElementState` 表，按节点 key 存取 |
| B5 | **`notify()` 式最小粒度重绘信号**（`app/context.rs:221`） | 取代"dispatch 一个自定义事件，然后谁也不知道谁该重画" | `Observable` + 一个**集中的重绘调度器**，接到现有的 `WinCtx.dirty` |
| B6 | **actions + key context + JSON keymap**（`docs/key_dispatch.md`；`key_dispatch.rs` 2216 行 + `keymap.rs`/`keymap/` 共 2169 行） | 键盘映射变成**数据**：可运行时改、可随上下文切换、可给用户自定义 | `ActionRegistry` + context 串 + keymap JSON；这是迁移 AIR 应用时用户最能立刻感知的一条 |
| B7 | **Tab 序是一棵**可增量维护、**可分组**的树**（`TabStopMap`：`Insert`/`Group`/`GroupEnd` + `insertion_history` + `SumTree`，`tab_stop.rs:11-23`）** | 我们有 Tab 遍历，但它是**扁平、每次按键从零重扫、硬上限 64 个可聚焦对象、无分组**（见 §3）。真界面一旦超过 64 个可聚焦对象，Tab 就完全不工作；对话框内循环也无从做起 | 在现有 `as_focus_obj`/`as_focus_tab` 之上加一层 `FocusChain`：分组进出 push/pop，序表增量维护；`as_tab_scan` 的 64 上限当作**已知边界**重新评估（不是默默抬高） |
| B8 | **"GPU 只认图元表，不认元素树"的渲染 seam**（`scene.rs:222-230` 图元表 + `bounds_tree.rs` 空间索引） | 让控件层**后端无关**：Skia 一条、Stage3D 一条，同一份控件代码 | 三条 seam：`NodeTree` / `LayoutEngine` / `Renderer`（详见 §6） |

### 4.2 必须**改造后借**

| # | GPUI 的做法 | 为什么不能照搬 | 改造方案 |
|---|---|---|---|
| R1 | **每帧重建整棵树**（`element.rs:10-14`） | 见 §5：正面违反 GC 红线，且我们的树本来就是 retained | **keyed reconcile**：节点路径/key → 复用旧节点，只对变化部分改样式与重排 |
| R2 | **布局交给 Taffy（Rust）**（`taffy.rs:31` `TaffyLayoutEngine`） | 语言不对；但 flexbox 的语义复杂度是真的，**自研＝违反 AGENTS.md §0"不因困难而降级"** | 把布局引擎做成**不透明接缝**（同 `rust-text-backend.md` 的 15 函数 seam 先例）：先链 **Yoga**（C API、MIT、可编到 wasm），AS3 侧只认接缝，将来可整体替换 |
| R3 | **Rust 类型系统撑起 API 形状**（`IntoElement` / `impl Trait` / 所有权下的 `cx`；`element.rs:52` 的 `Element: IntoElement`） | AS3 没有这些；硬仿会得到一个别扭的 API | 用 AS3 的惯用法重写：接口 + 闭包 + vtable 动态派发；`render()` 返回 `Node` 而非泛型 |

### 4.3 明确**不借**

| # | GPUI 的东西 | 不借的理由 |
|---|---|---|
| N1 | 自研 GPU 渲染管线（Blade / Metal / D3D 后端 + 图元着色器） | 我们已有 Skia 与 Stage3D 两条，且 Stage3D 已是 AIR 对齐面（`Context3D.profile`、`#3683`/`#3684` 等都在表内）。第三条管线只会增加"两个渲染器口径不一致"的类别。**（本 `gpui-src` 检出只含 `crates/{gpui,gpui_macros,refineable,util}`，平台渲染后端不在其中；后端事实见 `gpui-src/crates/gpui/README.md:31`（macOS→Metal）与 `:43`（Windows→Win32/DirectWrite）。）** |
| N2 | `text_system.rs`（自研排版/字体图集/子像素抗锯齿；`text_system.rs` 1505 行 + `text_system/` 子模块） | 我们的 SkParagraph 路线是**逐值对 `adl` 校准**的（`skia.md` §8、`rust-text-backend.md` §9 已经算过换引擎的账：唯一算得过来的场景是"移动端 + 体积硬约束"）。UI 库绝不能为它引入第二套文本口径 |
| N3 | 热重载 / inspector / profiler（`hot_reload.rs` 248 行 / `inspector.rs` 271 行 / `profiler.rs` 2225 行≈80 KB，连同 `profiler/journal.rs` 3540 行、`profiler/hang.rs` 1865 行） | 诱人但属**开发工具**，与"给 AS3 用户一套控件"是两件事；等控件层稳住再谈 |
| N4 | `gestures.rs`（2331 行 / 约 96 KB 的捏合/旋转/双击/长按手势识别） | 它的**输入源我们根本没有**（窗口后端不转发触摸）。顺序必须是"先接输入"，不是"先写识别器" |

---

## 5. 最关键的一条判断：为什么不能照搬"每帧重建"

这是本次评估里唯一一个会**改变架构**的取舍，值得单独论证。

**GPUI 能每帧重建，是因为它跑在 Rust 上、树是一批便宜的结构体、退出作用域就整批归还。**
我们不行，理由是硬性的、写在 AGENTS.md 里的：

1. **GC 红线**：`gc_step()` 每帧只推进固定预算的标记/清扫切片（GC-4 增量），设计目标就是
   "单帧停顿 O(budget) 而非 O(堆)"；并且明文禁止**"在每帧/每循环的热路径里产生进 arena 的临时分配"**
   （先例是 `as_disp_key` 造成 ~39 KB/s 的静默泄漏，阶段五十六）。
   一个 200 节点的界面按 60 fps 重建，就是每秒 1.2 万个节点的对象 + 字符串 + 数组分配，
   每一轮都得进 GC 堆被标记、被清扫；而我们的 arena 是**只 bump 不归还**的（`as_alloc`），
   真正可回收的那条路（`gc_alloc`）又要吃增量标记预算。
2. **更关键的是：重建换不来任何东西。** 我们的显示树**本来就是 retained 的**，
   `DisplayObject` 指针本身就是稳定的节点身份；改一个属性只会改一个字段。
   在这种前提下，"重建 + 丢弃"比"对新旧描述做 diff"**更贵**——我们丢掉的正是白拿的身份。
3. **GPUI 的 immediate 一半解决的是 Rust 的问题**（状态在多处、要 dedupe、要省去手写更新代码），
   而我们的问题清单里根本没有这一条：AS3 用户手写 `addChild` 不是痛在"没声明式"，
   是痛在"没有布局、没有控件、快捷键不可配置"。

**结论**：借 immediate 的**写法**（`render()` 描述树），不借它的**执行方式**（每帧重建）。
落地成 **keyed reconciler**：

```as3
// 描述是声明式的，节点是 retained 的：key 相同就复用旧节点（连同它的 hover/滚动状态）
override public function render():Node {
  return box({ direction: "column", gap: 8, padding: 12 }, [
    text(this.title, { style: Style.body }),
    button("确定", { key: "ok", onClick: this.onOk }),
    list({ items: this.rows, itemKey: function (r:*):String { return r.id; } }),
  ]);
}
```

`key` 与 `index` 共同构成节点身份（`GlobalElementId` 的 AS3 版）：同一身份在本帧与上一帧之间
**复用同一个节点对象**，只有描述里**变化了的部分**才写回（改样式 → 标脏 → 只重排/重绘该子树）。
这样既拿到声明式的好处（B1），又不付每帧全量分配的代价（避开 §5 的红线）。

---

## 6. 建议形态：`asaot.ui` 与三条接缝

**命名空间是硬约束**：新 API 一律放**独立命名空间**（`asaot.ui.*`，不要碰 `flash.*`）。
AGENTS.md §1.5 要求"增强不得改写任何 AIR 已定义行为"，而 `flash.*` 是与 `adl` 逐值对齐的面；
把控件塞进 `flash.ui`/`flash.display` 会让"AIR 同构"这条底线失去可判定性。

三条接缝（都照 `rust-text-backend.md` 的"不透明接缝"先例）——但 **`LayoutEngine` 接缝画在 AS3 interface 层**，不是 C 函数层（理由见下表后的说明）：

```
        asaot.ui（纯 AS3 源码，由我们自己的编译器编译 —— dogfooding）
                │
   ┌────────────┼──────────────────────────────┐
   │            │                              │
NodeTree    LayoutEngine（AS3 interface）     Renderer 接缝
（retained    ├── As3LayoutEngine（纯 AS3 flexbox 子集，mxmlc→adl 可跑）
  + keyed     └── NativeLayoutEngine（内建类 → 30 个 as_ui_yg_* 不透明 C 接缝 → Yoga）
    reconcile）   两个实现同接口可换，注入点在 UiApp
                                    │
                                    └─ 不透明 C 接缝（30 个 as_ui_yg_*；仅 native 内建可见）
```

三条 seam 的项目内先例与理由（前两条是接缝，第三条是让接缝**不花钱**的开关机制）：

| 接缝 | 先例 | 为什么必须是接缝 |
|---|---|---|
| `LayoutEngine` | `docs/zh-cn/rust-text-backend.md` §1.1（文本 glue 的 15 函数不透明接缝） | 接缝画在 **AS3 interface 层**（`asaot.ui.LayoutEngine`，纯 `.as`）：控件层只依赖接口，于是**整个库（含布局）都能 mxmlc 编译、在 `adl` 上跑**，拿到「`.as` 源码 mxmlc→adl vs AOT→native 双端对照」这条最值钱的杠杆。两实现：`As3LayoutEngine`（纯 AS3 flexbox 子集，adl 侧）与 `NativeLayoutEngine`（内建，转发到内层 **30 个** `as_ui_yg_*` C 函数 → Yoga）。flexbox 的语义复杂度（内在尺寸、换行、百分比 vs auto、min/max、baseline）不值得自研；接口独立于引擎，将来可整体替换。**接缝比预期轻**（U1 前置测量已证）：Yoga 是 **19 个 `.cpp` + 一个 `-I <repo>`**、**无 CMake 生成步骤**（`CMakeLists` 只产出 `yogaConfig.cmake`，与头文件无关） |
| `Renderer` | 文本后端拆分 + `stage3d_*` 多后端 | 让同一份控件代码既能跑在 Skia（正确性、wasm 无 GPU 兜底）又能跑在 Stage3D（性能）；不这样做就必然被锁死在一条路上 |
| 构建清单开关 | `swc-paths` / `sqlite` 条件链接（引用才链） + `--features` | 不用 UI 的构建必须**零成本**：这是本项目对体积的一贯态度（`size-optimization.md`、`rust-text-backend.md` §3/§10 的 19.43 MB → 6.05 MB） |

**为什么把接缝画在 AS3 interface 层（而不是 C 函数层）**：AS3 **目前没有 FFI**
（`enhancements.md` E11 未排期），纯 AS3 源调不到 C 函数 ⇒ 原生实现只能做成「**内建类
implements 纯 AS3 接口**」。而一旦接口是纯 `.as`，控件层就只依赖接口 ⇒ **整个库（含布局）
都能用 `mxmlc` 编译并在 `adl` 上跑**，从而拿到「同一份 `.as` 源码，`mxmlc`→`adl` 与我们的
AOT→native 双端逐值对照」这个最值钱的验收杠杆。内层那条 C 接缝（`as_ui_yg_*`）仍在，
但它从「AS3 可见的接缝」降级为 `NativeLayoutEngine` 的实现细节。契约骨架见 `asaotui/seam/`。

**关键取舍（如实写）**：
- **AIR 里根本没有 flexbox 概念** ⇒ 布局层的验收基准**不是 `adl`**，而是 **W3C flexbox 规范 /
  浏览器**（Yoga 就是按 web 标准实现的）。这不违反 AGENTS.md §1.5：布局属**增强**（AIR 无对应物），
  增强本来就没有 AIR 参照物。`adl` 只用来验 AS3 编排层与 `As3LayoutEngine` 子集的 AS3 语义。
- **代价**：要多维护**一份纯 AS3 flexbox**（子集），且两套实现有 **drift 风险** ⇒ 必须
  **差分测试**：同一份输入，两引擎的每个矩形**逐项相等**（容差 `EPS=0.01`），否则红。
- **前置依赖（已关闭）**：整个 native 路径的前提「**内建类 implements 用户 `.as` 接口**」这条新模式
  **2026-10-22 已实测成立**（正例 `x=120`/`is` 为真；反证报 `does not implement method 'bogus' of
  interface 'probe_ISizable'`。证据与确切命令见
  [`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md)）。
  回退方案（「内建静态方法 + 只在 AOT 编译的 AS3 适配器」，最后手段回到 C 函数接缝 + 内建类直发，
  见 `u1-implementation-plan.md` §4）**不再需要，仅备查**。

---

## 7. 分阶段提案（编号待定，顺延当前路线图末尾之后）

> 编号以 `TODO.md` 末尾小节为准（本仓库 `TODO.md` 最后一个阶段节为**阶段二百三十一**，`v0.4.202 → v0.4.203`；已核查 `阶段二百三十二` 及以上在 `TODO.md` 里**零命中**）。**但 `git log` 已含二百三十二~二百三十七的提交（写本节时 HEAD 为 `f688094`，且仍在推进）**，即 `TODO.md` 落后于提交序列；U1 的编号与版本号须在在途系列归位后复核（见 [`u1-implementation-plan.md`](u1-implementation-plan.md) §1）。
> 每阶段的验收标准一律按 AGENTS.md §2.7：**一个 `examples/*.as` 示例 + 断言式回归**；
> 单元组钉在 `test/unit/`（负例与结构不变量只能钉那里），端到端钉在 `test/examples.ts`。

| 阶段 | 内容 | 关键决策 | 验收物 |
|---|---|---|---|
| **U1 布局底座** | `asaot.ui.LayoutEngine`（**纯 AS3 interface**）+ **已实现**的纯 AS3 实现 `As3LayoutEngine`（flexbox 子集）；**三端逐值一致**：自家 AOT / Yoga(C，差分对手) / AIR。*native 内建类 → Yoga 为**已搁置**的备查选项（见 [`compiler-gaps.md`](compiler-gaps.md)）* | **纯 AS3 已实现并验收**；native 前置测量为 **Go（条件）**（native 增量 ≈ **92 KiB**、wasm ≈ **120 KiB**，commit pin `843dba8`），但需改编译器⇒搁置 | [`layout-check/`](layout-check/)（自家 AOT 16/16）+ [`diff-check/`](diff-check/)（同一份规格喂 Yoga 与 AS3）+ [`air-check/`](air-check/)（`mxmlc`→`adl` 16/16）；基准是 W3C flexbox/浏览器（AIR 无 flexbox） |
| **U2 元素身份 + 状态提升** | keyed reconciler、`ElementState` 表、`measure/arrange/paint` 三趟 | 复用而非重建；未变化子树**指针级复用** | `unit: ui/reconcile` 钉在**发射出的 C** 上：两帧同描述不产生新节点、改一个属性只重排该子树 |
| **U3 数据流与重绘调度** | `Observable` + `notify()`，挂到现有 `WinCtx.dirty` | 不得绕开窗口后端的 dirty 语义（它是"只重绘 dirty 窗口"的唯一入口） | `examples/ui-notify.as`：改一个字段只触发一次重绘；无变化帧**零重绘** |
| **U4 基础控件** | `Box`/`Text`/`Button`/`Image`/`ScrollView`/`List`（虚拟化）/`Checkbox`/`Radio`/`TextField` 包装 | 每个控件必须**声明 role/name/value**（为将来的 a11y 留出形状）；`TextField` 必须包在现有 SkParagraph 通道外，**不得**新开文本口径 | 每个控件一个示例；虚拟化列表钉"只实例化可见项" |
| **U5 键盘优先与焦点形态** | `ActionRegistry` + key context + keymap JSON；`FocusChain`（分组、模态内循环）；重新评估 `as_tab_scan` 的 **64 个可聚焦对象上限** | **不重建焦点模型**：复用现有 `as_focus_obj`/`as_focus_tab` 与它的 `adl` 口径，只换「序怎么来、谁在链上」；上限一旦放开，先测 `adl` 在 >64 个 tabbable 下的行为再定口径（不得凭直觉） | `examples/ui-keymap.as`：同一 action 在两个 context 下绑定不同键；Tab 在模态内循环且不逃逸；>64 个 tabbable 时 Tab 仍可达 |
| **U6 AIR 基线补齐：`flash.accessibility.*`** | `Accessibility` / `AccessibilityProperties` / `AccessibilityImplementation` / `ISearchableText` / `ISimpleTextSelection` | 这是 **AIR 有、我们没有** ⇒ 属**遗留欠账**（不是增强）；已登记在 [`compiler-gaps.md`](compiler-gaps.md) **G2**（按用户 2026-10-22 指示不直接改编译器）；若要立项才进 `遗留待开发` 表；先对齐 API 与语义，**平台 bridge（Windows UIA / macOS NSAccessibility）单独立项** | 按 `adl` 逐值对照的 API 形状 + 单元组；bridge 未做时**响亮报明**，不静默假装有 |
| **U7（可选）真应用验收** | 用 `asaot.ui` 重做一个真界面（如 talkmed-meeting 的登录页） | dogfooding 是这套库唯一的真实验收：它同时压 AS3 子集、文本、事件、GC | 与 `adl` 双端对照记录 |

**U1 的前置测量：已完成（2026-10-22），结论 Go（条件）**——全文见 [`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md)。

- **体积**：Yoga pin = commit `843dba8619420992e492bbb4b3d2f63d9ad6c683`（`main`，晚于最新 tag `v3.2.1`）。在最优配置（`-Oz -DNDEBUG -ffunction-sections -fdata-sections -fno-exceptions`）下，**链接后增量** native **≈ 92.0 KiB（94,208 B）**、wasm（emcc 3.1.44）**≈ 120.3 KiB（123,180 B）**——相对本项目 MB 量级的 GUI 构建（画字 6.05 MB）是**零头**。
- **它不是风险**：主文档 §8 曾把"体积"列为首条风险，实测**推翻了该假设**（precheck §7 表首行）。
- **wasm 可编性**：emscripten（`--package web` 后端）**零错误编过并链接**；严格 `clang --target=wasm32-wasip1` **本机无 sysroot 不可测**。
- **DCE 相容性**：COFF 对应物是 `-ffunction-sections -fdata-sections` + `/OPT:REF`（`-Wl,--gc-sections` 被 `lld-link` 静默忽略），**实测可剪**未引用 Yoga；macOS `-Wl,-dead_strip` **本机不可测**。
- **两个 CI 阻塞项（本机不可测，待 CI 验；任一红即退 AS3 子集，子集边界见 precheck §6.4）**：① `WASI_SDK_HOME` 就绪的 CI 上 `clang --target=wasm32-wasip1` 编 + 链 Yoga 成功且增量 ≤ 192 KiB；② macOS arm64 上 `-Wl,-dead_strip` 下 `yoga_one` 明显小于 `yoga_min`。
- **两条被修正的旧口径**：接缝**不需要 CMake / 任何生成步骤**（19 个 `.cpp` + 一个 `-I`）；`-DYG_NDEBUG` 是**空开关**（源码零引用），关断言只靠 `-DNDEBUG`。
- **一条新风险（主文档旧版未提）**：`__EMSCRIPTEN__` 下 `YG_EXPORT` 带 `__attribute__((used))` ⇒ `--package web` 侧 Yoga 公 C API 被强保留/强导出，wasm DCE 弱于 native（见 §8 风险表）。

---

## 8. 成本、风险与护栏

| 风险 | 具体形态 | 护栏 |
|---|---|---|
| **体积**（**已量证：零头级，< 3%**） | ~~Yoga + 控件层进二进制是风险~~ ⇒ **实测推翻**：完整 flexbox+grid 引擎增量 native **92 KiB** / wasm **120 KiB**（commit pin `843dba8`，见 [`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md) §3.2/§3.3），对 MB 级 GUI 构建 < 3%。**但这道硬门必须保留**： | **不用 UI 的构建必须零增量**——清单开关 + 引用才链（同 sqlite / 文本 glue 的 `usesFlashData`/`usesTextEngine`），`-O2`/`-dead_strip` 从 `main` 出发剪掉未引用 Yoga（COFF 实测可剪；macOS 待 CI）；超预算就退 AS3 子集实现 |
| **`__EMSCRIPTEN__` 下 `used` 削弱 web 侧 DCE**（**新风险，旧版未提**） | emcc 路径（`--package web`）定义 `__EMSCRIPTEN__`，其间 `yoga/YGMacros.h` 的 `YG_EXPORT` = `__attribute__((visibility("default"), used))` ⇒ Yoga 公 C API 被 `used` **强保留并进导出表**（实测 `wasm_yoga_min.wasm` 导出表挂满 `YGNodeStyleSet*`），DCE 弱于 native；`-sEXPORTED_FUNCTIONS` 限流**不能**阻止（把导出限成 `_start` 后产物反而更大，YG 符号仍在）。native / `--target wasm32-wasip1`（clang，无 `__EMSCRIPTEN__`）**无此问题**。 | 已在 §7 的 wasm 增量（120 KiB）里**计入**；U1 实施时二选一：接受该体积，或在粘合层编译 Yoga 时**抑制 `used`**（本地 `YG_EXPORT` 覆盖 / `-fvisibility` 组合）——属实施细节，见 [`u1-implementation-plan.md`](u1-implementation-plan.md) §3。 |
| **两个 CI 阻塞项未验**（**新风险，旧版未提**） | 严格 wasip1 编链（本机无 WASI sysroot，且 `src/build.ts:1322` 目前**对 `--target wasm` 的 C++ 源直接 throw**）与 macOS `-Wl,-dead_strip`（本机无 ld64）**本机均不可测**，只能待 CI（arm64 macOS）。**不臆造 CI 结果。** | 把两项设为**落地前的 CI 预检**：任一红即退 AS3 侧 flexbox 子集（边界见 precheck §6.4）；沿用 `u1-implementation-plan.md` §4 的回退路径（接缝 API 与示例可保留，只换引擎实现） |
| **双 UI 栈的维护面** | `flash.display`（AIR 对齐，必须逐值不动）+ `asaot.ui`（新）常年并存 | 命名空间隔离；控件层**只调用** display 的公开行为，不新增/改写 `flash.*` 语义 |
| **布局语义的正确性** | flexbox 边界（百分比 + auto、min-content、wrap + gap、baseline）容易"看着对"；且 **AIR 无 flexbox 概念**，布局**没有 `adl` 参照物** | 用引擎而不是自研（native 走 Yoga，R2）；AS3 侧只认接口；**基准是 W3C flexbox / 浏览器**（不是 `adl`）；两实现差分测试一致 |
| **两套布局实现的 drift**（**新风险**） | 纯 AS3 子集与 Yoga 是**两套**实现，边界（百分比、gap、auto、min/max）会分岔 ⇒ 同一输入两引擎给出不同矩形 | **差分测试是硬要求**：native 构建里同时挂两实现，同输入逐项比对（`EPS=0.01`），红则修；见 `seam/README.md` §3.2 |
| **内建类 implements 用户 `.as` 接口** | native 路径前提：`NativeLayoutEngine` 要 `implements:['asaot_ui_LayoutEngine']`，引用用户接口 `asaot.ui.LayoutEngine`——机制可通（接口 vtable 与一致性检查都遍历含内建类的全表），且**无先例** | **2026-10-22 已实测通过**（正例 `x=120`/`is` 真、反证 `does not implement`；见 [`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md)）⇒ 架构**无需回退**；§4 的回退方案仅备查；**不静默** |
| **GC 与帧预算** | 任何"每帧分配"都会把增量 GC 的预算吃光 | U2 的复用是**硬要求**，不是优化；`unit: ui/reconcile` 把"同描述不产生新节点"钉成不变量 |
| **无障碍是深水区** | AccessKit 在 Rust 侧一行依赖搞定；我们两侧是 Windows UIA 与 macOS NSAccessibility 两套模型，且 **AIR 自己这块也很弱** | **先做 U6 的 AIR 基线**（API 形状与语义），平台 bridge 单独立项、未做时响亮报明 |
| **不要变成"再造一个 Feathers"** | 控件是无底洞（Feathers/Starling 的量级是年计） | 控件集**只做被真实界面用到的那些**；U7 的真应用决定取舍，不做"通用控件集" |
| **触摸输入缺位** | 控件层的滚动/拖拽在触摸设备上无从谈起 | 明确把"窗口后端转发触摸事件"列为 U4/U5 的**输入前置**，而不是先进手势识别 |

---

## 9. 明确不做（防止范围蔓延）

- 不做新的 GPU 渲染管线（N1）；不换文本引擎（N2）。
- 不做热重载 / inspector / profiler（N3）；不做手势识别（N4，输入源都没有）。
- 不把控件层塞进 `flash.*`；不因为"方便"改动任何 AIR 已定义行为。
- 不做"通用控件集"，只做真实界面用到的控件。
- 本评估已在 `TODO.md` 末尾追加一段「UI 工具链待定项（未排期）」（`TODO.md:14086` 起，紧接 `### 增强待做` 之后）：**不占阶段号、不升版本**；只有进入实施才占阶段号、才升版本。
  （注：该段自身也抄录了本文修正前的 `src/emit.ts:10850` 旧行号与 `grep accessibility` 旧写法，**`as3compiler/TODO.md` 不在本次修正范围内**，以本文 §3 的实测值为准。）

---

## 10. 参考

- GPUI 官网 <https://gpui.rs/>；本地检出 `asaotui/gpui-src/`（`zed-industries/zed`，`main`@`54478042`，nightly）的
  `crates/gpui/`：`README.md:3`（自称 `hybrid immediate and retained`）、
  `src/element.rs`（`Element` 四趟 `:52-105`、元素树丢弃语义 `:10-14`、`Drawable`/`ElementDrawPhase` `:315-348`）、
  `src/taffy.rs`（布局接缝 `:31`/`:62`/`:187`/`:345`/`:439`）、`src/style.rs`（`Style` 值表 `:180-322` 与 refine）、
  `src/scene.rs`（图元表 `:222-230` 与分段 `:478-495`）、`src/bounds_tree.rs`（空间索引）、
  `src/tab_stop.rs`（Tab 序 `:11-23`）、`src/_accessibility.rs`（AccessKit `:15`）、
  `src/_ownership_and_data_flow.rs` 与 `docs/contexts.md`（entity/notify；`src/app/context.rs:221` 的 `notify`）、
  `docs/key_dispatch.md`（actions + keymap）、`src/key_dispatch.rs` 2216 行 / `src/keymap.rs` 1135 行。
  （注：本地检出只含 `crates/{gpui,gpui_macros,refineable,util}`，平台渲染后端不在内。）
- 本仓库相关文档：[`skia.md`](as3compiler/docs/zh-cn/skia.md)（渲染后端与 1:1 像素口径）、
  [`rust-text-backend.md`](as3compiler/docs/zh-cn/rust-text-backend.md)（不透明接缝与体积两刀的先例）、
  [`flash-text.md`](as3compiler/docs/zh-cn/flash-text.md)（文本度量与 `autoSize`）、
  [`gc.md`](as3compiler/docs/zh-cn/gc.md)（增量标记与写屏障、每帧安全点）、
  [`size-optimization.md`](as3compiler/docs/zh-cn/size-optimization.md)（体积手段）、
  [`enhancements.md`](as3compiler/docs/zh-cn/enhancements.md)（增强的判定标准与具名开关）。
- AIR 参考（`flash.accessibility` 的 API 形状）：<https://airsdk.dev/reference/actionscript/3.0/flash/accessibility/package-detail.html>
- Yoga（C API 的 flexbox 实现，U1 候选）：<https://github.com/facebook/yoga>
