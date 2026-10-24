# asaot.ui — 完成度实测表（STATUS）

> 回答一个问题：**「UI 库写完了吗？」**
>
> 结论：**深水区做透了，表面层补齐了三批（控件集 + 多页 App + 组件目录页 + 浮层系统 + 交互动线），但还不是一个完整工具箱。**
> 深水区（布局引擎 + 三端差分）做透；**控件集从 4 个扩到 35 个 kind / 40 个工厂**（第二批 media/feedback/data 九件、
> 第三批**浮层六件 dialog/drawer/popover/menu/toast/select**、第五批**列表虚拟化 `virtualList` + 选择三件**
> `tree`/`combobox`/`datePicker` 均已落地）；
> **样式面从 18 字段补到 31 字段**；**组件文档站已跑起来**（`ui-demo/demo/DocsMain.as`，**41 页 / 9 组**，每页两个 live 示例 + 产生它的源码），
> 且**每个注册过的 kind 都在画廊里看得见**（`tools/kind-coverage.cjs` 扫描门：**35/35**，变异 3/3）；
> **浮层走第二棵保留树**（`View.renderOverlay()` + `UiApp.overlayRoot`），主树因此不再为弹层重解布局。
> 第四轮（2026-10-24）补的是**交互动线**：`disabled` + `hover/pressed/focused` 四态绘制、`textField` 编辑回写、
> **键盘/焦点管线（Tab 环 / Esc / 方向键 / Enter / Space）**、浮层的**越界翻转 + 子菜单 + 入场动画**。
> 第六轮（2026-10-24）把 demo 收成**一个组件文档站**：41 页，每页 2 节示例，示例与源码同源；
> 删掉登录 demo 与旧 7 页画廊，`ui-demo/demo/` 现在只有文档站（17 个 `.as`）。
> 第五轮（2026-10-24）补的是**动画深度 + 三处控件空白**：`Anim` 现在分 **paint 字段**与 **layout 字段**
> （`width/height/padding/gap` 动画每帧重解、`textColor/cornerRadius` 可 tween）、浮层加**退场动画**；
> `virtualList`（千级列表只挂 9 个节点）、`tree`、`combobox`、`datePicker`（纯整数日历，无 `Date`）落地。
> 两个 demo 现均用 **`--air-app`** 编译：窗口属性（含**高分辨率/HiDPI**）由 AIR 描述符当唯一真相源。
> 仍然缺的是：`icon`（图标字体/矢量集）、`accordion` 多开、`table` 排序/列宽拖拽、
> 样式面的 `grid`/`boxShadow`/`cursor`，以及可访问性字段仍无消费者（`role`/`ariaName` 只是数据）。
>
> 本表每一行都有可复核的命令。**不要采信本表，跑它。**

生成日期：2026-10-24（第六轮） · 对应 `kit/` **155 个 .as** · 一次性验收：`node tools/gates.cjs`（**34 道门**）

---

## 1 一句话分层结论

| 层 | 状态 | 判据 |
|---|---|---|
| L1 渲染（Skia + Stage3D） | ✅ 复用编译器运行时 | `layout-check/visual-check.cjs` 12 项像素断言；AOT ↔ AIR 两张 BMP **0 字节差异** |
| L2 布局引擎（flexbox 子集） | ✅ **做透** | `layout-check` **133 项手算断言全绿**；Yoga == AOT == AIR **105 行 0 差异** |
| L2 显示树 / 协调 / 数据流 | ✅ 可用（累计修 12 个缺陷，见 §3.3） | keyed reconciler + `markLayoutDirty` 上传 + Observable/Binding；**两棵保留树**（主树 + 浮层树） |
| L2 事件 | ✅ **鼠标 + 键盘/焦点** | 悬停/按下/点击；`UiApp` 接 stage 的 `KEY_DOWN`/`FOCUS_IN`/`FOCUS_OUT`：**Tab/Shift+Tab 焦点环**（遍历保留树，浮层内是焦点陷阱）、`Esc`、方向键、`Enter`/`Space` 激活；控件用**可选接口** `WidgetKeys`/`WidgetFocus` 参与（`probes/widgets/interact` 25 项）。边界：Tab 环上限 64（`compiler-gaps.md` G3）、无按键重复/快捷键表 |
| L2 动画 | ✅ **样式 5 字段 + layout 字段 + 浮层入/退场** | 样式 `paint` 字段：`opacity`/`background`/`borderColor`/`textColor`/`cornerRadius`；样式 **`layout` 字段**：`width`/`height`/`padding`(T/R/B/L)/`gap`(X/Y)——写回后 `applyEngineStyle()` + `markLayoutDirty()`，**每帧重解布局**，落地即停（`probes/widgets/anim` 14 项 + `probes/widgets/motion` 23 项）；显示对象级：`OverlayMotion`（入场 140ms ease-out / **退场 120ms ease-in**，墙钟，每帧从引擎读基准，不累加），见 §3.4 |
| L3 控件库 | ✅ **40 个工厂 / 35 个 kind** | 见 §2；第三批浮层六件（dialog/drawer/popover/menu/toast/select）+ 第五批 `virtualList`（列表虚拟化）/`tree`/`combobox`/`datePicker` 已落地。**35 个 kind 全部上了画廊**（第七页 Advanced），由 `tools/kind-coverage.cjs` 自动核验：kind → 注册它的节点类 → 构造该类的工厂函数 → 画廊是否**调用**了其中之一。顺带修掉一处**陈旧计数**：文档原写「34 个 kind」，实际注册表有 35 个（`scrollView` 加进来后从没被计过数）——现在这个数字由门看着 |
| L3 样式面 | ✅ **31 字段** | 见 §3.2；仅剩 `grid`/`boxShadow`/`cursor` 刻意缺席 |
| L3 浮层（第二棵树） | ✅ **六件 + 一套 chrome + 翻转/子菜单/入退场** | `View.renderOverlay()`；主树先解、浮层树后解后画、置顶；**越界自动翻转**（四向 + 夹回窗口）、`menu` 支持**子菜单**（子菜单就是普通 anchored popover）、**入场 140ms / 退场 120ms**；`probes/widgets/overlay` **65 项**（变异 **9/9**）+ `probes/widgets/flip` **54 项**（变异 **5/5**）+ `probes/widgets/motion` **23 项**（变异 **7/7**） |
| L3 组合能力 | ✅ **41 页组件文档站** | `ui-demo/demo/Docs*.as`（17 个文件）+ `ui-demo/run-gallery.cjs`：左侧 9 组 / 41 页索引，右侧每页 = 标题 + 摘要 + meta + 若干节，每节 = 标题 + 说明 + **live demo** + **产生它的源码**（同一次 render ⇒ 源码不漂移）；控件驱动切页、手算矩形 + 浮层树销毁判据；**`--air-app` 构建 ⇒ 高分辨率已实测**（`ui-demo/check-dpi.cjs`：standard 1000×700 / high 1500×1050） |
| L3 可访问性 | ⚠️ 半成品 | `role`/`ariaName` **仍只是字段**（无消费者）；但 `Control.tabEnabled` 现在真被 Tab 环读（`UiApp.collectFocus`）、`Element.disabled` 真阻断点击与导航 |

---

## 2 作者可见 API 全清单（155 个文件里**只有这些**）

复核命令：

```sh
cd asaotui && node tools/scan.cjs kit/asaot/ui/list.as "public function"
```

