# asaot.ui — 完成度实测表（STATUS）

> 回答一个问题：**「UI 库写完了吗？」**
>
> 结论：**深水区做透了，表面层补齐了三批（控件集 + 多页 App + 组件目录页 + 浮层系统 + 交互动线），但还不是一个完整工具箱。**
> 深水区（布局引擎 + 三端差分）做透；**控件集从 4 个扩到 41 个 kind / 47 个工厂**（第二批 media/feedback/data 九件、
> 第三批**浮层六件 dialog/drawer/popover/menu/toast/select**、第五批**列表虚拟化 `virtualList` + 选择三件**
> `tree`/`combobox`/`datePicker` 均已落地）；
> **样式面从 18 字段补到 33 字段**；**组件文档站已跑起来**（`ui-demo/demo/DocsMain.as`，**56 页 / 10 组**，每页两个 live 示例 + 产生它的源码），
> 且**每个注册过的 kind 都在画廊里看得见**（`tools/kind-coverage.cjs` 扫描门：**41/41**，变异 4/4）；
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
> 第十六轮（2026-10-25）补的是 **`table` 欠的三件 + 滚动贴底**，其中一件不是缺功能而是**缺陷**：
> ① **表格几乎点不到** —— 运行时按**绘制区域**取命中目标，而表只画 1px 网格线和字形 ⇒ 在一个空单元格中间
> 点一下，目标是**表格背后的根**，行根本选不中（只有恰好点在网格线上才行）。修法：`shapeA` 先画一个
> **全透明命中矩形**（alpha 0 仍是区域，运行时注释里就是这么推荐的 Flash 惯用法），不动一个像素。
> ② **排序**：`onSort(column, descending)` 只报意图，秩序归作者的 `sortColumn`；循环是浏览器那套
> （另列→升序、同列→降序、再点→**-1 无序**）；`TableNode.sortRows` 排的是**拷贝**（qsort 不稳定 ⇒ 用原始
> 下标做 tie-break，且**在降序翻转之后**才加，否则降序会翻车），数字比数字、文本比文本（所以 Qty 排得出 1,2,10）。
> ③ **列宽**：拖拽只画 1px 预览线、**release 时调一次** `onColumnResize(index, width)`，**从不回写 `columns`**
> （作者模型常是内联字面量，写进去下一帧就没）；松手后窗口 glue 补的那个 CLICK 被吞掉，否则"调列宽"会顺手排序。
> ④ **虚拟化**：只挂可见窗口 + 一行被 `scrollRect` 裁掉的半行，header 不滚、body 高 = `height - rowHeight`
> （所以必须是 POINT 高度）、行 key 用**绝对下标**（窗口移动就得挂新节点）。⑤ `scrollView.stickToBottom`：
> **每帧一次比较，比的是上一帧的 `maxOffsetY`** —— 长大之后再问"我在末尾吗"永远得到否，所以那个答案必须
> 在更新前取；新视图算在末尾（日志开屏就是最新一行）；0.5px 内算末尾，再远一格就算读者接管。
> 判据：新探针 `probes/widgets/table2`（**6 变异全中**）与 `probes/widgets/stick`（**5 变异全中**）；并发现
> `tools/gates.cjs` 的探针名单是**手写**的 —— 上一批的 `pointer`/`imaging` 一直不在里面，也就是**没人跑**。
> 现在四道全接上，门 46 → **50 道**。
> 第十七轮（2026-10-25）补的是 **图标通道 `icon(svgPathData)`** —— 表面上是“加一个控件”，底下却先撞上
> 一条**整条缺失的底层能力**（登记为 **G26**）：`Graphics.cubicCurveTo` 与 `Graphics.drawPath` 在 `emit.ts` 里
> **一个字都没有**（17 个 `Graphics_` 成员里只有**二次** `curveTo`，Skia 桥也没有 `cubic_to`），而图标集
> （Lucide/Material/Feather）的曲线**绝大多数是三次**。三条处置，一条比一条重要：
> ① **转换放在 AS3 侧，不放在编译器侧**：`C/S` 用**自适应细分**转成二次段（偏差上界取标准结论
> `(√3/36)·|P0−3P1+3P2−P3|`，超过容差就 de Casteljau 二分，容差 = **四分之一个渲染像素**换算成 viewBox 单位）；
> 因为两个臂跑的是**同一串二次段**，跨臂逐像素一致——代价是对原始 SVG 有可量化的几何偏差，由探针钉住。
> ② **`A`（椭圆弧）抛错，不静默画弦**：SVG 的弧必须先转三次再转二次，而三次正是缺的那一层；把弧画成直线
> 会得到"看起来没错、其实形状不对"的图标——这正是本项目**拒绝**的那类失败。报错文案直接自报 G26。
> ③ **`icon()` 在 describe 时就解析一遍**：坏数据在作者写的那一行抛，而不是在某一帧的 paint 里抛。
> 顺带纠正了一条**过期一年**的库内实测注释：5 处注释称"本后端 `lineStyle` 描边宽度不生效"（所以全库的线条
> 都画成 1px 填充）。**重测为假**：`lineStyle(2/4/6/8/12)` 在直线、二次曲线、圆（r=7/14/20）、矩形上一律
> **精确等于声明宽度**（图标探针钉住 4px/8px/12px 三档）。描边因此可用；那批 1px 填充仍保留（整数像素，
> 探针能断言单像素），但**理由从"后端做不到"改成"这是选择"**。
> 判据：新探针 `probes/widgets/icon`（**57 项**，含三次曲线 t=0.5 点、三档描边宽度、viewBox 缩放，以及
> `A`/未知命令/工厂抛错三个**负例**）+ 变异 **6/6**；文档站新增 `icon` 页；门 50 → **51 道**。
>
> 第二十五轮（2026-10-27）是**运行时主题切换**——用户的要求是一句话
> （`Theme.setTheme(ThemeTokens.dark())` 之后整棵树在下一帧变暗，而默认亮色逐字节不变），
> 底下却是四件事一起改：**47 slot 的调色板**（`ThemeTokens`，亮色逐值复现旧字面量）、
> **`setTheme` 的 epoch 管线**（拷入 + 重建每 kind 基线 + 重建浮层 chrome + bump `themeEpoch()`）、
> **`UiApp` 的消费者**（epoch 变 ⇒ 全树 `lastStyleStale` + `M_PAINT` + 一次 `Dirty.THEME` 重新 describe，
> 那个存在多年却零消费者的脏位第一次接上）、以及**18 个自绘控件 + 5 个节点类 + 6 个工厂改成读调色板**。
> 顺带修掉三件结构性欠账：①`setControlDefault` 从「直写默认表」（主题一换就静默抹掉作者定制）
> 改成**override 层**（跨 swap 存活，`clearControlDefault` 才回落）；②暗色的**状态混合翻向**
> （亮色 hover→白 / press→黑，暗色两者都向白且 press 更强，否则按下去看不见）；③`knob` 在暗色保持纯白
> （被照亮的实体跟着变暗就消失了）。判据：新探针 `probes/widgets/theme`（**75 checks**，一棵树画**三个相位**、
> 12 个采样点 × 3 + 15 个矩形前后比对 + 6 条契约），第三个相位是**用户实际触发的入口**——
> `onClick` 里调 `setTheme`（在事件派发当中重建静态指针），这一段自己有牙（`probes/widgets/theme/click-teeth.cjs`，
> 把处理函数指回 `light()` ⇒ 12 点全红）；变异 `tools/mutation-widget-theme.cjs` **8/8**；
> 门 56 → **57 道**；`kit/` **178 → 179 个 .as**。**探针自己踩到三件事**（`showWindow` 会吃掉它之后的
> 模块级初始化、OFF 开关的旋钮就停在采样点上、1px 边框永远是两个半覆盖列 ⇒ 边框不可能有精确像素期望）
> 与**变异机抓到的一件真事**（根样式每次重建时 `markThemeDirty` 与 `staleDescendants` 互为备份 ⇒
> 删任一个都不变红；改法是让被测形状里所有指针都稳定，见 `reviews/theme-2026-10-27.md` §4.2）都写进了该文档。
>
> 仍然缺的是：样式面的 `grid`，以及可访问性字段仍无消费者（`role`/`ariaName` 只是数据）。
> （`accordion` 多开已在第二十二轮落地，见 §3.17d；`image` 的 `cover`、`list`/`table`/`tabs` 的键盘导航、
> 文字装饰同为该轮内容。）
>
> 本表每一行都有可复核的命令。**不要采信本表，跑它。**
生成日期：2026-10-25（第十九轮补：G24/G25/G26 修好之后的**库侧妥协编码审计** —— 图标通道的曲线细分与弧拒绝**全部撤除**，12 处「因为引擎做不到」的陈旧注释改写为「这是设计选择」；第二十轮补：G27 修好之后的同一套审计 —— `emcc` PE 转发器与 `.scratch/emcc-shim/` **整体删除**，`--check` 改问编译器自己的 `doctor`；第二十二轮补：四件「有槽位没行为」的空缺（`list`/`table`/`tabs` 键盘导航、
`accordion` 多开、`image` 的 `cover`、文字装饰自绘），新增缺口登记 **G28**（`TextFormat.underline` 不被绘制，✅ **已于 v0.4.303 在运行时修掉**，见 `compiler-gaps.md` G28）；第二十四轮补：**输入面最后四件**（右键 + 点锚菜单 / 双击 / `splitPane` / 键位系统 `ActionRegistry`+`KeyStroke`+`ContextExpr`+`Control.action`+`tabIndex`），顺手拆掉两个只报「条文」不报「代码」的门 —— `kind-coverage` 把字符串里的调用当成了真调用、`demo-options` 的共享键表是手抄的副本）；第二十五轮补：**运行时主题切换**（`ThemeTokens` 47 slot + `Theme.setTheme` 的 epoch 管线 + `UiApp` 的 `Dirty.THEME` 消费者 + 18 个自绘控件改读调色板；`setControlDefault` 改成跨 swap 存活的 override 层），判据 `probes/widgets/theme` **75 checks**、变异 **8/8**） · 对应 `kit/` **182 个 .as** · 第二十六轮补：**性能排查**（用户报「感觉性能有重大问题」——实测坐实且不在引擎：重复 key 检查是 O(n²)，占无变化 describe 的 98%，300 个按钮 39.3ms → 1.0ms；文本测量无缓存、`measureValid` 只写不读，占 layout 的 85%，单点文本变化整帧 13.3ms → 1.7ms；一个「paintAll→paintDirty」的优化被 `stick` 探针否决并已回退） · 一次性验收：`node tools/gates.cjs`（**59 道门**）；第四十二轮（MOBILE M1 前半）再加 `widgets/touch-scroll`，共 **61 道门**

> 第四十一轮（2026-10-31）补的是**移动端的第一块地基（MOBILE.md M0）**：`Pointer` / `PointerRouter` /
> `InputConstants` + `UiApp.pickAt` + **合成 mouse 兼容层** —— 一份合成 touch 序列就能驱动既有 kind，
> 且「手指底下是谁」不是库自算的矩形，而是与引擎 hover **逐点对账**过的。真触摸仍挂在 **G5**
> （窗口后端不产生 `TouchEvent`），所以这一轮的诚实说法是：**路由与按压语义可验，平台输入仍缺**。

> 第四十六轮（2026-10-31）**回头把 C1/C2/C3 三件做扎实**：三个真缺陷、八条新断言、两次全量门。
> 这一轮全部由「读代码 + 补相位」挖出来，没有一条靠猜：
> **① `appBar` 的槽位写 `opts.x as Node` ⇒ 传数组就静默丢掉**。文档站 `appBar` 页**自己的示例**是
> `trailing: [icon(...)]`，所以那只汉堡图标从第一版起就没上过屏——没有报错、没有告警、靠肉眼也看不出
> （bar 只是右边空了一点）。修法是工厂里归一：`Node` 原样、`Array` 长度 1 取出、长度 >1 用 `row(...)` 包一层
> （gap 8，与 bar 自己的一致），非 Node 成员**抛**。探针加相位 9：两个 24/28 宽的动作必须落在 248 与 280，
> 即与单槽同一个盒（24+8+28=60）。
> **② `navStack` 的 BACK 是 stage 监听 ⇒ 每个挂载的栈都听得见**。手机 app 的常态组合是「一个 tab 一个
> `navStack`，全挂载、只显一个」，于是**一次系统返回会掀掉所有 tab 的历史**（用户看不见的那些也在退）。
> 修法：`visibleChain(n)` 沿 `parent` 检查自己的与所有祖先的 `visible`，隐藏栈直接忽略该键——与
> `UiApp.pickAt` 对像素用的是同一条规则。探针在隐藏 tab 里多挂一个栈并计它的回调；删掉这段检查，
> 变异 M8 立刻红。
> **③ `safeArea` 退回 0 不会重排（两处叠加，缺一不可）**：`applyEngineStyle` 只在 `resolved.padding`
> **非 null** 时才写引擎，所以「折回 unset」等于**不写**，引擎里留着上次的 47；而 `setSafeInsets` 走的是
> `resolveStyle(true)`（`keepPrevious`），diff 基线停在加 inset 之前 ⇒ 折回 0 时 diff 归零、**没有任何
> measure 脏位**。症状：退出全屏/刘海消失后 bar 永远停在 103px，直到下一次无关重排。修法：声明过的边
> **必须产出定值**（inset 0 也写 0，未声明的边仍保留作者的 NaN），且 inset 变化要显式 `markLayoutDirty()`。
> 探针的铁律是**先加 inset、再撤掉**：appbar 47pt → 103px → 56px、tabbar 34pt → 90px → 56px，
> 并把底部 34px 那条带的像素钉成 bar 自己的颜色（证明 inset 是 PADDING 而不是 bar 下方的空隙）。
> 三件新能力也补上了断言：`items` 从 3 缩到 2 时**删掉的那格必须不在树上**（而不是变透明）、
> `icon:` 是 Node 时保留作者颜色（bar 只染字符串路径）、`pages: []` 是合法值（挂 0 个子节点，不崩）。
> 判据：`probes/widgets/navstack` **16 checks / 变异 9/9**、`probes/widgets/appbar` **22 checks / 变异 11/11**、
> `probes/widgets/tabbar` **13 checks / 变异 9/9**（三个探针的 program 内断言都比之前多）。
> 全量门：**50 PASS / 14 FAIL / 1 SKIP**（`reviews/gates-macos-2026-10-31h.txt`，**65 道门**）。
> 13 个红与上轮**完全同一批**（9 个要 AIR SDK、`G11` 采样窗口、`imaging` 只有告警、`choice` 的老 1.5px）；
> 第 14 个是 `widgets/touch-scroll` 的**惯性 coast 断言**在整机负载下偶发（`still at 109.70`）——
> 单跑 3 次全绿，机制是 coast 用 `getTimer` 实测 dt 积分，一帧被系统拖长就直接衰减到 0。**这是 flake，
> 不是回归**，但也说明那条断言对负载敏感，值得下一轮改成「至少推进了一步」而不是「明显滑了一段」。

