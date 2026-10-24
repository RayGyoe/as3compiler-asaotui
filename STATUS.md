# asaot.ui — 完成度实测表（STATUS）

> 回答一个问题：**「UI 库写完了吗？」**
>
> 结论：**深水区做透了，表面层补齐了三批（控件集 + 多页 App + 组件目录页 + 浮层系统 + 交互动线），但还不是一个完整工具箱。**
> 深水区（布局引擎 + 三端差分）做透；**控件集从 4 个扩到 36 个 kind / 41 个工厂**（第二批 media/feedback/data 九件、
> 第三批**浮层六件 dialog/drawer/popover/menu/toast/select**、第五批**列表虚拟化 `virtualList` + 选择三件**
> `tree`/`combobox`/`datePicker` 均已落地）；
> **样式面从 18 字段补到 32 字段**；**组件文档站已跑起来**（`ui-demo/demo/DocsMain.as`，**42 页 / 9 组**，每页两个 live 示例 + 产生它的源码），
> 且**每个注册过的 kind 都在画廊里看得见**（`tools/kind-coverage.cjs` 扫描门：**36/36**，变异 3/3）；
> **浮层走第二棵保留树**（`View.renderOverlay()` + `UiApp.overlayRoot`），主树因此不再为弹层重解布局。
> 第四轮（2026-10-24）补的是**交互动线**：`disabled` + `hover/pressed/focused` 四态绘制、`textField` 编辑回写、
> **键盘/焦点管线（Tab 环 / Esc / 方向键 / Enter / Space）**、浮层的**越界翻转 + 子菜单 + 入场动画**。
> 第六轮（2026-10-24）把 demo 收成**一个组件文档站**：41 页（本轮补一页 `textArea` 后为 42），每页 2 节示例，示例与源码同源；
> 删掉登录 demo 与旧 7 页画廊，`ui-demo/demo/` 现在只有文档站（17 个 `.as`）。
> 第七轮（2026-10-24）补上**滚动组件欠的那一半**：`scrollView` 有**真滚动条**（纵/横双轴、thumb 拖动、
> 轨道翻页、`auto/always/never`、滚轮回落横向、与 `offsetY/offsetX` 双向同步），并且文档站的
> **外壳改成流体**（`ROOT` 百分比、两列 `flex:1`）——当年窗口一放大，界面就定在 1000×700 不动。
> 第八轮（2026-10-24）先是**绕行审计**（G16/G19/G20/G21/G22 在编译器侧全修好后，库内当时的绕行能撤则撤），
> 随后顺手抓到一个**只有点击才会暴露**的缺陷：文档站有三页在**教错用**（`toast` 传 `tone: "info"` ⇒
> 工厂当场抛错、每帧刷屏；`tooltip` 传 `tone: "info"` ⇒ `Number("info")` = NaN；`progress` 传
> 一个它根本不读的 `tone`）。修了这 3 页，给 tour 加了「真点击 toastHost」判据，并新增扫描门
> `tools/demo-options.cjs`（见 §3.9）。
> 第九轮（2026-10-24）是同一种病症的第二个实例：**拖一下滑块就报 `#1063`、而且滑块不动** ——
> 四个开关类控件的 `onChange()` **不传参**，而每个调用方都声明 `function (v:Number)`；
> 另加滑块本身**没有拖动机制**。修了四个调用点 + 重写 `SliderWidget`（stage 临时监听 + 单写入点），
> 并补上**两层钉子**：行为门 `probes/widgets/callback`（唯一会点**未绑定**控件的探针）与静态门
> `tools/callback-arity.cjs`（双向参数个数扫描，见 §3.10）。
> 第十轮（2026-10-24）把**AIR 参考臂**变成一条命令：`ui-demo/air-gallery/build.sh`（默认走
> `mxmlc → adl`，`build.sh aot` 走我们的 AOT）。**默认臂此前根本不存在**：文档站的 tour 用
> `Stage.dispatchMouse/dispatchWheel/render` 这三个**只有我们有**的测试钩子，mxmlc 直接拒收该文件。
> 于是新增 `demo/DocsAir.as`（同一个 model/view/UiApp，不跑 tour），并顺手修好 mxmlc 才看得见的两处
> 可移植性缺陷（`DocsStart.as` 漏 `import asaot.ui.box`、`combo.as` 里放着 `public function combobox`
> —— 文件名规则的违反）。新增门 `6b5` + 变异工具（见 §3.11）。
> 第十一轮（2026-10-24）是**只有参考运行时才看得见**的第三个实例：`select`/`combobox`/`datePicker`
> **一点下拉就每帧招 `#2006 The supplied index is out of bounds`**。真因是 `Reconciler.fixDisplayOrder`
> 用「描述下标」算显示位，而弹层会把属主 `lifted` 出去（占描述槽、不占显示槽）⇒ 下标每多一个被抬起的
> 兄弟就多算一。**我们的运行时把越界索引夹紧而不抛错**（`emit.ts:11635`），所以 AOT 側全绿、41 页截图
> 逐像素相同，只有真 AIR 会抛。改法是结构性重写（只数「在用」孩子的槽位计数器），并新增**第一道也是
> 唯一一道真跑参考运行时的门** `tools/air-sweep.cjs`（41 页 × 每页开/关 10 个弹层，任何 AIR 报的错都算失败）。
> 同一件事在编译器侧登记为缺口 **G24**（见 `compiler-gaps.md`）。
> 第十二轮（2026-10-24）是**监听器寿命**：用户第四次报告「多点了几次报错」，控制台是
> `TypeError #1009 … at asaot.ui::UiNode/setHover()`。`destroySubtree()` 把显示对象摘掉、把字段置空，
> 却**摘不掉节点自己挂在那张 backing 上的匿名监听器**；而 AIR 的 `mouseOut` **晚一拍**才投递（先结束
> 帧、再重算指针目标）⇒ 闭包落到已置空的字段上，`accordion`/`dialog`/`drawer`/`menu` 四页中招。
> **AOT 侧结构上看不见**：`emit.ts` 里 `mouseOver` 出现 0 次（逐对象 roll-over/roll-out 从未发出）⇒
> 登记缺口 **G25**。库侧新增 `UiNode.listen()`/`releaseListeners()`（24 处监听、16 个文件改造），
> 并给 `air-sweep` 补了**指针钻**（悬停每页每个叶子 → 切页 → 下一拍投递 roll-out：3107 hovered /
> 348 真的已销毁 / 0 错）。
> 第十四轮（2026-10-25）补的是**「作者想画点东西」那批里最便宜的四件**：`Style.boxShadow`（落 background
> shape 而非 backing —— backing 上的滤镜会连 label/图标/子节点一起投影，那是文字投影不是盒子投影；
> `spread`/`inset` 显式抛错，因为 `DropShadowFilter` 没有对应旋钮，近似就是「画了作者没要的阴影」）、
> `Fill.gradient`（`beginGradientFill` + 每节点矩阵缓存、零每帧分配；**hover/pressed 不染色**、
> **不参与动画**——`lerpArgb` 只懂一个打包色，回落到首站纯色才是静默回退）、文本**换行**
> （`whiteSpace:"normal"`，只在测量期生效、且宽度必须解析成 POINT，百分比宽度要等 solver，猜就是错）与
> 文本**截断**（`textOverflow:"ellipsis"`，只能在 arrange 之后的 paint 做，因为需要最终盒宽），
> 以及 `textArea`（**独立 kind，不是单行文本框上的一个布尔开关**：Enter 的契约是反过来的——单行提交、
> 多行插入，所以它**不吃 13**，让运行时自己插换行；高度契约是 `rows × 行高`，也不是测量出来的）。
> 五组判据钉在新探针 `probes/widgets/textfx`（18 checks），变异 **5/5**（见 §3.14）；文档站 41 → **42 页**，门 45 → **46 道**。
> 第十五轮（2026-10-25）是**指针真实感 + 图片真的能加载**这两件：`Style.cursor`（`auto/arrow/button/hand/ibeam`，
> 树内**继承**、`CLICKABLE` 那批 kind 由主题给 `hand`）落地，并且把 hover **从逐对象 roll 事件改成一次
> stage `MOUSE_MOVE`** —— 因为 AOT **从不派发** `mouseOver`（G25），旧写法在 adl 里亮、在我们自己的产物里
> **永远不亮**；新写法用运行时自己的命中测试（`as_pick_hit`）取目标 + 整条**祖先链**置 hover，与 AIR 的冒泡
> 同义，且顺手把 `Mouse.cursor` 按链推导（`Mouse` 是进程级状态，离场必须回 `auto`）。第二件是 `image()` 的
> `src`：控件自己持 `Loader`，`onLoad()`（零参）/`onError(msg)`（一参）走**已有的 arity 契约**，失败写进
> `UiNode.loadError` 而**不是画一块空白**；`scaleMode` 未知值现在**抛错**（文档页过去写的 `letterbox`/`zoom`
> 从来不是合法值，`zoom` 一直渲染成 contain）。判据：新探针 `probes/widgets/pointer`（23 项）、`probes/widgets/imaging`
> （27 项，变异 **5/5**）；顺带按新语义**重导**了 `probes/widgets/callback` 的两个滑块像素钉（指针停在滑块上
> 就是 hover 态，裸轨道 #E5E7EB → #E7E9ED = 8% 提亮）。
> 第五轮（2026-10-24）补的是**动画深度 + 三处控件空白**：`Anim` 现在分 **paint 字段**与 **layout 字段**
> （`width/height/padding/gap` 动画每帧重解、`textColor/cornerRadius` 可 tween）、浮层加**退场动画**；
> `virtualList`（千级列表只挂 9 个节点）、`tree`、`combobox`、`datePicker`（纯整数日历，无 `Date`）落地。
> 两个 demo 现均用 **`--air-app`** 编译：窗口属性（含**高分辨率/HiDPI**）由 AIR 描述符当唯一真相源。
> 仍然缺的是：`icon`（图标字体/矢量集）、`accordion` 多开、`table` 排序/列宽拖拽、
> 样式面的 `grid`，以及可访问性字段仍无消费者（`role`/`ariaName` 只是数据）。
>
> 本表每一行都有可复核的命令。**不要采信本表，跑它。**
生成日期：2026-10-24（第十二轮补：监听器寿命 `#1009` + `air-sweep` 指针钻 + G25） · 对应 `kit/` **155 个 .as** · 一次性验收：`node tools/gates.cjs`（**46 道门**）