| 工厂函数 | 产出 | 说明（第一参数类型别传错：`chip`/`badge`/`radio`/… 收**标签串**） |
|---|---|---|
| `box(opts, children)` | `BoxNode` | 布局容器（默认 column） |
| `row(opts, children)` | `BoxNode` | 同上，`direction="row"` |
| `column(opts, children)` | `BoxNode` | 同上，`direction="column"` |
| `card(opts, children)` | `CardNode` | **真容器**（有 `internalCount` 子件：背景/边框/标题）；⚠️ 标题不占布局位，见 §3.3 |
| `text(content, opts)` | `TextNode` | 静态文本 |
| `label(content, opts)` | `TextNode` | `text` 的别名 |
| `button(opts)` | `ButtonNode` | 标签 + 点击（`label`/`onClick` 在 opts 里） |
| `textField(opts)` | `TextInput` | 单行输入，可绑定 `value`；**编辑回写**（`Event.CHANGE` → `Binding`/`onChange`），`Enter` 或失焦提交 `onCommit`，`Esc` 回滚；**占位符是独立文本层**（不再往编辑框里写 ghost text） |
| `checkbox(opts)` | `CheckboxNode` | 可绑定 `checked` |
| `radio(label, opts)` | `RadioNode` | 单选；`opts.selected` 收 boolean **或** `Binding`；`opts.group` 只是名字 |
| `toggle(label, opts)` | `SwitchNode` | 开关（**工厂名是 `toggle`**，`switch` 是保留字） |
| `slider(label, opts)` | `SliderNode` | 可绑定 `value`；拖动改值 |
| `progress(label, opts)` | `ProgressNode` | 可绑定 `value`（只读展示） |
| `chip(label, opts)` | `ChipNode` | 可点击小标签（tone: neutral/info/danger） |
| `badge(label, opts)` | `BadgeNode` | 纯展示标签 |
| `avatar(name, opts)` | `AvatarNode` | 首字母圆形头像 |
| `divider(opts)` | `DividerNode` | 1px 分隔线（`orientation`） |
| `tabs(labels, opts)` | `TabsNode` | 横向分段；**分段是控件自算**，见 §3.1.1 |
| `list(items, builder, opts)` | `ListNode` | 真容器（每行一个真实 UiNode）；**无虚拟滚动——万级用 `virtualList`** |
| `image(opts)` | `ImageNode` | 位图控件，**源是 `BitmapData`（不是 URL）**；`scaleMode`: `fit`/`stretch`/`none`；`payload` 懒建 `Bitmap` |
| `scrollView(opts, children)` | `ScrollViewNode` | **真裁剪**滚动容器（引擎 `scrollRect`）；竖向滚轮；视口用 `setMinMax(min)` 阻断子收缩 |
| `spinner(opts)` | `SpinnerNode` | 不定进度圆环；`diameter`/`thickness`/`tone`/`spin`/`phase`；**环画成填充带（描边宽度不被遵守）** |
| `skeleton(opts)` | `SkeletonNode` | 占位骨架；`variant`: `text`/`circle`/`rect` + `lines`/`barHeight`/`gap`/`tone` |
| `tooltip(text, opts)` | `TooltipNode` | 气泡提示；`arrow`: `up`/`down`/`left`/`right`/`none`；标签**自绘居中**，尺寸可留 auto（自带内边距） |
| `table(columns, rows, opts)` | `TableNode` | 表头 + 数据行；`rowHeight`/`stripes`/`grid`/`selectedIndex`/`onSelect`；网格/条纹/选中一律**画成填充** |
| `accordion(sections, opts)` | `AccordionNode` | 单开手风琴；`activeIndex`（`-1` = 全关）/`onToggle`；**header 刻意无背景**（高亮由容器画，子节点在前） |
| `breadcrumb(items, opts)` | `BreadcrumbNode` | 面包屑；`onNavigate(index)`/`separator`/`currentIndex`；末项与分隔符都不可导航 |
| `pagination(page, pageCount, opts)` | `PaginationNode` | 翻页器；`windowSize` 槽位窗口、省略号原型 `-1`、`onSelect`/`page` |
| `overlay(children, opts)` | `BoxNode` | **浮层宿主**（第二棵树的根）：`size:[100%,100%]`、`position:absolute`、置顶；子序列 = 堆叠序（**无 z-index**） |
| `dialog(opts, children)` | `DialogNode` | 模态框；`open`/`title`/`width`/`scrim`/`closeOnScrim`/`onClose`/`footer`；`open=false` 不占命中也看不见 |
| `drawer(opts, children)` | `DrawerNode` | 边沿抽屉；`side`: `top`/`bottom`/`left`/`right` + `size` |
| `popover(opts, children)` | `PopoverNode` | 锚定气泡；`anchorKey` + `placement`: `top`/`bottom`/`left`/`right` + `offset`；点外面关闭 |
| `menu(opts)` | `MenuNode` | 锚定行列表（继承 popover 的锚定与关闭）；`items`: 字符串或 `{label,value}`、`selectedIndex`/`onSelect`；**`submenuIndex` 可挂子菜单**（子菜单是 `menu` 工厂产出的普通 anchored popover，父菜单不必自己定位） |
| `select(opts)` | `SelectNode` | 下拉选择；trigger 无边框，菜单是 trigger 的绝对子；`value`/`items`/`onChange` |
| `toast(opts)` | `ToastNode` | 轻提示；`open`/`message`/`tone`(default/success/danger)/`duration`/`onClose`/`width` |
| `toastHost(opts, children)` | `BoxNode` | 吐司堆：右下角、`gap 8`、后进在下；`toast` 必须放在它里面才能堆 |

配套（非控件）：`bindTo(owner, field)`、`Binding`、`Observable`、`Subscription`、
`Dirty`、`Theme`、`Style`/`StyleRefinement`/`Fill`/`Edges`/`LengthEdges`/`Corners`/`Length`/`Size`/`TextStyle`、
`Node`/`Element`/`ElementState`/`Control`、`Widget`/`Widgets`（控件扩展点）、`WidgetTeardown`（可选销毁钩子）、
`PaintKit`、`OverlayChrome`（浮层调色板/风格常量）、`OverlayList`（菜单/下拉共用的行几何）、
`Reconciler`、`UiNode`、`UiApp`（`getOverlayRoot`/`overlayDisplay`）、`View`（`render`/`renderOverlay`/`tick`）、
`Anim`/`Ease`/`Tween`/`AnimState`。

### 2.1 仍缺的控件（对照常见工具箱）

| 类别 | 缺什么 | 影响的界面 |
|---|---|---|
| 选择 | `accordion` 多开、`table` 排序/列宽拖拽（树/日期/可输入下拉已落地） | 仪表盘、可编辑表格 |
| 图形 | `icon`（`image` 已有，但没有图标字体/矢量图标集） | 工具条、按钮图标 |
| 无障碍 | `role`/`ariaName` 仍只是字段（无消费者） | 屏幕阅读器 |

**⇒ 现在能舒适写出的是「多页表单 / 设置页 / 列表详表 / 万级滚动列表 / 带图与骨架的异步页 / 弹层与菜单驱动的交互 /
树形设置 / 日期选择 / 可输入下拉」，写不出「图标字体 + 可排序表格 + 内建无障碍」类界面。**
（浮层六件落地后，`dialog`/`drawer`/`popover`/`menu`/`select`/`toast` 都已可用，手算断言探针：`probes/widgets/overlay`，**65 项**。）

---

## 3 最硬的几块短板

### 3.1 交互：鼠标四态 + 键盘焦点管线（已补）

第三轮时这一节的标题是「交互只有鼠标——键盘完全不支持」，实测 `KeyboardEvent`/`KEY_DOWN`/`focus`
在 `UiApp.as` 里全是 **0 处**。现在补齐了，判据全在一个探针里：

```sh
cd asaotui && node tools/probe.cjs probes/widgets/interact   # 25 项，含四态像素 + 键盘相位
```