> 第四十七轮（2026-10-31）**「本机没装 AIR SDK」这个 SKIP 是假的，错在检测**。用户贴出 TalkMED 打包脚本
> `bin-aot/build-aot.sh` 问「你那个脚本是怎么找 SDK 的」，一对照就看出来：那个脚本**先问环境变量、再按候选路径
> 逐个验证**（`[ -f "$c/src/index.ts" ]`），而我们的四份检测（`gates.cjs` 的 `airSdkRoot()`、`mxmlc-check.cjs` 与
> `air-sweep.cjs` 各一份 `sdkFromPath()`、`ui-demo/air-gallery/build.sh` 的 `sdk_root()`）**只问 `AIRSDK_HOME`
> 和 `PATH`**，而且**十个探针 runner** 与 `air-check/verify-air.cjs` 里还写死了 `'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1'`
> 这个 Windows 兜底（`tools/mutation-docs-tour.cjs` 的 env 默认值也是它）。**在 macOS 上，这个兜底等于「保证找不到」。**
> 实测本机：`AIRSDK_HOME` **未设置**、`PATH` 里那条 `.../AIRSDK_51.2.1/bin` **目录已不存在**（是旧版本卸载后的残留），
> 而 SDK 真身在 `~/Documents/Software/AIRSDK/AIRSDK_51.4.1` —— `mxmlc` 编文档站 **1.8 s**，`adl` 跑完 **56 页**。
> 所以「本机没装 SDK」这个结论从第四十一轮起就是**检测的错觉**，代价是 10 道门四轮没测。
> 修法不是到处加 `||`，而是把「SDK 在哪」收敛成**一个**答案：`tools/air-sdk.cjs`
> ① 顺序 `--sdk` → `AIRSDK_HOME` → `PATH` → **按安装位置搜**（`~/Documents/Software/AIRSDK/*`、`~/AIRSDK*`、
> `~/Desktop`、`/Applications`、`/opt`、`/usr/local`、仓内 vendored，每个父目录**只下一层**，容器目录再下一层抓
> `AIRSDK_*` 子目录）；② 命中必须**结构化验证**：`bin/mxmlc`（POSIX 还要可执行）或 `bin/mxmlc.bat`（Windows），
> **按宿主平台选拼写，两个列表不相交** —— SDK 是一个 zip 带全平台启动器，`bin/adl.exe` 存在**不代表** macOS 能跑；
> ③ 同机多个版本按**版本号**取最新、`complete`（mxmlc 与 adl 都有）优先；
> ④ `--sdk` 指了个跑不起来的目录时**报错而不是偷偷换成搜到的那个**（「我要这个」和「随便给我一个」是两件事）；
> ⑤ 每个位置试过都记账，`--why` 能列出来 —— 「没装」这句话本身就是上一轮最贵的错误信息。
> 12 个文件收敛到它（`gates.cjs` / `mxmlc-check.cjs` / `air-sweep.cjs` / `build.sh` / 9 个探针 runner /
> `air-check/verify-air.cjs`）。**门**：新第 66 道 `AIR SDK resolution`，11 个用例全在 `temp/airsdk-check/` 夹具树上跑
> （HOME 重定向到夹具、PATH 清空），覆盖：最新完整装赢得过旧装、名字最新但 `bin/` 空的不算 SDK、只有
> `adl.exe`+`mxmlc.bat` 的 Windows 树在 POSIX 上不算、mxmlc 有而 adl 无标 `complete=false`、`--sdk` 不可用不回落、
> `AIRSDK_HOME` 有效时优先、`AIRSDK_HOME` 是别的系统的路径时**继续找**（这正是本机的情形）、`PATH` 指向过期
> `bin/` 时**继续找**、`ASC_NO_AIR_SCAN=1` 真不做搜索、CLI `--print` 与模块答案一致、miss 时 `exit 3` 且报出搜索过的地方。
> 变异 `tools/mutation-air-sdk.cjs` **5/5**（结构校验去掉 / 版本排行反向 / `--sdk` 回落 / `ASC_NO_AIR_SCAN` 失效 /
> `complete` 只看 mxmlc），且**先验基线必须绿**（会变异的跑法若基线就是红的，什么也证明不了）。
> 顺手修好 `air-check/verify-air.cjs`（**这个文件此前根本跑不起来**，与本轮无关）：`require('../../tools/mxmlc-run.cjs')`
> 指到了工作区外面（`air-check/` 只比 `asaotui/` 深一层，应为 `../tools`），且 mxmlc 用 `cwd: HERE` 写的
> `aircheck.swf` 之后却按**进程 cwd** 去 `statSync` ⇒ 编译刚成功就 `ENOENT`。修好后实测：mxmlc 11968 B、
> `adl exit=0`、`air-out.txt` 105 行 GOT、**与 yoga 臂和 as3 臂各 105 行全同**（两条 `*** IDENTICAL ***`）。
> 写这个门时**自己先被咬了两口**：① 夹具里 `AIRSDK_60.0` 只有 `mxmlc.bat`+`adl.exe`，旧实现照样判「可用」——
> 因为 `isLauncher` 的候选表是 `['mxmlc','mxmlc.bat']` 混排，而 0755 的 `.bat` 过得了 `access(X_OK)`；改成**按平台
> 不交叠**的列表才红；② `scan()` 里原先排了一次序、选中时又排一次，两处一致 ⇒ 反转任意一处都**不会**改结果
> （变异 M2 首跑 stayed green），删掉冗余那次，排行的唯一真相留在选中处。

> 第四十六轮（2026-10-31）**不改判据，只改跑法**。用户的原话是「改代码几分钟测试几小时」——
> 全量门从 **45 分钟**降到 **6.3 分钟**（`reviews/gates-macos-2026-10-31i.txt`：**52 PASS / 2 FAIL / 11 SKIP**，**380 s**，65 道门）。
> ① **探针块改有界并发**：39 个探针按 6 路跑（`--jobs N` / `ASC_GATE_JOBS`），每个探针本来就有自己的目录和
> 构建指纹，互不干扰；**计时类探针（`perf`/`anim`/`feedback`/`motion`/`touch-scroll`）单独串行** ——
> 它们的断言是「15ms 上限」「10 帧里重画了几次」「coast 按实测 dt 积分了多少」，混在构建噪声里只会假红
> （实测：`touch-scroll` 在 6 路池里报 `the third release did not coast (still at 20)`，单跑必绿）。
> ② **每道门打印自己的耗时**，长跑不再「看起来卡住」；`--only <regex>` 只跑相关的门，其余如实打 `[OMIT]` ——
> **被 stub 过的门一律不许报 PASS**（空 transcript 会让里面每条断言都平凡成立），这是把「快」和「诚实」分开的那条线。
> ③ **AIR 参考臂在缺 SDK 时改报 `exit 3` / SKIP**：以前是先把 AOT 臂建完再报红，9 道门每道白烧几分钟，
> 还把「本机没装 SDK」算成这个工作区的错。
> 顺带修掉**三个真缺陷**（都不是本轮新写的代码，是一直红着、或一直没被看见的）：
> ① `ui-demo/air-run.cjs` 的 `killImage` 只有 Windows 的 `taskkill`，macOS 上抛 ENOENT 又被「没在跑」这个
> 注释吞掉 ⇒ 每跑一次画廊就留一个 `GalleryApp` 窗口（实测一台机器攒了 **7 个**，最老的 1.5 小时）。而它
> **继承了父进程的 stdout** ⇒ `spawnSync` 等管道关闭等到 420 s 门闸超时 ⇒ `gallery tour` 与
> `descriptor DPI A/B` 各报 **420 s**（真值 22 s / 43 s），两道门白等 14 分钟。修法三件一起：
> `killall -q <name>`（按**进程名**精确匹配，不是 `pkill -f` 的子串——那条曾把别人的进程一起杀了）、
> 先按自己 spawn 的 pid 杀（带进程组，窗口跟着走）、窗口的 stdout 改指 `gallery.run.log`
> （**grandchild 不许持有父进程的管道**）。
> ② 编译器保留名表漏了 `poll`/`ppoll`/`select`/`pollfd`/`fd_set` 一族：`probes/widgets/imaging` 里一个
> AS3 自由函数 `poll()` 生成 C 后与 `<poll.h>` 撞名（`static declaration of 'poll' follows non-static
> declaration`，连带 `too few arguments to function call, expected 3, have 0`），这道门**长期红着**，而
> `probe.cjs` 只打印尾部 40 行 ⇒ 真错误埋在几百行 clang 告警里。补进 `symbols.ts` 的 `C_RESERVED_SEED`
> 后 **31/31 绿**（`poll.h` 本来就在 `gen-c-reserved.ts` 的 POSIX 头列表里，是没落进提交的那张表）；
> `probe.cjs` 失败时改为**先打 error 行、再打尾部**。
> ③ `buildsh-gpu` 门在 macOS 上断言 `--gpu gl` 必须退出 0，而 `build.sh` 是**故意拒绝**的（gl 是 Windows 后端）
> ⇒ 这道门在 mac 上永远红。改成「非 Windows 时断言**拒绝** + 说明原因 + 不写描述符」，变异 M1 同步改为打
> 本机真正会跑的 `d3d12`（同一行、同一个缺陷），5/5。
> 剩下两道红都是既有的：`widgets/choice` 的老 1.5px 文本居中断言、`G11` 的 `1/5 hashes`（编译器树在
> 采样窗口内被动过）。

> 第四十五轮（2026-10-31）落地 MOBILE.md §5 的 **C1/C2/C3 —— 手机骨架三件**（`navStack` / `appBar` / `tabBar`），
> 这是移动端第一次真正出现「页面」这个概念，也是第一次新增 kind 而不只是给旧 kind 加字段。
> 三条决定值得单独记：
> **① `navStack` 的页面全部常驻挂载，只切 `visible`** —— 这不是偷懒，而是「页面状态不丢」的唯一实现：
> 卸载再重建的栈即使把 `offsetY` 拷回来，也丢失了输入框里的未提交文本、焦点、正在跑的动画；代价是隐藏页
> 每帧仍参与 measure/arrange（注释里如实写明，不假装免费）。探针因此**同时断言像素与节点身份**：
> push→pop 回来后 `sv`/`svr0` 必须还是**同一个对象**，只查像素的话「卸载+重建+拷 offset」的假栈也能过。
> **② 页面尺寸由工厂强加，不要求作者知道栈的当前盒子**（`position:absolute` + `inset:0` + `size:[pct(1),pct(1)]`）。
> 实测两次才对：只给 `inset:0` 不给空盒定尺寸、给 `flexGrow:1` 在 absolute wrapper 里不长、`pct(1)` 塌成 0
> ——三种「显然」的写法都失败，最后是「absolute 页 + 带尺寸的栈」这一条同时满足两者。
> **③ `appBar` 的大标题收进 compact 行用的是 CLIP 而不是换行**：`collapse` 从 0 走到 `largeExtra` 时，
> 标题的顶端**不动**、高度被裁，所以 8px 剩余时看到的是半行字而不是跳一下。四个停靠点（0 / 28 / 48 / 溢出钳制）
> 都有像素与矩形断言。
> 期间抓到**一个真缺陷**：容器的背景不是引擎画的 —— `AppBarWidget`/`TabBarWidget` 的 `paint` 一开始是空的，
> 于是 bar 的 `background` 从来没上屏（像素断言直接报 `#ffffff`，而根容器也是白的，只看截图会以为「没问题」）。
> 修法是照 `BoxWidget` 的形态：`build` 里在 `backing` 的第 0 个孩子放 `Shape`，`paint` 里
> `PaintKit.paintBox + decorate`。
> 判据：`probes/widgets/navstack` **16 checks / 变异 7/7**、`probes/widgets/appbar` **22 checks / 变异 8/8**、
> `probes/widgets/tabbar` **13 checks / 变异 7/7**；文档站新增三页（共 **56 页**），`kind-coverage` 回到 **44/44**。
> 仍然缺的：页面过渡动画、`tabBar` 指示条、`safeArea` 底部的**真机实测**（桌面 env 全 0，只能验折 padding 的通道）。

> 第四十四轮（2026-10-31）把 MOBILE.md 的 **S3 越界回弹**补齐、并把 **S6 四件里的两件**（`onVisible` +
> `scrollToIndex`）落地 —— 两处都在**已有的两个 kind 里**，一个 kind 都没新增。回弹的关键决定是**语义分家**：
> `offsetY` 是「作者态」，`overscrollY` 是「拉伸量」，**手指是唯一能让 offset 出界的东西**（滚轮/拖 thumb
> 一律硬夹，桌面语义不变），所以拖到尽头再往回拉时作者的模型**不会被污染**（断言：拖到 220px 越界，
> `offsetY` 仍是 180、`overscrollY` 30~50）。阻尼用 iOS 那条 `f(x)=(x·dim·c)/(dim+c·x)`，回位是指数弹簧
> （按 `getTimer` 实测 dt 积分，<0.5px 直接写 **0**，所以 M1 的「回位误差 <1pt」是**误差为 0**）。
> 证据除了数值还有**像素**：拉伸时视口底部露出的必须是视口自己的 `#F5F5F5`，回位后必须变回行色。
> `scrollToIndex` 则踩到一个**只有跑起来才会发现**的库级坑：**在帧内 (`paint`/`payload`) 调用作者的
> `onScroll`，作者在回调里做的 `view.invalidate()` 会被 `UiApp.reflow` 结尾的 `_pending = 0` 清掉** ——
> 模型已经到 2400、树却永远停在 0..8。改法是把请求**移出帧内**（0ms 定时器回到事件循环，与滚轮/按键/
> 点击同一条时序），并且做成 **change-detection**（值不变不重复生效，否则用户滚走后任何一次无关 re-render
> 都会把窗口拽回模型里那个旧值）。判据 `probes/widgets/touch-scroll` **26 checks / 变异 14/14**、
> `probes/widgets/vlist` **26 checks / 变异 10/10**（新增 4 个变异里有一个专门守「请求必须在帧外」：
> 挪回帧内立刻红）。

