# `asaot.ui` 的 AS3 侧 API 设计草案（L3 作者模型）

> **一句话定位**：给 `as3compiler` 配一套 AS3 原生的声明式 UI 控件层——**借 GPUI 的作者模型，
> 不借它的「每帧重建整棵树」**——所有新 API 落在独立命名空间 `asaot.ui.*`，复用现有
> `flash.display` 显示树、Skia 渲染、SkParagraph 文本、`as_focus_*` 焦点与 `WinCtx.dirty` 重绘。
>
> **状态：草案（未实施、不占阶段号、不升版本）**。本文只定义 AS3 侧的**形状与语义**，不落实现；
> 对应主文档 [`ui-toolkit-feasibility.md`](ui-toolkit-feasibility.md) §7 的 **U2~U5** 四个阶段。
> 与主文档冲突处以主文档为准，逐条列在 **§11**。`as3compiler/` 全树只读，本文未改其任何文件。
>
> **实施路径（2026-10-22 口径）**：UI 库走**纯 AS3**；需改主机编译器的 native 路径（内联 Yoga）**已搁置**。
> 本文中凡涉及 `NativeLayoutEngine` / `as_ui_yg_*` 的描述均按「**备查选项**」阅读；
> 做库时撞到的编译器缺口登记在 [`compiler-gaps.md`](compiler-gaps.md)。
>
> **取证口径**：本文每个断言要么引 `as3compiler/` 源码位置，要么引 GPUI 检出位置
> （`asaotui/gpui-src/crates/gpui/src/<file>`，下同，短引用省略前缀），要么标「待 `adl` 实测」。
> 未实测的断言不写成结论。

---

## §0 范围、命名空间与三条接缝

### 0.1 本文覆盖什么

| 主文档 U | 内容 | 本文对应节 |
|---|---|---|
| **U2** | 元素身份 + keyed reconcile + `ElementState` + 三趟管线 | §1、§3 |
| **U3** | `Observable`/`notify()` 接到 `WinCtx.dirty` | §5 |
| **U4** | 基础控件集 + role/name/value + `TextField` 包装 | §4 |
| **U5** | `ActionRegistry` + key context + keymap JSON + `FocusChain` | §6 |
| 贯穿 | Style 值表与继承 | §2 |
| 贯穿 | 内存预算（硬要求） | §7 |
| 收尾 | 完整示例 / `flash.*` 边界 / 未决问题 | §8、§9、§10 |

### 0.2 命名空间硬约束

新 API **一律**在 `asaot.ui.*`（本文只写该命名空间）。**不写 `flash.*`、不改 `flash.*` 任何已定义行为**。
理由见主文档 §6：`flash.*` 是与 `adl` 逐值对齐的面，AGENTS.md §1.5「增强不得改写任何 AIR 已定义行为」；
把控件塞进 `flash.ui`/`flash.display` 会让「AIR 同构」这条底线失去可判定性。

### 0.3 三条接缝（与主文档 §6 一致）

```
             asaot.ui（纯 AS3 源码，由我们自己的编译器编译 —— dogfooding）
                     │
   ┌─────────────────┼──────────────────────────────┐
   │                 │                              │
NodeTree    LayoutEngine（AS3 interface）       Renderer 接缝
（retained    ├── As3LayoutEngine（纯 AS3 flexbox （NodeTree → 画）
  + keyed     │     子集，mxmlc→adl 可跑）            ├── DisplayListRenderer → 复用 as_render_object → Skia
  reconcile） └── NativeLayoutEngine（内建类 →      └── Stage3DRenderer      → GPU（后续）
                    30 个 as_ui_yg_* C 接缝 → Yoga）
```

本文所有 API 都显式标注它落在**哪条接缝**、对照 GPUI 的哪一处。`LayoutEngine` 接缝**画在 AS3 interface 层**：
`asaot.ui.LayoutEngine` 是**纯 `.as` 接口**，两条实现（纯 AS3 子集 + 内建类 → Yoga）由 `UiApp` 注入；
接口是纯 `.as` ⇒ 整库 `mxmlc`→`adl` 可跑。接缝形状与主文档 §6 一致，本文只补 AS3 侧该长什么样；
契约骨架见 [`seam/`](seam/)。

---

## §1 作者模型

### 1.1 `Node`：描述节点，不是显示对象

`render()` 返回的是一棵 **`Node` 描述树**——纯数据，可能是短命的（只在一次 describe 趟内存活）。
它和 retained 的 `UiNode`（内部实现，§1.3）是两回事：

- **`Node`（作者可见）**：`kind` + `key` + 样式增量 + 子节点 + 控件参数。描述「这一帧应该长什么样」。
- **`UiNode`（framework 私有）**：一个 retained 结构，持有 **1 个 backing `DisplayObject`**（§4.1）、
  已解析样式、瞬态状态（§3.2）、子节点索引表。描述「现在实际是什么」。

契约（作者必须遵守，framework 会做调试期断言）：

```as3
package asaot.ui
{
    public class Node
    {
        public var kind:String;              // 判别标签，与控件工厂一一对应
        public var key:Object;               // 显式身份：String | int；null = 用兄弟序号
        public var style:StyleRefinement;    // 局部样式增量（partial），null = 不覆盖
        public var keyContext:String;        // 键盘上下文串（§6.2），可空
        public var children:Vector.<Node>;   // 容器节点才有；叶子为 null

        // 说明：Node 子类只增加「控件参数」字段（value/onClick/placeholder…），
        // 不增加生命周期钩子。钩子全部在 UiNode 侧（§3）。
    }
}
```

```as3
package asaot.ui
{
    // View = 一帧描述一次的根；继承 Observable 才有 notify（§5.1）
    public class View extends Observable
    {
        // 唯一需要作者实现的入口
        public function render():Node;

        // 数据流接缝：把「我脏了」告诉调度器（不是直接重绘）
        protected function invalidate(dirty:int):void;

        // 由 UiApp.mount() 调用；对应 GPUI 的窗口根 View
        public function mount(stage:flash.display.Stage):void;
    }
}
```

**`render()` 的语义**（对齐 GPUI `element.rs:164-166` 的 `Render::render`）：

1. **纯描述，无副作用**：不得 `addChild`、不得改业务状态、不得依赖求值顺序。
2. **每帧最多跑一次，且只在脏时跑**（这是与 GPUI 最大的分歧，见 §1.3 与本仓主文档 §5）。
3. **返回值不得被作者保存**：`Node` 是 describe 趟内的一次性数据。
4. 作者拿不到 `UiNode` 指针，也就无法绕过 reconcile 去动 retained 树。

对照：GPUI 的 `Render::render(&mut self, window, cx) -> impl IntoElement`（`element.rs:164-166`）与
`RenderOnce::render(self, ...)`（`element.rs:180`）；GPUI 每帧递归重建整棵树，`element.rs:10-14`
原文「Before the start of the next frame, the entire element tree and any callbacks they have registered
with GPUI are dropped and the process repeats.」本文把「描述」保留、把「每帧重建」换成「脏时 describe + reconcile」。

### 1.2 节点身份：`key` / 兄弟序号 / 嵌套路径

**身份元组**（一个节点相对父的稳定身份）：

```
identity(node) = (parentIdentity, kind, part)
part = (node.key != null) ? ("key", node.key) : ("ix", siblingIndex)
```

- `parentIdentity` 递归到根（根的身份是 `View` 实例指针）。
- `siblingIndex` 是它在父 `children` 里的**显示序号**（从 0 起，数所有兄弟，不区分 kind）。
- `kind` 参与身份，保证「同一位置的同一个控件」不会和「换个类型的控件」复用同一节点。

因为身份是沿着树走的**元组**而不是拼接字符串，**热路径上不构造任何 key 字符串、不做任何 hash**。
路径字符串只在 a11y / 调试时才按需拼（见 §1.2 末）。

**规则（决定「复用」还是「换节点」）**：

| 场景 | 结果 |
|---|---|
| 同一父下 `key` 不变、`kind` 不变 | **复用同一 `UiNode`**（连同 hover/滚动/焦点/测量缓存一起活着） |
| `key` 变了（列表里换了数据项） | 旧 `UiNode` 销毁（其 backing `DisplayObject` removeChild），新建 |
| 同 `key` 但 `kind` 变了 | 销毁重建 |
| 无 `key`、同序号、同 kind | 复用——但**重排/中间插入会让后续兄弟全部错位**，见下 |
| 同一父下两个子节点 `key` 相同 | **硬错误**（`CodegenError` 级：`duplicate key "x" under parent "…"`），不是静默覆盖 |
| 旧树有、新树没有 | 销毁整个子树 |

**必须显式 `key` 的情形**（写进文档与调试期断言）：

- 列表/表格的每一项（`key = itemKey(item)`），否则数据项一换，状态会「粘」在错误的行上。
- 任何会发生重排（reorder）、中间插入、中间删除的兄弟序列。

**与 GPUI `GlobalElementId` 的异同**：

| 维度 | GPUI `GlobalElementId`（`element.rs:220`） | 本文 `identity` |
|---|---|---|
| 构造 | `Arc<[ElementId]>` + 逐前缀折叠的 `hash`（`extend_path_hash`，`element.rs:231`） | 树上的元组 `(父指针, kind, key/ix)`；不构造路径、不 hash |
| 作用 | 作为**帧外 state map 的 key**（`window.with_element_state`），元素树每帧丢弃后按 id 找回状态 | 作为**retained 子节点索引表的 key**（父 `UiNode` 上的 `key→child` 小表），状态就存在节点自身字段里 |
| 来源域 | `ElementId` 有 10 个变体（`window.rs:7635`：`View/Integer/Name/Uuid/FocusHandle/NamedInteger/Path/CodeLocation/NamedChild/OpaqueId`） | 只需要两种：字符串与整数（外加控件 kind） |
| 必需性 | 只有需要跨帧状态的元素才实现 `id()`（`element.rs:66`） | **每个 `Node` 都有身份**（没 key 就用序号） |
| 唯一性域 | 「在第一个带 id 的祖先元素内唯一」（`element.rs:65`） | 同一父下唯一（按 `kind` + part） |
| 路径物化 | `Display` 用 `.` 连接（`element.rs:283`） | 只在 a11y/debug 时懒拼，不进热路径 |