---

## 1 一句话分层结论

| 层 | 状态 | 判据 |
|---|---|---|
| L1 渲染（Skia + Stage3D） | ✅ 复用编译器运行时 | `layout-check/visual-check.cjs` 12 项像素断言；AOT ↔ AIR 两张 BMP **0 字节差异** |
| L2 布局引擎（flexbox 子集） | ✅ **做透** | `layout-check` **133 项手算断言全绿**；Yoga == AOT == AIR **105 行 0 差异** |
| L2 显示树 / 协调 / 数据流 | ✅ 可用（累计修 26 个缺陷，见 §3.3） | keyed reconciler + `markLayoutDirty` 上传 + Observable/Binding；**两棵保留树**（主树 + 浮层树） |
| L2 事件 | ✅ **鼠标 + 键盘/焦点** | 悬停/按下/点击；`UiApp` 接 stage 的 `KEY_DOWN`/`FOCUS_IN`/`FOCUS_OUT`：**Tab/Shift+Tab 焦点环**（遍历保留树，浮层内是焦点陷阱）、`Esc`、方向键、`Enter`/`Space` 激活；控件用**可选接口** `WidgetKeys`/`WidgetFocus` 参与（`probes/widgets/interact` 25 项）。边界：Tab 环上限 64（`compiler-gaps.md` G3）、无按键重复/快捷键表 |
| L2 动画 | ✅ **样式 5 字段 + layout 字段 + 浮层入/退场** | 样式 `paint` 字段：`opacity`/`background`/`borderColor`/`textColor`/`cornerRadius`；样式 **`layout` 字段**：`width`/`height`/`padding`(T/R/B/L)/`gap`(X/Y)——写回后 `applyEngineStyle()` + `markLayoutDirty()`，**每帧重解布局**，落地即停（`probes/widgets/anim` 14 项 + `probes/widgets/motion` 23 项）；显示对象级：`OverlayMotion`（入场 140ms ease-out / **退场 120ms ease-in**，墙钟，每帧从引擎读基准，不累加），见 §3.4 |
| L3 控件库 | ✅ **40 个工厂 / 35 个 kind** | 见 §2；第三批浮层六件（dialog/drawer/popover/menu/toast/select）+ 第五批 `virtualList`（列表虚拟化）/`tree`/`combobox`/`datePicker` 已落地。**35 个 kind 全部上了画廊**（第七页 Advanced），由 `tools/kind-coverage.cjs` 自动核验：kind → 注册它的节点类 → 构造该类的工厂函数 → 画廊是否**调用**了其中之一。顺带修掉一处**陈旧计数**：文档原写「34 个 kind」，实际注册表有 35 个（`scrollView` 加进来后从没被计过数）——现在这个数字由门看着 |
| L3 样式面 | ✅ **33 字段** | 见 §3.2；仅剩 `grid` 刻意缺席（`cursor` 第十五轮已落地） |
| L3 浮层（第二棵树） | ✅ **六件 + 一套 chrome + 翻转/子菜单/入退场** | `View.renderOverlay()`；主树先解、浮层树后解后画、置顶；**越界自动翻转**（四向 + 夹回窗口）、`menu` 支持**子菜单**（子菜单就是普通 anchored popover）、**入场 140ms / 退场 120ms**；`probes/widgets/overlay` **65 项**（变异 **9/9**）+ `probes/widgets/flip` **54 项**（变异 **5/5**）+ `probes/widgets/motion` **23 项**（变异 **7/7**） |
| L3 组合能力 | ✅ **42 页组件文档站** | `ui-demo/demo/Docs*.as`（17 个文件）+ `ui-demo/run-gallery.cjs`：左侧 9 组 / 42 页索引，右侧每页 = 标题 + 摘要 + meta + 若干节，每节 = 标题 + 说明 + **live demo** + **产生它的源码**（同一次 render ⇒ 源码不漂移）；控件驱动切页、手算矩形 + 浮层树销毁判据；**`--air-app` 构建 ⇒ 高分辨率已实测**（`ui-demo/check-dpi.cjs`：standard 1000×700 / high 1500×1050） |
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
| `image(opts)` | `ImageNode` | 位图控件；源二选一：`bitmapData`（调用者已有像素）或 **`src`（控件自己持 `Loader`，异步）**；
`scaleMode`: `fit`/`stretch`/`none`（**未知值抛错**）；`onLoad()`/`onError(msg)`、失败进 `UiNode.loadError` |
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
| **视口裁剪 / 滚动** | ✅ `scrollView` 用引擎 `scrollRect` 做**真裁剪**、接管滚轮，并**自绘滚动条**（第七轮）：纵/横双轴、thumb 拖动、轨道点击翻一屏、`scrollbarX/Y` 的 `auto`/`always`/`never`、没有竖向可滚时滚轮**回落横向**。条是**覆盖层**（画在内容之上、不参与布局，所以不改变任何矩形）。仍无：惯性/动量、弹性回弹、键盘翻页。`list` 本身仍不裁剪（超出自身高度的行会溢出），要滚动就套一层 `scrollView` |
| **键盘 / 焦点** | ⚠️ 部分是：焦点环/`Enter`/`Space`/`Esc` 已通（见 §3.1），但 `tabs` 还没接**方向键**、`list` 还没接**上下键选中**（两者仍只看鼠标点击）；`list` 的行也没进 Tab 环 |
| **tabs 分段的布局来源** | ⚠️ 分段是控件**自算**（`from n.absW` 的整数等分），**不是**引擎摆的子节点；`list` 的行**是**引擎摆的真实子节点 |
| **tabs 的 gap 来源** | ⚠️ `TabsWidget.payload` 先读 `opts.gap`，回落到 `n.resolved.gapX`（已解算值）。若一次重排**恰好只改了 gap**，分段 pitch 会用上一帧的 gap 一帧（`Reconciler` 是「先 resolve 后 payload」，payload 改方向会在同帧重解，见 §3.3） |
| **list 选择高亮** | ✅ 由 `list` 自身在 `shapeA`（子件之下）画高亮条；行本身需透明才能看见 |

### 3.2 样式面：从 18 补到 **33 字段**（不再缺布局字段）

`kit/asaot/ui/style/Style.as` 现有 **33 个字段**（`node tools/scan.cjs kit/asaot/ui/style/Style.as "public var"`）：

| 组 | 字段 |
|---|---|
| 布局 | `flexDirection` `justifyContent` `alignItems` `alignSelf` `alignContent` `flexWrap` `gapX` `gapY` `flexGrow` `flexShrink` `flexBasis` `display` `aspectRatio` `position` `inset` `margin` |
| 盒 | `size` `minSize` `maxSize` `padding` `borderWidths` `boxSizing` `overflow` |
| 装饰 | `background`（纯色**或** `Fill.gradient`）`borderColor` `cornerRadii` `opacity` `visibility` `boxShadow`（`BoxShadow` 数组）`cursor`（**树内继承**，见 §3.2 末尾） |
| 文本 | `text`（`TextStyle`，含 `whiteSpace` / `textOverflow`） |
| 动画 | `transitionMs` `transitionEase` |

- `margin`/`inset` 用 **`LengthEdges`**（四边各自 Length），镜像 `Edges`；
- **未知字符串值在 `UiNode.applyEngineStyle` 抛错**（报字段名 + 值 + 可接受集合），不静默回落（AGENTS.md §2.5）；
- `boxShadow` 落在 **background 形状**上，不是 backing：backing 上的滤镜会连 label/图标/子节点一起投影，
  那是**文字投影不是盒子投影**；只画了文字的 kind（无 `shapeA`）落到字段自身，两者皆无则**抛错**而不是静默丢弃；
  `spread != 0` / `inset == true` 也抛错（`DropShadowFilter` 没有对应旋钮，近似就是画了作者没要的阴影）；