> 第四十三轮（2026-10-31）补的是**环境层（MOBILE.md E1/E2）**：`Env`（接口）/ `EnvBase`（可写 +
> compare-before-notify）/ `DesktopEnv`（桌面地板）/ `SafeArea`（`safeArea:` 选项的解析），
> `UiApp.env` + `bindEnv`（重绑退订、`bindEnv(null)` **抛**）。消费侧只有两条，而且都是「一处裁决」：
> `hasHover` 接上 `UiApp.setHasHover`（103 处 hover 分支的唯一开关，此前**没有任何代码调用它**），
> `safeArea` 折进**声明了 `safeArea:` 的那个容器的 padding**（盒子不缩，背景铺到刘海下，未声明的节点一行不动）。
> 判据 `probes/widgets/env`（43 checks，FakeEnv 把同一棵树推过 47/0/34/0 → 全 0 → 仅底 34 → 47/0/34/0），
> 变异 **7/7**。**其余七个值只投递、不消费**（`keyboardRect`→S7、`appState`→E7、`isDark`→E5、
> `reduceMotion`→E8、`locale`→E6、`pixelRatio`/`hasTouch`→B9/B5），这一点写在 `Env.as` 与 `DesktopEnv.as`
> 的头部，也列进了文档站新页 `env`。**`pixelRatio` 不是真值**：这个运行时没有可读的 DPR
> （`Capabilities.screenDPI` 是硬编码 96/72 常量），所以它是构造参数，默认 1。

---

## 1 一句话分层结论

| 层 | 状态 | 判据 |
|---|---|---|
| L1 渲染（Skia + Stage3D） | ✅ 复用编译器运行时 | `layout-check/visual-check.cjs` 12 项像素断言；AOT ↔ AIR 两张 BMP **0 字节差异** |
| L2 布局引擎（flexbox 子集） | ✅ **做透** | `layout-check` **133 项手算断言全绿**；Yoga == AOT == AIR **105 行 0 差异** |
| L2 显示树 / 协调 / 数据流 | ✅ 可用（累计修 28 个缺陷，见 §3.3） | keyed reconciler + `markLayoutDirty` 上传 + Observable/Binding；**两棵保留树**（主树 + 浮层树） |
| L2 事件 | ✅ **鼠标 + 键盘/焦点** | 悬停/按下/点击；`UiApp` 接 stage 的 `KEY_DOWN`/`FOCUS_IN`/`FOCUS_OUT`：**Tab/Shift+Tab 焦点环**（遍历保留树，浮层内是焦点陷阱）、`Esc`、方向键、`Enter`/`Space` 激活；控件用**可选接口** `WidgetKeys`/`WidgetFocus` 参与（`probes/widgets/interact` 25 项）。边界：Tab 环上限 64（`compiler-gaps.md` G3）、无按键重复/快捷键表。**触摸（第四十一轮）**：合成 `TouchEvent` 序列经 `PointerRouter` 走同一条 press/click 通路；`pickAt` 与引擎 hover 逐点对账。**真触摸输入仍是 G5** |
| L2 动画 | ✅ **样式 5 字段 + layout 字段 + 浮层入/退场** | 样式 `paint` 字段：`opacity`/`background`/`borderColor`/`textColor`/`cornerRadius`；样式 **`layout` 字段**：`width`/`height`/`padding`(T/R/B/L)/`gap`(X/Y)——写回后 `applyEngineStyle()` + `markLayoutDirty()`，**每帧重解布局**，落地即停（`probes/widgets/anim` 14 项 + `probes/widgets/motion` 23 项）；显示对象级：`OverlayMotion`（入场 140ms ease-out / **退场 120ms ease-in**，墙钟，每帧从引擎读基准，不累加），见 §3.4 |
| L3 控件库 | ✅ **50 个工厂 / 44 个 kind** | 见 §2；第三批浮层六件（dialog/drawer/popover/menu/toast/select）+ 第五批 `virtualList`（列表虚拟化）/`tree`/`combobox`/`datePicker` + 第六批手机骨架 `navStack`/`appBar`/`tabBar` 已落地。**44 个 kind 全部上了文档站**，由 `tools/kind-coverage.cjs` 自动核验：kind → 注册它的节点类 → 构造该类的工厂函数 → 文档站是否**调用**了其中之一。顺带修掉一处**陈旧计数**：文档原写「34 个 kind」，实际注册表有 35 个（`scrollView` 加进来后从没被计过数）——现在这个数字由门看着 |
| L3 样式面 | ✅ **33 字段** | 见 §3.2；仅剩 `grid` 刻意缺席（`cursor` 第十五轮已落地） |
| L3 浮层（第二棵树） | ✅ **六件 + 一套 chrome + 翻转/子菜单/入退场** | `View.renderOverlay()`；主树先解、浮层树后解后画、置顶；**越界自动翻转**（四向 + 夹回窗口）、`menu` 支持**子菜单**（子菜单就是普通 anchored popover）、**入场 140ms / 退场 120ms**；`probes/widgets/overlay` **65 项**（变异 **9/9**）+ `probes/widgets/flip` **54 项**（变异 **5/5**）+ `probes/widgets/motion` **23 项**（变异 **7/7**） |
| L3 组合能力 | ✅ **56 页组件文档站** | `ui-demo/demo/Docs*.as`（18 个文件）+ `ui-demo/run-gallery.cjs`：左侧 10 组 / 56 页索引，右侧每页 = 标题 + 摘要 + meta + 若干节，每节 = 标题 + 说明 + **live demo** + **产生它的源码**（同一次 render ⇒ 源码不漂移）；控件驱动切页、手算矩形 + 浮层树销毁判据；**`--air-app` 构建 ⇒ 高分辨率已实测**（`ui-demo/check-dpi.cjs`：standard 1000×700 / high 1500×1050） |
| L3 主题 | ✅ **运行时换肤（47 slot）** | `ThemeTokens.light()/dark()` + `Theme.setTheme(t)`：**拷入**、重建每 kind 基线、重建浮层 chrome、bump `themeEpoch()`；`UiApp` 把 epoch 变化翻译成「全树 `lastStyleStale` + `M_PAINT` + 一次 `Dirty.THEME` 重新 describe」⇒ **下一帧整棵树变**，且**不动几何**。暗色的状态混合方向与亮色相反（press 比 hover 更亮），`knob` 保持纯白。作者自定义经 `setControlDefault` 落在 **override 层**，跨 swap 存活。判据 `probes/widgets/theme` **75 项**（变异 **8/8**）；四条取色通路与三件探针自身的教训见 `reviews/theme-2026-10-27.md` |
| L3 可访问性 | ⚠️ 半成品 | `role`/`ariaName` **仍只是字段**（无消费者）；但 `Control.tabEnabled` 现在真被 Tab 环读（`UiApp.collectFocus`）、`Element.disabled` 真阻断点击与导航 |

---