| 能力 | 实现点 | 验证 |
|---|---|---|
| **`disabled`** 字段 | `Element.disabled`；`UiNode.inert()`（自己或任一祖先） | `handleClick` 早退（disabled 不再触发 `onClick`），进 Tab 环时跳过 |
| **四态绘制** | `PaintKit.drawBoxFor`：`hover` 提亮 8%、`pressed` 下沉 12%、`focused` 画 **4 条焦点环**（后端不认 `strokeWidth`）、`disabled` 让 backing alpha = 0.45 | 像素：`#e0e7ff` → hover `#e2e9ff` → press `#c5cbe0`；焦点环左条 `#2563eb` 盖在填充上 |
| **Tab / Shift+Tab** | `UiApp.focusNext()`：遍历**保留树**（不用运行时 `as_tab_scan`），`tabEnabled && !inert()` | 探针相位 D：`btnA → inp → nxt` 且跳过 disabled 的 `btnD` |
| **浮层内焦点陷阱** | 焦点已在 `overlayRoot` 子树后就**不逃出去** | overlay 探针的 Tab 相位 |
| **Enter / Space 激活** | `WidgetKeys.onKey` 优先，否则 13/32 当作点击（`TextField` 除外） | `interact` 的 `nxt` 相位 |
| **Esc 关闭浮层** | `PanelShellWidget`/`MenuWidget`/`SelectWidget` 各自吃 Esc（仅 `closeOnScrim`） | overlay 探针 |
| **方向键** | `MenuWidget`/`SelectWidget`：上下环绕并高亮 | overlay 探针 |
| **编辑回写** | `InputWidget`：`Event.CHANGE` → `n.value` + `Binding` + `onChange`，`Enter`/失焦 → `onCommit`，`Esc` 回滚；`payload` **只在描述符值变化时**采纳（controlled/uncontrolled 分界），重绘**不重赋** `tf.text`（保住 caret） | `interact` 相位 E：`st.name == "Ada"`、重绘不擦字、`onCommit` 收到值 |

**仍然缺的**：按键重复（长按不是持续事件）、应用级快捷键表、`Ime`/输入法合成、鼠标右键/双击语义。
缺口若来自编译器侧（如 Tab 环上限 64）一律登记在 `compiler-gaps.md`。

#### 3.1.1 容器/导航控件的已知边界（`tabs` / `list`）

| 能力 | 现状 |
|---|---|
| **虚拟滚动** | ✅ `virtualList`（第五轮）：**只有窗口内的行是 UiNode**（1000 项、视口 150、行高 20 ⇒ **9 个**节点）；作者持有数据，控件只报 `onScroll(offset)`，作者写回模型后重渲染。⚠️ `list`/`table` 仍是「每行一个真实 UiNode」——要万级就用 `virtualList` |
| **视口裁剪 / 滚动** | ⚠️ `scrollView` 用引擎 `scrollRect` 做**真裁剪**并接管竖向滚轮；`list` 本身仍不裁剪（超出自身高度的行会溢出），要滚动就套一层 `scrollView` |
| **键盘 / 焦点** | ⚠️ 部分是：焦点环/`Enter`/`Space`/`Esc` 已通（见 §3.1），但 `tabs` 还没接**方向键**、`list` 还没接**上下键选中**（两者仍只看鼠标点击）；`list` 的行也没进 Tab 环 |
| **tabs 分段的布局来源** | ⚠️ 分段是控件**自算**（`from n.absW` 的整数等分），**不是**引擎摆的子节点；`list` 的行**是**引擎摆的真实子节点 |
| **tabs 的 gap 来源** | ⚠️ `TabsWidget.payload` 先读 `opts.gap`，回落到 `n.resolved.gapX`（已解算值）。若一次重排**恰好只改了 gap**，分段 pitch 会用上一帧的 gap 一帧（`Reconciler` 是「先 resolve 后 payload」，payload 改方向会在同帧重解，见 §3.3） |
| **list 选择高亮** | ✅ 由 `list` 自身在 `shapeA`（子件之下）画高亮条；行本身需透明才能看见 |

### 3.2 样式面：本轮从 18 补到 **31 字段**（不再缺布局字段）

`kit/asaot/ui/style/Style.as` 现有 **31 个字段**（`node tools/scan.cjs kit/asaot/ui/style/Style.as "public var"`）：

| 组 | 字段 |
|---|---|
| 布局 | `flexDirection` `justifyContent` `alignItems` `alignSelf` `alignContent` `flexWrap` `gapX` `gapY` `flexGrow` `flexShrink` `flexBasis` `display` `aspectRatio` `position` `inset` `margin` |
| 盒 | `size` `minSize` `maxSize` `padding` `borderWidths` `boxSizing` `overflow` |
| 装饰 | `background` `borderColor` `cornerRadii` `opacity` `visibility` |
| 文本 | `text`（`TextStyle`） |
| 动画 | `transitionMs` `transitionEase` |

- `margin`/`inset` 用 **`LengthEdges`**（四边各自 Length），镜像 `Edges`；
- **未知字符串值在 `UiNode.applyEngineStyle` 抛错**（报字段名 + 值 + 可接受集合），不静默回落（AGENTS.md §2.5）；
- 布局验收基准**不是 `adl`**（AIR 无 flexbox），而是 W3C flexbox / 浏览器；
- 仍刻意缺席：`grid`、`boxShadow`、`cursor`（引擎不实现；seam 层面也会抛错）。

复核命令：

```sh
cd asaotui && node layout-check/visual-check.cjs            # 12 项（含新字段的像素断言）
cd asaotui && node tools/gates.cjs                           # 31 道门，含 layout-check 133 项
```

### 3.3 已定位并修复的框架缺陷（每个都有钉子）

| # | 症状 | 根因 | 修法 | 钉子 / 变异证据 |
|---|---|---|---|---|
| 1 | **纯装饰变更永不上屏**（改 `background` 后画面不变） | `UiApp.reflow()` 的绘制闸门只看 `layoutRan`/`_needsPaint`，而 `Dirty.ALL==15` **不含** `M_PAINT==64` ⇒ reconcile 跑过但没绘制 | `reflow()` 里加局部 `reconciled`（本轮 `_pending != 0` 跑过 reconcile 即为真），绘制分支改 `else if (root != null && (this._needsPaint \|\| reconciled))` | `probes/redraw`（14 项）。**变异**：去掉 `reconciled` 项 ⇒ 3 像素 FAIL / exit 1；还原绿 |
| 2 | **子树里的布局变化永不解算**（多页 demo 里换页后只有容器有矩形，子节点全 `0,0,0,0`；`layoutSolves` 永远 1） | `UiApp.reflow()` 的布局闸门**只读根节点**的 `M_MEASURE\|M_ARRANGE`；深层新建/重排/删除/改样式只在本节点置位 | `UiNode.markLayoutDirty()`：置两位后**沿 `parent` 上爬到根**，遇「已同时带两位」的祖先即停；`applyPayload`(relayout)、`resolveStyle`(f&1 / f&2)、`Reconciler` 新建节点 / 顺序变化 / `destroyMounted` 后父节点 —— 共 6 处调用。**PAINT 位刻意不上传**（祖先自己装饰没变就不该重绘，且纯 paint 变更仍不得重解布局） | `ui-demo/run-gallery.cjs`（第 11 道门）。**变异**：`applyPayload` 里去掉 `directionOverride` 变化时的重解 ⇒ body 沿用**上一页的方向**布局，`colA/colB` 手算矩形 FAIL |
| 3 | **keyed 重排后节点不移动**（CheckUi 的 `reorder moved 'a' down` / `'b' up` 两红） | `Reconciler.reconcileChildren` 在 `n.children = next` **之后**调 `orderChanged(n, next)` ⇒ 两个引用指向同一个数组，比较自我、恒返回 false ⇒ 从不重解 | 把 `orderChanged` 提到赋值**之前**（紧邻仍需要旧数组的销毁扫描） | `ui-demo CheckUi` 23 项。**证据是本轮真红真绿**：修前 `2 of 23 failed`（两句原话见 `reviews/checkui-fail.txt`），修后 `23 checks, 0 failures`（`reviews/checkui-fixed.txt`） |