- 布局验收基准**不是 `adl`**（AIR 无 flexbox），而是 W3C flexbox / 浏览器；
- 仍刻意缺席：`grid`（引擎不实现；seam 层面也会抛错）。`cursor` 第十五轮落地：**继承**语义（子节点未设则
  沿祖先链取），值为 `auto`/`arrow`/`button`/`hand`/`ibeam`（与 `flash.ui.MouseCursor` 同名字面量），
  最终由 `UiApp.applyCursor()` 写 **进程级** `Mouse.cursor`——所以指针一离开声明它的节点就必须回 `auto`，
  这条由 `probes/widgets/pointer` 钉（“离开后进程上留下一个 hand” = 整个窗口都像坏了一样）。

复核命令：

```sh
cd asaotui && node layout-check/visual-check.cjs            # 12 项（含新字段的像素断言）
cd asaotui && node tools/gates.cjs                           # 46 道门，含 layout-check 133 项
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
| 20 | **提示文字（placeholder）输入时不消失**；焦点刚进入、还一个字都没输时，光标和 ghost 文字**叠在同一格** | ghost 是 `paint` 里算可见性的独立文本层，而可见性条件漏了「已聚焦」这一条；并且编辑走的是 `Event.CHANGE` 回调，回调只写模型 —— 屏幕是否重画取决于**作者**有没有 invalidate（不 invalidate 的作者就永远看不到变化） | ghost 条件收敛为 `model 为空 && state.focused == 0 && placeholder 非空`（聚焦即藏：光标就在那儿）；`onFieldChange`/`commit` 各自 `app.markPaint(n)`，**控件欠屏幕自己的重绘**，不指望作者 | `probes/widgets/typing`（18 项，含 ghost 扫描区渲染像素数、focus 后归零、失焦且空才回来）。**变异 4/4**（`probes/widgets/typing/mutation.cjs`）：M1 = 强制 ghost 常显（用户报告的原症状）、M2 = 去掉聚焦闸门、M3 = paint 把字符串写两遍（原本是「setTextFormat 回到 paint」，G20 修好后它变成绿跑 ⇒ 已重指）、M4 = 失焦不报 commit。探针的 `onChange` **刻意不 invalidate**（否则作者侧重绘会把第 20 条整个盖住） |
| 21 | **输入过的字在失焦再聚焦后「复制一遍」**（`1111` 变 `11111111`，字形挤着往外长；`textWidth` 从 28.9 涨到 56.7） | `TextField.setTextFormat` 当时是**追加 run**（`emit.ts:20417` 只 `_runs` 追加、`_runs_gen++`），不是替换范围（**G20，阶段二百六十八已修**：setter 现在重建 run 表）；而排版器 `sk_textlayout_new_runs`（`vendor/skia_text_glue.cc:495`）对**每条 run** 都 `addText` 一遍模型里的字符串 ⇒ **重画 N 次就画 N 份**。`InputWidget.paint` 每次都调它 ⇒ 每帧多一条 run | 单格式字段**仍不调 `setTextFormat`**（现在是**设计选择**而不是禁令：`defaultTextFormat` + `textColor` 就够，G20 修好后调它只是每帧多余工作量）；`paint` 只 `defaultTextFormat`/`textColor`，值没变**不重赋 `text`**（`text` setter 会清 run，但也会把 caret 甩到末尾） | 同上 `probes/widgets/typing`：`textWidth` 与**现场新建的干净字段**逐字对比（不抄字体度量）、字形列组只允许一串、`caretIndex` 跨 3 次重绘不动。变异 M3 **已重指**（原「setTextFormat 回到 paint」依赖 G20，修好后变绿；现为「paint 把字符串写两遍」，由最终文本断言抓获）；换行累积那条 `textWidth` 对照现在是**编译器 G20 的绊线**（主门是 `probes/g20-settextformat`）。登记见 `compiler-gaps.md` G20/G21 |
| 22 | **容器上的 `onClick` 永远不触发**（侧栏一行点了没反应，`model` 也不动；但 `button` 正常） | `UiNode.applyPayload` 老老实实从描述符镜像 `Element.onClick`，可**描述符上的那个字段从来没被写入** —— `OptionSupport.applyOpts` 只拷 key/role/ariaName/visible/disabled，`onClick` 只有 button/checkbox/radio/slider/toggle/textField 六个**控件**工厂自己拷。`box({ onClick: f })` 于是拿到一个 null | `OptionSupport.applyOpts` 加一行 `if (opts.onClick != null) n.onClick = (opts.onClick as Function);` —— 一处修好所有容器（box/row/column/card/overlay/…） | `ui-demo/run-gallery.cjs` 的 `index click` 段：真按 stage 坐标点侧栏行，断言 `model.doc=="box"` + `view.lastPick=="box"` + 标题变了 + 上一页的 demo 已卸载。**变异**：删掉那一行 ⇒ 四条断言同时红 |
| 23 | **点了控件，数据变了，界面不变**（同一次运行里 `doc=box` 而标题仍写 "Getting started"、上一页的 demo 还挂着） | 模型 `DocsModel extends Observable`，控件回调里 `model.put/pick` 会 `notify()`，**但没有任何人 subscribe** ⇒ `notify` 空转，`UiApp._pending` 一直是 0，`reflow()` 不重新 describe。widget 只报告、作者重渲染的契约断在最后一步 | `DocsMain` 建好 app 之后 `model.subscribe(function (d:int):void { self.app.invalidate(d); })` | 同上门（`index click` 段先 `click` 再 `reflow`，不额外 `invalidate`：能不能刷新完全取决于订阅是否在） |
| 24 | **侧栏整行只有文字本身可点**（行高 26、宽 219，但 Label 右侧的空白点下去什么都不发生） | 命中测试是**按绘制区域**而非布局盒（`as_pick_hit_local` → Graphics 的 fill/stroke ∪ 子件）：行的样式只有 padding 没有 `background`，于是行自己的 graphics 是空的，只有标签的 TextField 是目标。这是**Air 的真实语义**（透明的容器不是点击目标），但作为导航行是设计缺陷 | `DocsStyle.NAV_ITEM` 加 `background: 0xF8FAFC` —— 与 `SIDE` 同色，**屏幕上看不出差别**，但行从此有填充区域（选中态本来就是 `0xEFF6FF`） | 同上门：示例按**行中心**（x=123，远在标签右侧）派发，加这条背景之前断言必红（命中测试落在祖先容器上，行自己的 backing 不是 target）。注释写清「容器只在绘制处可点」这条 Flash 语义 |
| 25 | **滚动条被内容盖住**（第 0 页截图里 thumb 只从没被盖住的缝隙里露一条：代码块、选中的导航行、demo 卡片背景全压在条上） | 不是条画错。`fixDisplayOrder` 从 `internalCount`（= `build()` 之后 `backing` 的子件数）开始给内容子件排序，于是内容一律排在 `build` 造出的**所有**对象之上 —— 对背景是对的，对 chrome 是错的。条只能靠 `paintBars` 里那句 `setChildIndex` 补救，所以它**取决于这一帧有没有重绘这个滚动节点**；而切页是「描述但不重绘」（`Dirty.ALL` 不含 `M_PAINT`）⇒ 条永久埋在下面 | `UiNode.aboveContent`：kind 在 `build()` 里声明「我这一个对象在内容之上」，`internalCount` 于是**不数它** ⇒ 内容排到它前面，每次 describe 都自动把它推到最后，不再依赖重绘（`paintBars` 那句保留，它是给 `applyLift` 把子件重新挂到末尾那条路的） | `docs tour` 的 6d 阶段新增 `chromeOnTop("docScroll"/"nav")`：在**切页那一帧**（只有 describe、没有 paint）断言条是 backing 的**最后一个子件**。变异见 `tools/mutation-docs-tour.cjs`：去掉 `n.aboveContent = n.shapeB` ⇒ `the 'docScroll' bars sit at display index 1 of 3, so the content below them paints over the bars` |
| 26 | **拖一下滑块就报错、而且滑块根本不动**（用户第二次报告：截图里一行 `#1063 Argument count mismatch`，点了/拖了没反应） | 两个独立缺陷叠在同一个控件上：①`SliderWidget`/`CheckboxWidget`/`SwitchWidget`/`RadioWidget` 调 `n.onChange()` **不传参**，而每个调用方（42 页文档站 + 探针）都声明 `function (v:Number)` / `(v:Boolean)` ⇒ AVM2 上**参数个数不符即抛 #1063**，帧守卫恢复该帧，于是**回调从未运行**、模型从未变、唯一痕迹是控制台一行；②就算参数对了，`SliderWidget` 也只有「按下就地设值」——**没有拖动**（按下后移动鼠标什么都不发生） | 四个控件的调用点补上参数（`onChange(next)` / `onChange(true)`）；`SliderWidget` **重写**：实现 `Widget, WidgetTeardown`，按下设值、拖动期间在 **stage** 上临时挂 `MOUSE_MOVE/MOUSE_UP`（闭包存 `n.extra["dragmv"]/["dragup"]` 以便按引用摘除），`endDrag` 幂等、`teardown` 调它；单一写入点 `commit()`（状态 → `Binding` → `onChange(v)` → `markPaint` → `invalidate(Dirty.VALUE)`），值没变不报 | **行为面**：新探针 `probes/widgets/callback`（24 项，**只点未绑定控件**，含按下→拖动→越界夹紧→回 0→松手→松手后移动无效→纯点击设值）+ 像素（拖动中帧必须跟着走）。变异 8/8（`probes/widgets/callback/mutation.cjs`），含「回调不传参」的四条与「松手什么都不结束」「去掉自抬重绘」。**静态面**：新门 `tools/callback-arity.cjs`（双向扫描：kit 的**调用点**恰好 1 参数、文档站/探针的**声明**恰好 1 参数，`onClick` 两边都是 0），变异 6/6。**为什么此前无人发现**：`probes/widgets/form` 只点**绑定了** `binding` 的控件（走 Binding 分支，不碰 `onChange`），而 42 页截图只渲染不点击 |
| 27 | **一点下拉就报错、页面冻住**（用户第三次报告，`select`/`combobox`/`datePicker` 三页：`RangeError: Error #2006: The supplied index is out of bounds.` → `DisplayObjectContainer/setChildIndex()` → `asaot.ui::Reconciler/fixDisplayOrder()` → … → `UiApp/onEnterFrame()`，每帧一行，屏幕停在上一棵树） | **两个不同的事故叠在一起**：①库侧——`fixDisplayOrder` 用 `setChildIndex(c.backing, internalCount + <描述下标>)` 修显示序，而弹出的下拉会把**属主节点** `lifted` 出去（`UiNode.lifted`，为了越过后续兄弟的 z 序，见第 19 条）：它**仍占描述树一个槽位，但已不在父 backing 里** ⇒ 下标每遇到一个被抬起的兄弟就多算一，`index == numChildren` 即越界；②编译器侧——`emit.ts:11635` 的 `DisplayObjectContainer_setChildIndex` 对越界做了 `if (index >= length) index = length - 1;`（**夹紧**）且「不是孩子」时直接 `return`，而 AIR 分别抛 `RangeError #2006` / `ArgumentError #2025` ⇒ **同一份代码，AIR 报错、我们静默放行**。夹紧到末尾恰好是最后一个孩子的正确落点，所以画面逐像素相同：42 页截图扫描、全部 AOT 探针、41 道门全部看不见 | 库侧：`fixDisplayOrder` 改成**只数「在用」孩子的槽位计数器**（`slot = internalCount`，只有 `backing.parent == n.backing` 才 `setChildIndex(…, slot++)`），末位最多落到 `numChildren-1`（有 `aboveContent` 时少一），**结构性**不可能越界；`lastIndex` 仍是**描述下标**（那是未带 key 兄弟的身份 token，不是显示位）。编译器侧：**未动**（按本工作区约定登记为缺口 **G24**，附「建议对齐 AIR」的理由） | **新门 `tools/air-sweep.cjs`——本仓第一道也是唯一一道真跑参考运行时的门**：`mxmlc` 编 → `adl` 跑 42 页 × 每页把 10 个可弹层开关打开再关掉 → 读应用自己写的 `air-trace.txt`（`adl.exe` 是 GUI 子系统，管道拿不到 trace，实测）→ 任何 AIR 报的错都算失败。变异 `tools/mutation-air-sweep.cjs` **5/5**：把槽位计数改回 `internalCount + i` ⇒ 立刻在 `select`/`combobox`/`datePicker` 上报 `#2006`；去掉「打开弹层」这一步 ⇒ `OPENED` 缺失（扫得全绿但**已经瞎了**）；少走一步 ⇒ `visited 40/41`（死了的窗口不许当绿）；去掉 `releaseListeners()` ⇒ 145 个 `#1009`（见第 28 条）；只悬停不投递 ⇒ 指针钻报 `0/41`。五条都按 sha256 逐字节还原 |
| 28 | **多点了几下就报错**（用户第四次报告：`TypeError: Error #1009: Cannot access a property or method of a null object reference.` → `asaot.ui::UiNode/setHover()` ← `Function/UiNode.as$1::anonymous()`） | **两层时序缺一不可**：①库侧——`destroySubtree()` 把节点的 backing 从父容器摘掉、把 `app`/`extra`/`backing` 置空，但**监听器是挂在 backing 这个 EventDispatcher 上的**，`removeChild` 不会替你摘 ⇒ 那个闭包仍活着、捕获变量已全空；②AIR 侧——**`mouseOut` 晚一拍**才投递（先结束这一帧，**然后**才重算「指针下面是谁」并投给上一帧那个对象）⇒ 只要「指针停在某个控件上、而某一帧把那个控件拆了」就会落到尸体上。实测（`adl` 51.4.1，`air-trace.txt`）：只有**点了就拆树**的页中招——`accordion` 1 次、`dialog` 4 次、`drawer` 3 次、`menu` 3 次，其余 37 页 0 次 | 库侧：`UiNode` 新增 `wired:Array` + `listen(target,type,fn)`（登记三元组）+ `releaseListeners()`；`destroySubtree()` **第一句**就释放，再摘显示对象、再置空（顺序是契约：先断线再断电）；全库 **24 处 / 16 个文件**改造。**STAGE 监听器刻意不在此列**（它们属于某次手势，保留 widget 自己 teardown 的显式 add/remove 对）。编译器侧：**未动**，登记缺口 **G25**（AOT 从不派发逆对象的 roll-over/roll-out） | **三道新门 + 一道扩门**：`probes/lifecycle`（**9 项**：10 种 kind × 5 种指针事件，**销毁后**再派发不抛、`state.hover` 保持 0、无游离 `onClick`；同时证明活节点上这道闸不变行为）；`tools/listener-wiring.cjs`（静态扫描：禁裸 `x.backing.addEventListener(`、`destroySubtree` 必须有 `releaseListeners()`、**扫到 0 处也算失败**，现 **29 wired / 0 raw**）；`air-sweep` 新增**指针钻**（离开每页前悬停该页**每个叶子**，切页后**下一拍**投递 roll-out：**3107 hovered / 348 真的已销毁 / 0 errors**）。变异：`probes/lifecycle/mutation.cjs` **4/4**、`tools/mutation-listener-wiring.cjs` **3/3**、`mutation-air-sweep` **5/5** |

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