## 2 作者可见 API 全清单（179 个文件里**只有这些**）

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
| `textArea(opts)` | `TextAreaNode` | 多行编辑框：`rows`/`value`（可 Binding）；**Enter 插入换行**（与 `textField` 的「Enter 提交」相反，独立 kind 而不是一个布尔开关） |
| `checkbox(opts)` | `CheckboxNode` | 可绑定 `checked` |
| `radio(label, opts)` | `RadioNode` | 单选；`opts.selected` 收 boolean **或** `Binding`；`opts.group` 只是名字 |
| `toggle(label, opts)` | `SwitchNode` | 开关（**工厂名是 `toggle`**，`switch` 是保留字） |
| `slider(label, opts)` | `SliderNode` | 可绑定 `value`；拖动改值 |
| `numberInput(label, opts)` | `NumberInputNode` | 数字框 + 右端步进器：`value`（可 Binding）/`min`/`max`/`step`/`decimals`/`onChange`/`onCommit`；**唯一写点 `commit()`**（clamp→round→回调），打不进字的文本**回滚而不是当 0**，`step` 不作用于栅格 |
| `rangeSlider(label, opts)` | `RangeSliderNode` | 一轨双拇指：`value`/`value2`（倒置时**工厂里交换**，不是抛错）/`step`/`onRange(lo, hi)`；**故意不给 Binding**（一个 range 是两个值） |
| `progress(label, opts)` | `ProgressNode` | 可绑定 `value`（只读展示） |
| `chip(label, opts)` | `ChipNode` | 可点击小标签（tone: neutral/info/danger） |
| `badge(label, opts)` | `BadgeNode` | 纯展示标签 |
| `avatar(name, opts)` | `AvatarNode` | 首字母圆形头像 |
| `divider(opts)` | `DividerNode` | 1px 分隔线（`orientation`） |
| `icon(path, opts)` | `IconNode` | 图标：`path` 是 SVG `d` 字符串（**describe 时就解析**：坏命令/未实现命令当场抛，而不是画笔里抛）、`size`/`color`/`fill`/`stroke`/`strokeWidth`、`viewBox` 是数据自己的坐标空间（非正数抛错） |
| `tabs(labels, opts)` | `TabsNode` | 横向分段；**分段是控件自算**，见 §3.1.1 |
| `list(items, builder, opts)` | `ListNode` | 真容器（每行一个真实 UiNode）；**`virtual: true`** 时只挂窗口（本轮补：需显式点高 + `itemHeight`，`separator` 被拒，`offsetY`/`onScroll(y)`，行对齐由工厂 snap+clamp）；不然万级走 `virtualList` |
| `image(opts)` | `ImageNode` | 位图控件；源二选一：`bitmapData`（调用者已有像素）或 **`src`（控件自己持 `Loader`，异步）**；
`scaleMode`: `fit`/`stretch`/`none`/**`cover`**（**未知值抛错**；`cover` 用 `scrollRect` 开窗裁剪，窗口按缩放系数折算）；`onLoad()`/`onError(msg)`、失败进 `UiNode.loadError` |
| `tree(items, opts)` | `TreeNode` | 扁平化行列表（展开分支的子件作为**同一节点**的行，靠 `depth` 缩进）：`expanded`/`selectedKey`/`onToggle(key)`/`onSelect(key)`；`rowHeight` 可选；**`virtual: true` + `offsetY`/`onScroll(y)`** 只挂窗口（本轮补） |
| `virtualList(opts)` | `VirtualListNode` | 只有窗口的万级列表：`itemCount`/`itemHeight`/`offsetY` + `onScroll(y)` |
| `scrollView(opts, children)` | `ScrollViewNode` | **真裁剪**滚动容器（引擎 `scrollRect`）；竖向滚轮；视口用 `setMinMax(min)` 阻断子收缩；**`stickToBottom`**（日志式贴底 + 离开末尾就脱钩）、纵/横滚动条（`probes/widgets/scrollbar` 44 项 / `stick` 15 项） |
| `spinner(opts)` | `SpinnerNode` | 不定进度圆环；`diameter`/`thickness`/`tone`/`spin`/`phase`；**环画成填充带（描边宽度不被遵守）** |
| `skeleton(opts)` | `SkeletonNode` | 占位骨架；`variant`: `text`/`circle`/`rect` + `lines`/`barHeight`/`gap`/`tone` |
| `tooltip(text, opts)` | `TooltipNode` | 气泡提示；`arrow`: `up`/`down`/`left`/`right`/`none`；标签**自绘居中**，尺寸可留 auto（自带内边距） |
| `table(columns, rows, opts)` | `TableNode` | 表头 + 数据行；`rowHeight`/`stripes`/`grid`/`selectedIndex`/`onSelect`；**`sortColumn`/`sortDescending`/`onSort(col, desc)`**（秩序归模型，循环 升/降/-1）、**`resizable`/`onColumnResize(idx, w)`**（只 1px 预览，release 报一次，从不回写 `columns`）、**`virtual`/`offsetY`/`onScroll(y)`**（header 不滚、body = `height - rowHeight`）；网格/条纹/选中一律**画成填充**；另画一个**全透明命中矩形**（否则空单元格点不到） |
| `accordion(sections, opts)` | `AccordionNode` | 手风琴；`mode`: `single`（默认，`activeIndex`，`-1` = 全关）/`multi`（`openIndices`，一组）；两者互斥、错配抛错；`onToggle(i)` 报被点击的 index；**header 刻意无背景**（高亮由容器画，子节点在前） |
| `breadcrumb(items, opts)` | `BreadcrumbNode` | 面包屑；`onNavigate(index)`/`separator`/`currentIndex`；末项与分隔符都不可导航 |
| `pagination(page, pageCount, opts)` | `PaginationNode` | 翻页器；`windowSize` 槽位窗口、省略号原型 `-1`、`onSelect`/`page` |
| `overlay(children, opts)` | `BoxNode` | **浮层宿主**（第二棵树的根）：`size:[100%,100%]`、`position:absolute`、置顶；子序列 = 堆叠序（**无 z-index**） |
| `dialog(opts, children)` | `DialogNode` | 模态框；`open`/`title`/`width`/`scrim`/`closeOnScrim`/`onClose`/`footer`；`open=false` 不占命中也看不见 |
| `drawer(opts, children)` | `DrawerNode` | 边沿抽屉；`side`: `top`/`bottom`/`left`/`right` + `size` |
| `popover(opts, children)` | `PopoverNode` | 锚定气泡；`anchorKey` + `placement`: `top`/`bottom`/`left`/`right` + `offset`；点外面关闭 |
| `menu(opts)` | `MenuNode` | 锚定行列表（继承 popover 的锚定与关闭）；`items`: 字符串或 `{label,value}`、`selectedIndex`/`onSelect`；**`submenuIndex` 可挂子菜单**（子菜单是 `menu` 工厂产出的普通 anchored popover，父菜单不必自己定位） |
| `select(opts)` | `SelectNode` | 下拉选择；trigger 无边框，菜单是 trigger 的绝对子；`value`/`items`/`onChange` |
| `combobox(opts)` | `ComboBoxNode` | 可输入下拉：`options`/`query`/`onQuery(q)`/`onChange`；**过滤归作者**（库不猜匹配规则），`query` 只是投影 |
| `datePicker(opts)` | `DatePickerNode` | 日期选择：月历恒为 **6 周**（面板高度不随月份跳）、`<`/`>` 翻月、空格子也有 key；`value`/`onChange` |
| `multiSelect(opts)` | `MultiSelectNode` | 多选下拉：**菜单在每次勾选后保持打开**，`values`（数组）归作者、widget 永不改写，`onToggle(index)`/`onOpenChange(open)` |
| `toast(opts)` | `ToastNode` | 轻提示；`open`/`message`/`tone`(default/success/danger)/`duration`/`onClose`/`width` |
| `toastHost(opts, children)` | `BoxNode` | 吐司堆：右下角、`gap 8`、后进在下；`toast` 必须放在它里面才能堆 |
| `splitPane(first, second, opts)` | `SplitPaneNode` | 两段 + 一条可拖分隔条（第二十四轮）：`direction`: `row`/`column`、**`ratio`（第一段占比，0..1）**、`minSize`（**两侧地板**）、`dividerSize`、`onResize(ratio)`（拖动中逐像素 + 松手各报一次）；两段是**普通子节点**，widget 用 `setFlex(grow 0, shrink 0, basis px)` 锁死份额；`ratio` 低于地板时**按 minSize 夹住**（不是忽略） |

配套（非控件）：`bindTo(owner, field)`、`Binding`、`Observable`、`Subscription`、
**`Env`/`EnvBase`/`DesktopEnv`**（平台事实 + `UiApp.bindEnv`；`Element.safeArea` / `SafeArea` 决定哪几条边吃 inset）、
`Dirty`、`Theme`、`Style`/`StyleRefinement`/`Fill`/`Edges`/`LengthEdges`/`Corners`/`Length`/`Size`/`TextStyle`、
`Node`/`Element`/`ElementState`/`Control`、`Widget`/`Widgets`（控件扩展点）、`WidgetTeardown`（可选销毁钩子）、
`PaintKit`、`OverlayChrome`（浮层调色板/风格常量）、`OverlayList`（菜单/下拉共用的行几何）、
`Reconciler`、`UiNode`、`UiApp`（`getOverlayRoot`/`overlayDisplay`）、`View`（`render`/`renderOverlay`/`tick`）、
`Anim`/`Ease`/`Tween`/`AnimState`。

**键位系统（第二十四轮，非控件）**：`ActionRegistry`（`register`/`unregister`/`has`/`schemaOf`/
`dispatch(id, payload)`/`setKeymap(entries)`/`clearKeymap`/`keymapEntryCount`/`bindingCount`/`lookup`）、
`KeyStroke`（`parse("ctrl-shift-s")` → `code` + 四个修饰位，`matches(keyCode, ctrl, alt, shift, meta)`）、
`ContextExpr`（`parse("editor > modal")` → `matches(contexts)`，`a > b` 即 **a 是 b 的祖先**）。
作者侧只用三个字段：`Element.onRightClick(x, y)` / `Element.onDoubleClick()` / `Control.action`，
以及 `Control.tabIndex`（**-1 = 没有显式序**，不是「不可 Tab」）。

### 2.1 仍缺的（对照常见工具箱）

| 类别 | 缺什么 | 影响的界面 |
|---|---|---|
| 无障碍 | `role`/`ariaName` 仍只是字段（无消费者） | 屏幕阅读器 |

**⇒ 现在能舒适写出的是「多页表单 / 设置页 / 列表详表 / 万级滚动列表（`list`/`tree`/`table` 都能只挂窗口）/
带图与骨架的异步页 / 弹层与菜单驱动的交互 / 树形设置 / 日期选择 / 可输入下拉 / 数字与区间录入 / 多选列表」，
写不出「图标字体 + 内建无障碍」类界面。**
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
| **虚拟滚动** | ✅ `virtualList`（第五轮）：**只有窗口内的行是 UiNode**（1000 项、视口 150、行高 20 ⇒ **9 个**节点）；作者持有数据，控件只报 `onScroll(offset)`，作者写回模型后重渲染。✅ `table` 的 `virtual:true`（第十六轮）同契约（窗口 + 一行半行、`onScroll(y)`）。⚠️ `list`/`tree` 仍是「每行一个真实 UiNode」——要万级就用 `virtualList` |
| **视口裁剪 / 滚动** | ✅ `scrollView` 用引擎 `scrollRect` 做**真裁剪**、接管滚轮，并**自绘滚动条**（第七轮）：纵/横双轴、thumb 拖动、轨道点击翻一屏、`scrollbarX/Y` 的 `auto`/`always`/`never`、没有竖向可滚时滚轮**回落横向**。条是**覆盖层**（画在内容之上、不参与布局，所以不改变任何矩形）。仍无：惯性/动量、弹性回弹、键盘翻页。`list` 本身仍不裁剪（超出自身高度的行会溢出），要滚动就套一层 `scrollView` |
| **键盘 / 焦点** | ✅ 焦点环/`Enter`/`Space`/`Esc`（§3.1）+ **`list`/`table`/`tabs` 的方向键导航**（第二十二轮）：`list`/`table` CLAMP（Up/Down/Home/End/PageUp/PageDown，virtual 表选中后把行滚进窗口）、`tabs` WRAP（Left/Right/Home/End）；三者 `tabEnabled` 已进 Tab 环。⚠️ `tree` 的行仍是「展开/折叠 + 上下键」，`grid` 类控件没有 |
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
- **`overflow` 自 G29 结案起真的裁剪**（`UiNode.applyOverflowClip()` → `backing.scrollRect = rect(0,0,absW,absH)`，
  矩形缓存于 `extra["clipLast"]`、只在边长变化时重写）。三条口径：边界是**边框盒**（底色/描边与内容同处一颗
  sprite，按 padding 盒裁会把表面削细）、**命中测试跟着裁**（溢出的子件不再可点）、**节点自身的 box shadow
  也被裁**（阴影是 backing 内的滤镜 ⇒ 两者都要就挂 wrapper）。钉子 `probes/widgets/clip`，变异 **6 条全红**；
  圆角不参与裁剪（`scrollRect` 是矩形，异形才用 `mask`）；
- 布局验收基准**不是 `adl`**（AIR 无 flexbox），而是 W3C flexbox / 浏览器；
- 仍刻意缺席：`grid`（引擎不实现；seam 层面也会抛错）。`cursor` 第十五轮落地：**继承**语义（子节点未设则
  沿祖先链取），值为 `auto`/`arrow`/`button`/`hand`/`ibeam`（与 `flash.ui.MouseCursor` 同名字面量），
  最终由 `UiApp.applyCursor()` 写 **进程级** `Mouse.cursor`——所以指针一离开声明它的节点就必须回 `auto`，
  这条由 `probes/widgets/pointer` 钉（“离开后进程上留下一个 hand” = 整个窗口都像坏了一样）。

复核命令：

```sh
cd asaotui && node layout-check/visual-check.cjs            # 12 项（含新字段的像素断言）
cd asaotui && node tools/gates.cjs                           # 61 道门，含 layout-check 133 项
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
| 29 | **`tabIndex` 写了没用，而且 Tab 会跳过中间那一站**（`tabIndex` 从声明第一天起就是死字段，`Control.tabIndex` 没有任何消费者） | 两件事叠在一起：①`UiApp.focusNext` 直接按**文档序**走，`tabIndex` 从来没被读过；②改成「显式序在前、按值升序、同值按文档序」时，第一版用一个**复用数组**当 visited 表（`taken[j] == true` + 每次 `taken.length = 0`），实测**第二次调用起就丢项**：同一份 3 项输入，直接调 `orderRing` 得 3 项、经 `focusNext` 得 2 项（`btn2` 消失），于是焦点在 `btn3` 与 `btn` 之间来回弹 | 让**输出向量自己当 visited 集**（`emitted(out, index)` 扫已发出的项），不再有第二块可变状态；Tab 每次复用 `ringScratch`，语义照 HTML | 探针 `probes/widgets/actions` 相位 5：文档序 `btn,btn2,btn3` + `tabIndex` 1 和 0 ⇒ 环必须是 `btn3,btn2,btn`（**不是文档序的旋转**；从 `btn` 出发的下一站两法不同，这才是判别点），三次 Tab 逐项断言；变异 M3（`orderRing` 直接返回文档序）⇒ 两条断言同时红 |

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
./build.sh web      # 浏览器臂：stage → as-aot --target wasm --package web → 起服务并打开
./build.sh swf      # 只编译（不弹窗、不出 exe）
./build.sh desc     # 不建：只报 --gpu 会用哪份描述符、带什么后端
./build.sh clean    # 删三个臂的产物（**不删** gallery-page*.png，那是入库证据；删掉 air-gallery-web/）
```

三个臂读的是**同一个** `app.xml`（窗口尺寸/标题/`renderMode`/`requestedDisplayResolution` 的唯一真源）：
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

### 3.11b 第三条臂：`./build.sh web`（第十八轮）

同一份 AS3 树编到**浏览器**：`./build.sh web`（stage → `as-aot --target wasm --package web` →
起一个带 `application/wasm` 的静态服务器 → 打开）。它不复用 `run-gallery.cjs`：窗口由可执行文件
开，页面不是 —— 没有进程、没有 `gallery.done`、也没有 `Stage.render`，所以有独立的运行器
`ui-demo/web-gallery.cjs` 与独立的入口类 `demo/DocsWeb.as`（`DocsAir` 用了本编译器未实现的
`UncaughtErrorEvent`，wasm 编不过；`DocsMain` 用 `Stage.render` 测试钩子）。

底下撞到 **G27**：`as-aot` 直接 spawn `<EMSDK_HOME>/upstream/emscripten/emcc`（`#!/bin/sh` 脚本，
PATH 还是 `:` 拼的 POSIX 形态）——Windows 上实测 `ENOENT`；换成 `emcc.bat` 是 `EINVAL`（Node 不肯裸跑
.bat），只有 `cmd /c` 能跑。当时**编译器侧未动**（本工作区约定）：绕行是 `tools/emcc-launcher.c` 编出的
4.5 KB PE 转发器 + `EMSDK_HOME` 指向 `.scratch/emcc-shim/`。**G27 已在 v0.4.240 修掉，绕行于同日整体
删除**（审计与删改清单见 §3.11c）。

「像不像」的测量（对照原生臂 `gallery-page0.png`，同为 1500×1050，v0.4.239 抗锯齿生效后重测）：
canvas 尺寸/标题相同、**48 点采样（6 列×8 行格心）46 点逐点相同**、墨量差 0.85%。两个不同点与最大的
颜色计数差（按钮蓝 `#2563eb` −5.1%，它的纯色像素数由标签字形的覆盖率决定）都出在文字上 —— 页面自带
字体（wasm 读不到宿主字体）而原生臂用系统字体。要逐字节相等，得两个臂共用同一个字体文件（未做）。

门 `tools/buildsh-web.cjs`（**26 项**，~5 s，不编译）驱动 `build.sh web --check`：**问编译器能不能起
emcc**（`as-aot doctor --json --target wasm --package web`，即构建开跑前同一个 `webToolchainError()`），
并要求它报出的那个程序恰好是 `$EMSDK/upstream/emscripten/emcc(.bat)` —— **中间不许有东西**，这就是反 shim
断言；反面另有一条「`emcc.bat` 存在但退出 1 必须被判不可用」。此外钉住**构建会 exec 的那个 argv**、
钉「尺寸来自 app.xml 而不是写死的 1000×700」、钉三条拒绝（`--gpu`/未知 flag/指错的 `EMSDK_HOME`）、
钉暂存目录仍在库外。变异 `tools/mutation-buildsh-web.cjs` **7/7 CAUGHT**。这道门**看不见**编译本身、
看不见页面像素、也只在 Chromium 上开过 —— 三条都写在 `reviews/web-arm-2026-10-25.md` §6。

### 3.11c G27 修好之后的收口：绕行不是资产，是负债（第二十轮）

G27 在编译器侧修掉（阶段二百七十六，v0.4.240：`emccPath()` 在 win32 选 `emcc.bat` 并经
`cmd /d /s /c` 启动、`PATH` 用 `path.delimiter`、子进程环境继承宿主、诊断区分「不在」与「在但起不来」），
库侧的绕行就**只剩成本**：多一份要维护的 C、多一层编译器看不见的路径、多一个只有本机能复现的环境。
所以逐处撤除，而不是留着「反正不碍事」。

| 当时的妥协编码 | 当时为什么只能那样 | 现在 |
|---|---|---|
| `tools/emcc-launcher.c` + `shimHomeForWindows()` + `EMSDK_HOME -> .scratch/emcc-shim` | 编译器 spawn 不了 `emcc`，只能造一个它认得的路径喂给它 | **整体删除**（含 `shimHome`/`launcherSrc`/`isWindows` 与 `.scratch/emcc-shim/`）；`EMSDK_HOME` 重新就是真 SDK |
| `--check` 自己 spawn `emcc`，且**故意用 `:` 拼 PATH** 去复刻坏环境 | 只有复刻那个环境才会暴露 launcher 的生存条件 | 改问编译器（`doctor`），报告它**实际会启动的那个程序**。自己 spawn 等于把待测逻辑抄一份，抄件无法随原件修正 —— G27 正是这样躲过一轮的 |
| `findEmsdk()` 接受 `emcc` **或** `emcc.bat` | 两个名字都在同一个目录里，谁先到谁赢 | **按平台只认一个**（win32 → `emcc.bat`），与 `emccPath()` 逐字对齐：拿错平台的 SDK 当场报错，而不是两分钟后由编译器报 |
| 门 A1「`emcc --version` 能打出三连版本号」 | launcher 唯一可观测的证据 | 换成**正反两面**：编译器说 ok（且程序就在 `$EMSDK/upstream/emscripten/` 里）+ 一个**存在但退出 1** 的 `emcc.bat` 必须被判不可用 |
| 变异 M3「launcher `return 127`」 | 证明门真去 spawn 而不是 stat | 换成「门不再相信编译器的结论」；另加 **M7**「又把 SDK 外面的 emcc 报出来」——即 shim 复辟的形状 |

验收（本机 Windows，**全程不经 shim**）：`node tools/buildsh-web.cjs` ⇒ 26 checks / 0 failures；
`node tools/mutation-buildsh-web.cjs` ⇒ 7/7 CAUGHT；真编译 `cd ui-demo/air-gallery && ./build.sh web --no-serve`
⇒ exit 0（`GalleryApp.html/js/wasm/data`，wasm 7.02 MB），页面在真浏览器里真画出来（1600×1200 预览截图
里是完整的 Getting started 页）。
### 3.12 参考运行时门：为什么必须有一道门真跑 AIR（第十一轮补）

前三轮的用户报告是同一个形状：**我们的 AOT 比 AIR 宽容**，于是库的错误在我们这里可以无声通过。

| 缺陷 | AIR | 我们的 AOT | 谁能发现 |
|---|---|---|---|
| `toast({ tone: "info" })` | 抛（我们的 build 也抛） | 抛，但**帧守卫接住** ⇒ 屏幕停在上一棵树、只剩控制台一行 | 只能“真点一下”（第九轮：tour 新 stage） |
| `onChange()` 少传参 | 抛 `#1063` | **同样抛**（语义对齐），同样被帧守卫吞掉 | 只能“真点一下”（§3.10） |
| `setChildIndex(child, index >= numChildren)` | 抛 `RangeError #2006` | ~~静默夹紧~~ → **同样抛**（G24 已修，v0.4.239） | 当时只能跑真 AIR；修好后 AOT 探针也能红 |
| 死节点上的 `mouseOut` | 抛 `TypeError #1009`（**晚一拍**才投递） | ~~根本不投递~~ → **同样投递**（G25 已修，v0.4.239）；库侧仍用一条 stage `MOUSE_MOVE` 合成 hover | 当时只能跑真 AIR，而且**要自己发指针事件**（第十二轮补的「指针钻」）；现在 `probes/widgets/pointer` 还会把引擎自己的 `mouseOver` 与库的 hover 对账 |

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
| `probes/widgets/inputs`（**50 项**，变异 **8/8**） | 三个输入控件 + `list`/`tree` 的窗口：mounted 行数、`firstIndex/lastIndex`、纯裁剪像素、绝对行号的点击/键盘、`reveal`、四条拒绝 |

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

### 3.16 `table` 欠的三件 + 滚动贴底（第十六轮补）

这一轮进来的是三条“常见工具箱都有”的能力，但第一条不是缺功能，是**缺陷**——而且是一类只有“真去点一下”
才现形的缺陷。

#### 3.16.1 头一件事：这个表**几乎点不到**

运行时按**绘制区域**取命中目标（`as_pick_hit` → `as_obj_region_hit_local`，`emit.ts:17382`），而
`TableWidget` 只画 1px 网格线、字形、条纹和选中带。于是一个**空单元格中间**点一下，目标是**表背后的根**，
行根本选不中——只有恰好点在网格线上（1px 宽的线）才生效。旧 `probes/widgets/data` 看不见这个，因为它用
`clickLocal` **直接向 backing 派发**，绕过了命中测试；`data` 里那 77 项断言全绿而那行依然不可点。

修法不是自算矩形，而是**在 `shapeA` 先画一个全透明命中矩形**：alpha 0 依然是“区域”（命中测试不看 alpha，
`emit.ts:17401`），不改一个像素，而运行时注释里写的就是这条 Flash 惯用法（“every Flash ’catch the clicks
over this panel’ idiom draws a transparent fill first”）。钉子在 `probes/widgets/table2` 的**绝对行号**那一相：
变异 M5（拿掉那三行）立刻变红，同时连带把 `onScroll`/`onWheel` 也打红——因为滚轮也是按同一个命中测试路由的。

**教训：一个控件“能点”不是布局属性，是绘制属性。**透明的地方就是点不到的地方，而“看起来对”的截图一律看不出。

#### 3.16.2 排序：秩序在作者的模型里

`onSort(columnKey, descending)` **只报意图**，控件不排任何东西。`sortColumn` 是作者交回来的秩序，箭头从它画——
所以表头不可能声称一个行并不具备的秩序。循环是浏览器那套：另一列→升序，同列→降序，同列再点→**-1（无序）**，
用同一个词汇表而不是 `null`（作者还得自己翻回下标）。

几个真陷阱：

- **`sortRows` 返回新数组，永不改作者数组**：作者常在 `render()` 里写内联字面量，原位排序等于把别人的输入擦掉。
- **qsort 不稳定，所以要 tie-break**：用原始下标做决胜，而且**必须在降序翻转之后**加，否则降序反而把并列项倒过来。
- **数字比数字、文本比文本**：`"10" < "2"`，所以 Qty 列必须排成 1, 2, 10 而不是 1, 10, 2。
  `isNumeric()` 用 trim 后的精确比较（`" "` 不算数字）。探针故意选了 1/2/10 这组数据，**两种秩序不同**，
  否则“排了”和“没排”的像素一模一样。
- `sortColumn >= columns.length` **抛错**（模型 bug，不静默夹紧）。

#### 3.16.3 列宽：只报不改，而且只报一次

拖拽期间只画一条 1px 预览线，松手才调 **一次** `onColumnResize(index, width)`，且**从不回写 `columns`**。
重排在引擎手里：活 resize 意味着每次 move 都要全解一次布局。两个只有交互才暴露的细节：

- 窗口 glue 每次 release 之后都会补一个 `CLICK`。这个 click 正好落在**刚提交的那条分界线上**，不吞掉就会
  “调完列宽顺手把这一列排序了”（变异 M4 就是把这个吞掉的判断拿掉）。
- 一次手势丢了 release（指针在窗口外松开）之后，表头会**长期失聪**——所以下一次 `onPress` 先把那个标记清掉。
- 坐标用 `localX/localY` 而**不是** `stageX/stageY`：手工构造的 `MouseEvent` 的 stage 坐标恒为 `0.0`
  （`emit.ts:12842`），而 `localX/localY` 相对事件 target。一条 `localToGlobal`/`globalToLocal` 规则两臂通吃。

#### 3.16.4 虚拟化：契约抄 `virtualList`，但多三条

`virtual:true` 需要**正 `rowHeight`**和 `onScroll(offsetY)`（缺任一**抛错**）；header **不滚**，所以 body 高 =
`height - rowHeight` ⇒ **必须是 POINT 高度**（百分比要等 solver，猜就是错）。窗口 = `[round(offsetY/rh), +fit]`，
多挂**一行半行**留给容器的 `scrollRect` 裁。行 key 用**绝对下标**：窗口一动就得挂真新节点，否则滚进来的一行
会拿到刚走那行的节点（同 key、不同数据），挂在行上的东西全部错位。点击报的也是**绝对行号**。

#### 3.16.5 贴底滚动：问题问的是“过去”

`scrollView({ stickToBottom: true })` 是日志/聊天/控制台那类“一直跟着末尾”的视口。整个契约可以缩成一句话：
**每帧问一次“我刚才是末尾吗”，问的是上一帧的 `maxOffsetY`**。

- 在 `maxOffsetY` 更新**之后**再问，每个偏移都短于新末尾 ⇒ 永远不跟（变异 S3 就是把比较搬到更新之后）。
- 新视图算在末尾：日志开屏就是**最新一行**，不是最旧一行（变异 S4）。
- 0.5px 的余量是给拖动产生的分数偏移的，**不是**“接近末尾”的容差：往上滚一格（24px）就该撒手（变异 S5 把 0.5 改成 100）。
- 再滚回末尾就**自动重新粘上**，因为规则每帧从活偏移重推，不存在一个需要重置的 stuck 标志（变异 S2 是“不查位置”）。
- 自动滚动是一**次真的移动**：`onScroll` 会发、`offsetY` 会被写回，作者的模型不会跟屏幕分家。

判据：`probes/widgets/stick`（15 项，变异 **5/5**；像素钉的是“视口顶/底分别露出第几条色带”，所以追随、
不追随、重新追随三种状态在图上分得开）。

#### 3.16.6 顺带发现：探针名单是手写的

`tools/gates.cjs` 里那道 `for (const p of [...])` 是**手写枚举**，而上一批的 `probes/widgets/pointer` 与
`probes/widgets/imaging` **从未被加进去**——于是它们一直“绿”在一个没人跑的地方。探针不在门里等于不存在。
现在四道（`pointer`/`imaging`/`table2`/`stick`）全接上，门 **46 → 50 道**。

### 3.17 图标通道 + 一条过期注释挡住了整条路（第十七轮补）

#### 3.17.1 先撞墙：三次曲线根本不存在（G26）

`icon("M12 2 C…")` 这种数据，在动手前先做了一次编译期取证：

```
Codegen error at 9:13: undefined method 'cubicCurveTo' on class 'Graphics'
Codegen error at 12:13: undefined method 'drawPath' on class 'Graphics'
```

`emit.ts` 只发射 **17** 个 `Graphics_` 成员，曲线只有**二次** `curveTo`；Skia 桥（`as_skia_path_*`）也只有
`move_to`/`line_to`/`quad_to`/`close`。所以这不是“AS3 面少两个方法”，是**C 桥也少**。已登记 **G26**
（`compiler-gaps.md`），本轮**不碰 `as3compiler/`**。

#### 3.17.2 库侧绕行：把“近似”做成可测量的一件事

| 命令 | 处理 | 为什么 |
|---|---|---|
| `M L H V Z` | 直译 | 直线段没有近似 |
| `Q T` | 直译 | 引擎本来就画二次；`T` 只是把上一个控制点镜像过去 |
| `C S` | **自适应细分转二次段** | 偏差上界 `(√3/36)·|P0−3P1+3P2−P3|`，超过容差就二分（de Casteljau t=0.5） |
| `A` | **抛错并自报 G26** | 弧要先转三次；画成弦 = 静默错误，正是本项目拒绝的那类失败 |
| 其他 | **抛错并带偏移** | 坏数据不能靠“猜下一个命令”混过去 |

容差是**四分之一个渲染像素**，而细分发生在 AS3 侧 ⇒ AOT 与 `adl` 跑的是同一串二次段，**跨臂逐像素一致**。
三次曲线的 t=0.5 点恰好是第一次二分的分割点，所以它是**精确**的——探针就采那一点（弦的话那里是空白）。

> **已撤除（第十九轮）**：G26 在编译器侧修好（阶段二百七十五，v0.4.239）后，上表的「自适应细分」与「`A` 抛错」
> **全部删除**：`C`/`S` 直发 `Graphics.cubicCurveTo`，`A` 改为 SVG 1.1 端点→圆心参数化再转三次段（≤90° 一段，
> 误差 ≤ 2.7e-4·r），`tolerance` 参数随之取消。旧的 t=0.5 采样点留着，但它**不再能区分**“原生三次”与“细分后的三次”——
> 能区分的是新增的 t=0.789 采样点（距最佳单二次逼近最远）。详见 §3.17b。

#### 3.17.3 一条过期注释差点把方案堵死

`AccordionWidget`/`SelectWidget`/`TableWidget`/`OverlayChrome`/`PaintKit` 五处都写着同一句实测结论：
「本后端 `lineStyle` **描边宽度不生效**（`temp/stroke/`，2026-10-23）」，据此全库线条都画成 1px 填充。
按这条，图标只能用填充方案（要给每个图标离线 flatten），描边方案**不该被考虑**。

重测（2026-10-25，窗口探针读帧缓冲）：`lineStyle(2)` ⇒ **2 行**、`(4)` ⇒ **4 行**、`(6)` ⇒ **6 行**、`(8)` ⇒ **8 行**、
`(12)` ⇒ **12 行**；在**直线 / 二次曲线 / 圆（r=7、14、20）/ 矩形**上一律精确。**旧结论是错的**（或早于某次上游修复）。
结论：描边可用，图标走描边 + 填充两条路；那批 1px 填充**保留**（整数像素、探针可断言），但注释改成
「这是选择，不是限制」。**教训：注释里的“实测”会过期，而它一旦过期就会替后来者做决定。**

#### 3.17.4 变异：第一次漏了一个

`probes/widgets/icon` 的 6 个变异里有 5 个一次命中，**I3（忽略 viewBox）漏了**：把 `scale` 改成永远按 24 算，
12-viewBox 的字形缩放从 4 变 2——但字形是**居中**的，缩放变小后路径**仍然落在同一条 y 上**，只有**描边厚度**变了。
补一个 `(96,92)` 的采样点（8px 带的最上一行，缩错就变白）才咬住。
**教训：变异漏了先怀疑夹具的采样点，而不是怀疑变异太弱——“居中”会把缩放错误藏起来。**

### 3.17b 缺口修好之后：把当时的三处妥协编码撤掉（第十九轮补）

G24 / G25 / G26 在编译器侧全部修好后（**阶段二百七十五，v0.4.239**），先把库侧当初为它们写的东西逐条审了一遍：
**近似、拒绝、自算、绕路**，四条里凡是已无必要的都撤，凡是属于**设计选择**的都把注释改写过来。
完整表格见 `compiler-gaps.md` 的「库侧妥协编码审计」；这里只记结论与代价：

| 当时的妥协 | 为什么当时只能这样 | 现在 |
|---|---|---|
| 三次曲线**自适应二分转成二次段**（容差 0.25 渲染像素） | `Graphics.cubicCurveTo` 在 `emit.ts` 里不存在，Skia 桥也只有 `quad_to` | **删除**，一段一根 `cubicCurveTo` |
| `A`（椭圆弧）**抛错并自报 G26** | 弧要先转三次，而三次跑不了；画成弦是静默错误 | **实现**：端点→圆心 → ≤90° 切段 → `4/3·tan(d/4)` 手柄 |
| `parse(data, tolerance)` 的第二参 | 只服务细分 | **取消**（三处调用点跟改） |
| hover 自己算（不依赖 `mouseOver`/`rollOver`） | 引擎根本不派发 | **保留**，但它现在是**设计选择**：命中必须与 click 同源，且一个窗口一个监听器 |
| `Reconciler` 的槽位计数器 | 越界被静默夹紧，所以错法看不出 | **保留**（它本来就是正确修法），且现在运行时替我们抛 `#2006` |

**两件“有意不做”已经登记**（`compiler-gaps.md` 同节）：① 填充仍走 `beginFill`（even-odd），没换成
`drawPath(..., "nonZero")` —— 不是因为不支持，而是 `drawPath` 有一条「整表 = MOVE_TO + 一段曲线不填充」的
独有怪癖，换过去得拆两条路径，**没有真实图标数据踩到它之前不动**；② hover 不改成逐对象事件（见上）。

**代价与收获都在探针里**：`probes/widgets/icon` 从 57 → **66 checks**。旧的 t=0.5 采样点对“原生三次”与
“细分后的三次”**无区分度**（那是分割点，两者重合），真正能咬住降阶的采样点是 t=0.789（距最佳单二次逼近
最远，偏差 2.6e-3·边长）——所以降阶变异 I1 跃在 **(111,35)** 会直接变白。
`A` 从负例变成**几何正例**：两条弧拼整圆，四个采样点必须按弧走（弦的话圆心是中空的）。
变异 **6/6 → 7/7**（新增「弧旗按数字读」一条：紧凑写法 `a10 10 0 011 1` 是真实数据，按数字读会吃掉后面的坐标）。

**G25 的额外一层**：以前 probe 只能证明“库的 hover 自己内部自洽”；现在引擎也会派发
`mouseOver`/`rollOver`，于是 `probes/widgets/pointer` 在 stage 上接引擎自己的 `MOUSE_OVER`，
拿**原始 `e.target`**（不经过 UiApp 的注册表）去比对“它是否落在 app 认为 hover 的节点里”，
并验证 `rollOver` 到达进入节点**及其祖先**、不到达兄弟子树。**两套定义一旦分叉，探针变红** ——
这条断言存在的理由，正是“两个臂语义不同”那一类缺陷在原理上依赖独立参考。变异 **6/6**（M6 删掉探针自己的引擎监听）。

### 3.17c 文档站上公网：`gh-pages`（第二十一轮）

52 页文档站此前只有一条看的路：克隆 5.4 GB 仓库 + 同级的 5.4 GB 编译器 + 编四分钟。现在
<https://raygyoe.github.io/as3compiler-asaotui/> 直接打开就是它——`web` 臂的产物放在 `gh-pages` 分支。

先澄清一个常见误解：**`ui-demo/` 的示例代码从来没有被忽略**。`ui-demo/demo/` 20 个 `.as`、`README.md`、
`build.sh`、11 个 `.cjs`、16 张 `gallery-page*.png` 一直在 `main` 上（`git ls-files ui-demo` = 54 个文件；
当初写这段时的数字是 19 个 `.as` / 7 个 `.cjs` / 53 个文件，差额全是后来新加的文档页与其探针）。`.gitignore` 里的 `/ui-demo/air-*/*` 禁的是**跑过
构建之后长出来的那一层**：`src/`（`stage-air.cjs` 从 `demo/` 灌进去的拷贝）、`GalleryApp.c` 5.7 MB、
`.exe` 11.5 MB、`*.build.json`、`*.done`、`icudtl.dat` 9.7 MB、以及整个 `air-gallery-web/`。

发布器 `tools/publish-pages.cjs` 只做搬运，四条子命令：`（默认）`暂存并打印清单 / `--serve` 本地起服务 /
`--check` 拉线上比字节 / `--push` 建提交并推。

| 不变量 | 为什么它必须是硬的 |
|---|---|
| **逐字节，否则不发布** | 暂存时每个拷贝 sha256 不符就拒；树没变就不建提交；`--check` 比的是**部署后的字节**。“200 + 过期 7 MB wasm”与“200 + 正确 wasm”在状态码上长得一模一样 |
| **分支，不是 `main` 下八个文件** | `.gitignore` 的口径写在它自己的头部：输入与不可再生证据入库、可再生产物不入库，而 `air-*/` 正是后者。`gh-pages` 恰好是 GitHub 的服务来源 ⇒ 口径不必破例，克隆 `main` 的体积也不变 |
| **plumbing，不是 `git checkout --orphan`** | 工作树带着 5.4 GB 被忽略的产物；切分支会先把所有被跟踪文件重写一遍。`hash-object` → `mktree` → `commit-tree` → `update-ref` 只碰对象库和一个 ref |

发布内容 8 个文件 / 8.15 MB：`index.html`（= `GalleryApp.html` 改名）、`GalleryApp.{js,wasm,data}`、
`fonts/arial.ttf`、`app.xml`、`.nojekyll`、`README.md`。**不**发布 `air-gallery-web/` 现有内容——那里还有
`GalleryApp.c`（5.6 MB）、`src/`（19 份拷贝）与 `GalleryApp.build.json`，没人需要下载它们。

实测（都是当场跑的，不是推理）：`--check` 六个文件全部 `OK … byte-identical`（`index.html` 3056 B /
`wasm` 7357606 B / `arial.ttf` 1045720 B，MIME 分别是 `text/html`、`application/wasm`、`font/ttf`）；
在浏览器里打开线上地址，渲染结果与本地暂存目录逐项相同（“Getting started”页，字形有笔画 ⇒ 字体路径真的解析到了，
而一个拿不到字体的 wasm 构建表现为**所有 TextField 空白**）；`--push` 重跑一次打印
`tree … already on gh-pages -- nothing to publish`。

顺带修掉三处过期文档数字：`README.md`（两处）与本章的「最新落盘」仍写着 `gates-all-31.txt`（实际已跑到
`gates-all-32.txt`，即 G27 收口那次），以及 `README.md` 的缺口行里 G24/G26 仍标着“❌ 仍在”——它们和
G25/G27 一样已在 v0.4.239 / v0.4.240 修完。

### 3.17d 四件「有槽位、没行为」的空缺（第二十二轮）

这一轮**不加控件**，只把四处**早就存在、却做不到事**的槽位补上。它们的共同点是「API 面早就在，
表现层没人读」——所以模型断言、矩形断言全是绿的，屏幕上却是另一回事；四处也因此都是
**探针在结构上看不见**的缺件。

| 空白 | 事实（补之前） | 现在 | 钉子 / 变异 |
|---|---|---|---|
| **键盘导航** | `WidgetKeys` 接口第三轮就定了，实现者 8 个；`list`/`table`/`tabs` **只认鼠标点击**（§3.1 第 231 行自己写着「tabs 还没接方向键、list 还没接上下键」） | 三者都 `implements WidgetKeys`（实现者 11 个）：`list`/`table` 用 **CLAMP**（Up/Down/Home/End/PageUp/PageDown），`tabs` 用 **WRAP**（Left/Right/Home/End）—— 不是口味差异：listbox/grid 是**序列**（ARIA 语义），tab strip 是**环**。**端点也消费按键**（夹紧在端部时仍返回 true），否则键会落到滚动祖先。virtual table 选中后 `reveal()` 把行滚进**已挂载窗口**（否则 index 对、模型动了、屏幕上什么都没有）。三者 `tabEnabled = true` 才进 Tab 环 | `probes/widgets/keys`（**36 项**）；变异 **4/4**（list 端部回绕、tabs 端部夹紧、virtual 不 reveal、键写 `extra` 而不写 Binding） |
| **`accordion` 多开** | `AccordionNode` 自述「Single-open is the only mode … `multi` is NOT implemented」；`openIndices` 传进来会被**静默忽略** | `mode` 收 `single`/`multi`：multi 走 `openIndices`（一组），single 走 `activeIndex`（一个），**两者互斥、错配直接抛**（AGENTS.md §2.5）。集合**升序重建**、比较与顺序无关；`onToggle(i)` 报被点击的那个 index。header 的 key 带上**本 accordion 的 key 前缀**（同页两处 accordion 过去都出 `h0`，`findByKey` 只会拿到先来的那个） | `probes/widgets/accordion`（**18 项**，含 4 组拒绝组合）；变异 **4/4**（填色只认 `k==0`；工厂只挂第一个 open panel；toggle 用 `[target]` 替换集合；互斥 guard 改 `if (false)`） |
| **`image` 的 `cover`** | `scaleMode` 只有 `fit`/`stretch`/`none`，`cover` **直接抛错** | `cover` = 等比放大到**铺满**再裁剪，用 `scrollRect` 开窗。两个坑都是实测出来的：① 窗口必须**除以缩放系数**（renderer 把窗口 clip 在对象自身矩阵里，24 单位的盒子在 3x 图上等于 72 设备像素 ⇒ 图被裁没，三个采样点全 `#ffffff`）；② **退出 cover 必须清 `scrollRect`**，否则下一个模式继承一个没人要的裁剪 | `probes/widgets/imaging`（**31 项**，含窗口矩形 + 三点像素 + 退出 cover 的复检）；变异 **8/8**（新增 max→min、窗口单位、退出不清窗口） |
| **下划线 / 删除线 / 上划线** | `TextFormat.underline` 设得上、读得回、`clone` 得走，**绘制路径没有一处读它**（`as_tf_html_emit_run` 第一句就是 `(void)underline`）⇒ 登记 **G28** | 不走 `TextFormat.underline`，改用 `getLineMetrics()` **逐行自绘**：`TextStyle.textDecoration`（`none`/`underline`/`line-through`/`overline`，默认 `none`，随 `inheritFrom`/`copy` 级联），`PaintKit.decorate(n)` 在 14 个 kind 的 `paint()` 末尾画。`getLineMetrics` 与字形**同源**，所以线画在第几行、从哪个 x 起、多宽，都跟字形出自同一次布局 | `probes/widgets/textfx`（**18 项**：装饰相位在**字形够不到的四空格空隙**取样，并用同页一个无装饰节点做负例）；变异 **8/8**（M6 不画、M7 画错位置、M8 忽略行首 `lm.x`）。⚠️ **2026-10-30 追记**：G28 已由编译器侧修掉（v0.4.303，按 `adl` 的 1 设备像素口径自绘），所以库侧保留这三档的理由不再是「运行时画不出来」，而是**`line-through`/`overline` 没有任何 AIR 属性可委派 + 三档共用同一套行度量**；`textfx` 的装饰断言因此现在钉的是**库自己的线**，不再兼作缺口证据 |