| 4 | **auto 宽度的文本节点小于自己的内容**（面包屑分隔符的 `/` 挤在下一个 crumb 上：4px 字形被塞进 8px 盒、向右溢出） | `TextWidget.measure` 把**纯字形宽**当点尺寸发布，而引擎 `boxSizing` 默认 **border-box**（点尺寸 = 整盒）⇒ 内边距反过来吃掉内容。`Badge`/`Button`/`Card`/`Chip` 都加了内边距，只有 `TextWidget` 漏了 | `kind/TextWidget.as` 的 auto 分支改成 `measuredW + padH(padding) + borderH(borderWidths)`（高度同理） | `probes/widgets/data` 程序内断言 `sep.absW == sep.tf.textWidth + 8`（**与自己测量的字形比，不抄字体度量**）。**变异**：`probes/widgets/data/mutation.cjs` M5 把内边距去掉 ⇒ 红并点名「must include its insets」，还原逐字节一致 |
| 5 | **浮层树在窗口出现前按 560×460 兑底求解一次，之后永不再解**（弹层整体偏左偏上、宽度少 200px） | `UiApp.reflow` 只在 `availW/availH` 变化时抬头主树的 dirty；浮层的 HOST 是 `size:[100%,100%]`，**style 指针不变** ⇒ 指针级复用跳过 `resolveStyle`，百分比永远不重解 | `reflow` 的尺寸变化分支里**两棵树都** `dirty |= M_MEASURE\|M_ARRANGE` + `markLayoutDirty()` | `probes/widgets/overlay`（65 项）。**变异** `M4` 去掉浮层分支 ⇒ 红并手算矩形集体失配 |
| 6 | **面板画出来了但什么都没画**（矩形对、屏幕空） | `PaintKit.paintBox` / `OverlayList.band` 对 `n.shapeA == null` **静默跳过**；`PopoverWidget`/`ToastWidget`/`SelectWidget` 的 `build()` 没建 shapeA | 三者在 `build()` 里 `n.shapeA = new Shape(); n.backing.addChild(n.shapeA)`（child index 0） | 变异 `M5` 去掉 shapeA ⇒ 像素断言红 |
| 7 | **居中婵缩**（对话框/抽屉的层缩到面板宽） | 控件自己的选项 `width` 与样式简写同名，`OptionSupport.applyOpts` → `StyleRefinement.from(opts)` 把它当成 **layer 的显式尺寸**；flex 里显式 size **赢过 inset** | 两个工厂 patch 完 layer style 后 `n.style.size = null` | 变异 `M1` 恢复该泄漏 ⇒ `dlg:scrim`/`dlg:panel` 矩形红 |
| 8 | **菜单/下拉点哪行都只选第 0/1 行** | `MouseEvent.localX/localY` 是 **TARGET-relative**（冒泡时不变，与 AIR 一致），而点击目标是行 ⇒ 拿到的 y 永远在 0..rowHeight | 新增 `OverlayList.localYIn(n, e)`：沿 parent 累加 `t.y` 回到容器坐标系（chain 不到返回 `NaN`），菜单/下拉都用它 | 变异 `M3` 退回 `e.localY` ⇒ 高亮带永不移动 |
| 9 | **可见性翻转不上屏**（下拉重开时树上是 visible、Sprite 还是旧值） | `visible` 由 `arrangeSelf` 写给 `backing`，而只改 visible 的 payload 既不碰样式也不碰布局 ⇒ 没有 arrange 扫描 | `UiNode.applyPayload` 在 `vis != this.visible` 时补 `M_ARRANGE\|M_PAINT` + `markLayoutDirty()` | 变异 `M7` 退回单写字段 ⇒ 重开的下拉不可见 |
| 10 | **离开浮层页后的下一次点击抛 #1009**（画廊 tour 死在切页那一下，runner 报 TIMEOUT） | 弹层的「点外面关闭」监听挂在 **stage** 上，而节点销毁时无人摘除；回调读 `n.extra`，销毁已把它置空 | 新接口 `WidgetTeardown`（可选钩子）+ `UiNode.destroySubtree` 在置空**之前**调用；`PopoverWidget`（菜单/气泡/下拉）摘 stage 监听，`ToastWidget` 清 `setTimeout` | `ui-demo/mutation-gallery-teardown.cjs` **M1**：去掉钩子 ⇒ `Uncaught exception #1009` + TIMEOUT。**这个缺陷只有「建了再拆」的程序能看见——探针从不拆树** |
| 11 | **浮层宿主被永久留在 stage 上**（空 Sprite 叠在主树之上，每拆一次多一个） | 根节点**没有父 NODE**，`destroySubtree` 的「从父 backing 摘除自己」对根永不生效 | `Reconciler.destroyRoot` 先存 `backing` 再 `destroyMounted`，然后 `b.parent.removeChild(b)` | 画廊 tour 的 `stage.numChildren` 对基线断言；变异 **M2** ⇒ 红并点名「leaving page 5 left 1 display object(s) on the stage」 |
| 12 | **旋转的 spinner 其实只画了一次**（看上去在转，实际是第一帧的角度定住了） | 两个缺陷叠在一起：①`paintDirty`/`paintAll` **画完才清 `M_PAINT`**，于是 paint 里 `markPaint(n)` 抬的「下帧再画」当场被抹掉；②`reflow` 末尾 `_needsPaint = false` 同样抹掉 paint 期间抬的请求。③它一直没暴露，是因为 `_solvedW` 只在主树 solve 时才写 ⇒ `ENTER_FRAME` 的窗口尺寸检查**每帧都误判变了**、每帧重描述并顺带重画（一个缺陷遮住了另一个） | 把「消费」提到「画之前」：`reflow` 开头 `var wantsPaint = _needsPaint; _needsPaint = false;`（闸门用 `wantsPaint`）；`paintAll`/`paintDirty` 先清 `M_PAINT` 再 `paintSelf()` | `probes/widgets/feedback` 的「spinning repainted ≥3 in ≥4 frames」+「spinning re-solved layout == 0」两句。变异 **M5**（回到后清） ⇒ `repainted only 2 time(s) in 10 frames`；**M6**（把自抬位换成布局位） ⇒ `re-solved layout 9 time(s)` |
| 13 | **输入框看上去能用，实际上一摸就坏**（敲进去的字被下一次重绘擦掉，`onCommit` 永不触发） | `InputWidget` 是**只镜像**的：每帧把模型写进 `tf.text`；且 `payload` 把 `onChange`/`binding` 写到了一个**节点从未携带**的字段上 | `Event.CHANGE` 回写 `n.value`/`Binding`/`onChange`；`payload` **只在描述符值变化时**采纳（controlled/uncontrolled）；占位符拆成**独立文本层**；重绘时值相同则**不重赋** `tf.text`（保住 caret） | `probes/widgets/interact` 相位 E。变异 **M7**（退回只镜像） ⇒ 「retained node's value is '' not 'Ada'」；**M8**（去掉 commit） ⇒ 「Enter did not commit」 |
| 14 | **窗口变小后靠边定位的浮层永久错位**（flip 探针实测 `y=-80`，面板挂在锚点上方 200px） | 上一版用**尾随边**（`EDGE_BOTTOM`/`EDGE_RIGHT` + inset）定位，inset 由 parent 的 `absW/absH` 算 —— 而 `abs*` 是 **arrange 才写**的，measure 阶段读到的是**上一帧（旧窗口）**的尺寸；之后没人再测它，就永久偏了 | `measure` 只用**起始边**：位置 = 锚点矩形 ± `offset` ∓ 面板自身尺寸，**一个 parent 尺寸都不读**（只减 parent 原点做坐标换算） | `probes/widgets/flip` 54 项。变异 **M1/M2/M3/M5** 各去掉一半（不翻/少算自身高/不横翻/不夹回）⇒ 手算坐标红 |
| 15 | **入场动画在手泵帧的程序里永不落地**（画廊第 5 页整层弹层只有 3% 不透明，可所有矩形都完美） | `OverlayMotion` 是**墙钟**的，而 tour 用 `app.reflow()` 连拉，两帧之间 ~0 ms ⇒ 截图时 `t≈0`。更强的事实：一个**第一帧就开着**的浮层本来就没有「从哪来」 | `OverlayMotion.start()` 在 `enterFrameTicks == 0`（还没有帧时钟）时**不开动画**；同时画廊 tour 加两条像素判据（scrim `#999999`、面板 `#ffffff`） | `ui-demo/run-gallery.cjs` 的 `page5 pixels` 行；变异：把 skip 去掉 ⇒ scrim 不再是 `#999999` |
| 16 | **悬停/按下状态字段一直没人读**（`state.hover` 有维护、绘制不看） | `PaintKit.paintBox` 只读背景色，`Element.disabled` 甚至不存在 | `drawBoxFor` 派生四态；**且只对「可交互节点」派生**（`tabEnabled` 或带 `onClick`）——否则每个布局容器都会变成 CSS `:hover`，页面根节点在鼠下会亮 8% | `probes/widgets/interact` 相位 B/C 的手算像素。变异 **M1/M2/M3** 把三个常量归零 ⇒ 各自点名 |
| 17 | **浮层退场动画被` visible` 镜像当场擦掉**（开场 120ms 里面板直接消失，只剩背景色闪一下） | 作者的模型里 `open=false` 是**立即**的：下一次 reconcile 就把 `visible:false` 写到 `n.backing` | `UiNode.visibleHold`：退场期间**按住**镜像，只有拥有退场的 `PanelShellWidget` 写它；落地帧才放开 | `probes/widgets/motion` 的「**退场中强制重渲染**」相位（描述符全程 `visible:false`，中间态必须仍有 `alpha>0` 且 `backing.y != absY`）；变异 **M4/M5** |
| 18 | **虚拟列表的每一行被 flexbox 压成 16.67px**（1000 项里只挂 9 行，其中最后一行被压扁、窗口行数也算错） | 行高开` height` 不够：窗口取 `fit+1` 行，九行 20px 溢出 150px 视口，flexbox 把九行等分；而 `flexShrink:0` 被引擎编码成「flex:1 zero basis」反而夹成 0 | 每行同时钉 `height` **和** `minSize.height`——**min 才是真正钉住的那一个**（solve 后生效，溢出行整体落在 clip 外） | `probes/widgets/vlist` 的逐行矩形 + 溢出行像素 `(30,175)=#ffffff`；变异 **M3** 去掉 `minSize` ⇒ 「a row must not be flexed into the viewport」 |