### 3.8 滚动条："视口" 只做了一半（第七轮补齐）

`scrollView` 从落地起就写着 "no scrollbars"：它只做了**裁剪 + 滚轮**。用户看到的那个现象
（文档站右栏能滚但没有任何可视指示）不是多出来一个 bug，而是**设计没做完**。现在补齐的那一半：

| 关注点 | 做法 | 为什么不那么做 |
|---|---|---|
| 条的归属 | **绘制在 `n.shapeB` 上的覆盖层**，paint 里按 viewport 坐标画（并做 `+offset` 补偿，否则会被 scrollRect 一起滑走） | 如果把条做成**布局子节点**，内容宽度就取决于「条此刻在不在」——经典的 scrollbar-gutter 反馈环，而且会让所有已钉的矩形失效 |
| 何时画 | `scrollbarX/Y`: `auto`（该轴有溢出才画）/`always`/`never`；**非法字符串在工厂里直接抛**（不静默回落，AGENTS.md §2.5） | `always` 在无溢出轴上会白盖内容；但那是作者的显式选择 |
| thumb 尺寸/位置 | `len = track * view/(view+max)`（比例），地板 24px 保证可拖，位置 = `off/max * (track-len)` | 拖拽必须 1:1 跟手，所以 span 用**完整 thumb 长度**，而不是画出来的（四周内缩 2px 的）矩形 |
| 拖拽 | 按下 thumb 时在 **stage** 上挂临时 `MOUSE_MOVE`/`MOUSE_UP`（本运行时没有 pointer capture），`endDrag`/`teardown` 栈式摘除 | 只挂在自己身上：指针一离开 viewport，事件就发给了别的对象，拖拽会"粘"在原地 |
| 轨道点击 | 向点击方向**翻一屏**（0.9 个 viewport），方向由 thumb 位置决定 | 直接跳到点击点会让长列表里误点一下跳走几千行 |
| 与点击语义冲突 | 按在条上或拖过的那个 CLICK **被控件吃掉**（`click(n):Boolean` 的 consumed 位），不触发作者的 `onClick` | 不吞的话，一个给整个滚动区写了 `onClick` 的作者会在拖条时收到点击 |
| 横向 | `offsetX` 现在**真的进 scrollRect**（旧控件算出 `offsetX` 却只把 `offsetY` 写进去，横向滚动是假的）；竖向无范围时滚轮**回落横向** | shift+滚轮做不到：运行时的 wheel 事件**不带 modifier**（`Stage_dispatchWheel`） |
| 能力边界 | 无惯性/动量、无弹性回弹、无键盘翻页、无双击到底 | 写进注释与文档站（“the honest list”），不让用户以为没响应是 bug |

**验证**：`probes/widgets/scrollbar`（新门）——手算 thumb/track 几何与颜色（*先写 expect.json，再跑*），
拖 15px 必须得 `offsetY = 15*160/53.333 = 45`，横向滚动必须真的**换像素**（不是只改一个数字），
并反证「无溢出的轴不出条」。变异 4/4（`probes/widgets/scrollbar/mutation.cjs`）：M1 = 不画条、
M2 = 拖拽用画出来的短 thumb、M3 = `offsetX` 不进 scrollRect（旧缺陷）、M4 = 滚轮不回落横向。