一条方法论，比这四件本身更值钱：**「属性对、屏幕错」这一类缺陷，探针必须在只有那条行为才会
改变像素的地方取样** —— 键盘（只有按键才动）、multi（只有两个 panel 同时开才出现的填色）、
cover（只有裁剪窗口对了才对的三点像素）、装饰（只有横线那一行才会变色的空隙）。四次都是先写
模型断言、发现全绿，才把采样点挪过去的。

另一条：**变异机自己也会假绿**。本轮两个变异（A4、K4）报的是 `SKIPPED -- anchor text not found`，
原因一个是锚点跨了「后来被搬走的注释」、一个是锚点在 JS 单引号串里写 `\"` 而文件里真的是
反斜杠加引号 —— 两者都没跑，汇总却仍叫「4 个变异」。修法：锚点不跨注释/转义符，且换行符
**按目标文件的实际行尾**解析（本仓库 `.gitattributes` 只钉 `*.bat`，文件是混的）。

### 3.17e 同一轮的下半场：文档站把四件事**演**出来（第二十二轮补）

上一节把四处空位补上了，但**只有探针看得见**：`probes/` 是给变异机用的，读者打开文档站
读到的仍是「键盘导航：已支持」这一句话。所以同一轮又给四个页面各加了节，每节都是
**说明 + 能上手试的 demo + 产生它的源码**（源码与 demo 同一次 render，不会漂移）：