| 19 | **弹层被下面的 UI 盖住**（下拉/日期面板一开，下层的卡片、按钮压在它上面；点了行没反应——点其实打在被盖住的位置） | **引擎没有 z-index**（`Style` 里刻意没有这个字段），**绘制顺序 = 兄弟顺序**。而 `select`/`combobox`/`datePicker` 的下拉是**属主的子节点**（`n.backing.addChild(drop)`）⇒ 在 display 列表里它夹在卡片中间，同一帧里后画的兄弟把它整块盖住。改 `visible`、改样式、上抬 1px 都不解决问题：位置对、矩形对、像素不对 | `UiNode.lifted`：控件在**打开翻转**时把**自己的 backing reparent 到 `app.stageContainer`**，放到 `overlayDisplay()` **之前**（= 主树全部之上、浮层树之下，所以 dialog 仍能盖住下拉），坐标改成 `absX/absY`（`stageContainer` 的原点就是窗口原点）；关闭时重新挂回 `parent.backing` 并用 `absX - parent.absX` 换算回来。layout / reconcile / keys / focus / 点击路径**一律不动**（它们走 `parent` 链，不看 display 树） | `probes/widgets/popup`（26 项，含「盖住卡片的那一行读像素」「lifted 时 `backing.parent == stageContainer` 且 x/y == abs」「关闭后像素回卡片色」「unmount 后 stage 子件数回基线」）。**变异 4/4**（`probes/widgets/popup/mutation.cjs`）：M1 = 不 lift（就是用户看到的那个缺陷）、M2 = 沿用 parent-relative x（整体左偏 20px）、M3 = 关闭不挂回、M4 = 只按 `parent.backing` 摘除（lifted 节点漏摘 ⇒ sprite 永久留在屏上） |
| 20 | **提示文字（placeholder）输入时不消失**；焦点刚进入、还一个字都没输时，光标和 ghost 文字**叠在同一格** | ghost 是 `paint` 里算可见性的独立文本层，而可见性条件漏了「已聚焦」这一条；并且编辑走的是 `Event.CHANGE` 回调，回调只写模型 —— 屏幕是否重画取决于**作者**有没有 invalidate（不 invalidate 的作者就永远看不到变化） | ghost 条件收敛为 `model 为空 && state.focused == 0 && placeholder 非空`（聚焦即藏：光标就在那儿）；`onFieldChange`/`commit` 各自 `app.markPaint(n)`，**控件欠屏幕自己的重绘**，不指望作者 | `probes/widgets/typing`（18 项，含 ghost 扫描区渲染像素数、focus 后归零、失焦且空才回来）。**变异 4/4**（`probes/widgets/typing/mutation.cjs`）：M1 = 强制 ghost 常显（用户报告的原症状）、M2 = 去掉聚焦闸门、M3 = `setTextFormat` 回到 paint、M4 = 失焦不报 commit。探针的 `onChange` **刻意不 invalidate**（否则作者侧重绘会把第 20 条整个盖住） |
| 21 | **输入过的字在失焦再聚焦后「复制一遍」**（`1111` 变 `11111111`，字形挤着往外长；`textWidth` 从 28.9 涨到 56.7） | `TextField.setTextFormat` 在本运行时是**追加 run**（`emit.ts:20417` 只 `_runs` 追加、`_runs_gen++`），不是替换范围；而排版器 `sk_textlayout_new_runs`（`vendor/skia_text_glue.cc:495`）对**每条 run** 都 `addText` 一遍模型里的字符串 ⇒ **重画 N 次就画 N 份**。`InputWidget.paint` 每次都调它 ⇒ 每帧多一条 run | 单格式字段**一律不调 `setTextFormat`**：`defaultTextFormat`（新建字段时生效）+ `textColor` 就够了；`paint` 只 `defaultTextFormat`/`textColor`，值没变**不重赋 `text`**（`text` setter 会清 run，但也会把 caret 甩到末尾） | 同上 `probes/widgets/typing`：`textWidth` 与**现场新建的干净字段**逐字对比（不抄字体度量）、字形列组只允许一串、`caretIndex` 跨 3 次重绘不动。变异 M3 ⇒ `textWidth is 56.7265625 ..., a fresh field measures 28.8828125 (runs accumulated)`。编译器侧登记在 `compiler-gaps.md` G20 |
| 22 | **容器上的 `onClick` 永远不触发**（侧栏一行点了没反应，`model` 也不动；但 `button` 正常） | `UiNode.applyPayload` 老老实实从描述符镜像 `Element.onClick`，可**描述符上的那个字段从来没被写入** —— `OptionSupport.applyOpts` 只拷 key/role/ariaName/visible/disabled，`onClick` 只有 button/checkbox/radio/slider/toggle/textField 六个**控件**工厂自己拷。`box({ onClick: f })` 于是拿到一个 null | `OptionSupport.applyOpts` 加一行 `if (opts.onClick != null) n.onClick = (opts.onClick as Function);` —— 一处修好所有容器（box/row/column/card/overlay/…） | `ui-demo/run-gallery.cjs` 的 `index click` 段：真按 stage 坐标点侧栏行，断言 `model.doc=="box"` + `view.lastPick=="box"` + 标题变了 + 上一页的 demo 已卸载。**变异**：删掉那一行 ⇒ 四条断言同时红 |
| 23 | **点了控件，数据变了，界面不变**（同一次运行里 `doc=box` 而标题仍写 "Getting started"、上一页的 demo 还挂着） | 模型 `DocsModel extends Observable`，控件回调里 `model.put/pick` 会 `notify()`，**但没有任何人 subscribe** ⇒ `notify` 空转，`UiApp._pending` 一直是 0，`reflow()` 不重新 describe。widget 只报告、作者重渲染的契约断在最后一步 | `DocsMain` 建好 app 之后 `model.subscribe(function (d:int):void { self.app.invalidate(d); })` | 同上门（`index click` 段先 `click` 再 `reflow`，不额外 `invalidate`：能不能刷新完全取决于订阅是否在） |
| 24 | **侧栏整行只有文字本身可点**（行高 26、宽 219，但 Label 右侧的空白点下去什么都不发生） | 命中测试是**按绘制区域**而非布局盒（`as_pick_hit_local` → Graphics 的 fill/stroke ∪ 子件）：行的样式只有 padding 没有 `background`，于是行自己的 graphics 是空的，只有标签的 TextField 是目标。这是**Air 的真实语义**（透明的容器不是点击目标），但作为导航行是设计缺陷 | `DocsStyle.NAV_ITEM` 加 `background: 0xF8FAFC` —— 与 `SIDE` 同色，**屏幕上看不出差别**，但行从此有填充区域（选中态本来就是 `0xEFF6FF`） | 同上门：示例按**行中心**（x=123，远在标签右侧）派发，加这条背景之前断言必红（命中测试落在祖先容器上，行自己的 backing 不是 target）。注释写清「容器只在绘制处可点」这条 Flash 语义 |