**外壳流体化**：`DocsStyle.ROOT` 从 `[px(1000), px(700)]` 改 `[pct(1), pct(1)]`，
`SIDE` 高度、`NAV`/`DOC_SCROLL` 改成 `flexGrow:1 + flexBasis:0`（= CSS `flex:1`；**百分比高会按父容器算而溢出侧栏**）。
文档站 tour 加了一段真实的**尺寸变化**：它写 stage 宽高 + 发 `Event.RESIZE`（= `ASC_window_on_resize`
所做的那两件事，布局路径分辨不出差别），然后断言 `side/main/docScroll/nav` 四块手算矩形，再变回去。

### 3.9 文档站有三页在**教错用**（第八轮补：只有点击才暴露）

用户点了画廊 `toastHost` 页的 “Show two toasts”，控制台开始**每帧**刷
`Uncaught exception: asaot.ui.toast: unknown tone 'info' (accepted: default | success | danger)`，
而页面本身看起来正常（矩形都对、其它页都正常）。

**根因不是编译器，也不是 `toast`**：`toast()` 按契约在未知 tone 上抛错（AGENTS.md §2.5 “不静默回落”），
是**文档页示范了一个不存在的取值**——它把 chip 的语气词（`neutral/info/danger`）用到了 toast 上
（toast 是 `default/success/danger`）。之所以一直没人发现：**42 页的扫描只渲染、不点击**，
而这一页的两条 toast 只有 `tsh.open` 翻转后才存在。

顺着这个形状做了一次源码扫描（`tools/demo-options.cjs`：把每个工厂**真的读**的键 ——
`opts.x` / `OptionSupport.opt(opts,"x")` / `applyOpts` 的共享键 / `StyleRefinement.from` 的样式简写 ——
与文档站每个调用点传入的顶层键求差），又抓到两页同类缺陷：

| 页面 | 示范的写法 | 工厂实际行为 | 修法 |
|---|---|---|---|
| `toastHost` | `toast({ tone: "info" })` | **抛错**（`default/success/danger`），且抛在 build 里 ⇒ 帧守卫恢复后**每帧再抛一次**，屏幕停在上一棵树 | 改 `tone: "default"`；`toast` 页的代码块也补一句「`tone` 是**名字**不是颜色」 |
| `tooltip` | `tooltip("…", { arrow: "bottom", tone: "info" })` | `arrow` 只认 `up/down/left/right/none` ⇒ `"bottom"` **不画箭头**但白占 6px；`tone` 是**填充色**（Number），`Number("info")` = **NaN** ⇒ 每帧重绘（`prev != NaN` 恒真），填充色 0 | 改 `arrow: "down"` + `tone: 0x2563EB`（info 蓝）；文案补「`arrow` 是 up/down/left/right/none，`tone` 是填充色」 |
| `progress` | `progress("Indexing", { tone: "danger" })` | `progress()` **没有 `tone` 选项**（只读 `value`），传了等于没传 —— 静默的“红色进度条”从没红过 | 去掉 `tone`（第二根条靠 `value: 0.9` 区分） |

**钉子（两道，都做过变异）**：

- **行为面**：`docs tour` 新阶段 `6d toastHost` —— 选中该页 → **真按 stage 坐标点按钮** → 断言只开一帧就
  出现两条 toast（`x = 1000-16-220 = 764`、下沿 `700-16 = 684`、间距 8，全部**先推导再断言**），
  再把 `tsh.open` 翻回去断言两条都卸载、`stage.numChildren` 回基线。reflow 包在 `try/catch` 里：
  帧守卫会**吞掉**异常继续跑（这正是它刷满一屏还不崩的原因），不包的话 tour 永远写不出 `gallery.done`。
  变异 2/2：M1 = 把 `tone` 改回 `"info"` ⇒ `opening the toastHost demo threw: asaot.ui.toast: unknown tone 'info' …`；
  M2 = `TOAST_LAYER` 的 `gap 8 → 0` ⇒ `the toast gap is not 8 (652 -> 652)`。
- **静态面**：`tools/demo-options.cjs`（门）—— 文档站的**字符串代码块也一起扫**（那才是读者复制的东西），
  变异 3/3：给真实调用加一个 `bogusOption`、让 `progress()` 不再读 `value`（= 工厂从对的文档下面搬走）、
  以及从 `StyleRefinement.from` 删掉 `flexGrow` 这一条简写（证明“样式简写放行”是**从源码推导**的，
  不是一句万能豁免；这条变异的第一版只加了 `false &&`，扫描照绿 ⇒ 锚点改成整行）。

**这道门看不见什么（如实登记）**：它只比**键名**，不看**取值**——`tone: "info"` 的键是存在的，
所以那一类只能靠**行为**（tour 的真点击）发现。

**顺带的第二个发现**（同一轮，来自**证据文件自己**）：修完之后 `gallery-page0.png` 变了。追下去
是**滚动条被内容盖住**（`internalCount` 把条层也算成了内容基点）——一个从第七轮就存在、
42 页像素断言都没抓住的缺陷（条画对了，只是画在下面）。修法与钉子见 §3.3 第 25 条。

### 3.10 回调参数个数：一个只有「真点击」才暴露的类缺陷（第九轮补）

用户第二次报告的形状和上一次（§3.9）**一模一样**：屏幕上只有一个报错，页面其它部分都正常。
这次是滑块——点不动、拖不动，控制台一行 `#1063: Argument count mismatch`。

**根因是两个独立的缺陷，叠在同一个控件上**：

1. **调用传 0 个参数，声明要 1 个**。`SliderWidget` 里是 `n.onChange()`，而文档站每一页写的是
   `function (v:Number):void { … }`。AVM2 上**参数个数不符就抛 #1063**（不是「少传的算 undefined」），
   而帧守卫把它接住 ⇒ 回调**从未运行**、模型从未变、屏幕保持上一棵树，只有控制台有流。
   同一种错在 `CheckboxWidget`/`SwitchWidget`/`RadioWidget` 里也有（`onChange()` / 少了 `true`）。
2. **滑块没有拖动机制**。按下就地设值，之后移动鼠标什么都不发生——一个「看起来能拖」的控件。

**修法**：四个调用点补参数（`onChange(next)` / `onChange(true)`）；`SliderWidget` 按
`ScrollViewWidget` 的同一套写法重写（无 pointer capture ⇒ 拖动期间在 **stage** 上临时挂
`MOUSE_MOVE`/`MOUSE_UP`，`endDrag` 幂等 + `teardown` 摘除；单一写入点 `commit()`，值没变不报）。

**为什么两道旧门都漏了**：`probes/widgets/form` 的滑块用例**只点绑定了 `binding` 的控件**
（走 Binding 分支，压根不经过 `onChange`），而 42 页画廊只**渲染**——不点击就永远看不到 #1063。
所以这次补的是**两层**：

- **行为面** `probes/widgets/callback`（24 项，门）：只点**未绑定**的控件；滑块走完整手势
  （按下 → 拖到 0.75 → 越界夹到 1 → 拖回 0 → 松手 → 松手后再移动必须无效 → 纯点击设 0.5），
  并且**在拖动中间那一帧**读像素（松手会翻转 pressed 态、那次重绘会掩盖「控件没自抬重绘」的缺陷）。
  变异 **8/8**。
- **静态面** `tools/callback-arity.cjs`（门，双向）：kit 里每个值回调**调用点**恰好 1 个实参、
  `onClick` 恰好 0 个；文档站与探针里每个**声明**恰好 1 个形参（`onClick` 0 个）。
  变异 **6/6**。**它看不见什么**：按引用传的回调（`onChange: this.tabChanged`）解析不到 ——
  那一半只能靠行为门。

**顺带的承诺写进代码**：`UiNode.as` 顶部登记了三条约定（`onClick()` 零参、`onCommit(v)` 一个
提交值、`onChange(v)` 一个新值），`CONTRIBUTING-widget.md` §4 同步。

### 3.11 AIR 参考臂：默认跑法的入口，以及它顺手抓到的两个可移植性缺陷（第十轮补）

`ui-demo/air-gallery/build.sh` 现在把「看这个界面」变成一条命令：

```sh
cd asaotui/ui-demo/air-gallery
./build.sh          # AIR 参考臂：mxmlc 编出 GalleryApp.swf，再 adl app.xml
./build.sh aot      # 我们的 AOT 臂：stage → as-aot --air-app → tour → 跑起来
./build.sh swf      # 只编译（不弹窗、不出 exe）
./build.sh desc     # 不建：只报 --gpu 会用哪份描述符、带什么后端
./build.sh clean    # 删两个臂的产物（**不删** gallery-page*.png，那是入库证据）
```

两个臂读的是**同一个** `app.xml`（窗口尺寸/标题/`renderMode`/`requestedDisplayResolution` 的唯一真源）：
`--air-app` 在建期读它，`adl` 在运行期读它，脚本本身不重复任何一个窗口参数。AOT 臂刻意**不重写构建配方**
——它就是 `run-gallery.cjs`（stage/编译/tour/量截图都在那儿），脚本只负责选臂。