一句话：**GPUI 用「路径哈希」去外部的状态表里查；我们用「树上的父子关系」直接定位 retained 节点，
指针本身就是身份。** 这正是本项目显示树本来 retained、可以白拿身份的体现（主文档 §5 第 2 点）。

### 1.3 复用规则与 reconcile 伪算法

**`UiNode` 的内部形状**（framework 私有，作者不可见）：

```as3
// framework 内部；不是作者 API
class UiNode
{
    var kind:String;
    var key:Object;              // 本节点的 part
    var backing:flash.display.DisplayObject;   // 1 个顶层锚点（§4.1）

    var resolved:Style;          // 已解析样式，节点内写就的 buffer（§2.4）
    var lastStyle:StyleRefinement;             // 上一趟的 partial 指针，用于跳过
    var lastStyleStale:Boolean;

    var state:ElementState;      // 瞬态态（§3.2），值类型内联
    var childrenByKey:Object;    // key(规范化字符串或序号) -> UiNode
    var childOrder:Vector.<UiNode>;

    var parent:UiNode;
    var dirty:int;               // 位图：M_MEASURE / M_ARRANGE / M_PAINT（§3.3）
    var a11y:A11yInfo;           // §4.3
}
```

**reconcile 伪算法**（每一趟 describe 之后跑一次；稳态帧整段跳过，见 §5.3）：

```text
function reconcile(old:UiNode, node:Node, parent:UiNode) -> UiNode:
    # 1) 同型判定：kind 变了就整棵换掉
    if old == null or old.kind != node.kind:
        n = allocateNode(node.kind)          # 分配（仅结构变化）
        n.backing = createBacking(node.kind) # new Sprite()/Shape/TextField（§4.1）
        parent.backing.addChild(n.backing)   # 走现有 addChild（它自己带 gc_write_barrier_value）
        if old != null: destroySubtree(old)  # 旧子树 removeChild + 脱离 GC 根
        old = n
    else:
        n = old                              # ★ 指针级复用：状态、缓存、焦点全留着

    # 2) 样式：指针身份比较，未变则一次 refine 都不做（§2.4）
    if n.lastStyle !== node.style or n.lastStyleStale:
        resolveStyleInto(n.resolved, n.kind, parent.resolved, node.style)   # 写就，不分配
        n.dirty |= styleDirtyMask(n.lastStyle, node.style)                  # §3.3 的传播表
        n.lastStyle = node.style
        n.lastStyleStale = false

    # 3) 子节点：keyed diff
    next = new Map()                          # 复用旧 map 的容量；稳态帧不进来
    for i, child in node.children:
        k = child.key != null ? tag("key", child.key) : tag("ix", i)
        hit = n.childrenByKey.remove(k)       # 同位置同身份 → 命中旧节点
        c = reconcile(hit, child, n)
        if parentSet(c.parent) != n: reparent(c, n)   # 只在需要时
        next.put(k, c)
    for leftover in n.childrenByKey.values(): # 新树里没再出现
        destroySubtree(leftover)              # removeChild + 断开所有引用
    n.childrenByKey = next
    n.childOrder = 顺序与 node.children 对齐   # 只重排 backing 的显示序，不重建对象

    return n


function destroySubtree(n):
    for c in n.childOrder: destroySubtree(c)
    n.parent.backing.removeChild(n.backing)   # 走现有事件语义（REMOVED/REMOVED_FROM_STAGE）
    n.backing = null
    n.childrenByKey = null
    n.childOrder = null
```

要点：

1. **稳态零重建**：同一份描述再来一次，`old.kind == node.kind`、`n.lastStyle === node.style`、
   `childrenByKey` 每个 key 都命中——整段只有几次查表，**不分配、不 removeChild**。
2. **指针级复用**：`UiNode` 指针不变，`state`（hover/滚动/测量缓存）和焦点（backing 对象的
   `tabEnabled`/`as_focus_obj`）全部原样保留。这避免了主文档 §5 点名的「每秒 1.2 万个节点」。
3. **`addChild` 的既有语义必须保留**：`DisplayObjectContainer_addChild`（`src/emit.ts:10607`）
   会做隐式 reparent、派发 `removed`/`added`/`removedFromStage`/`addedToStage`。我们不另写挂树逻辑，
   所以 AIR 的显示列表事件语义自动不变。
4. **顺序调整用 `addChildAt`**（`src/emit.ts:10629` 起，带 `gc_write_barrier_value`），不重建对象。

---

## §2 Style

### 2.1 `Style` 值表：分组

对照 GPUI `Style`（`style.rs:180-322`，实测 **38 个 `pub` 字段**）。AS3 侧同构裁剪，按内聚分四组：

```as3
package asaot.ui.style
{
    public class Style
    {
        // ---- 布局（Layout）----
        public var display:String;          // "flex" | "block" | "grid" | "none"
        public var position:String;         // "relative" | "absolute"
        public var inset:Edges;             // top/right/bottom/left : Length
        public var size:Size;               // width/height : Length
        public var minSize:Size;            // : Length
        public var maxSize:Size;            // : Length
        public var aspectRatio:Number;      // NaN = 未设
        public var alignItems:String;
        public var alignSelf:String;
        public var alignContent:String;
        public var justifyContent:String;
        public var flexDirection:String;    // "row" | "column" | "rowReverse" | "columnReverse"
        public var flexWrap:String;         // "noWrap" | "wrap" | "wrapReverse"
        public var flexBasis:Length;
        public var flexGrow:Number;
        public var flexShrink:Number;
        public var gap:Size;                // gapX / gapY : DefiniteLength
        public var gridCols:GridTemplate;   // 可选
        public var gridRows:GridTemplate;
        public var gridLocation:GridLocation;

        // ---- 盒模型（Box）----
        public var margin:Edges;            // : Length
        public var padding:Edges;           // : DefiniteLength
        public var borderWidths:Edges;      // : AbsoluteLength
        public var overflowX:String;        // "visible" | "clip" | "hidden" | "scroll"
        public var overflowY:String;
        public var scrollbarWidth:AbsoluteLength;

        // ---- 装饰（Decoration）----
        public var background:Fill;         // 实色 / 渐变（先只做实色）
        public var borderColor:uint;        // 0xAARRGGBB
        public var borderStyle:String;      // "solid" | "dashed"
        public var cornerRadii:Corners;     // : AbsoluteLength
        public var boxShadow:Vector.<BoxShadow>;
        public var opacity:Number;          // NaN = 未设

        // ---- 文本与交互（Text & Interaction）----
        public var text:TextStyle;          // 见下：唯一参与「继承」的一组
        public var mouseCursor:String;      // "default" | "hand" | "text" | …
        public var visibility:String;       // "visible" | "hidden"

        // 关键操作（§2.3）
        public function refine(parent:Style):Style;
    }
}
```

`TextStyle`（GPUI `TextStyle`，`style.rs:438` 起）：`fontFamily` / `fontSize:AbsoluteLength` /
`fontWeight` / `fontStyle` / `color` / `leading:DefiniteLength` / `letterSpacing` / `textAlign` /
`whiteSpace` / `textOverflow` / `lineClamp`。

> **不引入的东西**：`debug`/`debug_below` 是 GPUI 的调试字段，不进 AS3 公共面；
> `allow_concurrent_scroll` / `restrict_scroll_to_axis` 依赖触摸输入（窗口后端目前不转发触摸，
> 见主文档 §3），先不暴露，等输入源到位再加。

### 2.2 长度三分法（严格对齐 GPUI `geometry.rs`）

```as3
final class AbsoluteLength { }   // Pixels(px) | Rems(rem)          —— geometry.rs:3310
final class DefiniteLength { }   // Absolute(AbsoluteLength) | Fraction(f)  —— :3472
final class Length { }           // Definite(DefiniteLength) | Auto         —— :3623
```

- `AbsoluteLength`：与父字号无关的绝对量（字体大小、边框宽、圆角、滚动条宽）。
- `DefiniteLength`：可以是绝对量，也可以是**父尺寸的比例**（`Fraction`，0..1，**不是 0..100 的百分比**）。
  用于 `padding`/`gap`/`lineHeight`——与 GPUI 一致。
- `Length`：`Definite` 或 `Auto`（由内容/上下文决定）。用于 `size`/`min`/`max`/`margin`/`inset`/`flexBasis`。

辅助构造：`px(n)`、`rem(n)`、`pct(f)`（=`DefiniteLength.Fraction`）、`auto`、`edges(t,r,b,l)`。
逻辑单位与设备像素的换算链复用现有 `ASC_render_scale` / `as_bake_scale`（`src/emit.ts:21797`），
**不新开一套 DPR 口径**。

### 2.3 `refine(parent)`：合并语义、可继承字段、优先级

先分清两件事（这一步做错就会「看着对」）：

1. **`refine` 是合并原语**：把 `this`（partial）里**设了的字段**盖到 `parent` 上；复合值
   （`Edges`/`Corners`/`Size`）**逐分量合并**，标量字段整体替换。这与 GPUI 的
   `Refineable::refine`（`refineable/src/refineable.rs`：`#[refineable]` 字段递归 refine、
   `Option<T>` 保留 `Some`、普通字段 `Option<T>` 有值才替换）同构。
2. **CSS 式「继承」只发生在小子集上**：flexbox 的布局属性**不继承**（`size`/`margin`/`padding`/
   `flex*`/`align*`/`gap` 都不从父遗传）。把布局属性做成继承会偏离 flexbox 语义，是最典型的
   「看着对」陷阱。真正往下传的只有排版相关的一组。

**可继承字段（inherited subset）**：