**已知边界（登记，不修）**：`card({title: ...})` 的标题画在内容盒左上角、**不占布局位**，
因此会压住第一个子节点（`kind/CardWidget.as:81` 的 `tf.x/tf.y = inset`）。
规避：把标题写成一个真正的子 `text(...)` 节点（画廊 demo 就是这么写的，见 `ui-demo/demo/GalleryView.as` 顶部注释）。
同理，`progress`/`slider` 的标签画在节点**顶部**、轨道在 `height-12` ⇒ 控件高度需 ≥ ~28 才不自我重叠
（这不是 bug，是「控件自绘 + 高度由作者给」的约定）。

### 3.4 动画：样式 5 字段 + **layout 字段** + 浮层**入/退场**（两种机制，刻意不合并）

`UiNode.applyAnim()` 拦截两类字段（`n.resolved` 是单一拦截点）：

| 类别 | 字段 | 落地方式 |
|---|---|---|
| **paint** | `opacity`/`background`/`borderColor`/`textColor`/`cornerRadius`（仅均匀半径可动） | 写回 `resolved` + `markPaint`，**不碰布局** |
| **layout** | `width`/`height`/`padding`(T/R/B/L)/`gap`(X/Y) | 写回后 `applyEngineStyle()` + `markLayoutDirty()`，**每帧重解布局**，落地即停 |

layout 动画的代价是明说的：它每帧触发一次 solve（`motion` 探针的 `solves 4→9→20`），所以
**只有真会动的长度才该 tween**；点长度（`margin`/`inset`）与非均匀圆角故意不支持，拼错字段名由
`Anim.isLayoutField()` 守成 **no-op**（不静默改错字段）。这也不违反「纯 paint 变更不得重解布局」——
那里钉的是 **paint** 变更，这里是**声明为 layout 的字段**在动。

浮层动效是**第二种机制** `OverlayMotion`：不重瞄样式字段，只在显示对象层做墙钟淡入 + 位移，
位置每帧从引擎读（**不累加、不缓存基准**——缓存过一次，toast 就永久高 100px）。入场 140ms ease-out；
**退场 120ms ease-in**（`startExit`/`applyExit`），落地才真正 `visible=false`——为此
`UiNode.visibleHold` 在退场期间**按住**镜像的 `visible`（描述符一直 `visible:false`，探针的
「退场中重渲染」相位专门盖这个）。
两者刻意不合并：样式动画的「from」是 `previous` 的差分量，而入场动画开始前后样式**一模一样**，
硬塞进 `resolveStyle` 只会让下一次真解析去跟一个假 `previous` 打架。

另外动画时钟刻意用 `getTimer()`（单调），不用 `new Date().getTime()`（系统时钟可能回退）。

### 3.5 工作树是**并发**的（本轮的一条真实教训）

本轮期间，**编译器侧的另一个会话在同一个工作树里**同时干活：它把 G13 修了（阶段二四九，含自己的
单测，未提交）、把 G8 的修复落了提交（阶段二四七）、把本工作区两个 runner 的 `--all-sources`
删了，甚至连我这个状态表的阶段号都校正过。⇒ 两条硬规矩：

1. **交付结论必须当场重测**。我的 `ui-demo/README.md` 写成于 21:25:54，runner 里
   「G13 已修、不再需要 `--all-sources`」落于 21:26:36——**同一分钟内文档就陈旧了**。
   凡「零改动」「当前处置」「不再需要 X」类断言，都不得拿几分钟前的结论当现况。
2. **仪器少报比没仪器更糟**。同样的排查里，“证明我们没碰编译器”的指纹工具暴露出自己**静默
   漏报首个脏文件**（对 `git status` 整段 `.trim()` ⇒ `" M path"` 的左空格被吃掉，路径被切成
   `rc/reach.ts`）。修好后加了 20 项钉子 + 一次变异，并升为第 15 道门。
   详见 [`reviews/probe-air-app-hidpi-2026-10-23.md`](reviews/probe-air-app-hidpi-2026-10-23.md) §6.1。

### 3.6 浮层的结构与边界（第二棵保留树）

浮层不是「画在主树上方的子节点」，而是 **`UiApp` 里的第二个根**（`overlayRoot`）。一条帧内的顺序是：
主树 describe→reconcile → 浮层树 describe→reconcile → **主树 solve** → **浮层树 solve** → 两棵树各画一次（浮层树最后，因此最上）。
为什么是两次 solve：锚定弹层（`popover`/`menu`/`select`）在自己的 `measure` 里读**锚点本帧的最终矩形**，
合成一棵树就没有「锚点已定稿、弹层才量」这个时刻。

| 能力 | 现状 |
|---|---|
| 堆叠顺序 | **子序列 = 堆叠序**，无 `z-index`。同一位置两个弹层同时开：后 add 的在上面。**从属主内部弹出的**下拉/日期面板/菜单要盖住后面的兄弟，就必须 **`lifted`**（reparent 到 stageContainer、排在浮层树之下，见 §3.3 第 19 条）——这是唯一手段，没有 z 序可以调 |
| 开关归属 | `open` 在**作者模型**里（`bindTo`/直接赋值），控件只负责 `visible` + 是否吃指针；关闭不删节点 ⇒ 行/滚动/悬停态不丢 |
| 遮罩 | `dialog` 的 scrim 是 `argb=0x00000000` 的透明填充**子件**：吃到点击（因此「点遮罩关闭」可行），但**看不到颜色**；叠在白底上实测 `#999999`（0x66 alpha） |
| 遮罩拦截范围 | 拦**鼠标**；并拦**键盘焦点**——`dialog.open` 时焦点进 `overlayRoot` 子树，Tab 在浮层内成环（焦点陷阱），关闭后回到主树（§3.1） |
| 锚定 | `anchorKey` 经 `findByKey` **跨两棵树**解析；锚点不在 = 关掉四条 inset（不会 `#1009`），弹层回到内容尺寸 |
| 越界 | **四向翻转 + 夹回窗口**：`placement` 是「**首选**方向」，放不下时翻到对面（对面也放不下就不翻）；inset 只用**起始边**，位置 = 锚点矩形 ± `offset` ∓ 面板自身尺寸（**不读 parent 尺寸**，见 §3.3 第 14 条）。`probes/widgets/flip` 54 项 |
| 子菜单 | `menu` 的 `submenuIndex` 挂一个**普通 `menu`**，`anchorKey` 指向自己的行、`placement:"right"`（于是自动继承翻转/点外关闭）。嵌套面板的 inset 必须做 **absolute→parent-local 换算**（减 parent 原点），否则整体偏一个菜单偏移 |
| 点击路由冲突 | 子菜单的矩形会与父菜单某行**在高度上重叠** ⇒ `OverlayList.rowAt` 跳过 `kind == "menu"` 的子件，`MenuWidget.onRowClick` 先用 `isInside` 排掉落在子菜单里的点击 |
| 动画 | **入场**有：`OverlayMotion`（140ms 墙钟 ease-out，淡入 + 8px 位移，落地即停、稳态零重画）；**退场**没有（关闭是瞬时） |
| 销毁 | `View.renderOverlay()` 返回 `null` ⇒ `destroyRoot` 拆整棵浮层树；挂在外部的资源（stage 监听、timer）由 `WidgetTeardown` 释放（§3.3 第 10/11 条） |