**默认臂此前根本不存在，原因是 tour**：`DocsMain.as` 同时是 AOT 文档类**和**无头验收 tour，而 tour 需要
`Stage.dispatchMouse` / `Stage.dispatchWheel` / `Stage.render` 三个钩子——AIR 里没有这种东西（AIR 的窗口由
操作系统驱动，不由程序驱动），所以 mxmlc 对那个文件直接报「通过静态类型为 Stage 的引用来调用的方法
`dispatchMouse` 可能未定义」（14 处）。新增 **`demo/DocsAir.as`**：同一个 `DocsModel` + `DocsView` + `UiApp`、
同一套订阅接线（少了那一行，首帧正常而点一下永远不响应）、落在同一页，**不跑 tour**。

**「我们的编译器收下了」不是可移植性的证据**（`tools/mxmlc-check.cjs` 存在的理由）。这次两处被抓出来：

| 位置 | 形态 | 为什么两边不一致 | 修法 |
|---|---|---|---|
| `ui-demo/demo/DocsStart.as` | 调 `box(...)` 而没有 `import asaot.ui.box` | 我们按名解析（同一包里当成可见）；mxmlc 要求显式 import | 补 import |
| `kit/asaot/ui/combo.as` | 文件里放着 `public function combobox` | AS3 硬规则：**一个对外可见的定义必须在同名文件里**。我们不看文件名；mxmlc 于是「找不到定义 `asaot.ui.combobox`」⇒ 调用处报未定义 | `git mv` 成 `combobox.as`（也是本库一直的命名约定：工厂 `xxx.as`，类 `XxxNode.as`） |

**钉子**：新门 `6b5` 直接跑一遍 81 KB 的 mxmlc 编译（约 1 s）；`tools/mutation-air-arm.cjs` **2/2 抓获**
（M1 = 删掉那条 import，M2 = 让 `DocsAir` 摸 `Stage.render`），每个文件按 sha256 逐字节还原，
还原后**再跑一次基线**确认文件真被放回去了。**它看不见什么**：编译通过不等于画面对——那一半靠
AOT 臂的 tour（手算矩形 + 像素）和人工看一眼 AIR 窗口（本轮实测：`requestedDisplayResolution=high`
在 AIR 上同样给 1000×700 逻辑窗口 / 1500×1050 物理像素，与我们的 AOT 一致）。

`build.sh` 的另一件事是**路径拼写**：本工作区同时从 Git-Bash 与 WSL 里驱动，而 Windows 的 node 读不了
`/mnt/d/...`、bash 又 exec 不了 `D:/...`，所以脚本把 SDK 根**两种拼写都算一遍**、各取能用的那一种；
`adl` 与 `adl.exe` **同名都在 SDK 的 bin/ 里**（无扩展名那个是 Unix shell 包装），选错就是
`Exec format error`——这些都写进了脚本注释，而不是靠“机器上恰好能用”。

> 顺带修掉一处**仓库级**缺陷：`.gitignore` 的 `/ui-demo/air-*/*` 把 `app.xml` 一起吞了 ⇒
> **干净克隆里没有描述符**，`stage-air.cjs` 会直接拒绝运行。现在显式放行 `air-*/app.xml` 与
> `air-*/build.sh`。

#### 3.11.1 选择窗口合成模式：`--gpu cpu|gpu|d3d12|gl|direct`（第十三轮补）

「能不能用 GPU 跑？」是拿到这套 demo 的人第一个会问的问题，而它在这个仓库里是**两个变量、两个通道**：

| 通道 | 谁读它 | 合法值 | 备注 |
|---|---|---|---|
| `app.xml` 的 `<renderMode>` | `adl`（运行期）与 `--air-app`（建期） | `auto`/`cpu`/`gpu`/`direct` | AIR 的 XSD 语义 |
| 构建清单的 `gpu-backend` | 我们的构建 | `auto`/`d3d12`/`gl` | **AIR 的 XSD 里没有槽位**（`adt` 直接把 `<windows><gpuBackend>` 当错 103 拒掉）⇒ 只能走 `as-aot --gpu-backend` |

所以 `--gpu <mode>` 把两半**一起**决定并一起送达：`gl`/`d3d12` = `<renderMode>gpu</renderMode>` **加**具名后端，
`gpu` = gpu + 平台自选（Windows 上是 D3D12），`cpu`/`direct` = 各自的 renderMode、不提后端。

**不写进 `app.xml`**，原因不是洁癖：`check-dpi.cjs` 要求 `air-gallery/app.xml` 与它的 `air-gallery-standard`
孪生**只差一行**（`requestedDisplayResolution`）。手改 `<renderMode>` 会让那道 A/B 变成双变量、因为与
HiDPI 无关的原因变红——本轮开工时工作树里正好躺着这样一处未提交改动。改成按需**派生**
`app.<mode>.xml`（相对 `app.xml` 只差 renderMode 那一行、被 `.gitignore` 覆盖、`clean` 会删），两个臂各自读它。

**这五档全都画同样的 42 页**——也就是说「我看了一眼，没问题」在这件事上是零信息：一个被解析后丢掉的模式
与真正生效的模式像素完全一致。能观测的只有描述符与 argv，于是新门 `6b5b`（`tools/buildsh-gpu.cjs`，29 项）
用 `desc` 臂把两者打出来（`desc` 走的就是 `aot` 臂 exec 的那个 `aot_args()`，不是另写一遍配方），2 秒、不需要编译器；
`tools/mutation-buildsh-gpu.cjs` **5/5 抓获**：后端只在文案里提过却没传、`cpu` 接成了 `gpu`、未知模式被吞掉、
派生描述符只打印不传、派生描述符**多漂一行**（最后这条正是会打红 DPI A/B 的那种）。运行时那一半由
`run-gallery.cjs` 每次构建自己断言：gpu 模式下清单里必须出现 `ASC_RENDER_WINGPU=1` 与对应后端宏，否则报错。

两个消费臂本轮真跑过：`aot --gpu gl`（清单 `ASC_RENDER_GL=1`、41/41 页 PASS、源里带 `gl_glue.cc`）、
`aot --gpu gpu`（`ASC_RENDER_D3D=1`、带 `d3d_glue.cc`）、`air --gpu gl`（`adl` 真开窗）。

### 3.12 参考运行时门：为什么必须有一道门真跑 AIR（第十一轮补）

前三轮的用户报告是同一个形状：**我们的 AOT 比 AIR 宽容**，于是库的错误在我们这里可以无声通过。

| 缺陷 | AIR | 我们的 AOT | 谁能发现 |
|---|---|---|---|
| `toast({ tone: "info" })` | 抛（我们的 build 也抛） | 抛，但**帧守卫接住** ⇒ 屏幕停在上一棵树、只剩控制台一行 | 只能“真点一下”（第九轮：tour 新 stage） |
| `onChange()` 少传参 | 抛 `#1063` | **同样抛**（语义对齐），同样被帧守卫吞掉 | 只能“真点一下”（§3.10） |
| `setChildIndex(child, index >= numChildren)` | 抛 `RangeError #2006` | **静默夹紧**（`emit.ts:11635`） | 只能跑真 AIR（本节） |
| 死节点上的 `mouseOut` | 抛 `TypeError #1009`（**晚一拍**才投递） | **根本不投递**（`emit.ts` 里 `mouseOver` 出现 0 次，即 G25） | 只能跑真 AIR，而且**要自己发指针事件**（第十二轮补的「指针钻」） |

前两类是「两边都错、但只有交互才看得见」，第三类是**只有 AIR 才错** —— 它靠 AOT 探针在原理上就无解：
夹紧后的显示序恰好等于正确显示序，像素一模一样。所以补了一道**反向**的门：不去猜 AOT 差在哪里，
而是**让参考运行时自己宣告**。

```sh
AIRSDK_HOME=$AIRSDK_HOME node tools/air-sweep.cjs     # 全量门的一部分（门 6b6），也可以单独跑
```

三个设计点，每个都是踩过坑才定下来的：

| 问题 | 做法 | 为什么不能更简单 |
|---|---|---|
| 42 页怎么在 AIR 里走完 | `DocsAir` 读旁挂的 `air-gallery/air-mode.txt`（`sweep [log] [open=k1,k2]`） | `NativeApplication.argv` **mxmlc 拒收**（实试：`通过静态类型为 NativeApplication 的引用来访问的属性 argv 可能未定义`）；AIR 又不能被脚本点击 |
| 结果怎么拿回来 | 应用自己写 `air-trace.txt`（`START` / `OPENED n` / `PAGE id` / `ERROR <page> …` / `SWEEP DONE n` / `END errors=n`） | `adl.exe` 是 GUI 子系统：父进程拿管道**收到空流**（实测，带窗口正常开）。另：`File.applicationDirectory` 拿到的 File **只读**（开写抛 `fileWriteResource` #3003），同一路径用 `new File("C:/…")` 就能写 —— 两半都实测 |
| 「关着的下拉」怎么变成「开着的」 | 门从 demo 源码里**推出**所有 `m.bool("<x>.open")` 键（现 10 个），每页把它们置 true 一帧再置回 | 演示默认是关的（`open: m.bool("sel.open", false)`），而**关着的状态本来就能跑**；不让它开，这道门永远是绿的、也永远是瞎的。键从源码推出，新增可弹层不用改门 |
| 怎么防止门自己变瞎 | `OPENED <n>` 是**翻完之后从模型里数出来的**，门要求它 == 键数；页数/顺序也从 `DocsCatalog.as` 推 | 只写个“我执行了打开步骤”的日志是不够的 —— 删掉翻页那行，日志照样有。数模型才是测量 |