| 页面 | 新增 | 上手方式 |
|---|---|---|
| `list` | 「Keyboard: the arrows move the selection」 | 按 **Focus it** 再按 Up/Down/Home/End；末行仍停住 ⇒ CLAMP 可见 |
| `table` | 「Keyboard: arrows, Home/End, PageUp/PageDown」+「A virtual table reveals the row it selects」 | 同上；virtual 那张 200 行表按 Down 到窗口边缘后 `onScroll` 的偏移开始走，End 直接到底（`of 4312` 是 `200*22 - (110-22)`） |
| `tabs` | 「Keyboard: Left / Right WRAP」 | 在 Billing 上按 Right 回到 Overview —— 列表会停、条带会绕，两个形状的差别一眼可见 |
| `accordion` | 「Every header has its own key」 | 页面上方就是 multi 示范（One/Three 同开）；这一节说清 `demoAccM:h0` 的前缀为何不是装饰 |
| `image` | 「cover: fill the box, then crop」 | 同一个 16×8 双色带、同一个 96×96 盒子，`fit` 上下留白、`cover` 铺满并裁掉两侧 —— 顺手把上一版写在「Scale modes」里的那句 **「There is no cover/fill」** 删掉（它当时是对的，现在是错的） |
| `text` | 「Underline, strikethrough, overline」 | 三条线 + 一条**换行**的长句：换行后每行各自一条线，这是「线来自 `getLineMetrics`」的直接证据 |

键盘 demo 都带一个 **Focus it** 按钮，而不是写「点一下再按方向键」：AIR 的 `mouseDown`
**不会**把焦点给一个普通 Sprite（只有 `TextField` 会给，编译器的 `as_focus_from_mouse_down`
就是这么实测下来的），所以「点一下就能按方向键」在我们的运行时里是假的。焦点来自 Tab 环
或 `app.focusNode()`，demo 直接调后者并把这件事写进正文。

三件在写 demo 时才暴露的事，都比 demo 本身值钱：

1. **我们的编译器接受尾逗号，mxmlc 不接受。** 生成小节时 `"…",` 一律带逗号，我们的前端
   照单全收、AOT 跑得通、`run-gallery` 也 PASS，只有 AIR 臂的 `mxmlc` 报错。它报的位置还是
   **下一个元素**（`应为 BRACKET_CLOSE，而实际为"new"` 指向 `new DocSection(...)`），真正
   缺逗号的那一行在它上面 25 行。没有那道门，这个文件会以「AOT 绿」的状态合进去，
   而 AIR 臂从此编不过。
2. **tour 的「子件不许跑出自己的块」看不见控件自己的溢出。** multi 示范里 accordion 给了
   150px，三个 header 加两个展开面板要 160px：面板画到盒子外面，而所有块级断言仍是绿的
   （溢出的东西没出 demo 面）。改成 212px 并同步 `demoH`。
3. **`button` 收的是 `(opts)`，不是 `(label, opts)`。** 写成 `button("Focus it", {...})` 时
   前端报的是**外层那句** `return column({...}, [...])` 的参数过多（`expected 1, got 2`
   指向 `column`），一眼看去像是 `column` 的问题。写新 demo 前先读工厂签名，比猜错误信息快。

验收：`node ui-demo/run-gallery.cjs` → `PASS`（43 页、`badPages=0`、`overflowingBlocks=0`、
8 张 1500×1050 截图）；`node tools/mxmlc-check.cjs … ` → `OK: compiled by AIR -- 103111 bytes`；
`node tools/gates.cjs` → **54/54 PASS**。

### 3.18 输入类三件 + `list`/`tree` 虚拟化（第三十四轮）

**加了什么**：`numberInput`（数字框 + 右端步进器）、`rangeSlider`（一轨双拇指）、`multiSelect`
（勾选后**菜单不关**的下拉），以及 `list`/`tree` 的 **`virtual: true`**（只挂窗口）。三个新控件
都**没有动任何共享文件**（`Widgets.as`/`UiNode.as`/`Reconciler.as` 一行未改）：各自在 `*Node` 的
构造器里 `Widgets.register(...)`，用 `private static var registered:Boolean` 守卫。

#### 3.18.1 虚拟化的契约是**抄**来的，不是新造的

`virtual: true` + `offsetY` + `onScroll(y)` 与 `virtualList`/`table.virtual` 完全同构：作者持模型，
kit 只挂窗口。四条硬规则（每条都有探针断言）：