### 3.7 编译器工作树：本地的两个补丁**已随上游提交消失**

上一轮（2026-10-23）在这里披露了两个本地补丁：P1 `src/runtime.ts` 的 Win32 字符串转义
（否则生成的 C 语法错）、P2 `vendor/window_glue.cc` 的菜单空桩（否则链接期未定义符号）。
两者都已登记为 **G17/G18**。

**本轮复核（2026-10-24）：两个都已经在上游修好并提交**（HEAD `6121b30` → **`480b81c`**），
于是本地补丁被撤掉，编译器树回到 **CLEAN**：

```sh
cd asaotui && node tools/compiler-fingerprint.cjs
#   now 2026-10-24...  head 480b81c  0 files
#   -> the working tree is CLEAN right now (0 modified/untracked/deleted files)
```

⇒ 「`asaotui` 不动 `as3compiler/` 一行」这句结论**恢复了**（不是一个文件：零个）。
指纹工具的这次输出同时证明它是**双向**仪器：上一轮它报 2 个 modified，这一轮报 0 个；
两次差异完全在 HEAD（并发会话提交了），它自己能分清「我改了」与「别人提交了」。
收尾时用 `node tools/compiler-fingerprint.cjs --capture` 重拕快照（HEAD `480b81c`、**0 个脏文件**），
之后再跑就是 `compiler tree UNCHANGED -- 0 dirty files, byte-for-byte`。

## 4 已完成且**可复现**的部分（不是意图，是跑过的）

一条命令跑全部 **31** 道门：

```sh
node tools/gates.cjs          # 31/31 PASS 才叫绿（定稿记录 reviews/gates-all-16.txt）
```

> 全量 **31 道门**在 **CLEAN** 编译器树上跑绿（定稿记录 `reviews/gates-all-16.txt`，HEAD `480b81c`）；
> 上一轮 25 道门那次是 `gates-all-13.txt`，当时树上还带两个本地补丁（见 §3.7）——
> 那道 G11 门当时会据实报「modifications: M src/runtime.ts | M vendor/window_glue.cc」但**不会**因此变红，
> 它只对「测量期间又动了」敏感。

> 那道 G11 determinism 门在「**测量期间编译器源码真的在动**」时会给 `[SKIP]`（exit 3）而不是假红/假绿：
> 稳定但脏的树照样可测（PASS 会点名 `src/` 内容哈希），动了才算测不了。那分支自己也做过集成钉子
> （`reviews/gates-skip-path.txt`：`15/16 PASS, 1 SKIPPED`，exit 0 —— 那份记录是 **16 道门**时代跑的，机制与判据未变）。

| 验收 | 命令 | 期望 |
|---|---|---|
| **多页 App** | `cd asaotui/ui-demo && node run-gallery.cjs` | **7 页** tour 全绿（含组件目录页、浮层页与高级控件页）+ 7 张 `gallery-page*.png` + `RESULT: PASS`；tour 还把「无 engine 节点 / 零矩形 / backing 未挂」三类静默失败**升级为判据**（变异自证：把目录页的 `image` 设成 0×0 ⇒ 红并点名 page 4），并对浮层树断言「切页后 `stage.numChildren` 回到基线、`findByKey(ovlDlg)` 为 null」（变异 `ui-demo/mutation-gallery-teardown.cjs` **2/2**）；另加**两条浮层像素判据**：scrim `#999999`、面板 `#ffffff`（钉住「入场动画落地」，见 §3.3 第 15 条） |
| **画廊覆盖全部 kind** | `node tools/kind-coverage.cjs` | **35/35** 个注册 kind 都被画廊调用（0 个「无工厂」kind = 无作者面缺口）+ `RESULT: PASS`；**变异** `tools/mutation-kind-coverage.cjs` **3/3**（把 tree 调用改名；新增一个 kind+工厂却没人用——这正是**发生过两次**的回归；把调用藏进 `//` 注释——扫描器第一版就是这样把散文算成了代码） |
| **高分辨率（HiDPI）自证** | `cd asaotui/ui-demo && node check-dpi.cjs` | `standard` 700×560(1×) vs `high` 1050×840(1.5×)，且两次 tour 文本**逐字节相同** |
| **单页登录 App** | `cd asaotui/ui-demo && node build-and-run.cjs` | 8 项手算断言 + `750×563` 截图（1.5×）+ `RESULT: PASS` |
| **`--air-app` 闭包回归钉（G13，已修）** | `node probes/reach-freefn/run.cjs` | 默认闭包 kept **5/5** 且默认面**能建能跑**（修前是：红 + `unknown superclass 'Base' of 'p_Leaf'`） |
| 工具箱自检 | `cd asaotui/ui-demo && node run-check.cjs` | `23 checks, 0 failures / RESULT: PASS` |
| 控件探针 ×5（第一批） | `node tools/probe.cjs probes/widgets/{chip,form,display,nav,anim}` | 19 / 41 / 48 / 41 / 14 checks，全 0 failures |
| 控件探针 ×3（第二批） | `node tools/probe.cjs probes/widgets/{media,feedback,data}` | 43 / 43 / 77 checks，全 0 failures；变异 `tools/mutation-widget-probes.cjs`（media+feedback 4/4）、`probes/widgets/data/mutation.cjs`（**5/5**，含 M4 复现本轮修的层叠 bug、M5 复现本轮修的文本内边距缺陷） |
| **浮层探针（第三批）** | `node tools/probe.cjs probes/widgets/overlay` | **65 checks**，0 failures（A 段全场景矩形 + 像素、B 段真事件路点击、C 段抽屉、D 段菜单高亮带、E 段**子菜单**、F 段**入场动画**：中间态 `alpha<1` 且 `backing.y != absY`，落地后 `isRunning==false` / `alpha==1` / 不再重画）；变异 `probes/widgets/overlay/mutation.cjs` **9/9**（其中 5 例是把真缺陷重新植入，1 例是子菜单的 parent-local 换算） |
| **越界翻转探针（第四轮）** | `node tools/probe.cjs probes/widgets/flip` | **54 checks**，0 failures：竖向翻转（`popB` 到锚点上方、底边 156）、横向翻转（`popR` 的 `x=134`）、夹回窗口（`popR` 底边 256 = `H-4`）三件一起验；变异 `mutation.cjs` **5/5**（翻 / 自身高 / 横翻 / parent-local / 夹紧，各去一半） |
| **交互探针（第四轮）** | `node tools/probe.cjs probes/widgets/interact` | **25 checks**，0 failures：7 个相位（disabled 惰性 / hover / press / 焦点环 / Tab+Shift+Tab / 文本回写+Enter 提交 / 运行时 disabled 翻转），像素全部手算（`#e0e7ff` → hover `#e2e9ff` → press `#c5cbe0`，焦点环 `#2563eb` 画在填充上）；变异 `mutation.cjs` **8/8** |
| **动效探针（第五轮）** | `node tools/probe.cjs probes/widgets/motion` | **23 checks**，0 failures：pin 住 layout 字段动画（`sizer` 20→200 宽、`solves 4→9→20` 证明**每帧重解**）+ 浮层**退场**（入场 140 / 退场 120，落地才 `visible=false`），并含「**退场中强制重渲染**」相位（描述符一直 `visible:false` 也不能把表面提前藏起来）；变异 `mutation.cjs` **7/7** |
| **虚拟列表探针（第五轮）** | `node tools/probe.cjs probes/widgets/vlist` | **26 checks**，0 failures：1000 项只挂 **9 个**节点、`clip` 真的裁掉了溢出行（像素 `(30,175)=#ffffff`）、滚轮/`End`/`Home` 三个入口都汇到同一个 `onScroll`（`19840 = 992 × 20`）；变异 `mutation.cjs` **6/6** |
| **选择三件探针（第五轮）** | `node tools/probe.cjs probes/widgets/choice` | **44 checks**，0 failures：树（展开/折存/选中 + 三层缩进 x=42/60/42 + twisty 像素）、可输入下拉（开/选/输入过滤）、日历（`2026-10-01` 落在**周四**列 x=137、翻月后 `2026-09-01` 落在**周二**列 x=81）；变异 `mutation.cjs` **9/9** |
| **`Array(x)` 两臂一致** | `node probes/array-coerce/run.cjs` | 8 格 AOT ↔ AIR **AGREE**（`Array([1,2]).length==1`、`[0] is Array`、`Array(a)===a` false …）。这是「`OptionSupport.list()` 不能用 `Array()` 代替」的测量，不是编译器缺口 |
| 重绘钉子 | `node tools/probe.cjs probes/redraw` | 14 checks，0 failures |
| 布局文本半边 | `tools/gates.cjs` 里的 layout-check 门 | `133 checks, 0 failures` |
| 布局视觉半边 | `cd asaotui && node layout-check/visual-check.cjs` | `12 checks, 0 failures`，EXIT 0（弹真窗 + 读帧缓冲 + 断言） |
| 三端差分 | `diff-check/`（Yoga / AOT / AIR） | 105 行逐字符相同 |
| AOT ↔ AIR 像素 | `air-check/` | 两张 200×120 BMP **0 字节差异** |
| 静态钉子（原 G9 扫描） | `node tools/find-bound-truthy.cjs kit seam` | `0` 命中 / 34 个 `:Object` 局部变量无一当条件用。**这道门曾经不可能变红**（它数一个工具从没打印过的字符串），已修为消费退出码；变异 `tools/mutation-bound-truthy.cjs` **4/4** |
| 「未碰编译器」的仪器自身 | `node tools/fingerprint-parse-check.cjs` | 20 项（含两条前导空格回归断言）；变异 `tools/mutation-parse.cjs`；另 `node tools/compiler-fingerprint.cjs` 现报 **0 个脏文件 / byte-for-byte** |
| **G11 结案（生成器确定性）** | `node probes/g11-nondeterminism/run.cjs` | 同源 **5 次**构建 → **1** 份生成 C（`f0ac0ff461e604bf`）+ 拼写三处一致 + 三份历史产物误差 20→1→0；`src/` 内容哈希**逐次构建前后各采一次**（首尾各一次看不见「改完又还原」的窗口）；变异 `mutation.cjs` **10/10** |
| **G14 `Array` 进 `Object` 槽的身份（已修，阶段二百五十三）** | `node probes/obj-array-identity/run.cjs` | 26 条×两臂：**AIR 26/26 符合手写 AS3 规则**，AOT 修后 **26/26 一致（0 偏离、0 崩溃）**；修前 AOT 偏离 8 条（含 5 条 **`0xC0000005`**）。变异 `mutation.cjs` **4/4** |
| **G16（新）`cond ? null : X` 的条件为假** | `node probes/g16-ternary-null/run.cjs`（门 §9b） | 17 格：**AIR 17/17 一致**；AOT **12 格偏离**（1/3/4/5/7/8/9/10/14/15/16/17 塌成结果类型零值）。门要求 AOT 偏离集**恰好等于**已登记集（新增偏离、用例停跑、**偏离无声消失**都报警）；变异 `mutation.cjs` **4/4** |
| **`Vector.<T>` vs `Array`（两 runtime）** | `node probes/vec-vs-arr/run.cjs` | N=1M：AOT `Vector.<int>` fill+sum **2ms** vs `Array` **11ms**（**0.18x**）；AIR 同两项 33/36ms（0.92x）。门只钉 AOT **≤0.5x**；变异 `mutation.cjs` **2/2** |

