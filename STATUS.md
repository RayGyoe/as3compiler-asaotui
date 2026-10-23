# asaot.ui — 完成度实测表（STATUS）

> 回答一个问题：**「UI 库写完了吗？」**
>
> 结论：**深水区做透了，表面层补齐了两批（控件集 + 多页 App + 组件目录页 + 浮层系统），但还不是一个完整工具箱。**
> 深水区（布局引擎 + 三端差分）做透；**控件集从 4 个扩到 31 个 kind / 37 个工厂**（第二批 media/feedback/data 九件、
> 第三批**浮层六件 dialog/drawer/popover/menu/toast/select** 均已落地）；
> **样式面从 18 字段补到 31 字段**；**多页可切换 App 已跑起来**（`ui-demo/demo/GalleryMain.as`，**6 页**、含组件目录页与浮层页）；
> **浮层走第二棵保留树**（`View.renderOverlay()` + `UiApp.overlayRoot`），主树因此不再为弹层重解布局。
> 两个 demo 现均用 **`--air-app`** 编译：窗口属性（含**高分辨率/HiDPI**）由 AIR 描述符当唯一真相源。
> 仍然缺的是：**键盘/焦点（0 处）**、列表虚拟化、日期/树选择，以及动画只覆盖 3 个字段。
>
> 本表每一行都有可复核的命令。**不要采信本表，跑它。**

生成日期：2026-10-23（第四轮） · 对应 `kit/` **138 个 .as** · 一次性验收：`node tools/gates.cjs`（**25 道门**）

---

## 1 一句话分层结论

| 层 | 状态 | 判据 |
|---|---|---|
| L1 渲染（Skia + Stage3D） | ✅ 复用编译器运行时 | `layout-check/visual-check.cjs` 12 项像素断言；AOT ↔ AIR 两张 BMP **0 字节差异** |
| L2 布局引擎（flexbox 子集） | ✅ **做透** | `layout-check` **133 项手算断言全绿**；Yoga == AOT == AIR **105 行 0 差异** |
| L2 显示树 / 协调 / 数据流 | ✅ 可用（累计修 12 个缺陷，见 §3.3） | keyed reconciler + `markLayoutDirty` 上传 + Observable/Binding；**两棵保留树**（主树 + 浮层树） |
| L2 事件 | ⚠️ **只有鼠标** | 悬停/按下/点击；**键盘 0 处**（见 §3.1）。浮层的「点外面关闭」走 stage 监听，销毁时由 `WidgetTeardown` 摘除 |
| L2 动画 | ⚠️ 只覆盖 3 个字段 | `opacity`/`background`/`borderColor` + `transitionMs/Ease`；`probes/widgets/anim` 14 项 |
| L3 控件库 | ⚠️ **37 个工厂 / 31 个 kind** | 见 §2；第三批浮层六件（dialog/drawer/popover/menu/toast/select）已落地；仍缺日期/树选择、列表虚拟化 |
| L3 样式面 | ✅ **31 字段** | 见 §3.2；仅剩 `grid`/`boxShadow`/`cursor` 刻意缺席 |
| L3 浮层（第二棵树） | ✅ **六件 + 一套 chrome** | `View.renderOverlay()`；主树先解、浮层树后解后画、置顶；`probes/widgets/overlay` **65 项**，变异 **7/7** |
| L3 组合能力 | ✅ **多页可切换 App** | `ui-demo/run-gallery.cjs`：**6 页**共用 body 槽位（含组件目录页、浮层页）、控件驱动切页、手算矩形 + 浮层树销毁判据；**`--air-app` 构建 ⇒ 高分辨率已实测**（`ui-demo/check-dpi.cjs`：standard 700×560 / high 1050×840） |
| L3 可访问性 | ❌ 字段有、消费者无 | `role`/`ariaName`/`Control.tabEnabled` 只是字段 |

---

## 2 作者可见 API 全清单（138 个文件里**只有这些**）

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
| `textField(opts)` | `TextInput` | 单行输入，可绑定 `value`；⚠️ 编辑不回写模型，见 §3.1 |
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
| `list(items, builder, opts)` | `ListNode` | 真容器（每行一个真实 UiNode）；无虚拟滚动 |
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
| `menu(opts)` | `MenuNode` | 锚定行列表（继承 popover 的锚定与关闭）；`items`: 字符串或 `{label,value}`、`selectedIndex`/`onSelect`；**选项是扁平行**，无子菜单 |
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
| 选择 | `datePicker`、`tree`、`combobox`（可输入的下拉） | 表单、设置树 |
| 虚拟化 | `list`/`table` 的虚拟滚动（当前每个 item/行都是一个真实 UiNode） | 万级列表 |
| 图形 | `icon`（`image` 已有，但没有图标字体/矢量图标集） | 工具条、按钮图标 |
| 其它 | `accordion` 的多开模式、`table` 的排序/列宽拖拽、`menu` 的子菜单 | 仪表盘 |