| 字段 | 继承 | 理由 |
|---|---|---|
| `text.*`（fontFamily/fontSize/fontWeight/fontStyle/color/leading/letterSpacing） | ✅ | CSS 继承属性；主题的排版基线必须往下传 |
| `visibility` | ✅ | CSS 继承属性（`hidden` 隐藏自身、子可覆盖为 `visible`） |
| `mouseCursor` | ❌ | 由控件自身默认决定 |
| `display`/`position`/`inset`/`size`/`min`/`max`/`margin`/`padding`/`borderWidths`/`gap`/`flex*`/`align*`/`grid*` | ❌ | flexbox 不继承 |
| `background`/`borderColor`/`borderStyle`/`cornerRadii`/`boxShadow`/`opacity` | ❌ | 装饰不继承（`opacity` 用合成层语义，不做 CSS 之外的隐式相乘） |

**解析一个节点的 `resolved:Style` 的优先级（低 → 高）**：

```
1. 控件默认        controlDefault(kind)                    // 编译期静态常量
2. 主题            theme.apply(kind, stateVariant)          // 只覆盖主题声明过的槽
3. 继承             parentResolved.projectInherited()       // 只投影上表的可继承字段
4. 显式             node.style（StyleRefinement，partial）
```

即：`resolved = controlDefault(kind).refine(themeSlot).refine(parent.inherited()).refine(node.style)`。
其中 `refine` 只在参数里「有值」的字段上生效，复合值逐分量。这给出题目要求的顺序
**控件默认 → 主题 → refine 父级 → 显式设置**。

状态变体（主题层）：`theme.apply` 的 `stateVariant` 由 §3.2 的 `hover`/`pressed`/`focused` 推出
（`normal` / `hover` / `pressed` / `focused` / `disabled`）。**悬停态只影响装饰字段**，不触发布局
（§3.3 的脏传播表），所以悬停不会引起 reflow。

### 2.4 关键：`Style` 不每帧分配

**硬要求**：稳态帧零分配（§7）。方案四层，每层都可核对：

1. **静态常量**：主题、控件默认、`Styles.body`/`Styles.primary` 等，**启动时构造一次**，
   之后只读。作者的 `StyleRefinement` 应 hoist 成 `static const` 或实例字段，不在 `render()` 里
   `new`。
2. **节点内写就 buffer**：每个 `UiNode` 持有一个 `resolved:Style`。`resolveStyleInto(out, kind, parent, partial)`
   把结果**写进 out**，返回 `void`——不产生新 `Style` 对象。`Style` 在作者侧是「不可变值」，
   在编译/dogfood 后的运行时侧是「**只读 + 复用**」。
3. **指针身份跳过**：`UiNode.lastStyle` 记住上一趟的 partial 指针。**指针相同就整段跳过**——
   连 `resolveStyleInto` 都不调用。这是最常见的稳态：作者把样式 hoist 后，`render()` 每次返回同一个
   partial 指针。（`render()` 本身在稳态帧不会被调用，见 §5.3；这一层额外保证「脏但只改数据」的
   帧里样式也不重算。）
4. **写时复制（copy-on-write）**：author-facing 便捷方法 `Style.with(patch)` 只有在 `patch` 与本实例
   不同时才返回新实例，相同则返回 `this`（`===` 身份不变）。这样「用便捷方法拼样式」的代码在
   循环里也不会无脑分配。

**必须标脏的时机**：`setTheme()` 会让所有 `UiNode.lastStyleStale = true`（不是立刻重建 `Style`，
而是下一趟递归 re-resolve）。主题切换是低频事件，允许一次全树 re-resolve。

> **为什么不搞树外 Style 缓存（interning table）**：见 §10 未决问题 1。本文先选「节点内 buffer +
> 指针跳过」，因为它零 hash、零全局锁、零生命周期管理；interning 对「多窗口共享同一主题」有收益，
> 但会把样式对象的生命周期绑到全局表上，收益/复杂度比未算清。

---

## §3 三趟管线

### 3.1 `measure` / `arrange` / `paint` 与 GPUI 的对应

```as3
// UiNode 侧（framework 内部），作者通过控件覆盖实现，不直接调用
function measure(constraints:Constraints):Size;   // 母给约束，返回固有尺寸（写缓存）
function arrange(rect:Rect):void;                 // 母给最终矩形，摆放自身与子件
function paint(gfx:RenderCtx):void;               // 把图元写进 Renderer 接缝
```

| 趟 | 本文 | GPUI | 对照说明 |
|---|---|---|---|
| 1 描述 | `View.render()` → `Node` 树 | `Render::render()`（`element.rs:164-166`） | 都产出描述；GPUI 每帧，本文脏时才跑 |
| 2 测量 | `measure(constraints)` | `Element::request_layout`（`element.rs:74`）+ Taffy measure | 都会把样式交给布局引擎、算内在尺寸 |
| 2' 求解 | `LayoutEngine.compute(root, available)` | `window.compute_layout` → `TaffyLayoutEngine::compute_layout`（`taffy.rs:187`） | 一次求解整棵 flex 树，产出每节点矩形 |
| 3 摆放 | `arrange(rect)` | `Element::prepaint`（`element.rs:84`，参数就是最终 `bounds`） | 都拿到最终矩形；写回 backing、建命中区域、收瞬态态 |
| 4 绘制 | `paint(gfx)` | `Element::paint`（`element.rs:96`） | 都把图元交给渲染器 |

> **为什么 `prepaint` 对应 `arrange` 而不是 `measure`**：GPUI 的 `prepaint` 签名里
> `bounds: Bounds<Pixels>` 是**布局已算完的最终矩形**（`element.rs:85`），而测量发生在
> `request_layout`（它返回 `LayoutId`，真正求解在 `compute_layout`）。所以本项目的
> `measure ↔ request_layout`、`arrange ↔ prepaint` 是逐签名对齐的，不是类比。

**与现有渲染的接合**：本文的 `paint` **不另开 Skia 调用**，而是更新 backing `DisplayObject` 的
可绘制状态（`Graphics` / `TextField` / `Bitmap`），交给现有 `as_render_object`（`src/emit.ts:22235`）
与 `as_render_object_content`（`:22477`）去画。这样：
- 光栅化、缓存烘焙（`ASC_AUTO_BAKE_FRAMES 3`，`:21749-21764`）、`cacheAsBitmap`、九宫格、
  滤镜、`scrollRect`（`:22313`）全部零改动。
- `DisplayListRenderer` 的职责是「维护 backing DisplayObject 树」，**不是重写 Skia 调用**。
  `Stage3DRenderer`（后续）才需要另写图元路径。

```as3
// Renderer 接缝（两个实现）
interface Renderer
{
    function beginFrame(stage:flash.display.Stage):void;
    function rect(r:Rect, paint:Paint):void;
    function text(r:Rect, run:TextRun):void;
    function image(r:Rect, bmp:flash.display.BitmapData, fit:String):void;
    function pushClip(r:Rect):void;
    function popClip():void;
    function endFrame():void;
}
```

### 3.2 `ElementState`：瞬态状态存在哪里

**存在 `UiNode` 的私有字段里**，不是外部表、不是每帧 map。形状固定、值类型内联：

```as3
// 内联在 UiNode 里（非 GC 指针，进不了 GC 堆）
class ElementState
{
    var hover:int;          // 0/1
    var pressed:int;
    var focused:int;
    var disabled:int;
    var scrollX:Number;     // 滚动偏移（逻辑单位）
    var scrollY:Number;
    var measuredW:Number;   // 测量缓存
    var measuredH:Number;
    var measureValid:int;   // 位图：W 有效 / H 有效
    var arrangedW:Number;   // 上帧最终矩形（命中测试复用）
    var arrangedH:Number;
    var arrangedX:Number;
    var arrangedY:Number;
    var hitValid:int;
}
```

为什么是这个形状：

- **不进 GC**：全是 `int`/`Number`；没有字符串、没有数组、没有对象。滚动偏移是一个 `Number`，
  与 GPUI 把滚动偏移放 `PrepaintState` 同性质（`element.rs:17` 的「太小太多、不值得塞进业务对象」）。
- **零分配**：`UiNode` 在 mount/结构变化时分配一次，之后 `state` 原地读写。
- **不需要 hash / 不需要跨帧找回**：节点指针就是身份（§1.2），GPUI 需要 `with_element_state` +
  `GlobalElementId` 去 map 里找回，我们没有这层成本。
- **命中测试**：沿用现有 `as_pick_hit_local`（`src/emit.ts:15998`）、`as_obj_region_hit_local`
  （`:16043`）——这些按**绘制区域**而非包围盒判定，是已经对 `adl` 校准过的口径。我们只把控件的
  可命中区域保证与 `paint` 一致。

### 3.3 脏传播：改什么触发哪一趟

`UiNode.dirty` 是位图。**只有 `dirty != 0` 的节点才进入对应趟；未标脏的子树整棵跳过。**

| 变化 | measure | arrange | paint | 备注 |
|---|---|---|---|---|
| 布局类 style（`display`/`position`/`inset`/`size`/`min/max`/`margin`/`padding`/`borderWidths`/`gap`/`flex*`/`align*`/`grid*`） | ✅ 自身 + 祖先链 | ✅ | ✅ | 尺寸变化会向上影响父的固有尺寸 |
| 装饰类 style（`background`/`borderColor`/`borderStyle`/`cornerRadii`/`boxShadow`/`opacity`） | — | — | ✅ | |
| 文本类 style（`text.*`） | 若控件是 autoSize | ✅ | ✅ | 文本布局缓存失效（`as_tf_paragraph`，`:18493`） |
| 文本内容变化（`String`） | 若 autoSize | ✅ | ✅ | 句柄按字符串指针判定（见 `:11106` 注释的「按 text 指针失效」） |
| 图片源变化 | 若未定尺寸 | ✅ | ✅ | |
| `hover`/`pressed`/`focused` 状态翻转 | — | — | ✅ | 只切主题状态变体（装饰），不 reflow |
| `scrollX/scrollY` 变化 | — | — | ✅ | 命中区域在 pick 时按 `arranged + scroll` 现算 |
| 子节点增删/重排 | ✅ | ✅ | ✅ | reconcile 后 |
| `visibility = hidden` | ✅ | ✅ | （不画但占位） | |
| `display = none` | ✅ | ✅ | — | 不画、不占位 |
| 窗口尺寸变化（`stage.stageWidth/Height`） | ✅ 根 | ✅ 根 | ✅ | 根重排，见 §10 未决 11 |
| 主题切换 | ✅ 全树 | ✅ 全树 | ✅ 全树 | `lastStyleStale = true` |