| 规则 | 为什么 |
|---|---|
| mounted = `fit + 1`（`fit = ceil(视口高/行高)`） | 非整数倍视口底部那半行是**真的**，漏了会留白条（变异 M1：去掉 `+1`，六行变五行，探针当场红） |
| 裁剪是**纯裁剪** `scrollRect=(0,0,w,h)` | 只挂了窗口、行本来就在视口内，所以不该像 `scrollView` 那样**滑动**；缺了它第 6 行会画到视口外（变异 M2：像素 `(30,216)` 变 `#606060`） |
| `selectedIndex`/`actRow` 是**绝对行号** | 滚动后 `click`/方向键必须 `+ firstIndex`、画笔必须 `- firstIndex`，否则选错记录（变异 M3：点击报 0 而不是 3） |
| `reveal` 保证选中行**不留在未挂载处** | End 选中第 199 行时窗口必须跟着走（变异 M5：`reveal` 空转 ⇒ 选择对了、窗口没动） |

**主动拒绝两件**（`THROW`，不静默近似）：`separator: true`（窗口算术是行粒度，行间细线改变 offset 的量纲 ⇒
每屏漂一行）、视口高度不是显式点值（窗口必须在布局**之前**知道能放几行）。负例断言写在探针 phase 6。

#### 3.18.2 探针逼出的两个**库级缺陷**

1. **行点不到**：命中测试走**绘制内容**而不是布局矩形，而 tree 的行只画了文字 ⇒ 在 `x=30`（文字右侧）
   点下去命中链直接落到根节点。证法是把命中链打出来（`DIAG row1 backing chain={null:0,20,18x16}`），
   修法是每行 `background: Fill.fromArgb(0,0,0,0)` **铺满整行** —— alpha 0 的填充照样吃鼠标，这正是
   Flash 时代做隐形点击区的经典手法（记在 `compiler-gaps.md` §2，**不是**缺口）。
2. **点一次就丢键盘**：`mouseDown` 落在非 `TextField` 上会把 `stage.focus` 置空 ⇒ UiApp 的 `FOCUS_OUT`
   把库焦点丢掉，于是「点一行再按 End」什么都不发生。修法是三个控件在**自己的**点击处理里
   `n.app.focusNode(n)` 重新 claim（`ListWidget.onClickY` / `TreeWidget.onClickAt` / `NumberInputWidget.onPress`）。
   ⚠️ 探针最初是**显式** `focus("vl")` 再按键，把这个缺陷挡住了 —— 把那一行删掉、让**点击本身**负责焦点，
   变异 M4 才有牙（`End reported 3 not 199`）。**探针里多余的一行 setup，等于一条被藏起来的契约。**

#### 3.18.3 另外两条只有写探针才会遇到的语义

- **`select()` 是「作者的回声」**：它只调 `onChange` + `invalidate(Dirty.VALUE)`，**从不写回** `selectedIndex`。
  所以探针断言必须 `setTimeout(..., 350)` 去读**下一帧**的 desc，回调里还要 `view.invalidate(Dirty.ALL)`
  并把模型喂回 `selectedIndex:`/`selectedKey:`。同步读状态是错的。
- **tree 的 End ≠ list 的 End**：`TreeWidget.onKey` 的 36/35 只移动 **ACTIVE band**，选中要靠 `Enter`；
  `ListWidget` 的 36/35 直接 select。探针不能把 list 语义钉到 tree 上。

#### 3.18.4 判据与验收

| 项 | 结果 |
|---|---|
| `probes/widgets/inputs`（新门） | **50 checks / 0 failures**：三个控件 + 两个窗口 + 四条拒绝 + 三个手算像素点 |
| 变异 `tools/mutation-widget-inputs.cjs` | **8/8 全中**，每条都红在 `expect` 指名的断言上，`finally` 还原后 sha256 逐字节一致 |
| 文档站 | `numberInput`（2 节）/ `rangeSlider`（2 节）/ `multiSelect`（2 节）+ `list`/`tree` 各一节虚拟化 ⇒ **52 页**；`kind-coverage` **41/41**；`callback-arity` **0 违规** |
| AIR 臂 | `mxmlc` **OK: 124985 bytes**（新增的 5 个 API 全是合法纯 AS3） |
| 画廊 | `pages=50 nodes=8796 badPages=0 overflowingBlocks=0` → **PASS** |
| 门 | **55/55 PASS**（日志 `reviews/gates-all-35.txt`） |

**这一批最值得记的一条**：两个库级缺陷都**不是**「功能没写」，而是「写好了但摸不到 / 按下去没反应」。
位图、矩形、`kind-coverage` 全都看不见它们 —— 只有**真的按坐标点一下、再真的敲一个键**才看得见。
### 3.19 触摸可路由：`Pointer` + 合成 mouse 兼容层（第四十一轮 · MOBILE M0）

**为什么从这儿开始**：`MOBILE.md` §0.1 的「先做哪六件」第 1 件。移动端的控件数量不是主要缺口
（拿 NSH 的 48 个 element 对表，等价物 19 个、语义不同 14 个、真缺 9 个），缺的是**输入层**：
全库 **0 处** `TouchEvent`，41 个 kind 只会被鼠标驱动。

**落地三件 + 一处裁决**（全部在 `asaotui/` 内，编译器一行未改）：

| 文件 | 职责 |
|---|---|
| `kit/asaot/ui/Pointer.as` | 一个指针的状态（id / x / y / phase / isPrimary / pressure + press 锚点）。**可变**，因为 move 热路径上**路由自己的判定**不许分配（§2.4 的 GC 红线）；兼容层每次派发仍要 new 一个 `MouseEvent`（与引擎一次真实事件同量级），所以这不是「零分配」的证明 |
| `kit/asaot/ui/PointerRouter.as` | 一个 touch 序列进，一套既有词汇出：`down/move/up/cancel` → `MOUSE_DOWN/MOVE/UP` + `CLICK`，外加 press 延迟（滚动容器内 130ms）、slop（8pt）、长按（500ms）与取消 |
| `kit/asaot/ui/InputConstants.as` | 阈值**唯一出处**（另有 `TOUCH_CANCEL` 字面量：AIR 3.0 的类没有 cancel 常量，平台却总能撤销一段序列） |
| `UiApp` | 四个 stage 监听 + `pickAt` + `dispatchPointerMouse` + `setHasHover`（一处裁决 103 处 hover 分支） |

**三条刻意的设计决定**

1. **兼容层发合成 `MouseEvent`，是为了让 41 个 kind 一行不改**。代价写在代码里：这些事件不是引擎发的，
   所以引擎自己的鼠标状态（`ASC_mouse_down`、roll-over 记账、TextField 的 mouse-down 聚焦）看不见它们；
   库侧只补了 hover 与焦点，其余当作已知边界。
2. **命中不许自造第二套规则**。`pickAt` 只用引擎的 `hitTestPoint(x,y,true)`（同一块「已绘制内容」区域）
   + 保留树的顺序事实；探针再拿**真引擎指针**在同一点上派生 hover，逐个点位断言 `pickAt` 与它相等。
   四个点位里有一个是根 padding —— 那里两边都必须是 `null`，否则"永远返回最深节点"的假实现也会绿。
3. **合成的 move 不许自我确认**。这些事件会冒泡回同一个 stage 监听，若让它重新派生 hover，
   "我们的 hover 等于引擎的 hover"就变成同义反复。`_synthetic` 标志是这条的闸门。

**变异测试抓到的两件事（比新功能本身值钱）**

- **M4 第一次是绿的**：删掉「slop 不再否决点击」后探针仍然 PASS。真因不是探针太松，而是**同一个判决被
  写了两遍** —— `move()` 把 slop 记进 `longDone`、`end()` 又重算一次 `slopExceeded`，删任一处都还有另一处兜着。
  修法是把"这一串不算 tap"收成**一个** `noTap` 位；重跑后 M4 变红并指名 `a dragged touch still clicked the button`。
- **M7 是补上去的**：`TOUCH_CANCEL` 原来没有任何断言。平台可以随时撤销一段序列（来电、手势抢占），
  而**不释放 press 槽的后果是之后所有触摸都被静默丢掉** —— 看起来像"界面卡死"，不像指针缺陷。
  探针现在钉两条：取消当场不点击、以及**紧接着的那一次 tap 必须仍然有效**。

**判据与验收**

| 项 | 结果 |
|---|---|
| `probes/widgets/pointer-touch`（新门） | PASS / 0 failures：tap（press 即时 + click）、拖拽（不点击）、scroller 内延迟 press（130ms 后落地且仍可点）、取消（不留槽）、hover 两态、pick 与引擎四点对账 |
| 变异 `probes/widgets/pointer-touch/mutation.cjs` | **7/7 全中**，每条红在指名的断言上，`finally` 还原后 sha256 逐字节一致 |
| 手算几何 | 320×240 窗口、padding 10、gap 8：`chip 10,10,120,32`、`btn 10,50,120,32`、`sw 10,90,80,32`、`scroll 10,130,200,60`、`row 10,130,200,60`；5 个像素点（含根 padding 与三个控件内底左角） |
| 仍然缺的 | 真触摸（G5）、`hitSlop`/44pt 最小命中（P6）、触控态视觉（P5 后半）、`Env`（E1）、手势仲裁（P3）、多指（P4） |

**没有动的东西**：`as3compiler/` 一行未改（本轮只读核对 `TouchEvent` 类形状与 `hitTestPoint` 语义）；
`Widget` 契约、41 个 kind 的实现、`Reconciler` 全部保持不变 —— 这正是"兼容层放在协调者层"的意义。

### 3.20 手指能滚：1:1 拖动 + 惯性（第四十二轮 · MOBILE M1 前半）

**接在 M0 后面做哪一件**：`MOBILE.md` §0.1 的第 2 件（S1/S2）。M0 让触摸能"按"，但手机上
"按得动、滚不动"等于不可用；而这一件**同样不需要真触摸**——合成序列就能验完。

**落地（仍然只动 `asaotui/`）**

| 文件 | 变更 |
|---|---|
| `kit/asaot/ui/TouchScrollable.as`（新） | 可选能力接口（与 `WidgetKeys`/`WidgetTeardown` 同型）：`touchDragBegin/To/End/Cancel`。走 kind 注册表解析，**不再用 `kind == "scrollView"` 判** |
| `PointerRouter` | 越过 press slop 且落在视口里 ⇒ 触摸序列交给视口：**press 被撤回（发 `MOUSE_UP` 不发 `CLICK`）**，后续 move 全部转发；`cancel` 交 `touchDragCancel`（不滑行）；新增 `dragStarts/dragMoves/dragEnds` 计数 |
| `ScrollViewWidget` | 实现 `TouchScrollable`：**按节点内部两套坐标**（按下点定轴、越 slop 点定锚）、轴锁（选中轴不能滚 ⇒ 消费但不移动）、`moveTo()` 单一写点、`applyGlide()` 纯重绘自走滑行 |
| `ScrollViewNode` / `scrollView.as` | 新字段 `momentum`（默认 true）与 `decelerationRate`（默认 0.95，范围 (0,1)，**越界抛**，同 `barMode` 体例） |
| `InputConstants` | `FLING_MIN/STOP_PT_PER_MS`、`FLING_FRAME_MS`（dt 修正的分母）、`FLING_FRESH_MS`（陈旧速度不算甩） |

**四条写进代码的理由（都不是“设计品味”）**

1. **轴用“按下点”、锚用“越 slop 点”**：8pt 的抖动是判“这是拖动”的证据，**不应同时滚内容**，
   否则一次会抖的点击就把列表带跑一像素。两套坐标分开存。
2. **press 撤回而不是等它变 click**：`MOUSE_UP` 无 `CLICK`，与真实鼠标“指针离开控件”同形；
   不撤的后果是**行在列表滚动时一直亮着**，这是移动端被报最多的视觉 glitch。
3. **滑行是 `markPaint` 自走，不是布局**：每帧只写 offset，**不抬布局位**；停下后不再要帧。
   （否则一次甩动 = 每帧重解整棵树。）
4. **程序化滚动取消滑行**：作者写 `offsetY = 0`（"回到顶部"）必须赢过动量；
   `paint` 把自己的写回**同步进请求账**（`REQ_X/REQ_Y`），于是 `payload` 只对**别人的写**反应。

**探针顺手抽出来的两个真缺陷（比新功能值钱）**

- **整个位移被吞**：`startDrag` 只调 `touchDragBegin` 不调 `touchDragTo`，于是第一个样本是**下一次**
  move，轴判定拿着一个远离按下的位置去决定——20pt 拖动落在 **0**。修法：把“越 slop 的那一点”
  也交给接口。
- **作者的程序化滚动在滑行中看不见**：`payload` 只在 describe 时跑，而滑行只抬 `M_PAINT`，
  于是滑行期间写的 `offsetY` **永远不被读**，视图与作者打架。修法：`paint` 同步 `REQ_*`，
  让“请求变了”只剩一种来源。

**判据与验收**

| 项 | 结果 |
|---|---|
| `probes/widgets/touch-scroll`（新门） | PASS / 0 failures（26 checks）：20pt→**20px**（精确）、slop 不滚、press 撤回、横向不动竖向列、`momentum:false` 停在**精确** 20、越界钉 180、回中取消滑行、**手指落下冻住滑行**、滑行会自己停 |
| 变异 `probes/widgets/touch-scroll/mutation.cjs` | **10/10 全中**（半速/反向/锚在按下点/不撤 press/momentum 两向/不锁轴/不夹界/请求不取消滑行/手指落下不停），还原 sha256 逐字节一致 |
| 手算几何 | 320×240、padding 10、gap 8：`sv 10,10,200,60`、`svf 10,78,200,60`、行 40 高 ⇒ `maxOffsetY = 240-60 = 180` |
| 刻意不钉的 | 滑行**距离**（帧时钟的函数）。只钉「更远 / 不越界 / 最终停下」，确定性留给 `momentum:false` 的精确相等 |
| 仍然缺的 | 真触摸（G5）、回弹（S3）、分页（S4）、嵌套轴仲裁（S5）、`hitSlop`（P6）、触控态视觉（P5 后半） |

**顺带修的回归钉**：`PointerRouter.insideScroller` 改成 `scrollerOf`（能力判定）后，
`probes/widgets/pointer-touch/mutation.cjs` 的两个变异锚点**会变成 SKIP**——已同步改写
（M2/M3 锚 `scrollerOf`，M4 改锚 `noTap` 赋值行）；改完复跑 **7/7 仍全中**。
一个“锚点找不到就跳过”的变异机是假绿，这次正好自己咬到了。