**⇒ 现在能舒适写出的是「多页表单 / 设置页 / 列表详表 / 带图与骨架的异步页 / 弹层与菜单驱动的交互」，
写不出「万级滚动列表 + 图标字体 + 日期选择器」类界面。**（浮层六件落地后，`dialog`/`drawer`/`popover`/
`menu`/`select`/`toast` 都已可用，手算断言探针：`probes/widgets/overlay`，**65 项**。）

---

## 3 最硬的几块短板

### 3.1 交互只有鼠标——**键盘完全不支持**

复核命令：

```sh
cd asaotui && node tools/scan.cjs kit/asaot/ui/UiApp.as KeyboardEvent KEY_DOWN KEY_UP TEXT_INPUT focus
```

实测（2026-10-23 第二轮）：`KeyboardEvent` / `KEY_DOWN` / `KEY_UP` / `TEXT_INPUT` / `focus` **全部 0 处**。

| 后果 | 证据 |
|---|---|
| **Tab 键不走焦点** | `Control.tabEnabled`/`tabIndex` 只是两个**字段**，全库无消费者 |
| **回车不提交** | `TextInput.onCommit` 字段存在，**没有任何代码调用它** |
| **焦点态不绘制** | `UiNode.as` 里 `focused` 0 处、`disabled` 0 处；`hover` 4 处、`pressed` 2 处 ⇒ 只有鼠标态被画 |
| **输入框的编辑不回写模型** | `kind/InputWidget.as:98` 每帧 `if (n.tf.text != shown) n.tf.text = shown`（`shown` 来自模型）⇒ **一次重绘就把用户刚敲的字擦掉**；没有 `TEXT_INPUT` 监听把编辑写回 `Binding` |

注：输入框底层是**真 `TextField`（`type="input"`）**（`PaintKit.makeText(true)`），
所以底层运行时有能力接键——**缺的是我们这一侧的焦点管理与回写管线**。

#### 3.1.1 容器/导航控件的已知边界（`tabs` / `list`）

| 能力 | 现状 |
|---|---|
| **虚拟滚动** | ❌ `list`（与 `table` 的行）对**每个 item 都建一个真实 UiNode** 并参与布局；万级列表会建万级节点。`scrollView` 只裁可视区，不省节点 |
| **视口裁剪 / 滚动** | ⚠️ `scrollView` 用引擎 `scrollRect` 做**真裁剪**并接管竖向滚轮；`list` 本身仍不裁剪（超出自身高度的行会溢出），要滚动就套一层 `scrollView` |
| **键盘 / 焦点** | ❌ 同 §3.1：`tabs` 不用方向键、`list` 不用上下键选中；都是鼠标点击选中，`tabEnabled=false` |
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
cd asaotui && node tools/gates.cjs                           # 25 道门，含 layout-check 133 项
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

**已知边界（登记，不修）**：`card({title: ...})` 的标题画在内容盒左上角、**不占布局位**，
因此会压住第一个子节点（`kind/CardWidget.as:81` 的 `tf.x/tf.y = inset`）。
规避：把标题写成一个真正的子 `text(...)` 节点（画廊 demo 就是这么写的，见 `ui-demo/demo/GalleryView.as` 顶部注释）。
同理，`progress`/`slider` 的标签画在节点**顶部**、轨道在 `height-12` ⇒ 控件高度需 ≥ ~28 才不自我重叠
（这不是 bug，是「控件自绘 + 高度由作者给」的约定）。

### 3.4 动画只覆盖 3 个字段