**每道门都做过变异测试**（改一个单位就让门变红并给出非 0 退出码），清单与每道门的
变异配方写在 `tools/gates.cjs` 头部注释里；落盘结果见 `reviews/gates-all-*.txt`。

---

## 5 结论

- **深水区（布局引擎）**：做透了，且有三端交叉验证——这是本项目最有说服力的资产。
- **中水区（协调/数据流/样式面/控件扩展点/浮层/交互）**：已补齐，并**修掉 16 个真缺陷**（§3.3）——
  其中 2 个（纯 paint 不上屏、子树布局不解算）只有在**多页 App** 这种形态下才暴露；
  第 4 个（auto 文本忘加自身内边距）只有在**把控件放进真实页面并看图**时才看得见；
  第 10/11 个（销毁的弹层还在监听 stage、浮层宿主留在 stage 上）只有**建了再拆**的程序能看见——
  单页探针永远不会拆树；第 13 个（输入框一重绘就擦字）要靠**真的去敲字**才看得见；
  第 14 个（翻转定位读到上一帧的 parent 尺寸）要靠**先开窗再缩窗**才看得见；
  第 15 个（入场动画在手泵帧的 tour 里永不落地）要靠**截图**才看得见——而它把所有矩形断言全部躲过去了。
  这条经验比这些 bug 本身更值钱：**探针要配一个真实应用，而且要真的看图。**
- **表面层（控件集 / 组件目录页 / 浮层系统）**：五批共 35 kind / 40 工厂已落地并有手算探针；
  仍缺的见 §2.1。当前可交付上限约「多页表单 / 设置页 / 列表详表 / 带图与骨架的异步页 / 弹层与菜单驱动的交互」。

### 补齐优先级建议

1. **列表虚拟化**（§3.1.1）——`scrollView` 已能真裁剪，但 `list`/`table` 仍对每个 item 建真实节点；
   这是剩下最贵的一块（万级列表会建万级节点）。
2. **布局动画**（§3.4）——需要先定义「布局动画为什么要重解布局」；浮层的**退场**动画也卡在这里。
3. **选择类控件**（§2.1）——`datePicker`/`tree`/`combobox`。其中 `combobox` 只差「输入框 + 过滤列表」这一层，
   而 §3.1 的编辑回写管线是它的前置（已通）。
4. **浮层的 `z-index` / 堆叠策略**（§3.6）——现在「子序列 = 堆叠序」够用，但多弹层叠加时作者没有表达力。

> 本表所有「缺」项均为**登记**；对 `as3compiler/` 本轮是**零改动**（上一轮的两个编译阻塞补丁
> 已随上游提交消失，见 §3.7）：
> 复核 `node tools/compiler-fingerprint.cjs`（快照 `reviews/compiler-tree-fingerprint.json`）现报
> **`0 files` / tree CLEAN**，HEAD **`480b81c`**（开工时 `6121b30`，期间并发会话连续提交，含 G17/G18 的修）。
> **本轮 31 道门就是在这个 CLEAN 树上重跑出来的**（`reviews/gates-all-16.txt`）。
> 期间的编译器侧提交全部是并发会话的，**没有一个是我的**；我在本工作区只做只读复核、测量与
> `asaotui/` 内的代码（见 §3.5）。另有一份强制走 `[SKIP]` 分支的运行做钉子（`reviews/gates-skip-path.txt`）。
> 编译器侧缺口登记处仍是 `asaotui/compiler-gaps.md`：**G17/G18 上游已修（2026-10-24，`480b81c`）**，本地补丁已撤；
> G1/G4/G8 上游已修；**G13 已修（阶段二四九）**；**G11/G12 已结案为非缺口**（G11 不是生成器随机，而是
> **在另一个进程正改写的编译器树上测量**，见 `reviews/probe-g11-nondeterminism-2026-10-23.md`）；
> **G9 已修（阶段二四八）但 10 处 `*` 保留**（`*` 现已是纯粹的性能默认：省一次装箱）；
> **G14 已修（阶段二百五十三）**——`Array` 进 `Object` 槽不装箱；**G16 新登记、未修、库内已绕行**
> （`cond ? null : X` 的条件为假时塌成结果类型零值；`probes/g16-ternary-null/`，门 §9b，AOT 现有 **12 格**偏离、AIR 17/17 一致）；
> **G3（Tab 环上限 64）仍是本库唯一的键盘能力上限**；G8/G9/G14 的复核见 `reviews/revisit-g8-g9-workarounds-2026-10-23.md`。