---

## §4 控件集

### 4.1 `Node` → `DisplayObject` 的桥

**决定：一个 `UiNode` ↔ 一个顶层 backing `DisplayObject`；这个对象内部可以含多个子 `DisplayObject`。**

```
UiNode (kind=button)
  backing: Sprite            ← 布局矩形、变换、命中、焦点都锚在这一个对象上
    ├─ Shape (背景/圆角/边框)  ← paint 写它的 Graphics
    └─ TextField (标签)        ← paint 写它的 text/textFormat
```

为什么不是「一个 Node 对多个 DisplayObject」：

1. **布局需要单一锚点**：flex 求解出的是「这个节点」的矩形；多个根就没有唯一的 `x/y/width/height`
   可以写回，也没有唯一的对象承接 `transform`。
2. **命中与焦点需要单一对象**：现有命中测试从 stage 往下走到具体对象（`as_pick_hit_local`），
   焦点是 `InteractiveObject`（`as_focus_obj`）。多根会让「这个控件被点到了吗」没有唯一答案。
3. **AIR 语义自动继承**：一个 `Sprite` 的 `alpha`/`blendMode`/`scrollRect`/`mask`/九宫格/
   滤镜，全部按对象生效，`as_render_object` 已实现。多根就得手工协调这些语义。

例外与约束：控件内部允许任意多的子 `DisplayObject`（按钮的背景 + 文字），但它们**不是**独立的
`UiNode`，不参与布局/焦点；它们由控件的 `paint` 全权管理。

**挂树不另写逻辑**：一律用现有 `DisplayObjectContainer_addChild`（`:10607`）/`addChildAt`（`:10629`）
/ `removeChild`，以保留 AIR 的 `added`/`removed`/`addedToStage`/`removedFromStage` 事件与隐式 reparent。
`UiNode` 自己持有的 GC 指针字段（如 `_a11yName`）写入时调 `gc_write_barrier`（写法同 `:10492`
的 `_scroll_rect`）。

### 4.2 基类层次与工厂函数

```as3
// 继承链：Node → Element → Control → 具体控件
package asaot.ui
{
    public class Element extends Node
    {
        public var role:String;          // §4.3，缺省由控件决定
        public var ariaName:String;
        public var ariaValue:*;
    }

    public class Control extends Element
    {
        public var tabEnabled:Boolean = true;
        public var tabIndex:int = -1;
        public var onClick:Function;
        public var action:String;        // 键盘 action id（§6.1）
    }
}
```

| 基类 | 直接子类 | 说明 |
|---|---|---|
| `Node` | — | 纯描述（key/style/children） |
| `Element` | `Box`、`Text`、`ImageView` | 有 a11y 元数据但不可聚焦 |
| `Control` | `Button`、`TextInput`、`Checkbox`、`Radio`、`ScrollView`、`List`、`TextFieldNode` | 可聚焦、可绑 action |

工厂函数（作者主要用这一层；`opts` 是对象字面量，字段直接对应上表）：

```as3
function box(opts:Object, children:Array = null):Node;       // opts: key/style/keyContext/direction/gap/padding…
function text(content:String, opts:Object = null):Node;      // opts: key/style/ariaName/visible
function image(opts:Object):Node;                            // opts: key/src(BitmapData)/fit/style/ariaName
function button(opts:Object):Node;                           // opts: key/label/style/action/onClick/ariaName
function checkbox(opts:Object):Node;                         // opts: key/label/checked/style/onChange
function radio(opts:Object):Node;                            // opts: key/label/value/group/value2/onChange
function textField(opts:Object):Node;                        // opts: key/value/placeholder/password/onCommit
function scrollView(opts:Object, children:Array):Node;       // opts: key/style/scrollX/scrollY
function list(opts:Object):Node;                             // opts: key/items/itemKey/itemHeight/onSelect
```

对照 GPUI：基础元素在 `elements/mod.rs`（`div`/`text`/`img`/`list`/`uniform_list`/`svg`/`canvas`/
`anchored`/`deferred`/`surface`…），成品控件散在 `ui/`（本检出不含）。GPUI 用
`IntoElement` + `#[derive(IntoElement)]` 组组件（`element.rs:118`），我们用「工厂函数 + Node 子类」，
因为 AS3 没有 `impl Trait` / 所有权下的 builder。

### 4.3 每个控件的 role / name / value（给 a11y 留形状）

**硬要求**：每个控件在构造时**必须**填 `role` 与 `ariaName`；`ariaValue` 按控件语义填。
framework 在调 `render()` 后做调试期断言：缺 `role` 或 `ariaName` 直接报错，不静默。

存储形状（`UiNode.a11y`，内联）：

```as3
class A11yInfo
{
    var roleId:int;        // 映射到常量表；将来接 AccessKit Role / UIA ControlType
    var name:char*;        // GC 字符串，写入时 gc_write_barrier
    var valueKind:int;     // 0 none / 1 bool / 2 num / 3 str
    var valueNum:Number;
    var valuePtr:void*;    // 字符串指针（GC），写入时 gc_write_barrier
}
```

| 控件 | role | name | value | 备注 |
|---|---|---|---|---|
| `Box` | `"group"` | 必填（可空串但需显式） | 无 | 纯布局容器 |
| `Text` | `"text"` | 缺省 = 文本内容 | 无 | |
| `Button` | `"button"` | 必填 | 无 | `pressed` 进状态 |
| `ImageView` | `"image"` | 必填 | 无 | |
| `Checkbox` | `"checkBox"` | 必填（label） | `bool` = checked | |
| `Radio` | `"radioButton"` | 必填（label） | `bool` = checked | `group` 内互斥 |
| `TextInput` | `"textField"` | 必填 | `str` = 当前文本（密码为掩码） | |
| `TextFieldNode` | `"textField"` | 必填 | `str` = 当前文本 | 富文本/多行 |
| `ScrollView` | `"group"` | 必填 | `num` = scrollY | |
| `List` | `"list"` | 必填 | `num` = 选中序号 | 子项 `"listItem"` |

对照：GPUI 的 `Element::a11y_role` / `write_a11y_info` / `a11y_synthetic_children`（`element.rs:113-140`）
只在 `a11y_role()` 返回 `Some` 且元素有非空 id 时进 a11y 树（`element.rs:110` 注释、`prepaint` 里的
`accesskit::Node` 构造）。我们因为每个节点都有身份，天然满足「有 id」；role/name/value 存节点上，
等 **U6 / `flash.accessibility`** 到位时再物化成树，**现在只留形状、不假装有**。

### 4.4 `TextField` 包装：复用 SkParagraph，不新开文本口径

**规则**：`textField()` / `TextInput` 的文本测量与绘制**必须**全部走现有 `TextField` 通道：

- backing 里放一个**真正的** `flash.text.TextField`（不是自研文本对象）。
- 测量：`TextField.get textWidth` / `get textHeight`——它们内部就是
  `TextField.get textWidth`（定义 `src/emit.ts:18796`，内部调 `as_skia_textlayout_max_width` 于 `:18805`）与
  `TextField.get textHeight`（定义 `:18808`，内部调 `as_skia_textlayout_height` 于 `:18828`），底层是 `sk_text_measure`
  （`vendor/skia_text_glue.cc:308`）。
- 绘制：`as_render_object_content` 的 `TextField` 分支（`src/emit.ts:22477` 起）——含
  `autoSize`、`scrollV/scrollH`、选区高亮、caret 闪烁（`as_tf_blink_t0`/`as_tf_blink_reset`/`as_tf_caret_on`，`:10789-10791`）。
- 语义口径：`autoSize` / `multiline` / `wordWrap` 按 [`flash-text.md`](../as3compiler/docs/zh-cn/flash-text.md)、
  渲染与 1:1 像素口径按 [`skia.md`](../as3compiler/docs/zh-cn/skia.md)。

**禁止**：新写一套排版/度量/断行；用 `Graphics` 自绘文字；把 `TextField` 的 `defaultTextFormat`
换成另一套字体枚举。这些都会引入第二套文本口径，主文档 §4.3 N2 已明确否决。

---

## §5 数据流

### 5.1 `Observable` / `notify()` 用 `addEventListener` 还是自建订阅？

**决定：自建轻量订阅（`Observable.subscribe`），不用 `addEventListener`。**

```as3
package asaot.ui
{
    public class Observable
    {
        // listener:(dirty:int) -> void，同步调用
        public function subscribe(listener:Function):Subscription;
        public function unsubscribe(s:Subscription):void;
        public function notify(dirty:int = Dirty.ALL):void;
    }

    public final class Dirty
    {
        public static const VALUE:int     = 1;   // 只改数据值
        public static const DECOR:int     = 2;   // 只改装饰（样式）
        public static const STRUCTURE:int = 4;   // 改结构（items/children）
        public static const THEME:int     = 8;   // 换主题
        public static const ALL:int       = 15;
    }

    // 单向绑定：读走 get，写走 set（set → owner.notify(Dirty.VALUE)）
    public class Binding
    {
        public function get():*;
        public function set(v:*):void;
    }
    function bind(owner:Observable, field:String):Binding;
}
```

**理由（逐条，都可核对）**：

1. **不需要三阶段事件、也不该有**：`addEventListener` 走 AS3 的捕获/目标/冒泡（`as_disp_target`，
   `src/emit.ts:10052`）与 `Event` 对象；业务对象不是显示树的一环，派发事件既语义错、又要为
   每次 notify 构造 `Event`（→ 每帧分配，撞 §7 红线）并遍历祖先链。