`UiNode.applyAnim()` 只拦截 `opacity`/`background`/`borderColor`（`n.resolved` 是单一拦截点）。
`size`/`margin`/`padding`/`inset` 等**布局字段的过渡尚未接**——它们会触发重解布局，
与「纯 paint 变更不得重解布局」（`probes/redraw` 钉的）冲突，需先设计「布局动画」的语义。
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
| 堆叠顺序 | **子序列 = 堆叠序**，无 `z-index`。同一位置两个弹层同时开：后 add 的在上面 |
| 开关归属 | `open` 在**作者模型**里（`bindTo`/直接赋值），控件只负责 `visible` + 是否吃指针；关闭不删节点 ⇒ 行/滚动/悬停态不丢 |
| 遮罩 | `dialog` 的 scrim 是 `argb=0x00000000` 的透明填充**子件**：吃到点击（因此「点遮罩关闭」可行），但**看不到颜色**；叠在白底上实测 `#999999`（0x66 alpha） |
| 遮罩拦截范围 | 只拦**鼠标**。没有键盘焦点/焦点陷阱（§3.1）⇒ 对话框后面的 tab 顺序依然无从谈起 |
| 锚定 | `anchorKey` 经 `findByKey` **跨两棵树**解析；锚点不在 = 关掉四条 inset（不会 `#1009`），弹层回到内容尺寸 |
| 越界 | **不做翻转/夹紧**：`placement` 写什么就是什么，锚点靠右/靠下时会出窗 |
| 销毁 | `View.renderOverlay()` 返回 `null` ⇒ `destroyRoot` 拆整棵浮层树；挂在外部的资源（stage 监听、timer）由 `WidgetTeardown` 释放（§3.3 第 10/11 条） |
| 动画 | 开合**无过渡**（封在布局动画同一道缺口里，§3.4） |

### 3.7 编译器工作树上的两个本地补丁（必须披露）

本工作区的长期约定是「**`asaotui` 不动 `as3compiler/` 一行**」，但本轮有两个**编译阻塞**缺陷（两者都会让
任何窗口程序**在 Windows 上根本链不上/编不过**，不只影响本库）：

| # | 文件 | 缺陷 | 改法 |
|---|---|---|---|
| P1 | `as3compiler/src/runtime.ts` | `as_job_dir_push` 的 Win32 分支里字符串转义非法 ⇒ **生成的 C 语法错** | 把 `'\'`/`'\0'` 改成 `'\\\\'`/`'\\\\0'`（2 行） |
| P2 | `as3compiler/vendor/window_glue.cc` | 非 Skia 菜单分支缺 `sk_menu_flush`/`sk_menu_ensure` ⇒ **链接期未定义符号** | 在 `#else` 分支补两个空桩 |

两者都已登记在 `compiler-gaps.md`（G17/G18），并附最小复现条件。代价是诚实的：
`node tools/compiler-fingerprint.cjs` 现在会**报两个 modified 文件**，所以「未碰编译器」这句话本轮到 P1/P2 为止**不再成立**；
并发会话把上游修好并提交后，这两个补丁应当删除、指纹回到 CLEAN。

---

## 4 已完成且**可复现**的部分（不是意图，是跑过的）

一条命令跑全部 **25** 道门：

```sh
> 全量 **25 道门**在 clean 树上跑绿（定稿记录 `reviews/gates-all-13.txt`；编译器 HEAD 见该文件首行；
>   ⚠️ **本轮编译器工作树被本地打过两个补丁**（见 §3.7），G11 门会据实报「modifications: M src/runtime.ts | M
>   vendor/window_glue.cc」但不会因此变红——它只对「测量期间又动了」敏感
```

> 那道 G11 determinism 门在「**测量期间编译器源码真的在动**」时会给 `[SKIP]`（exit 3）而不是假红/假绿：
> 稳定但脏的树照样可测（PASS 会点名 `src/` 内容哈希），动了才算测不了。那分支自己也做过集成钉子
> （`reviews/gates-skip-path.txt`：`15/16 PASS, 1 SKIPPED`，exit 0 —— 那份记录是 **16 道门**时代跑的，机制与判据未变）。