**它看不见什么**（写清楚，不粉饰）：只覆盖**不需要点击就能到达的**状态（页面切换 + 由模型驱动的弹层开合）。
靠一次点击才出现的路径（比如“点了 trigger 才 `open` 的那个下拉”）在 AIR 里无法到达，那一半仍归
AOT tour + 各个探针；这道门补的是**反向的一半**：AOT 看不见的，让 AIR 说。

### 3.13 指针钻：没有指针的 UI 门等于没测指针类缺陷（第十二轮补）

第十二轮的用户报告（`#1009`，见 §3.3 第 28 条）暴露出 3.12 那道门的一个大漏洞：它自称「真跑参考运行时」，
却**一个指针事件都没发过**。AIR 不能被脚本点击。但那不是理由 ——
**门需要的不是 OS 指针，是事件**，而事件可以自己 `dispatchEvent`。

现在 `DocsAir` 每次切页前做两件事：

1. **悬停**即将离开那一页的**每一个叶子**（主树 + 浮层树）；
2. 切页，**等一拍**（reconciler 已把整棵树换掉），再把 `mouseOut` 投给**之前记下的那些 display 对象**。

日志里每一页一行：

```
ROLL <page> hovered=<h> destroyed=<k> errors=0
```

`destroyed` 是**测量**，不是声明：它数「刚才悬停的对象里有多少个**真的**已经死了」（`node.app == null`）。
实测：全站 **3107 hovered / 348 destroyed**。门的下限是 **100**（实测值的三分之一）：
如果哪天它掉到几十以下，说明钻头已经不咬了 —— 那就是**失败**，而不是「扫得全绿」。

两条变异把这件事钉死（`tools/mutation-air-sweep.cjs`，该文件现为 5/5）：

| 变异 | 期望 | 实测 |
|---|---|---|
| 去掉 `releaseListeners()`（把 `#1009` 种回去） | 红 | **15/41 页、145 个 `#1009`**（当时的口径） |
| 只悬停、不投递（钻头不咬） | 红 | 指针钻报 `0/41`、「destroyed 0 of 0 (floor 100)」 |

**代价**：每页多几百次 `dispatchEvent`，总时长基本不变（仍 ~20 s 一个窗口）。

### 3.14 阴影 / 渐变 / 换行截断 / 多行输入（第十四轮补）

这四件共同的危险不在「没实现」，而在**实现了却看不见**——三种都不会让任何属性断言变红：

| 件 | 假绿的样子 | 为什么只有像素/行为能拆穿 |
|---|---|---|
| `boxShadow` | 滤镜列表建好了、**没有赋给显示对象** | 属性全对、画面与没有阴影时**逐像素相同** |
| `Fill.gradient` | 只画**首站纯色** | 左边缘仍是对的暗色，只有「是不是斜坡」能看见 |
| `whiteSpace:"normal"` | 测量时**把 wrap 宽度丢掉了** | 节点发一个单行高度，文字溢出盒子但框本身合法 |
| `textOverflow:"ellipsis"` | 解析了、绘制时**不截** | 文本节点仍然「有文本、有宽度」 |
| `textArea` | 把 Enter **吃掉**（单行契约泄漏进来） | 不报错、不碎裂，只是**把已输入的内容恢复成上次提交值** |

探针 `probes/widgets/textfx`（18 checks）逐条钉住，且每条都是**测量**不是声明：阴影用 `blur 0 + (0,8)`
让断言成为**精确像素**（盒面上方必须 `#ffffff`、面 `#ffffff`、下方 4px `#808080`）；渐变量三点
（左近黑 / 中严格居中 / 右近白）；换行与**同串未换行参照节点**比高度（≥ 2.5 行）；截断要求
「变短 + 含 U+2026 + `textWidth ≤ 120`」；多行输入要求「`ab` + Return + `cd` 真的出现换行、
`onCommit` 仍为空、`onChange ≥ 4`」，再 blur 才轮到 commit。

变异 **5/5**（`probes/widgets/textfx/mutation.cjs`）：每一条都**移除一个机制**（滤镜不赋值 / 渐变画首站 /
wrap 宽度置 NaN / 截断条件置 false / Enter 加入消费集），且每个被改文件都在 `finally` 里还原并 sha256
**逐字节核对**。实测每条都让对应那一句具名变红——包括 M1 那句 `(80,84) is #ffffff`
（阴影根本没上屏，所以「下方必须有灰」是唯一能看见它的断言）。

礼仪边界（AGENTS.md §2.5，全部具名抛错而不是近似）：`BoxShadow` 的 `spread != 0` / `inset`、
`Fill.gradient` 的非 `linear` / < 2 色标 / 非 0 `focalPointRatio` / 非法 ratio、`whiteSpace:"normal"`
但宽度不是 POINT、`textArea` 无 `shapeA` 无 `tf` 时却带 `boxShadow`、未知 `whiteSpace`/`textOverflow` 值。

### 3.15 指针真实感（hover 在 AOT 里从来是死的）+ 图片真的能加载（第十五轮补）

**头号项不是「缺功能」，是「两个臂语义不同」**：库的 hover 过去只挂 `MOUSE_OVER`/`MOUSE_OUT`
（`UiNode.createBacking`），而 `as3compiler/src/emit.ts` 里 `mouseOver` 这个串**出现 0 次**——
生成的 C 里它只作为常量存在（`MouseEvent_MOUSE_OVER`），**没有任何派发点**（G25）。
后果是：`adl` 里按钮悬停会亮，**我们自己的产物里永远不亮**，而 41 页截图、所有 AOT 探针、
整个像素对比**全绿**——因为没有任何东西让指针动一下。

修法在库侧，且刻意**不自算矩形**：`UiApp` 接**一个** stage `MOUSE_MOVE`（两个臂都会派发、`bubbles=true`、
没命中时 target 退化为 stage），命中判定**复用运行时自己的 `as_pick_hit`**（与点击同一套规则，
自算就是第二套规则——“亮着但点不到”正是它的后果），再经 `backing → UiNode` 的 `Dictionary`
把**整条祖先链**置 hover（AIR 的 `mouseOver` 会冒泡，所以卡片必须随它的子件亮）。
`Mouse.cursor` 是**进程级**状态，因此 `applyCursor()` 每次从链上重新推导、否则回落 `auto`。
顺带一个真缺陷被这次重构抓住：`setHover` 会 `markPaint` 一个**已销毁**的节点（`#1009`），
所以 `destroySubtree` 必须注销注册表，且 `setHover` 对 `app == null` 要直接返回。

| 判据 | 钉什么 |
|---|---|
| `probes/widgets/pointer`（23 项，变异 **5/5**） | 叶子亮 / **祖先亮** / 兄弟不亮 / 换目标同一拍清旧的 / `MOUSE_LEAVE` 全清 + `Mouse.cursor` 回 `auto` / hover **不 reflow** / 撤销后注册表 −1 且下一次移动仍可用 |
| `probes/widgets/lifecycle`（9 项） | 销毁前后注册表计数；**仍然派发** `mouseOver`/`mouseOut` 当负控（它们现在什么也不该做） |
| `probes/widgets/interact`（25 项） | 禁用控件不吃 hover、离开后清干净 |

**第二件：`image()` 的 `src`**。控件自己持 `Loader`（`COMPLETE`→采纳 Bitmap 并**重新测量**、
`IO_ERROR`→写 `UiNode.loadError` 并调 `onError(msg)`，**不画任何自造的错误 chrome**）。
三个真陷阱：①**完成回调必须带上它自己的那个 Loader**，否则换过 `src` 之后旧的那次完成会
落到新节点上；②`onLoad()` **零参**、`onError(msg)` **一参**——这是已有的 arity 契约，`tools/callback-arity.cjs`
现在把这两个名字也纳入了两个方向的扫描；③`scaleMode` 未知值**抛错**（文档页过去写 `letterbox`/`zoom`，
两个都从来不是合法值，`zoom` 一直静默渲染成 contain ⇒ 页已按真词汇表重导）。

变异 `probes/widgets/imaging/mutation.cjs` **5/5**，而**第一版是 3/5**，两类假绿值得记住：

- M1（`COMPLETE` 不重新测量）在**第一版里 MISSED**：那时 `auto` 那张图的 `src` 从第一帧就在，
  于是“提交任务 → 首次布局”之间没有空隙，测量时像素已经在了，`markLayoutDirty()` 拿掉也看不出来。
  改成 **`src` 晚一点才出现**（300ms 后写 model 再 reflow），同一个变异立刻变红——
  **夹具的时序本身就是被钉住的契约**。
- M5（忽略 `stretch`）也 MISSED：`pic` 当时是 40×40 方框配 16×16 方图，**contain 和 fill 恰好同形**。
  改成 60×20 之后 `min(3.75, 1.25) ≠ 1.25`，两种语义才分得开——**一个变异不在几何上分叉，就什么也没证明**。

## 4 已完成且**可复现**的部分（不是意图，是跑过的）