2. **业务对象不是 `EventDispatcher`**：`addEventListener`（`:10161`）挂在 `EventDispatcher`/
   `IEventDispatcher` 上；让每个 model 继承 `EventDispatcher` 是把事件模型硬塞进数据层。
3. **需要一个**被观察者 → 一个 View**的同步、最小通知**：GPUI 的 `Context::notify`（`app/context.rs:221`）
   就是「告诉窗口我变了」，不对应任何事件广播。
4. **订阅是低频的**：`subscribe` 在构造/mount 时调一次，listener 存进一个固定容量的小数组
   （观察者通常 ≤ 3），不进入每帧路径。

**同时**，`Observable` 也可以让 View 订阅另一个 View（组合），对应 GPUI 的 `observe`/`subscribe`
（`context.rs:64`/`:94`），但**不由 framework 自动做**——本文先用「显式 `subscribe`」把依赖写清，
避免隐式依赖图带来的重入与顺序问题（§10 未决 5）。

### 5.2 接到 `WinCtx.dirty`：唯一入口，不许绕开

现有重绘唯一入口：`WinCtx.dirty`（`vendor/window_glue.cc:387`），且 frame pump 只重绘 dirty 窗口
（`:809-820`：`if (c->visible && c->dirty && c->on_redraw != NULL) { c->on_redraw(i); … c->dirty = 0; }`）。
**我们绝不新增第二条上屏路径**（不直接调用 `ASC_window_render`，不自己建 Canvas）。

现有 glue 有两处把窗口标脏：

- **事件路径**：鼠标/键盘/滚轮等事件处理里 `c->dirty = 1`（`:1270`/`:1307`/`:1320`/`:1338`/`:1357`/`:1418`
  /`:1437`/`:1454`/`:1465`）。
- **帧时钟路径**：一次应用帧给**所有可见窗口**标脏（`:792-796`，`c->dirty = 1` 在 `:796`）。

因此本文的数据流分两层：

1. **「何时重绘」**：`notify()` 只 `invalidate`（OR 进 `_pendingDirty`），**不直接重绘**。
   - 当前后端每帧都会标脏所有可见窗口，所以 notify 的重绘**事实上由帧时钟兜住**；
   - 为了「只重绘 dirty 窗口」这条语义不被绕过、也为将来加 idle 模式，本文**提出一个新接缝**
     `sk_window_mark_dirty(int id)`（3 行的 glue 导出）+ 一个生成侧桥 `ASC_ui_invalidate(int id)`
     （下一阶段随 U3 落地；现在 `as3compiler/` 只读，不在此次改动范围内）。它**只置 `c->dirty`**，
     不碰渲染。
2. **「重绘时做什么」**：reflow（describe/reconcile/measure/arrange）由一个 **ENTER_FRAME 监听器**
   驱动。`Stage_dispatchFrame`（`src/emit.ts:21087`）在 present 之前广播 `enterFrame`
   （`:21134-21137`），而 `sk_pump_frame` 的顺序是「on_frame（→ ENTER_FRAME）→ 标脏可见窗口 → present」
   （`:786-820`）。所以 reflow 发生在**同一帧、present 之前**，且 `_pendingDirty == 0` 时整段跳过。

> **诚实的偏差**：主文档 U3 的验收写「无变化帧零重绘」。当前 glue 的帧时钟每帧把所有可见窗口标脏
> （`:792-796`），所以**字面意义上的「零重绘」在当前后端达不到**——除非给 glue 加 idle 模式（见 §10 未决 6）。
> 本文能做到且验收的是：**无变化帧不做 describe、不做 reconcile、不做 measure/arrange**；只跑现有
> render walk（它已被自动烘焙 `ASC_AUTO_BAKE_FRAMES 3` 摊薄）。这一条与主文档的偏差列在 §11。

### 5.3 一次 `notify()` 到一次重绘的完整调用链

```text
[业务代码]  form.account = "alice"          // 或显式 form.notify(Dirty.VALUE)
   │
   ▼
[§5.1] Observable.notify(Dirty.VALUE)        // 同步
   │  遍历订阅者（≤3，小数组），无分配
   ▼
[§5.1] LoginView.onFormChanged(dirty)        // 作者的订阅回调
   │
   ▼
[§1.1] View.invalidate(dirty)
   │
   ▼
[§5.2] UiApp.invalidate(dirty)
   │  _pendingDirty |= dirty;                 // 一个 int OR，无分配
   │  as_ui_request_redraw(windowId)          // 新接缝：置 WinCtx.dirty（唯一入口）
   ▼                                        // ---- 同一帧边界 ----
[window_glue.cc] sk_pump_frame()
   │  on_frame(clock)  →  Stage_dispatchFrame(::emit.ts:21087)
   │      ├─ gc_step()                        // 帧安全点（增量标记切片）
   │      ├─ timers / MovieClip / audio
   │      └─ 广播 ENTER_FRAME
   │           ▼
   │        [§5.2] UiApp.onEnterFrame()
   │           if (_pendingDirty != 0) {
   │             [§1]  describe()   → View.render() → Node 树（仅此帧）
   │             [§1.3] reconcile() → 复用/新建/销毁 UiNode（写屏障）
   │             [§3]  measure(root, available) → LayoutEngine.compute()
   │                   arrange(root, rect)
   │             _pendingDirty = 0;
   │           }
   │  标脏所有可见窗口 c->dirty = 1            // 现有行为（window_glue.cc:796）
   ▼
[window_glue.cc] present 循环
   │  if (visible && dirty && on_redraw) on_redraw(i)     // :809-820
   ▼
[§3.1] ASC_window_on_redraw(id) (::emit.ts:23621) → ASC_window_render(id) (:23197)
   │
   ▼
[§3.1] as_render_object(canvas, stage) (:23304 → :22235)
   │  按 retained DisplayObject 树绘制；控件的 paint 已把 Graphics/TextField 更新好
   ▼
Skia → present_frame (window_glue.cc:496) → c->dirty = 0 (window_glue.cc:817)
```

关键点：**notify 不做绘制、不做布局**；reflow 是帧边界的一次批量；绘制仍是现有 render walk。
`UiApp.onEnterFrame` 是**唯一**的 reflow 入口，且只在 `_pendingDirty != 0` 时工作。

---

## §6 键盘与焦点

### 6.1 `ActionRegistry`：action 用字符串 id 声明

```as3
package asaot.ui
{
    public final class ActionRegistry
    {
        // app 级单例；keymap 加载与查找都走它
        public static function register(id:String, handler:Function, schema:Object = null):void;
        public static function setKeymap(json:String):void;
        public static function unregister(id:String):void;
    }
}
```

**为什么是字符串 id，不是静态单例/类型**：

1. **keymap 是 JSON**，必须能序列化引用；GPUI 用 Rust 类型全名（`"menu::MoveUp"`，见
   `docs/key_dispatch.md` 的 keymap 例），AS3 没有类型字面量可序列化成 key，所以用稳定字符串
   （`"login.submit"`）。
2. **用户可改**：keymap 是数据、可运行时替换（主文档 B6 的核心价值）。
3. **可带参数**：`schema` 描述 payload 形状；keymap 里 `["action.id", {…}]` 提供实参
   （对齐 GPUI 复杂 action 的 `["menu::Move", {direction:"up", select:false}]` 写法）。

### 6.2 context 串语法（对齐 GPUI 的 predicate 文法）

GPUI 的 `KeyBindingContextPredicate`（`keymap/context.rs:172-197`）支持：
`Identifier`、`key == value`、`key != value`、`parent > child`（后代）、`!pred`、`&&`、`||`、括号。

本文采用同一文法，语义是「从当前焦点往上收集所有 `keyContext`（由内到外），看是否存在一条路径满足谓词」：

```text
context   := or
or        := and ( "||" and )*
and       := unary ( "&&" unary )*
unary     := "!" unary | "(" or ")" | atom
atom      := ident                       // 存在该上下文
           | ident "==" value            // 存在带该键值对的上下文
           | ident "!=" value
           | atom ">" atom               // 左侧是右侧的祖先（更靠近根）
```

例：`"login"`、`"login > modal"`、`"os == macos && editor"`、`"!im"`。

实现要点：焦点变化时沿 parent 链**收集一次** context 串（O(深度)），按键时才做匹配，**不是每次按键
都走树**。这与 GPUI 把 key context 挂在元素上、按键时匹配不同；我们因为焦点是单一 `as_focus_obj`
指针，向上走父链即可。

### 6.3 keymap JSON schema（完整例子）

```json
[
  {
    "context": "login",
    "bindings": {
      "enter": "login.submit",
      "tab": "ui.focus.next",
      "shift-tab": "ui.focus.prev"
    }
  },
  {
    "context": "login > modal.confirm",
    "bindings": {
      "cmd-enter": "login.submit",
      "escape": "modal.cancel",
      "tab": "ui.focus.nextInGroup",
      "shift-tab": "ui.focus.prevInGroup"
    }
  },
  {
    "context": "login && os == macos",
    "bindings": {
      "cmd-k": "palette.open"
    }
  },
  [
    {
      "context": "editor",
      "bindings": {
        "ctrl-s": ["doc.save", { "force": false }],
        "ctrl-shift-s": ["doc.save", { "force": true }]
      }
    }
  ]
]
```

> **同一 action 在两个 context 下绑不同键**：`login.submit` 在 `login` 下绑 `enter`，在
> `login > modal.confirm` 下绑 `cmd-enter`。这就是 U5 的验收场景。

`keystroke` 文法复用现有 `keyCode` + 修饰键位（`ASC_MOD_CTRL/ALT/SHIFT/CMD`，`src/emit.ts:10812-10816`）。
keymap 的 `"tab"` 绑定不改变内置行为：见 §6.4。

**分派规则（避免偷走文本输入）**：