| 验收 | 命令 | 期望 |
|---|---|---|
| **多页 App** | `cd asaotui/ui-demo && node run-gallery.cjs` | **6 页** tour 全绿（含组件目录页与浮层页）+ 6 张 `gallery-page*.png` + `RESULT: PASS`；tour 还把「无 engine 节点 / 零矩形 / backing 未挂」三类静默失败**升级为判据**（变异自证：把目录页的 `image` 设成 0×0 ⇒ 红并点名 page 4），并对浮层树断言「切页后 `stage.numChildren` 回到基线、`findByKey(ovlDlg)` 为 null」（变异 `ui-demo/mutation-gallery-teardown.cjs` **2/2**） |
| **高分辨率（HiDPI）自证** | `cd asaotui/ui-demo && node check-dpi.cjs` | `standard` 700×560(1×) vs `high` 1050×840(1.5×)，且两次 tour 文本**逐字节相同** |
| **单页登录 App** | `cd asaotui/ui-demo && node build-and-run.cjs` | 8 项手算断言 + `750×563` 截图（1.5×）+ `RESULT: PASS` |
| **`--air-app` 闭包回归钉（G13，已修）** | `node probes/reach-freefn/run.cjs` | 默认闭包 kept **5/5** 且默认面**能建能跑**（修前是：红 + `unknown superclass 'Base' of 'p_Leaf'`） |
| 工具箱自检 | `cd asaotui/ui-demo && node run-check.cjs` | `23 checks, 0 failures / RESULT: PASS` |
| 控件探针 ×5（第一批） | `node tools/probe.cjs probes/widgets/{chip,form,display,nav,anim}` | 19 / 41 / 48 / 41 / 14 checks，全 0 failures |
| 控件探针 ×3（第二批） | `node tools/probe.cjs probes/widgets/{media,feedback,data}` | 43 / 43 / 77 checks，全 0 failures；变异 `tools/mutation-widget-probes.cjs`（media+feedback 4/4）、`probes/widgets/data/mutation.cjs`（**5/5**，含 M4 复现本轮修的层叠 bug、M5 复现本轮修的文本内边距缺陷） |
| **浮层探针（第三批）** | `node tools/probe.cjs probes/widgets/overlay` | **65 checks**，0 failures（A 段全场景矩形 + 像素、B 段真事件路点击、C 段抽屉、D 段菜单高亮带）；变异 `probes/widgets/overlay/mutation.cjs` **7/7**（其中 5 例是把本轮真缺陷重新植入） |
| **`Array(x)` 两臂一致** | `node probes/array-coerce/run.cjs` | 8 格 AOT ↔ AIR **AGREE**（`Array([1,2]).length==1`、`[0] is Array`、`Array(a)===a` false …）。这是「`OptionSupport.list()` 不能用 `Array()` 代替」的测量，不是编译器缺口 |
| 重绘钉子 | `node tools/probe.cjs probes/redraw` | 14 checks，0 failures |
| 布局文本半边 | `tools/gates.cjs` 里的 layout-check 门 | `133 checks, 0 failures` |
| 布局视觉半边 | `cd asaotui && node layout-check/visual-check.cjs` | `12 checks, 0 failures`，EXIT 0（弹真窗 + 读帧缓冲 + 断言） |
| 三端差分 | `diff-check/`（Yoga / AOT / AIR） | 105 行逐字符相同 |
| AOT ↔ AIR 像素 | `air-check/` | 两张 200×120 BMP **0 字节差异** |
| 静态钉子（原 G9 扫描） | `node tools/find-bound-truthy.cjs kit seam` | `0` 命中 / 34 个 `:Object` 局部变量无一当条件用。**这道门曾经不可能变红**（它数一个工具从没打印过的字符串），已修为消费退出码；变异 `tools/mutation-bound-truthy.cjs` **4/4** |
| 「未碰编译器」的仪器自身 | `node tools/fingerprint-parse-check.cjs` | 20 项（含两条前导空格回归断言）；变异 `tools/mutation-parse.cjs` |
| **G11 结案（生成器确定性）** | `node probes/g11-nondeterminism/run.cjs` | 同源 **5 次**构建 → **1** 份生成 C（`f0ac0ff461e604bf`）+ 拼写三处一致 + 三份历史产物误差 20→1→0；`src/` 内容哈希**逐次构建前后各采一次**（首尾各一次看不见「改完又还原」的窗口）；变异 `mutation.cjs` **10/10** |
| **G14 `Array` 进 `Object` 槽的身份（已修，阶段二百五十三）** | `node probes/obj-array-identity/run.cjs` | 26 条×两臂：**AIR 26/26 符合手写 AS3 规则**，AOT 修后 **26/26 一致（0 偏离、0 崩溃）**；修前 AOT 偏离 8 条（含 5 条 **`0xC0000005`**）。变异 `mutation.cjs` **4/4** |
| **G16（新）`cond ? null : X` 的条件为假** | `node probes/g16-ternary-null/run.cjs`（门 §9b） | 17 格：**AIR 17/17 一致**；AOT **12 格偏离**（1/3/4/5/7/8/9/10/14/15/16/17 塌成结果类型零值）。门要求 AOT 偏离集**恰好等于**已登记集（新增偏离、用例停跑、**偏离无声消失**都报警）；变异 `mutation.cjs` **4/4** |
| **`Vector.<T>` vs `Array`（两 runtime）** | `node probes/vec-vs-arr/run.cjs` | N=1M：AOT `Vector.<int>` fill+sum **2ms** vs `Array` **11ms**（**0.18x**）；AIR 同两项 33/36ms（0.92x）。门只钉 AOT **≤0.5x**；变异 `mutation.cjs` **2/2** |

**每道门都做过变异测试**（改一个单位就让门变红并给出非 0 退出码），清单与每道门的
变异配方写在 `tools/gates.cjs` 头部注释里；落盘结果见 `reviews/gates-all-*.txt`。