**验收台本身的一个真缺陷（用户报的“UI 测试启动就卡在那儿”）**：这些门都是**真窗口**，
程序出错时不会退出——而 `tools/gates.cjs` 的 `sh()` 与 `tools/probe.cjs` 的构建
都是**无 timeout 的 `spawnSync`**，于是“一个进程卡住”就等于“整轮门永不返回”。已改：

- `gates.cjs` 的每个子进程都有 15 分钟上限（`ASC_GATE_TIMEOUT_MS` 可降），被杀时**点名**
  命令并报 `exit 124`，不再是莫名的 `exit null`；`probe.cjs` / `run-gallery.cjs` /
  `air-sweep.cjs` 的构建同样带上限（`ASC_BUILD_TIMEOUT_MS`）。
- `run-gallery.cjs` 的 tour 超时（`ASC_TOUR_TIMEOUT_MS`，默认 60s）**现在会杀窗**：以前它
  故意留着窗让你看，但那正是“测试卡住了”的外观；要看半成品请显式 `ASC_KEEP_WINDOW=1`。
- 牙齿：`ASC_GATE_TIMEOUT_MS=1200 node tools/gates.cjs` ⇒ 全部子进程按时长被杀、
  51 行 `[TIMEOUT]`、**命令正常返回**（不是挂死）。来源：adl/AOT 程序写错时**永久不退出**，
  所以「启动类」调用的上限必须短（≤10s 量级），而这是脚本层自己必须做到的，不靠人记得。

## 4 已完成且**可复现**的部分（不是意图，是跑过的）

一条命令跑全部 **62** 道门：

```sh
node tools/gates.cjs          # 65/65 PASS 才叫绿（最新落盘 reviews/gates-macos-2026-10-31h.txt）
```

> 第四十七轮（**SKIP 是假的**）后的全量：**64 PASS / 2 FAIL / 0 SKIP，549 s**（`reviews/gates-macos-2026-10-31j.txt`，**66 道门**）。
> 前四轮一直把 10 道门（9 条 AIR 参考臂 + `docs app on AIR (adl)`）记成「本机没装 AIR SDK」——**这句是错的**，
> 错在检测：它只问 `AIRSDK_HOME` 与 `PATH`，而本机 SDK 装在 `~/Documents/Software/AIRSDK/AIRSDK_51.4.1`，
> `PATH` 里那条是**已卸载的 51.2.1 的 `bin/`**（`ls` 直接 `No such file`）。`tools/air-sdk.cjs` 现在是唯一解析器
> （env → PATH → 安装位置，命中必须验证**本机真能跑**那个 launcher），四份各写一遍的检测全部收敛；
> 10 条 SKIP 全部变成**真测量且全绿**（`adl` 全站 56 页 / 15 弹层 / 指针钻 / **0 运行时错误**）。
> 新增第 66 道门 `AIR SDK resolution`（11 cases，变异 5/5，夹具在 `temp/airsdk-check/`、HOME 重定向、PATH 清空，
> 所以「本机有没有 SDK」不会让用例假绿）。549 s 的增量**全部来自新做的测量**：那 10 道门以前立刻 `exit 3`，一秒不花。
> 剩 2 红与上轮同批（`widgets/choice` 文本竖排 1.5px；`G11` `1/5 hashes` —— `as3compiler/` 里有并发会话的 3 个 `M` 文件）。

> 第四十六轮（跑法提速 + 三个真缺陷）后的全量：**52 PASS / 2 FAIL / 11 SKIP，380 s**（`reviews/gates-macos-2026-10-31i.txt`，**65 道门**）。
> 与上一版（`31h`：50 PASS / 14 FAIL / 1 SKIP，45 分钟）的差别**全部来自跑法与三个修复**，判据一条没松：
> ① **11 个 SKIP 是「本机没有参考运行时」**（9 道 AIR 臂改报 `exit 3`，以前是先建 AOT 臂再报红；
> 另 2 道是 G11「编译器源码在采样窗口内动过」与 `docs app on AIR`）。**SKIP 不是绿**，它只是老实说「没测到」。
> ② `widgets/imaging` 由红转绿（保留名表补 `poll` 一族），`build.sh --gpu` 由红转绿（mac 上断言的是「拒绝」）。
> ③ 剩两道红是既有问题、与本轮无关：`widgets/choice` 一条文本竖直居中差 1.5px 的老断言、`G11` 的 `1/5 hashes`。

> 第四十五轮（navStack/appBar/tabBar）后的全量：**51 PASS / 13 FAIL / 1 SKIP**（`reviews/gates-macos-2026-10-31g.txt`，**65 道门**）。
> 三道新门 `widgets/navstack`(16) / `widgets/appbar`(22) / `widgets/tabbar`(13) 全部 PASS，
> `gallery tour: 56 component pages` 与 `gallery kind coverage 44/44` 也回到绿（本轮新增三页，否则覆盖率门会红）。
> 13 个红全是**环境或历史遗留**，与前几轮同一批、本轮一个都没碰：**9 个要 AIR SDK**（本机 `AIRSDK_HOME`
> 仍指向 Windows 路径 ⇒ `AIR arm (mxmlc)`、`build.sh --gpu`、`G14/G19/G20/G21/G22`、`Vector vs Array`、
> `style fromAny`、`Array(x)`），`G11` 因编译器树在 5 次构建窗口内被动过而报 `1/5 hashes`，
> `probe widgets/imaging` 只有告警没有判定，`probe widgets/choice` 一条**文本竖直居中差 1.5px** 的老断言。
> 上一轮红着的 `G13 air-app reach`（当时是并发会话在改 `as3compiler/`）本轮**转绿**——树现在是 CLEAN。

> 第四十四轮（S3 回弹 + S6 两件）后的全量：**48 PASS / 13 FAIL / 1 SKIP**（`reviews/gates-macos-2026-10-31d.txt`，**62 道门**）。
> 13 个红全部是**环境或历史遗留**，本轮一个都没碰：**10 个要 AIR SDK**（`AIRSDK_HOME` 在本机仍是
> `D:/Adobe/Flex_Sdk/...` 这条 Windows 默认值 ⇒ `G14/G19/G20/G21/G22/Vector/style-fromAny/Array(x)`、
> `AIR arm (mxmlc)`、`build.sh --gpu`），`G11` 是它的 clang 错误帽夹具随编译器变强而失效（它自己把证据追加到
> `probes/g11-nondeterminism/`），`probe widgets/imaging` 只有告警没有判定，`probe widgets/choice` 一条
> **文本竖直居中差 1.5px** 的断言（自 10-30a 起就红，与本轮无关）。两个新门 `widgets/touch-scroll`、
> `widgets/vlist` 均 **PASS**。
> 15 道红没有一道来自本轮：**9 道是本机没装 AIR SDK**（`exit 2`）；**2 道（G13 / descriptor DPI）是并发会话
> 正在改 `as3compiler/` 造成的构建失败**（生成的 C 报 `static declaration of 'RangeError_new' follows
> non-static declaration`，而报错的那几个程序一行 `asaot.ui` 都不含）；`G11` 因树脏报 `0/0`；其余 3 道
> （`widgets/choice` 1 项、`widgets/imaging`、`build.sh --gpu` 2 项）是既有红。**本轮新加的门
> `probes/widgets/env` 是 43 checks / 0 failures，画廊 tour 也是 PASS（53 页 / badPages=0）。**
>
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
| **环境层（第四十三轮，E1/E2）** | `node tools/probe.cjs probes/widgets/env` | **43 checks**，0 failures：`DesktopEnv` 的九个答案（含 `locale == Capabilities.language` 的镜像断言）、insets 折进根 padding（`4+47 / 4 / 4+34 / 4`）且**盒子仍是 320×240**、只认声明过的边、未声明的节点不动、47→0→仅底 34→47 的往返、**一次平台改动 = 一次通知**、重绑退订、`bindEnv(null)` 抛、`hasHover` 两态；变异 `probes/widgets/env/mutation.cjs` **7/7**（不折 inset / 每个节点都宣称四条边 / inset 落到错误的边 / 不从 Env 取 `hasHover` / 重绑不退订 / 改动不唤醒帧 / 桌面地板编一个安全区） |
| **指针钻：死节点上的 roll-out（第十二轮补，G25）** | `AIRSDK_HOME=<sdk> node tools/air-sweep.cjs` + `node tools/listener-wiring.cjs` + `node tools/probe.cjs probes/lifecycle` | `air-sweep` 行末报 **3107 node(s) hovered and 348 of them destroyed**、0 errors（每页离开前悬停该页每个叶子，切页**下一拍**投递 `mouseOut`）；静态扫描 **29 wired / 0 raw**；探针 **9 项** 0 failures；变异 4/4 + 3/3 |
| **滑块拖拽 + 回调参数（第九轮补）** | `node tools/probe.cjs probes/widgets/callback` + `node tools/callback-arity.cjs` | **24 checks**，0 failures（只点**未绑定**控件：checkbox/toggle/radio + 滑块的按下→拖动→越界夹紧→松手→松手后移动无效→纯点击）；变异 `probes/widgets/callback/mutation.cjs` **8/8**；静态门 15 调用 / 81 声明 / **0 违规**，变异 `tools/mutation-callback-arity.cjs` **6/6** |
| **多页 App（组件文档站，56 页）** | `cd asaotui/ui-demo && node run-gallery.cjs` | **56 页** tour 全绿（start→box→…→toastHost 四组逐页编译、布局、拉像素）+ **8 张** `gallery-page*.png`（1× 与 1.5× 各一套）+ `RESULT: PASS`；tour 还把「无 engine 节点 / 零矩形 / backing 未挂」三类静默失败**升级为判据**（变异自证：把目录页的 `image` 设成 0×0 ⇒ 红并点名 page 4），并对浮层树断言「切页后 `stage.numChildren` 回到基线、`findByKey(ovlDlg)` 为 null」（变异 `ui-demo/mutation-gallery-teardown.cjs` **2/2**）；另加**两条浮层像素判据**：scrim `#999999`、面板 `#ffffff`（钉住「入场动画落地」，见 §3.3 第 15 条） |
| **画廊覆盖全部 kind** | `node tools/kind-coverage.cjs` | **41/41** 个注册 kind 都被画廊调用（0 个「无工厂」kind = 无作者面缺口）+ `RESULT: PASS`；**变异** `tools/mutation-kind-coverage.cjs` **3/3**（把 tree 调用改名；新增一个 kind+工厂却没人用——这正是**发生过两次**的回归；把调用藏进 `//` 注释——扫描器第一版就是这样把散文算成了代码） |
| **高分辨率（HiDPI）自证** | `cd asaotui/ui-demo && node check-dpi.cjs` | `standard` 700×560(1×) vs `high` 1050×840(1.5×)，且两次 tour 文本**逐字节相同** |
| **单页登录 App** | `cd asaotui/ui-demo && node build-and-run.cjs` | 8 项手算断言 + `750×563` 截图（1.5×）+ `RESULT: PASS` |
| **`--air-app` 闭包回归钉（G13，已修）** | `node probes/reach-freefn/run.cjs` | 默认闭包 kept **5/5** 且默认面**能建能跑**（修前是：红 + `unknown superclass 'Base' of 'p_Leaf'`） |
| 工具箱自检 | `cd asaotui/ui-demo && node run-check.cjs` | `23 checks, 0 failures / RESULT: PASS` |
| 控件探针 ×5（第一批） | `node tools/probe.cjs probes/widgets/{chip,form,display,nav,anim}` | 19 / 41 / 48 / 41 / 14 checks，全 0 failures |
| 控件探针 ×3（第二批） | `node tools/probe.cjs probes/widgets/{media,feedback,data}` | 43 / 43 / 77 checks，全 0 failures；变异 `tools/mutation-widget-probes.cjs`（media+feedback 4/4）、`probes/widgets/data/mutation.cjs`（**5/5**，含 M4 复现本轮修的层叠 bug、M5 复现本轮修的文本内边距缺陷） |
| **浮层探针（第三批）** | `node tools/probe.cjs probes/widgets/overlay` | **65 checks**，0 failures（A 段全场景矩形 + 像素、B 段真事件路点击、C 段抽屉、D 段菜单高亮带、E 段**子菜单**、F 段**入场动画**：中间态 `alpha<1` 且 `backing.y != absY`，落地后 `isRunning==false` / `alpha==1` / 不再重画）；变异 `probes/widgets/overlay/mutation.cjs` **9/9**（其中 5 例是把真缺陷重新植入，1 例是子菜单的 parent-local 换算） |
| **图标通道探针（第十七轮，十九轮重钉）** | `node tools/probe.cjs probes/widgets/icon` | **66 checks**，0 failures：三次曲线 t=0.5 点（弦的话是空白）+ **t=0.789 点**（距最佳单二次逼近最远，细分/降阶都会变白）、二次曲线顶点、**两条弧拼成的整圆**四个采样点、填充三角形内外、**三档描边宽度**（2px/4px/12px，含 12-viewBox 缩放到 8px）、无 `size` 时盒子=viewBox；**负例**两个：未知命令抛错并带偏移、截断的弧参数抛错。变异 `probes/widgets/icon/mutation.cjs` **7/7**（三次降成二次；描边不缩放；忽略 viewBox；弧当弦；相对命令当绝对；忽略节点颜色；弧标志按数字读），每次都按 sha256 逐字节还原 |
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
- **表面层（控件集 / 组件目录页 / 浮层系统）**：五批共 40 kind / 46 工厂已落地并有手算探针；
  仍缺的见 §2.1。当前可交付上限约「多页表单 / 设置页 / 列表详表 / 带图与骨架的异步页 / 弹层与菜单驱动的交互」。

### 补齐优先级建议

1. **布局动画**（§3.4）——需要先定义「布局动画为什么要重解布局」；浮层的**退场**动画也卡在这里。
2. **浮层的 `z-index` / 堆叠策略**（§3.6）——现在「子序列 = 堆叠序」够用，但多弹层叠加时作者没有表达力。
3. **无障碍**（§2.1 唯一登记项）——`role`/`ariaName` 有字段、没有消费者。

> 已经从这里划掉的：`list`/`tree` 的虚拟化（本轮，只挂窗口）、`numberInput`/`rangeSlider`/`multiSelect`、
> `tree`/`combobox`/`datePicker` 三件选择类控件。数字不手写：工厂数由
> `kit/asaot/ui/*.as` 里「有自己的同名 public 工厂函数」计得（47），kind 数由 `tools/kind-coverage.cjs` 计得（41/41）。

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