1. 按键先按现有路径派发成 AS3 `KeyboardEvent`（`Stage_dispatchKey`，`:11551`）——**这条不动**。
2. `ActionRegistry` 在 stage 级 `KEY_DOWN` 监听里查当前 context 的绑定。
3. **命中才执行 action 并 `preventDefault()`**；没命中就什么都不做，让内置文本输入/光标移动照常。
   所以纯字符键（没绑）永远进文本，被绑定过的组合键才被拦。
4. 组合键的 `preventDefault()` 会置 `evt->cancelled`（`Event_preventDefault`，`:10141`），
   从而抑制后续内置处理（例如 Tab 的焦点移动，见 §6.4）。

### 6.4 `FocusChain`：在 `as_focus_obj`/`as_tab_scan` 之上加一层

**明确回答：加一层，不替换。** 分成「焦点模型」与「焦点序」两件事：

| 关注点 | 谁负责 | 是否改动 |
|---|---|---|
| 谁有焦点（单一真源） | `as_focus_obj`（`src/emit.ts:10782`，永久 GC 根，`:5686`）+ `as_set_focus`（`:10827`） | **不动** |
| focusIn/focusOut 冒泡、caret 重启 | `as_focus_dispatch`（`:10820`）+ `as_tf_blink_reset`（`:10790`） | **不动** |
| 鼠标点击聚焦 / 清空焦点 | `as_focus_from_mouse_down`（`:10904`） | **不动** |
| Tab 序从哪来 | 现有 `as_tab_scan`（`:10860`）/`as_focus_tab`（`:10881`） | UI 控件走新 `FocusChain`；非 UI 的 `flash.*` 对象仍走旧路径 |
| 焦点移动本身 | `stage.focus = obj` → `Stage_set_focus`（`:11725`）→ `as_set_focus` | **复用** |

**接管机制（不碰 C）**：`Stage_dispatchKey` 在派发完 keyDown 之后才做内置 Tab 移动，且
`if (keyCode == 9 && !evt->cancelled) { as_focus_tab(...); return; }`（`:11611`）——**`preventDefault()`
能抑制它**。于是：

1. `FocusChain` 在 stage 级 `KEY_DOWN` 里，遇到 Tab/Shift+Tab 先 `event.preventDefault()`；
2. 从自己的序表里取下一个/上一个可聚焦 `InteractiveObject`；
3. `stage.focus = target`（走 `Stage_set_focus` → `as_set_focus`，focusIn/focusOut 照常）。
4. 若 `FocusChain` 没有接管（例如焦点在非 UI 对象上），不 `preventDefault()`，内置 `as_focus_tab` 照常。

**分组语法（对照 GPUI `Group`/`GroupEnd`）**：GPUI 的 `TabStopMap` 用
`insertion_history: Vec<TabStopOperation>`（`Insert`/`Group`/`GroupEnd`）+ `SumTree`（`tab_stop.rs:11-23`）；
`tab_group()` + `tab_index()` 决定顺序（`examples/tab_stop.rs` 的 `div().tab_group().tab_index(6)`）。
AS3 侧以「容器节点声明一个焦点作用域」表达：

```as3
// 普通容器：子控件按视觉顺序进父作用域
box({ key: "form" }, [ /* … */ ]),

// 模态/对话框：一个焦点作用域，可 trap
group({ key: "confirm", modal: true, trap: true }, [
    text("确定删除？", { key: "msg" }),
    button({ key: "yes", label: "确定", action: "modal.confirm" }),
    button({ key: "no",  label: "取消", action: "modal.cancel" })
])
```

- `modal:true` + `trap:true`：该作用域激活时，`next()/prev()` 只在组内环绕，Tab 不逃逸到组外
  （这就是主文档 B7 要的「模态内循环」）。
- 嵌套组：组里可以再开组；顺序 = 先入组、组内按视觉序、再出组，与 GPUI 的
  `TabStopPath`（`tab_stop.rs:39-42`）一致。
- 顺序来源：**在 arrange 趟之后**，按 `childOrder` 的显示前序遍历可聚焦控件（`tabEnabled` 为真），
  与 `as_tab_scan` 的「显示列表前序 + `tabEnabled` 过滤」同口径（`:10842-10851`）。

```as3
package asaot.ui
{
    public final class FocusChain
    {
        public static function rebuild(root:UiNode):void;   // arrange 之后调用
        public static function next():flash.display.InteractiveObject;
        public static function prev():flash.display.InteractiveObject;
        public static function pushScope(groupKey:String):void;
        public static function popScope():void;
    }
}
```

**64 个可聚焦对象硬上限怎么处理**：

- 现状：`as_focus_tab` 用栈上 `DisplayObject* tabs[64]`（`:10884`），越限「Tab 就不再移动」
  （注释自述在 `:10857`）。这是 `as_tab_scan` 的实现边界，不是 AIR 语义。
- 本文：`FocusChain` 的序表用 `Vector.<InteractiveObject>`，在**结构变化时**扩容/重建，
  不用固定 64。因此 UI 控件的 Tab 序**不受 64 限制**。
- **但口径必须先实测**：`adl` 在 >64 个 tabbable 下的行为（顺序、环绕点、焦点为空时的起点、
  `tabEnabled=false` 的锚点语义）**尚未测量**。本文不凭直觉下结论——U5 的前置是写一个 >64 tabbable
  的 `.as`，在 `adl` 上驱动 Tab/Shift+Tab、记录顺序与环绕，再让 `FocusChain` 逐项对上。
  在实测完成前，「>64 仍可达」只作为**目标**，不作为已证事实。
- 非 UI 对象（作者的 `flash.*` 显示对象）仍走 `as_tab_scan` 的 64 上限——这是既有边界，不静默抬高。

---

## §7 内存预算（硬要求）

AGENTS.md 的红线：**「禁止在每帧/每循环的热路径里产生进 arena 的临时分配」**；先例是 `as_disp_key`
每帧 `as_alloc(strlen(type)+5)` 造成 **~39 KB/s** 的静默泄漏（阶段五十六，修到 0.85 KB/s——
`TODO.md:1238`/`:1242`/`:1249`，`docs/zh-cn/gc.md:12`）。GC-4 增量标记的目标是「单帧停顿 O(budget)
而非 O(堆)」（`docs/zh-cn/gc.md` §6）。下面逐项列出本 API 的分配行为。

### 7.1 稳态帧（无 notify、无结构变化、无动画）= 零分配

| 阶段 | 分配 | 说明 |
|---|---|---|
| describe | **0（整段跳过）** | `_pendingDirty == 0`，`View.render()` 不调用 |
| reconcile | **0（整段跳过）** | 同上 |
| measure | **0** | 复用 `ElementState.measuredW/H` + `measureValid` |
| arrange | **0** | 只写 `int`/`Number` 字段与 backing 的 `x/y/width/height` |
| paint | **0** | 更新 `Graphics` 命令表与 `TextField` 字段；文本未变则不重排版 |
| 事件（hover 翻转） | **0** | 只切状态变体 + 标 `M_PAINT`；装饰字段已预解析，不 `new Style` |
| `notify` | **0** | 一个 int OR |

### 7.2 允许分配的时机（低频、非每帧）

| 时机 | 分配什么 | 生命周期 |
|---|---|---|
| mount / 首次 describe | `Node` 描述树、`UiNode`、backing `DisplayObject`（`new Sprite/Shape/TextField`） | GC 堆；`UiNode` 由 `UiApp` 根持有 |
| 结构变化（增删/换 key） | 新增的 `UiNode` + backing；销毁的子树交给 GC | GC 堆 |
| 文本内容变化 | `TextField.text` 的字符串（`as_str_alloc`）；SkParagraph 段落缓存重建 | GC / 运行时光栅缓存 |
| 主题切换 | 一次全树 re-resolve（不分配 `Style`，写就 buffer） | — |
| keymap 加载 | 解析后的绑定表（一次性） | GC 堆，app 生命周期 |
| 图片源变化 | 解码后的 `SkImage`/`BitmapData` | 既有缓存 |

### 7.3 描述树本身怎么不每帧分配

即便在「脏」的帧里，`Node` 描述树也不该每次都进 GC。方案：**per-root 描述缓冲（bump reset）**：

- `UiApp` 持有一个私有的 `NodeArena`：一块可增长的 `Node` 槽位数组；
- 每趟 describe 开始时 `arena.reset()`（把**已用指针回退到 0**，不是释放、不是 `as_alloc`），
  然后从槽位里切 `Node`；
- `Node` 不逃逸 describe 趟（reconcile 只读它），所以 reset 安全；
- 只有「槽位不够」才增长（摊还 O(1)）。

这与 AGENTS.md 的 arena 禁令不冲突：禁令针对的是 **`as_alloc`（只 bump 不归还）**；`NodeArena`
是**我们自己拥有、每趟 reset 回收**的私有缓冲，不是 `as_alloc`。实现时必须显式注释这条区别。

`key` 的规范化和 `childrenByKey` 的 key：用**整数 `keyId`**（interned 一次）而不是每次 `strcmp`；
`key` 的来源是作者提供的字符串或序号，intern 表只在 mount/结构变化时插入。这样 reconcile 的比较是
整数比较，不是字符串比较，更不是字符串拼接。

### 7.4 GC 写屏障（必须显式写）

reflow 发生在 `Stage_dispatchFrame` 的 **`gc_step()` 之后**（`:21108` 在 `:21134` 的 ENTER_FRAME 广播之前），
也就是**增量标记可能仍在进行**。因此：

- 向 `UiNode` 的 GC 指针字段（`backing`、`_a11yName`、`valuePtr`、`childrenByKey` 的值）写入时，
  必须调 `gc_write_barrier` / `gc_write_barrier_value`（同 `:10492` 的 `_scroll_rect` 与 `:10644`
  的 `children` 写法）。
- 挂树/摘树一律走 `addChild`/`addChildAt`/`removeChild`，它们已经自带
  `gc_write_barrier_value`（`as_array_push` 在 `src/runtime.ts:2959` 里调；`addChildAt` 在 `:10644`）。