---

## 5 结论

- **深水区（布局引擎）**：做透了，且有三端交叉验证——这是本项目最有说服力的资产。
- **中水区（协调/数据流/样式面/控件扩展点/浮层）**：已补齐，并**修掉 11 个真缺陷**（§3.3）——
  其中 2 个（纯 paint 不上屏、子树布局不解算）只有在**多页 App** 这种形态下才暴露；
  第 4 个（auto 文本忘加自身内边距）只有在**把控件放进真实页面并看图**时才看得见；
  第 10/11 个（销毁的弹层还在监听 stage、浮层宿主留在 stage 上）只有**建了再拆**的程序能看见——
  单页探针永远不会拆树。
  这条经验比这些 bug 本身更值钱：**探针要配一个真实应用。**
- **表面层（控件集 / 组件目录页 / 浮层系统）**：三批共 31 kind / 37 工厂已落地并有手算探针；
  仍缺的见 §2.1。当前可交付上限约「多页表单 / 设置页 / 列表详表 / 带图与骨架的异步页 / 弹层与菜单驱动的交互」。

### 补齐优先级建议

1. **键盘 + 焦点 + 输入回写**（§3.1）——投入最小、解锁最大；现在输入框一重绘就擦字，
   且**任何模态交互都缺焦点陷阱**（对话框开在屏幕上，键盘却仍属于后面那棵树）。
2. **列表虚拟化**（§3.1.1）——`scrollView` 已能真裁剪，但 `list`/`table` 仍对每个 item 建真实节点。
3. **布局动画**（§3.4）——需要先定义「布局动画为什么要重解布局」；浮层开合的过渡也卡在这里。
4. **浮层策略补齐**（§3.6）——越界翻转/夹紧、子菜单、`z-index` 语义；都比前三项轻，但都是真实产品的刚需。

> 本表所有「缺」项均为**登记**；本轮对 `as3compiler/` 只动了两处**编译阻塞**补丁（§3.7，已登记 G17/G18）：
> 复核 `node tools/compiler-fingerprint.cjs`（快照 `reviews/compiler-tree-fingerprint.json`）现会报
> `M src/runtime.ts` + `M vendor/window_glue.cc`——**这是预期的**，并发会话把上游修好并提交后应删除这两个补丁。
> 本轮开工时编译器是 `92a1239`/`0.4.208`；本轮收尾时已到 **`5949cb7`（阶段255+）**
> ——G14 由 **`54bda6d`（阶段二百五十三）** 修好，其后并发会话又连续提交。**本轮 25 道门是在
> `5949cb7` 上重跑的**（`reviews/gates-all-13.txt`）。
> 期间的编译器侧提交全部是并发会话的（阶段二四九 G13、阶段二五零/254 `--as-class-path`、
> 阶段二五三 G14 …），**没有一个是我的**；我在本工作区只做只读复核、测量与 `asaotui/` 内的代码
> （见 §3.5），唯一例外是 §3.7 的两个编译阻塞补丁。
> 全量 **25 道门**在本地编译器树（带 §3.7 两个补丁）上跑绿（定稿记录 `reviews/gates-all-13.txt`；
> `gates-all-12.txt` 是 23 道门时代的那次，仪器版本不同）；另有一份强制走 `[SKIP]` 分支的
> 运行做钉子（`reviews/gates-skip-path.txt`）—— 编译器侧这些提交没有弄坏本工作区。
> 编译器侧缺口登记处仍是 `asaotui/compiler-gaps.md`（G1/G4/G8 上游已修；**G13 已修（阶段二四九）**；
> **G11 已结案为非缺口**（不是生成器随机，而是**在另一个进程正改写的编译器树上测量**，
> 见 `reviews/probe-g11-nondeterminism-2026-10-23.md`）；**G12 已结案为非缺口**（见证程序自身声明顺序）；
> **G9 已修（阶段二四八）但 10 处 `*` 保留**（`*` 现已是纯粹的性能默认：省一次装箱）；
> **G14 已修（阶段二百五十三，2026-10-23）**——`Array` 进 `Object` 槽不装箱；转交编译器侧的
> **最小复现包** `node probes/g14-minimal/run.cjs` 已闭环，26 格矩阵现 **0 偏离 / 0 崩溃**；
> **G16 新登记、未修、库内已绕行**（`cond ? null : X` 的条件为假时塌成结果类型零值；
> `probes/g16-ternary-null/`，门 §9b，AOT 现有 **12 格**偏离、AIR 17/17 一致）；
> G8/G9/G14 的复核与可改动点清单见
> `reviews/revisit-g8-g9-workarounds-2026-10-23.md`。