一条命令跑全部 **46** 道门：

```sh
node tools/gates.cjs          # 46/46 PASS 才叫绿（定稿记录 reviews/gates-all-28.txt）
```

> 第十二轮补那次全量：**44/44 PASS**（`reviews/gates-all-26.txt`，exit 0），包括新门 `probe lifecycle`（9 项）
> 与 `kit listeners are all releasable`（29 wired / 0 raw），以及 6b6 改判后的
> `docs app on AIR (adl): … pointer drill … (41/41 pages, 10/10 popups, 0 errors, 348/3107 destroyed)`。
>
> 第十一轮补那次全量：**42/42 PASS**（`reviews/gates-all-25.txt`，exit 0），包括新门「docs app on AIR
> (adl): every page, popups open, no runtime error (41/41 pages, 10/10 popups, 0 errors)」。
> 新增的那道门每跑一次会**真弹一个 AIR 窗 ~20 秒**（它跑的就是参考运行时，没有无头形态）；机器上没有
> AIR SDK 时它 exit 3，`gates.cjs` 报 **SKIP**（不当事过，也不当绿）。

> 第九轮补那次全量：**39/40 PASS + 1 SKIPPED**（`reviews/gates-all-23.txt`，exit 0）。被跳过的是
> **G11 determinism**，原因正是它该跳的那一种：**测量期间编译器源码真的在动** ——
> 另一个会话正在改 `../as3compiler`（`M src/air-app.ts`、`M vendor/window_glue.cc`、`?? vendor/gl_glue.cc`），
> 它在本门 5 次构建的窗口里写了一次（`afefbcd0… -> 28588474…`）。
> 树稳定后单独重跑同一门 → **PASS**（内容哈希 `285884741a2ce350`，`reviews/gate-g11-rerun-2026-10-24.txt`）。
> 新增的两道门（`probes/widgets/callback` 24 项、`author callbacks carry their documented argument`）都在那次全量里跑绿。

> 全量 **31 道门**在 **CLEAN** 编译器树上跑绿（定稿记录 `reviews/gates-all-16.txt`，HEAD `480b81c`）；
> 上一轮 25 道门那次是 `gates-all-13.txt`，当时树上还带两个本地补丁（见 §3.7）——
> 那道 G11 门当时会据实报「modifications: M src/runtime.ts | M vendor/window_glue.cc」但**不会**因此变红，
> 它只对「测量期间又动了」敏感。

> 那道 G11 determinism 门在「**测量期间编译器源码真的在动**」时会给 `[SKIP]`（exit 3）而不是假红/假绿：
> 稳定但脏的树照样可测（PASS 会点名 `src/` 内容哈希），动了才算测不了。那分支自己也做过集成钉子
> （`reviews/gates-skip-path.txt`：`15/16 PASS, 1 SKIPPED`，exit 0 —— 那份记录是 **16 道门**时代跑的，机制与判据未变）。

| 验收 | 命令 | 期望 |
|---|---|---|
| **参考运行时扫全站（第十一轮补，G24）** | `AIRSDK_HOME=<sdk> node tools/air-sweep.cjs` | **41/41 页 × 10/10 弹层 × 0 runtime error**（`mxmlc` 编 → `adl` 跑 → 读应用自己写的 `air-trace.txt`）；变异 `tools/mutation-air-sweep.cjs` **5/5**（把槽位计数改回 `internalCount + i` ⇒ `#2006`；去掉「打开弹层」⇒ `OPENED` 缺；少走一页 ⇒ `visited 40/41`；去掉 `releaseListeners()` ⇒ 145 个 `#1009`；只悬停不投递 ⇒ 指针钻 `0/41`） |
| **指针钻：死节点上的 roll-out（第十二轮补，G25）** | `AIRSDK_HOME=<sdk> node tools/air-sweep.cjs` + `node tools/listener-wiring.cjs` + `node tools/probe.cjs probes/lifecycle` | `air-sweep` 行末报 **3107 node(s) hovered and 348 of them destroyed**、0 errors（每页离开前悬停该页每个叶子，切页**下一拍**投递 `mouseOut`）；静态扫描 **29 wired / 0 raw**；探针 **9 项** 0 failures；变异 4/4 + 3/3 |
| **滑块拖拽 + 回调参数（第九轮补）** | `node tools/probe.cjs probes/widgets/callback` + `node tools/callback-arity.cjs` | **24 checks**，0 failures（只点**未绑定**控件：checkbox/toggle/radio + 滑块的按下→拖动→越界夹紧→松手→松手后移动无效→纯点击）；变异 `probes/widgets/callback/mutation.cjs` **8/8**；静态门 15 调用 / 81 声明 / **0 违规**，变异 `tools/mutation-callback-arity.cjs` **6/6** |
| **多页 App（组件文档站，42 页）** | `cd asaotui/ui-demo && node run-gallery.cjs` | **42 页** tour 全绿（start→box→…→toastHost 四组逐页编译、布局、拉像素）+ **8 张** `gallery-page*.png`（1× 与 1.5× 各一套）+ `RESULT: PASS`；tour 还把「无 engine 节点 / 零矩形 / backing 未挂」三类静默失败**升级为判据**（变异自证：把目录页的 `image` 设成 0×0 ⇒ 红并点名 page 4），并对浮层树断言「切页后 `stage.numChildren` 回到基线、`findByKey(ovlDlg)` 为 null」（变异 `ui-demo/mutation-gallery-teardown.cjs` **2/2**）；另加**两条浮层像素判据**：scrim `#999999`、面板 `#ffffff`（钉住「入场动画落地」，见 §3.3 第 15 条） |
| **画廊覆盖全部 kind** | `node tools/kind-coverage.cjs` | **36/36** 个注册 kind 都被画廊调用（0 个「无工厂」kind = 无作者面缺口）+ `RESULT: PASS`；**变异** `tools/mutation-kind-coverage.cjs` **3/3**（把 tree 调用改名；新增一个 kind+工厂却没人用——这正是**发生过两次**的回归；把调用藏进 `//` 注释——扫描器第一版就是这样把散文算成了代码） |
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
| **G16 `cond ? null : X` 的条件为假（已修，阶段二百六十六）** | `node probes/g16-ternary-null/run.cjs`（门 §9b） | **20 格**（新增 18-20 = `x != null ? null : 42/true/7`）：**AIR 20/20 符合手写规则，AOT 20/20 一致（0 偏离、0 崩溃）**；门要求 AOT 偏离集**恰好等于**已登记集（已清空 ⇒ 任何新增偏离、用例停跑、**偏离无声消失**都报警）；变异 `mutation.cjs` **4/4**。库内 if/else 绕行已于 2026-10-24 换成三元（4 处），3 处选项守卫保留 |
| **G19 `drawRoundRect` 圆角（已修，阶段二百六十七）** | `node probes/g19-roundrect/run.cjs`（门） | 每行逐字节对照：**292 行相同 / 27 行在 AA 容差内 / 0 行分歧 / 40 行已登记**（负半径）；库侧无绕行可撤，只把 `probes/widgets/motion` 的 `(20,20)` 期望像素从直角色改成 `#ffffff` |
| **G20 `setTextFormat` 追加 run（已修，阶段二百六十八）** | `node probes/g20-settextformat/run.cjs`（门） | 12 格关系式双 runtime 全绿（修前 7 格红：`46.66 → 91.53 → 136.41 px`）；变异 **5/5**；库侧唯一调用点 `PaintKit.measureField` 依赖替换语义，`InputWidget.paint` 仍不调（设计选择）；`typing` 的 M3 已从「setTextFormat 回到 paint」重指为「paint 把字符串写两遍」 |
| **G21 `getTextFormat` 读回（已修，阶段二百七十）** | `node probes/g21-gettextformat/run.cjs`（门） | **30 格双 runtime 逐字相同（0 分歧）**：无 run 回 `defaultTextFormat`、跨界/反序/空区间回空格式（十字段全 null）、相邻等值 run 仍回格式、`(0,0)`/`(begin>=length)` 抛 `#2006`；变异 **5/5**；库内 `getTextFormat` 调用点 **0 处**（无绕行） |
| **G22 闭包内静态读（已修，阶段二百六十九）** | `node probes/g22-closure-statics/run.cjs`（门） | **10 格双 runtime 逐字相同** + 对**生成的 C** 做源码审计（每个静态读都带 `(Owner_cinit(), …)`，前向声明先于首次调用）；变异 **4/4**；`warmUp()` 脚手架全仓 **0 命中** |
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
> **G14 已修（阶段二百五十三）**——`Array` 进 `Object` 槽不装箱；**G16 已修（阶段二百六十六）**，
> （`cond ? null : X` 的条件为假时塌成结果类型零值）；**G19/G20/G21/G22 均已修（阶段二六七~二七〇）**；
> 对应的**库侧临时应对已在 2026-10-24 全量审计并回退**（4 处 if/else 换回三元、陈旧注释与失去牙的变异 M3 重指），
> 逐条结论见 `reviews/revisit-g16-g22-workarounds-2026-10-24.md`；
> **G3（Tab 环上限 64）仍是本库唯一的键盘能力上限**；G8/G9/G14 的复核见 `reviews/revisit-g8-g9-workarounds-2026-10-23.md`。