- `ElementState` 全是非 GC 值，**不需要**屏障。
- 虚拟化列表的 item 复用是重点风险，见 §10 未决 2。

### 7.5 与 `as_disp_key` 教训的对照

| 反例（`as_disp_key`） | 本文的对应做法 |
|---|---|
| 每帧为查找构造临时字符串（`strlen+5` 进 arena） | key 用整数 `keyId`；样式用指针身份；`childrenByKey` 用整数查表 |
| 用完即弃但进永不回收的 arena | describe 用**可 reset 的私有 buffer**；持久对象才进 GC 堆 |
| 每帧对每个祖先/目标都调用 | reflow 每帧一次批量；未标脏子树整棵跳过；hover 只标 paint 位 |

---

## §8 完整示例：AS3 登录页

> 语法按 AS3 写；每个 API 后面用注释标出它落在哪条接缝。

```as3
// LoginView.as —— 登录页根 View
package
{
    import asaot.ui.*;
    import asaot.ui.style.*;

    public class LoginView extends View
    {
        // ---- 业务状态：App 所有，跨帧存活（对应 GPUI 的 Entity<T>）----
        public var form:LoginForm = new LoginForm();

        // ---- 样式：静态常量，只构造一次（§2.4）----
        private static const PAGE:StyleRefinement = StyleRefinement.from({
            flexDirection: "column",
            gap: 12,
            padding: 24,
            size: [Length.pct(1), Length.pct(1)]
        });

        public function LoginView():void
        {
            this.form.subscribe(this.onFormChanged);   // §5.1 数据流接缝（订阅一次）
        }

        // §5.1：Observable.notify → View.invalidate → UiApp.invalidate
        private function onFormChanged(dirty:int):void
        {
            this.invalidate(dirty);
        }

        // ★ 作者模型接缝（§1.1）：只在脏时被 framework 调用；纯描述、无副作用
        override public function render():Node
        {
            return box({
                key: "root",
                style: PAGE,
                keyContext: "login"                       // §6.2 键盘上下文
            }, [
                text("登录", {
                    key: "title",
                    style: Styles.title,
                    ariaName: "登录标题"                   // §4.3 a11y 元数据
                }),

                textField({
                    key: "account",
                    value: bind(this.form, "account"),     // §5.1 数据流接缝（单向绑定 + 回写）
                    placeholder: "账号",
                    style: Styles.input,
                    ariaName: "账号",
                    onCommit: this.onCommit
                }),

                textField({
                    key: "password",
                    value: bind(this.form, "password"),
                    password: true,
                    style: Styles.input,
                    ariaName: "密码",
                    onCommit: this.onCommit
                }),

                checkbox({
                    key: "remember",
                    label: "记住我",
                    checked: bind(this.form, "remember"),
                    ariaName: "记住我"
                }),

                button({
                    key: "submit",
                    label: "登录",
                    style: Styles.primary,
                    action: "login.submit",                // §6.1 键盘接缝（action id）
                    onClick: this.onCommit                 // 鼠标点击
                }),

                // 空字符串在 AS3 里是假值；用它控制 visible（§3.3 → M_ARRANGE|M_PAINT）
                text(this.form.error, {
                    key: "error",
                    style: Styles.error,
                    ariaName: "错误信息",
                    visible: this.form.error.length > 0
                })
            ]);
        }

        // 提交：改业务状态 → notify → 同一重绘路径（不直接碰 UI）
        private function onCommit():void
        {
            this.form.submit();
        }
    }
}
```

```as3
// Styles.as —— 主题/样式常量（静态，只构造一次）
package
{
    import asaot.ui.style.*;

    public final class Styles
    {
        public static const title:StyleRefinement = StyleRefinement.from({
            text: { fontSize: px(24), fontWeight: "bold", color: 0xFF1A1A1A }
        });

        public static const input:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), auto()],
            padding: edges(8, 12, 8, 12),
            cornerRadii: corners(4, 4, 4, 4),
            background: Fill.solid(0xFFFFFFFF),
            borderWidths: edges(1, 1, 1, 1),
            borderColor: 0xFFCCCCCC
        });

        public static const primary:StyleRefinement = StyleRefinement.from({
            padding: edges(10, 16, 10, 16),
            cornerRadii: corners(6, 6, 6, 6),
            background: Fill.solid(0xFF2F80ED),
            text: { color: 0xFFFFFFFF, fontWeight: "bold" }
        });

        public static const error:StyleRefinement = StyleRefinement.from({
            text: { color: 0xFFD32F2F }
        });
    }
}
```

```as3
// LoginForm.as —— 纯业务状态（Observable，不继承 EventDispatcher）
package
{
    import asaot.ui.*;

    public class LoginForm extends Observable
    {
        public var account:String = "";
        public var password:String = "";
        public var remember:Boolean = false;
        public var error:String = "";

        public function submit():void
        {
            if (this.account.length == 0) {
                this.error = "请输入账号";
                this.notify(Dirty.VALUE);              // §5.1
                return;
            }
            // …真实登录…
        }
    }
}
```

```as3
// Main.as —— 启动
package
{
    import asaot.ui.*;
    import flash.display.Sprite;
    import flash.system.Capabilities;

    public class Main extends Sprite
    {
        public function Main():void
        {
            var app:UiApp = new UiApp(new LoginView());
            app.setKeymap(KEYMAP_JSON);                // §6.3
            app.mount(this.stage);                     // §5.2 建 UiRoot、注册 ENTER_FRAME
        }

        [Embed(source="keymap.json", mimeType="application/octet-stream")]
        private static const KEYMAP_JSON:String;
    }
}
```

```json
[
  { "context": "login", "bindings": { "enter": "login.submit" } },
  { "context": "login > modal.confirm", "bindings": { "cmd-enter": "login.submit", "escape": "modal.cancel" } }
]
```

**逐 API 标注（与接缝对照）**

| 示例里出现的 API | 接缝 / 章节 | 对照 GPUI |
|---|---|---|
| `View.render():Node` | 作者模型（§1.1） | `Render::render`（`element.rs:164-166`） |
| `box/text/button/textField/checkbox` | 控件集（§4.2） | `div`/`text`/`button` 元素 |
| `key:` | 节点身份（§1.2） | `Element::id()`（`element.rs:66`） |
| `style:` + `Styles.*` | Style（§2） | `Style`/`StyleRefinement`（`style.rs:180`） |
| `bind(this.form,"account")` + `subscribe` | 数据流（§5.1） | `Entity`/`Context::notify`（`context.rs:221`） |
| `ActionRegistry` / `action:` / keymap JSON | 键盘（§6.1–6.3） | actions + key context（`docs/key_dispatch.md`） |
| `ariaName:` | a11y 形状（§4.3） | `a11y_role`/`write_a11y_info`（`element.rs:113/:121`） |
| `textField` 内部 | `TextField` 通道（§4.4） | GPUI 自有 text system（我们**不借**） |
| framework 的 measure/arrange/paint | 三趟管线（§3.1） | `request_layout`/`prepaint`/`paint` |

---

## §9 与 `flash.*` 的边界

一句一例。总原则：**已在 `flash.*` 里与 `adl` 逐值对齐的东西继续用 `flash.*`；新控件层只在
`asaot.ui.*`；两者不互相改写、不互相塞成员。**

### 9.1 必须继续用 `flash.*`（已与 `adl` 对齐）

| 能力 | 用什么 | 为什么不新写 |
|---|---|---|
| 显示对象与父子/变换/遮罩/九宫格 | `flash.display.Sprite/Shape/Bitmap/MovieClip` + `addChild`/`transform`/`mask`/`scrollRect` | `as_render_object`（`:22235`）已逐条实现 AIR 语义 |
| 文本对象与排版 | `flash.text.TextField`（`textField` 包装内部用它） | SkParagraph 通道已对 `adl` 校准（`flash-text.md`/`skia.md`） |
| 事件三阶段 | `flash.events.EventDispatcher` / `Event` / `KeyboardEvent` / `FocusEvent` | `as_disp_target`（`:10052`）已校准 |
| 几何 | `flash.geom.Rectangle/Point/Matrix` | 零新口径，直接复用 |
| 舞台与窗口 | `flash.display.Stage`（`stage.focus`/`stageWidth`）、`flash.display.NativeWindow` | 焦点/窗口已对齐（`:11725`、`NativeWindow` 43 成员） |
| 定时/异步/资源 | `setTimeout`、`Loader`、`BitmapData` | 既有实现 |

### 9.2 新的 `asaot.ui.*`（AIR 无对应物 ⇒ 增强，具名开关）

| 新 API | 说明 |
|---|---|
| `Node` / `View` / `UiApp` | 声明式作者模型 |
| `Style` / `StyleRefinement` | 样式值表与继承 |
| `LayoutEngine` | 自动布局（flexbox）的**纯 AS3 接口**；**当前唯一实现** `As3LayoutEngine`（纯 AS3 子集，`mxmlc`→`adl` 可跑），`UiApp` 恒用它；已完成三端逐值对照验收。（`NativeLayoutEngine`（内建类 → 不透明 C 接缝 `as_ui_yg_*` → Yoga）为**已搁置**的备查选项——需改编译器，见 `compiler-gaps.md`。） |
| `box`/`text`/`button`/… | 控件集 |
| `Observable` / `bind` / `notify` | 最小粒度重绘信号 |
| `ActionRegistry` / `ActionRegistry.setKeymap` | 可配置快捷键 |
| `FocusChain` / `group(...)` | 分组 Tab 序、模态内循环 |

### 9.3 不得混入（红线）

1. **不给 `flash.*` 加成员**（无 `Sprite.setStyle`、无 `TextField.onAction`）。
2. **不用 `flash.events.Event` 做 UI 通知**（`notify` 不走 `dispatchEvent`，见 §5.1）。
3. **不对控件 backing 直接 `addChild`/`removeChild`**（会绕过 reconcile，导致 retained 树与描述树脱节）。
4. **不对控件 backing 直接设 `x/y/width/height`**（布局归 LayoutEngine；手写会重演「没有布局」的时代）。
5. **不新开文本口径**（见 §4.4）。
6. **不绕开 `WinCtx.dirty`**（见 §5.2）。
7. **不改 `as_focus_obj`/`as_tab_scan`/`as_focus_tab` 的 C 实现**（见 §6.4，只 `preventDefault` 旁路 Tab 分支）。

---

## §10 本草案未决的问题

1. **Style 到底要不要树外缓存（interning）？** 本文选「节点内写就 buffer + 指针身份跳过」，
   零 hash、零全局表。若多窗口共享同一主题、或同一样式被上千节点共用，interning 可能省内存；
   但会把 `Style` 生命周期绑到全局表。**需先测**：典型界面的 `Style` 实例数与查表成本。
2. **虚拟化列表与 GC 写屏障怎么写？** item 复用（同一 backing 换数据）时，`children` 数组的
   splice、`scrollRect` 的更新、item 池的根注册都需要明确屏障与根策略。`scrollRect` 已有屏障
   （`:10492`），但 item 池的复用路径没有先例。**必须先 write-barrier 清单再实现。**
3. **`as_tab_scan` 64 上限放开后的 `adl` 口径未实测。** 需写 >64 tabbable 的 probe，在 `adl`
   上记录顺序/环绕/锚点，再让 `FocusChain` 逐项对上。**未实测前不声明 >64 的语义。**
4. **describe 缓冲池的生命周期。** 若作者把 `Node` 存进字段跨帧使用，会与 `arena.reset()` 冲突。
   是否要在 `render()` 返回后做「逃逸检测」（例如引用计数/版本号）并报错？
5. **`notify()` 的粒度是否够用。** `VALUE/DECOR/STRUCTURE/THEME` 四类是本文的猜测；跨 View 的
   批量合并（一次 notify 影响多个 View）与重入（notify 里再 notify）策略未定。
6. **「无变化帧零重绘」需要 glue 的 idle 模式。** 当前 `window_glue.cc:792-796` 每帧标脏所有可见
   窗口；本文只能保证「无变化帧不 describe/reflow」。要字面零重绘，需给 `sk_pump_frame` 加
   「无 pending 且无动画则不休眠之外的跳过」的规则，属独立改动。
7. **keymap 与文本输入的冲突细节。** plain 字符键、AltGr、IME 组合期（`textEditing`）都还没测；
   GPUI 的 `prefer_character_input`（`interactive.rs` 的 `KeyDownEvent`）等价物未定。
8. **`Stage3DRenderer` 的 paint 语义未定**：是复用 backing DisplayObject 树，还是直接写 Scene 图元？
   主文档 §6 把它列为后续接缝，本文未展开。
9. **a11y role 枚举 → AccessKit Role / UIA ControlType 的映射表未定**（属 U6）。
10. **LayoutEngine 接缝的 measure 闭包形态未定**：Yoga 用 measure callback，我们可能两趟
    （先测 intrinsic，再 solve）；文本 intrinsic measure 的缓存键（字符串指针？段落哈希？）需定。
11. **窗口 resize 时是否重跑 describe？** 若 `render()` 读 `stage.stageWidth`，resize 必须重跑；
    若不读，只需重排根。如何判定（静态扫描？运行时 `_readsStageSize` 标志？）未定，且有抖动风险。
12. ~~**两后端（`As3LayoutEngine` 子集 vs `NativeLayoutEngine`/Yoga）的一致性怎么保证？**~~
    **已落定（2026-10-22）**：UI 库走**纯 AS3**，`NativeLayoutEngine`（Yoga）**已搁置**——不再有两套
    实现需要防 drift。差分测试已建成并跑通（[`diff-check/`](diff-check/)：同一份 `spec/cases.txt` 喂
    Yoga 与 AS3 引擎逐行比对；含单侧变异证明 harness 有牙），但它现在的角色是**验收基准对照**
    （不是两实现互校）。未实现的语义一律 `throw`，缺口表见 [`seam/README.md`](seam/README.md) §4。

---

## §11 与主文档的偏差 / 澄清

主文档 `ui-toolkit-feasibility.md` 是裁决文档；本文如与之不一致，以主文档为准。逐条：

1. **U3「无变化帧零重绘」**：当前 `window_glue.cc` 的帧时钟每帧把所有可见窗口标脏
   （`:792-796`），字面零重绘在当前后端**达不到**。本文把验收降为「无变化帧不做
   describe/reconcile/measure/arrange」，并把「glue idle 模式」列为 §10 未决 6。这是**偏差**，
   需主文档/U3 在实施时确认验收口径。
2. **B7「在 `as_focus_obj`/`as_focus_tab` 之上加一层 FocusChain」**：本文明确为「加层 +
   `preventDefault()` 旁路 C 的 `as_focus_tab` Tab 分支（`:11611`）+ `stage.focus` 回到
   `as_set_focus`（`:11725`）」。这不是替换焦点模型，而是换「序从哪来」；与主文档一致，仅**补充**了
   旁路的具体机制。
3. **§5 的示例 API**：主文档用 `list({ items: this.rows, itemKey: ... })`；本文沿用同名参数
   （§4.2 的 `list(opts)`）。
4. **§6 的 `Renderer` 接缝**：本文把 `DisplayListRenderer` 定义为「维护 backing DisplayObject
   树、复用 `as_render_object`」，即 renderer 不重写 Skia 调用。这是对主文档 seam 的**澄清**，
   不改变「后端无关」的目标（`Stage3DRenderer` 仍另走图元）。
5. **主文档 §7「U1 前置测量」**：本文不重复 U1 的 Yoga 体积/wasm 测量结论，只把 LayoutEngine
   当作已存在的接缝；U1 测不过时退回「AS3 侧 flexbox 子集」的退路与主文档一致。

---

## §12 参考（本文引用到的位置）

- **主文档**：[`ui-toolkit-feasibility.md`](ui-toolkit-feasibility.md)（§5 为什么不能每帧重建、§6 三条接缝、§7 U2~U5）。
- **GPUI 检出**（`asaotui/gpui-src/crates/gpui/`）：
  - `src/element.rs`：`Element` 关联类型 `:59`、trait `:52-105`、`id()` `:66`、四趟 `:74/:84/:96`、
    树丢弃语义 `:10-14`、`GlobalElementId` `:220`、`hash`/`extend_path_hash` `:231`、
    `a11y_role`/`write_a11y_info` `:113/:121`、`Render::render` `:164-166`。
  - `src/style.rs`：`Style` 值表 `:180-322`（38 字段、11 个 `#[refineable]`）、`TextStyle` `:438`。
  - `src/geometry.rs`：`AbsoluteLength` `:3310`、`DefiniteLength` `:3472`、`Length` `:3623`。
  - `src/tab_stop.rs`：`TabStopMap` `:11`、`TabStopOperation` `:19-23`、`TabStopPath` `:39-42`。
  - `src/window.rs`：`ElementId` `:7635`、`FocusHandle`/`FocusId` `:543`/`:339`。
  - `src/app/context.rs`：`notify` `:221`、`observe` `:64`、`subscribe` `:94`。
  - `src/keymap/context.rs`：`KeyBindingContextPredicate` `:172-197`。
  - `docs/key_dispatch.md`（actions + key context + JSON keymap）、`docs/contexts.md`（entity/notify）。
  - `examples/tab_stop.rs`（`tab_group()`/`tab_index()` 用法）、`grid_layout.rs`、`tree.rs`。
  - `crates/refineable/src/refineable.rs`（`Refineable::refine` 语义）。
- **本项目源码**（`as3compiler/`）：
  - `src/emit.ts`：`as_focus_obj` `:10782`、`as_set_focus` `:10827`、`as_tab_scan` `:10860`
    （64 上限注释 `:10857`、`tabs[64]` `:10884`）、`as_focus_tab` `:10881`、`as_focus_from_mouse_down` `:10904`、
    `Stage_set_focus` `:11725`、Tab 分支 `:11611`、`as_render_object` `:22235`、
    `as_render_object_content` `:22477`、`DisplayObjectContainer_addChild` `:10607` / `addChildAt` `:10629`、
    `_scroll_rect` 屏障 `:10492`、`as_tf_paragraph` `:18493`、`TextField` 度量 `:18796`/`:18808`、
    `Stage_dispatchFrame` `:21087`（`gc_step` `:21108`、ENTER_FRAME `:21134`）、
    `ASC_window_on_redraw` `:23621`、`ASC_window_render` `:23197`、`as_render_object(canvas, stage)` `:23304`、
    自动烘焙 `:21749-21764`、`as_bake_scale` `:21797`、命中测试 `:15998`/`:16043`、`as_disp_target` `:10052`。
  - `vendor/window_glue.cc`：`WinCtx.dirty` `:387`、帧时钟标脏 `:776`/`:796`、只重绘 dirty 窗口 `:809-820`、
    `sk_pump_frame` `:758`、`present_frame` `:496`、`SDL_KEYDOWN` `:1360`。
  - `src/runtime.ts`：`as_array_push` `:2959`（含 `gc_write_barrier_value`）、`as_str_alloc` `:985`、
    `as_show_redraw_regions` `:177-188`。
  - `docs/zh-cn/`：[`flash-text.md`](../as3compiler/docs/zh-cn/flash-text.md)、
    [`skia.md`](../as3compiler/docs/zh-cn/skia.md)、[`gc.md`](../as3compiler/docs/zh-cn/gc.md)、
    [`rust-text-backend.md`](../as3compiler/docs/zh-cn/rust-text-backend.md)。
  - `TODO.md`：`as_disp_key` ~39 KB/s 先例 `:1238`/`:1242`/`:1249`；「UI 工具链待定项（未排期）」`:14086`。
  - `as3compiler/AGENTS.md` §0 / §1.5 / §2.4 / §2.6 / §2.7（红线，本文未改）。
