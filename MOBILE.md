# MOBILE.md —— asaotui 移动端（iOS / Android）支持分析与改造清单

> 日期：2026-10-28 · 工作树：`asaotui/`（**未改 `as3compiler/` 一行**，只读核对）
> 参考：<https://nsh.dev/elements/>（Native Shell 的 element 清单）+ 同站 `/docs/touch-and-gestures`、
> `/docs/accessibility`、`/elements/safe-area`、`/elements/keyboard`
>
> 本文是**可执行清单**：每条都有编号、现状证据（文件:行 / 扫描计数）、改法与验收方式。
> 评估过程与更长的证据链留在 [`reviews/nsh-mobile-support-gap-2026-10-26.md`](reviews/nsh-mobile-support-gap-2026-10-26.md)，
> 两篇冲突时**以本文的当次实测数为准**（本文所有 kit 数字都出自本文 §10 的一条命令）。

---

## 0 三句话结论

1. **控件数量不是主要缺口。** 拿 NSH 的 48 个 element 逐项对表：我们有**等价物 19 个、语义不同 14 个**、
   真正缺且该做 **9 个**、明确不做 **6 个**。我们 41 个 kind 里的绝大多数都能在 NSH 清单里找到直接对应。
2. **真正缺的是三层地基**：**输入层**（`TouchEvent` 类有、输入源没有：全库 0 命中）、
   **环境层**（安全区 / 键盘矩形 / 密度 / 屏幕阅读器：0 命中）、**导航结构**（`navStack`/`tabBar`/`sheet`：0 命中）。
3. **但有三块底座已经存在，只是库没用起来**（§2.3）：`pointerEvents` 语义（`mouseEnabled`/`mouseChildren`
   已被命中测试完全遵守）、`hitSlop`（透明填充即可命中）、软键盘通路（`SDL_StartTextInput` 启动时已调用）。
   **这三件事今天就能做，不需要编译器立项。**

### 0.1 先做哪六件（其余都可排在后面）

| 序 | 事项 | 为什么排第一 | 规模 |
|---|---|---|---|
| 1 | `Pointer` 抽象 + 合成 mouse 兼容层（P1/P2） | 不做则 41 个 kind 全部只能靠鼠标；兼容层让它们**不改就动** | M |
| 2 | 触摸拖动滚动 + 惯性（S1/S2） | 手机上「滚不动」等于不可用 | M |
| 3 | `Env`（安全区 / 键盘 / 密度 / hasHover）（E1/E2） | 刘海与键盘一挡，界面就残；且 `hasHover` 决定 103 处 hover 是否该跑 | M |
| 4 | `navStack` + `appBar` + `tabBar`（N1–N3） | 现在**没有"页面"概念**，手机上没有返回栈 | L |
| 5 | 触控态样式 + `hitSlop` + `pointerEvents`（P5/P6） | 触摸设备没有 hover；小目标点不中 | S |
| 6 | 列表四件 + 下拉刷新（S6/C4） | 列表只能当展示用，不能当列表用 | M |

---

## 1 方法：把 NSH 当验收清单，不当架构

### 1.1 它和我们不是一条路

NSH 的每个 element 在 iOS/Android 上就是**一个原生视图**（`UIView` / `android.view.View`），
由平台创建与布局。于是滚动、软键盘、安全区、手势、无障碍树、文本选择、列表复用**全部由平台负责**；
NSH 只补「声明式属性 + 一层共享的行为组件」。

我们自绘（Skia + 自家布局引擎），所以同一张表在我们这里是**反向**的——平台免费的，我们要自己造：

| 能力 | NSH 谁做 | 我们必须自己做的部分 | 我们的现状 |
|---|---|---|---|
| 滚动惯性 / 回弹 / 吸附 | UIScrollView / ScrollView | 触摸拖动 + 物理 + 与按压竞争 | 自述「no momentum / elastic overscroll」（`ScrollViewWidget.as:32`） |
| 软键盘弹出与顶起 | 平台自动 | 键盘矩形 → inset → 滚入视口 | `softKeyboardRect` 全库 0；`SDL_StartTextInput` 已调用 |
| 安全区 | 平台视图自动 | 平台查询 → 环境值 → 根 padding | `safeArea` 全库 0 |
| 手势（pan/pinch/rotate） | 平台识别器 | 识别器 + 仲裁 + 轴锁 | `pinch` 0、`rubber` 0 |
| 无障碍树 | 平台自动（真视图层级） | 自绘语义树 → 平台 a11y 节点 | 只有 `role/ariaName/ariaValue` 三个**形状**字段 |
| 文本选择/光标/复制菜单 | 系统文本控件 | —— | **已有**：真 `TextField type="input"`，caret/selection/masking 走运行时 |
| 列表复用/吸顶/可见性 | 平台列表 | 复用 + 吸顶 + 可见性 + 变高 | 复用**有**，其余四件 0 |
| 页面栈/侧滑返回/返回键 | UINavigationController / 返回键 | 栈 + 过渡 + 键映射 | **无路由概念**；`Keyboard.BACK` 库内 0 引用 |

**这张表就是 §4/§5 的骨架。**

### 1.2 两条最值得抄的规则

**规则一：系统要"同步答案"的问题，一律做成声明式属性。**
NSH 明确「主线程从不等待应用代码」（`/elements#why-handlers-never-block-the-ui`），所以：
`maxLength`（还能输几个字符）、`popOnBack`（侧滑返回允许吗）、`closeOnSwipe`（下滑关面板吗）、
`hitSlop`（热区大于绘制区吗）、`delayLongPress`（多久算长按）、`panActivation`（轴冲突谁赢）——
**都是属性，不是回调返回值。**

⇒ 对我们的直接约束：手机端每一个阈值（按压延迟、长按、滑动阈值、刷新阈值）**必须是描述符字段
（有默认、可覆盖）**，不得是 widget 里的字面量；也**不得**在触摸事件里回调应用代码再等它回答。
这条可以写成一道静态门（§8 V2）。

**规则二：按压是三件事，不是一件事。**
NSH 的 common props 里，按压相关是：`onPress` / `onLongPress` / `onPressDown` / `onPressUp`、
`delayLongPress`（默认 500ms）、`hitSlop`，外加三条行为约束——**只有最内层可压者响应**、
**滚动容器内按下先等约 130ms**（让滚动有机会先开始）、**按压反馈由本地状态直接绘制**（不回应用代码）。

⇒ 我们现状：`pressed` 由 `MOUSE_DOWN` 直接置位（无延迟、无滑出取消、无长按、无热区扩展）。
这在桌面上无感，在手机上就是「一按就亮、想滚动却先触发点击」。

---

## 2 现状实测（2026-10-28）

命令：`node tools/mobile-gap-scan.cjs`（只读，不动编译器；本文所有数字都出自它）。

### 2.1 计数

| 指标 | 值 |
|---|---|
| kit `.as` 文件 | **179** |
| 注册 kind / 作者工厂 | **41 / 47** |
| `Style` 字段 | **33**（flexbox 子集 + 视觉；**无 grid、无 z-index**） |
| 处理 `MouseEvent` 的文件 | **24 / 179**，**174 处**引用 |
| `hover` 相关引用 | **103 处**（悬停假设遍布控件层） |
| 文档站页数 | **52**（`new DocPage`） |
| 验收门 | **58**（`node tools/gates.cjs`） |
| `VirtualListWidget` | **202 行**，固定行高 |

### 2.2 移动端令牌：全 0

| 令牌 | 命中 | 含义 |
|---|---|---|
| `TouchEvent` / `Multitouch` / `TouchPhase` | 0 / 0 / 0 | 库内没有任何触摸路径 |
| `safeArea` / `keyboardHeight` / `softKeyboard` | 0 / 0 / 0 | 安全区与键盘 inset 无人消费 |
| `stageOrientation` / `Capabilities` / `pixelRatio` | 0 / 0 / 0 | 方向、密度、物理像素比都读不到 |
| `hitSlop` / `pointerEvents` / `longPress` / `pressDelay` | 0 / 0 / 0 / 0 | 按压契约（§1.2 规则二）一个都没有 |
| `navStack` / `appBar` / `tabBar` / `bottomSheet` | 0 / 0 / 0 / 0 | 手机骨架全缺 |
| `rubber` / `pinch` | 0 / 0 | 无回弹、无捏合 |
| `reduceMotion` / `appState` / `screenReader` | 0 / 0 / 0 | 系统偏好与前后台状态拿不到 |
| `inertia` | 2（**都在注释里**：`ScrollViewWidget.as:32` 的自述 + `UiApp.as:543`） | 不是实现 |
| `accessibility` | 2（`Element.as` 的注释） | 只有形状字段，无语义树 |

### 2.3 三块**已有但没用起来**的底座（本文最有用的发现）

这三条是「**不用等编译器、也不用改引擎**」就能落地的：

**① `pointerEvents` 的语义已经在引擎里了。**
`as_pick_hit_m` 完全遵守 `mouseEnabled` / `mouseChildren`（`as3compiler/src/emit.ts:19688–19747`，
注释原文：「`mouseEnabled`/`mouseChildren` are already honoured by the hit test」）。
NSH 的三种取值可直接一一映射，**库内 0 处使用**：

| `pointerEvents` | `mouseEnabled` | `mouseChildren` | 效果 |
|---|---|---|---|
| `auto`（默认） | `true` | `true` | 正常 |
| `box-none` | `false` | `true` | 自己不吃，孩子照吃（叠层容器用） |
| `box-only` | `true` | `false` | 自己吃，孩子不吃（整块当按钮） |
| `none` | `false` | `false` | 全透（装饰层、遮罩背景） |

**② `hitSlop` 可用透明填充实现。**
`as_shape_region_hit` 判定 `Graphics` 的**填充路径**是否包含该点，**不看 alpha**（`emit.ts:19611`）。
本轮 `numberInput` 的修复（加减列整列可点）用的就是这一条。⇒ 热区扩展是纯 AS3，无需引擎改动。

**③ 软键盘的通路已经存在。**
`window_glue.cc:2510` 在启动时调用 `SDL_StartTextInput()`，`:1498` 调 `SDL_SetTextInputRect()`，
`SDL_TEXTEDITING`（组字）有 6 处引用——这就是桌面 IME 走得通的那条老路。
移动端缺的是**平台壳**（B 组），不是键盘通道。
同一件事还有第二个好处：`textInput` 的编辑对象是**真 `TextField type="input"`**（`TextInput.as:1-6`），
caret / 选区 / 密码掩码 / 组字都走运行时。所以旧评估里的 E3 (a)/(b)（要不要做镜像原生输入框）
在我们这里**收敛为 (b)**：字符与组字走运行时，只有「选择手柄 / 长按菜单」需单做（T2）。

---

## 3 NSH elements → asaotui 逐项对照

清单来自 2026-10-28 抓取的 `/elements` 首页表格（29 个 base）**加上该页侧栏单独成页的
`Calendar` / `ColorPicker` / `Combobox` / `DatePicker` / `TimeField` / `RichEditor`**
（`RichEditor` 并入 `Editor` 一行）——首页表格本身不全，只照表格抄会漏掉这四个。

图例：**✓ 等价** / **~ 语义不同（能用但不像手机）** / **✗缺**（该做）/ **— 不做**（明确出范围）。

### 3.1 Primitives（14）

| NSH | 我们 | 判定 | 差什么 |
|---|---|---|---|
| `View` | `box` / `row` / `column` | ✓ | — |
| `Text` | `text` | ✓ | 字号缩放（E4） |
| `Image` | `image` / `avatar` / `icon` | ✓ | — |
| `Scroll` | `scrollView` | ~ | 触摸拖动、惯性、回弹、吸附（S1–S4） |
| `List` | `vlist` | ~ | 变高、吸顶、`onVisible`、`scrollToIndex`（S6） |
| `Canvas` | （用 `Graphics` 直画） | ✗缺 | 无「画布元素」形态；作者要自定义 kind 才行 |
| `Shader` | — | — | 不做 |
| `WebView` | — | — | 不做 |
| `Video` | — | — | 不做 |
| `Overlay` | `overlay` + `OverlayChrome` | ✓ | 叠放靠 display order（`overlay.as:10`，引擎无 z-index） |
| Safe area | — | ✗缺 | 无 API、无消费者（E1/E2） |
| Keyboard inset | — | ✗缺 | 无 API、无消费者（E1） |
| Text selection | 运行时 `TextField` | ~ | 无 `setSelection` 等 ref 方法（T1） |
| `If` / `Each` | AS3 原生 `if` / `for` / `Array` | ✓ | 形态不同，语义等价 |

### 3.2 Base（34）

| NSH | 我们 | 判定 | 备注 |
|---|---|---|---|
| `Button` | `button` | ✓ | 缺按压延迟与热区（P2/P6） |
| `Checkbox` / `Switch` / `Radio` | `checkbox` / `switch` / `radio` | ✓ | 缺 `checked:"mixed"` 三态语义与样式 |
| `Collapsible` | `accordion` | ✓ | — |
| `Combobox` | `combo` | ✓ | 手机上应转底部面板（N4） |
| `DatePicker` | `datepicker` | ✓ | 月历网格已有（`DatePickerWidget` 深路由） |
| `Dialog` | `dialog` | ✓ | 缺 `popOnBack` / 下滑关闭 |
| `AlertDialog` | `dialog` | ~ | 缺「两键确认 + destructive + 平台动作表」语义 |
| `Input` | `textInput` / `textArea` | ✓ | 缺键盘类型 / 回车键 / 自动大写（T3） |
| `Menu` | `menu` | ~ | 桌面弹层；手机应转 sheet |
| `NavStack` | — | ✗缺 | **P0**（N1） |
| `NumberInput` | `numberInput` | ✓ | 本轮刚修：整列命中 + 32pt |
| `OtpInput` | — | ✗缺 | P1 |
| `Popover` | `popover` | ~ | 锚定气泡不是手机用法，需 `presentation`（N4） |
| `Progress` | `progress` / `spinner` / `skeleton` | ✓ | — |
| `Resizable` | `splitPane` | ~ | 有拖柄，无嵌套组；手机基本不用 |
| `Scrollbar` | `scrollView` 内置 | ~ | 无独立元素；手机上应默认淡出（S8） |
| `Select` | `select` | ✓ | 同上，需 `presentation` |
| `Sheet` | `drawer`（bottom） | ~ | 静态版：无拖拽把手、无半开/全开吸附、无下滑关闭 |
| `Slider` | `slider` / `rangeSlider` | ✓ | 触摸拖动已有（stage 手势），缺热区与 haptic |
| `Table` / `DataTable` | `table` | ~ | 手机横向表基本不可用，需「列优先级 + 折叠」 |
| `Tabs` | `tabs` | ~ | 顶部分段控件；**不是**底部 tabBar |
| `Calendar` | `datepicker`（面板） | ~ | 有网格，无独立「日历」元素 |
| `ColorPicker` | — | ✗缺 | P2 |
| `Plot` | — | ✗缺 | P2 |
| `TextView` | — | ✗缺 | P2（Markdown 阅读） |
| `TimeField` | — | ✗缺 | P1 |
| `Toast` | `toast` / `toastHost` | ✓ | 需避让安全区底部 |
| `Tooltip` | `tooltip` | ~ | hover-only；触摸上应长按或禁用 |
| `DiffView` / `Dock` / `Editor` | — | — | 不做（桌面向/编辑器向） |

### 3.3 对照结论

- **统计**：✓ 19 · ~ 14 · ✗缺 9 · — 6（共 48）。
- **控件不是瓶颈**：真正缺的 9 个里，只有 `navStack` 是结构性的，其余（Otp/Time/ColorPicker/Plot/TextView/Canvas/安全区/键盘）都能后排。
- **Common props 的差**（NSH `/elements#common-props` 与我们对照）：
  我们有 `disabled` / `hover` / `pressed` / `focused` 四态；
  **缺** `activeStyle`（等价于我们的 pressed，命名不同）、`checked` / `indeterminate` / `selected` /
  `expanded` / `pressed`（toggle 态）五个**状态化样式**，以及 `hitSlop` / `delayLongPress` /
  `pointerEvents` / `focusable` 四个**行为属性**。
  前五个是样式层的扩容（便宜），后四个是交互契约（手机必需）。
- **`hover` 是负资产**：103 处引用，触摸设备上一条都不会触发；必须由 `Env.hasHover` 统一裁决，
  而不是逐控件加判断（P5）。

---

## 4 需要改进的机制（不是新增控件）

编号：`P` 输入 · `S` 滚动/列表 · `E` 环境 · `N` 导航 · `T` 文本输入 · `A` 无障碍 · `B` 后端。

### 4.1 P —— 输入层（纯 AS3，今天可开工）

| ID | 事项 | 现状证据 | 改法 | 优先级 |
|---|---|---|---|---|
| P1 | `Pointer` 抽象：`{id, x, y, phase, isPrimary, pressure}`，统一 touch/pen/mouse | 24 文件直接吃 `MouseEvent`（174 处） | 新增 `asaot.ui.Pointer` + `PointerRouter`；**合成 mouse 兼容层**（primary → `MouseEvent`）让 41 kind 不改就能被触摸驱动 | **P0** |
| P2 | 按压语义：`pressDelay`(≈130ms) / `longPress`(≈500ms) / `pressSlop`(≈8pt) / 滑出取消 | `pressed` 由 `MOUSE_DOWN` 直接置位 | 字段进描述符（可覆盖），默认值集中在一处常量；滚动容器内自动走 `pressDelay` | **P0** |
| P3 | 手势识别器：tap / doubleTap / longPress / pan / swipe / pinch，含**仲裁**（同一时刻一个赢家） | 0 命中 | 识别器只回答「谁赢 + 位移/速度」，**不重解布局**（手势期走 transform / `scrollRect`） | P1 |
| P4 | `claim`（触摸抢占）：控件说「这次触摸归我」，滚动容器据此取消按压 | 现有「临时挂 stage 监听」是鼠标抓取 | 与 S1 同一处；`onStartShouldSetResponder` 的最小等价物 | P1 |
| P5 | 触控态样式：`Env.hasHover == false` ⇒ 103 处 hover 分支不触发；`pressed` 立即反馈 | `UiApp.as:202–225` 从 `MOUSE_MOVE` 派生 hover | **统一裁决**，不是逐控件加 `if`；`hover` 在触摸上转为 `pressed` 或禁用 | **P0** |
| P6 | 最小命中 44pt + `hitSlop`（四边可不同） | `hitSlop` 0；新修 `numberInput` 是第一个热区 | 透明填充（§2.3②）；做成静态门：每个 kind 的命中矩形 ≥ 44×44 | P1 |
| P7 | 触摸热路径零分配 | AGENTS.md §2.4 的 GC 红线 | move 事件不 new 对象/字符串；指针状态复用同一实例 | **P0** |

### 4.2 S —— 滚动与列表

| ID | 事项 | 现状证据 | 改法 | 优先级 |
|---|---|---|---|---|
| S1 | 1:1 触摸拖动 + 取消子项按压 + 抢占 | `ScrollViewWidget.as:32` 自述无动量；`touchDragWords` 0 | 拖动期间把 `pressed` 置灰并取消点击 | **P0** |
| S2 | 惯性（按 dt 积分，不假设 16ms） | `inertia` 只在注释里（2 处） | `ENTER_FRAME` + 时间差；`decelerationRate` 进描述符 | **P0** |
| S3 | 越界回弹（rubber-band）或 Android 拉伸/辉光 | `rubber` 0 | 越界阻尼 + 回位动画；终止条件用速度阈值 | P1 |
| S4 | 分页吸附（`paging` / `snap`） | `scrollView` 内 `paging` 只出现 1 次，且在「不做」清单里（`ScrollViewWidget.as:33`） | 轮播/引导页必需 | P2 |
| S5 | 嵌套滚动与轴锁 | 无 | 依赖 P3 仲裁：内层先声明轴，外层让位 | P2 |
| S6 | 列表四件：变高估算 / 吸顶分组 / `onVisible` / `scrollToIndex` | `estimated`/`sticky`/`onVisible`/`scrollToIndex` 全 0 | `vlist` 202 行是固定行高；四件里**先做 `scrollToIndex` + `onVisible`**（最便宜且最常用） | P1 |
| S7 | 键盘焦点滚入可见区 | 无 | 依赖 E1 的 `keyboardRect` | P1 |
| S8 | 滚动条移动端化：不常显、滚动时淡入、可隐藏 | 现有 `auto/always/never`（桌面语义） | 加 `"fade"` 取值 | P2 |

### 4.3 E —— 环境 / 键盘 / 文本度量

| ID | 事项 | 现状证据 | 改法 | 优先级 |
|---|---|---|---|---|
| E1 | `asaot.ui.Env`：`safeArea` / `keyboardRect` / `pixelRatio` / `hasTouch` / `hasHover` / `reduceMotion` / `appState` / `locale`，**读即订阅** | 全部 0 命中 | 接口 + 桌面实现（读 `Stage`/`Screen` 回退）；平台填充留给 B 组；订阅复用现有 `Observable`/`Subscription` | **P0** |
| E2 | 安全区消费：**根节点 padding**（或 `safeAreaBox` 容器），不在引擎里散布 inset | 无 | 只在一处消费；`Style.inset` 已存在且是 CSS 定位语义，**不要**复用这个名字 | **P0** |
| E3 | 输入法移动化：键盘类型 / 回车键 / 自动大写 / 自动更正 / 密码 / 多行自增高 | `emit` 里 `softKeyboardType`/`returnKeyLabel`/`needsSoftKeyboard` 全 0 | AIR **有**这三个 API ⇒ **遗留欠账**（B 组），不是增强；库侧先出字段与默认值 | P1 |
| E4 | 字号缩放（`fontScale` 参与度量与行高） | 无 | 与「手算高度」那类逻辑冲突，需一起改 | P2 |
| E5 | 深色跟随系统 | 只有库内 `Theme`（运行时切换已就绪） | 读 `Env.isDark` 即可 | P2 |
| E6 | RTL / locale | 无 | 与 `flexDirection: row` 耦合，单独立项 | P3 |
| E7 | 前后台：后台停帧、回来补 delta | 无 | 否则后台烧电、回来跳帧 | P1 |
| E8 | `reduceMotion` | 无 | 读 `Env`，关掉过渡动画 | P2 |

### 4.4 N —— 导航与容器（手机骨架）

| ID | 事项 | 为什么必须有 | 现状 |
|---|---|---|---|
| N1 | `navStack` / `navPage`：栈、push/pop、页面过渡、每页状态保持 | 现在**没有路由**；文档站靠「换 model + 重建内容」模拟 | 0 命中 |
| N2 | `appBar`：标题/大标题、左返回、右动作、随滚动收起、与安全区联动 | 页面骨架 | 0 命中 |
| N3 | `tabBar`：底部一级导航（现有 `tabs` 是顶部分段控件，语义不同） | 手机一级入口 | 0 命中 |
| N4 | `presentation`：同一份描述符，小屏转底部面板/全屏页（`select`/`menu`/`popover`/`datepicker` 共用） | 锚定气泡不是手机做法 | 0 命中 |
| N5 | 返回键与侧滑返回：`Keyboard.BACK` → `navStack.pop` | 手机上「返回」是最高频动作 | 符号表有 `BACK`，库内 **0 引用** |
| N6 | 页面过渡动画与手势返回（边缘滑动） | 手机「返回」的第二种入口 | 缺 |

### 4.5 T —— 文本输入

| ID | 事项 | 现状 | 说明 |
|---|---|---|---|
| T1 | 暴露 `setSelection` / `caretIndex` 等 ref 方法 | 运行时**有** `setSelection`（`emit.ts` 6 处）、`caretIndex`（4 处），**库内 0** | 最便宜的一条：纯粹是没接出来 |
| T2 | 选择手柄与长按菜单 | 无 | 自绘（选中态已有 31 处引用可复用）；**不引入镜像原生输入框** |
| T3 | 键盘类型 / 回车键 / 自动大写 | `needsSoftKeyboard`/`softKeyboardType`/`returnKeyLabel` 全 0 | AIR 有 ⇒ 欠账（B 组） |
| T4 | 多行自增高与滚动跟随 | `textArea` 存在 | 与 S7 联动 |
| T5 | 自动填充 / 密码管理器 | 无 | 平台行为，需 B 组的原生输入通道 |

### 4.6 A —— 无障碍（最贵的一项）

| ID | 事项 | 现状 | 判定 |
|---|---|---|---|
| A1 | 语义树：`role` / `name` / `value` / `state`(disabled/selected/checked/busy/expanded) | `Element.as:10–12` 只有 `role`/`ariaName`/`ariaValue` **形状字段**，无消费者、无树 | AIR 有 `flash.accessibility` ⇒ **遗留欠账**（G2） |
| A2 | 平台桥（iOS `UIAccessibility` / Android `AccessibilityNodeProvider`） | 无 | 自绘路线特有 ⇒ 增强 |
| A3 | 焦点序 / 朗读序 / Tab 序共用一份排序 | Tab 序有 64 上限、扁平（G3） | 欠账 |
| A4 | 自定义动作（"删除"、"标为已读"） | 无 | 增强 |

> **建议**：A 组单独立项，不要塞进手机端首版。它的工作量约等于「新增 6 个组件」，且**不达标的后果
> 是残障用户完全不可用**，不是"体验差一点"。

### 4.7 B —— 编译器 / 后端（**不在 asaotui 做，只登记**）

| ID | 缺什么 | 证据 | 判定 |
|---|---|---|---|
| B1 | `Target` 无 iOS/Android | `build.ts`：只有 `'native'` 与 `'wasm'` 两个值 | 工具链 |
| B2 | Skia 无移动端产物 | `vendor/skia/lib`：`macos-arm64 wasm windows-x64 windows-x86` | 工具链 |
| B3 | SDL2 无移动端产物 | `vendor/sdl2/lib`：`macos-arm64 windows-x64 windows-x86` | 工具链 |
| B4 | 平台壳（iOS `UIApplicationDelegate` + `CAMetalLayer`；Android `ANativeActivity` + `EGL`） | 现有 glue 只有 Cocoa/Win32/X11 | 工具链 |
| B5 | 触摸输入源 | `emit` 有 `TouchEvent`（15 处，类存在）；glue `SDL_FINGER` **0** | **AIR 遗留欠账**（G5） |
| B6 | `Stage.softKeyboardRect` | `emit` 0 | **AIR 遗留欠账** |
| B7 | `needsSoftKeyboard` / `softKeyboardType` / `returnKeyLabel` | `emit` 0 / 0 / 0 | **AIR 遗留欠账** |
| B8 | `stageOrientation` / `autoOrients` | `emit` 0 / 0 | **AIR 遗留欠账** |
| B9 | 安全区 / `pixelRatio` 查询 | `SDL_GetDisplayDPI` 0 调用；`safeArea` 0 | **增强**（AIR 无此 API） |
| B10 | Android 字体管理器 | `sk_platform_fontmgr` 的 `#else` 恒走 CoreText | 工具链 |
| B11 | 打包：iOS `.app`/`.ipa`、Android `.apk` | `android-project` 直接 throw | 工具链 |
| B12 | 浏览器臂：`pointer*` / `touch*` / `keydown` | `web_glue.cc` 只挂 mouse/wheel；`(void)on_key`（`:375`、`:458`）⇒ **浏览器里打不了字** | 缺口 |
| B13 | 返回键派发 | `Keyboard.BACK` 符号存在，无派发 | 缺口 |
| B14 | 触觉反馈 | AIR 无 ⇒ 增强 | 增强 |

---

## 5 需要新增的组件

| ID | 组件 | 为什么必须 | 形状要点 | 规模 | 优先级 |
|---|---|---|---|---|---|
| C1 | `navStack` + `navPage` | 没有页面就没有返回栈 | `pages` 数组 + 当前索引；header 由 appBar 提供；过渡动画独立于布局 | L | **P0** |
| C2 | `appBar` | 页面骨架 | 左/中/右三槽；`large` 变体随滚动收起；安全区顶部内边距 | M | **P0** |
| C3 | `tabBar` | 手机一级导航 | 底部、图标 + 标签、选中态、安全区底部内边距 | M | **P0** |
| C4 | `refreshControl` | 列表标配 | 阈值 + 阻尼 + 释放触发；与 `vlist`/`scrollView` 联动 | M | **P0** |
| C5 | `actionSheet` + 两键 `alert` | 危险操作确认 | destructive 色调；底部呈现；取消按钮固定 | S | P1 |
| C6 | `swipeableRow` | 列表标配 | 左滑/右滑、阈值、回弹、与滚动竞争（P3 仲裁） | M | P1 |
| C7 | `searchBar` | 首页标配 | 输入 + 清空 + 取消 + 搜索键；焦点态；搜索态覆盖 | S | P1 |
| C8 | `snackbar` | 反馈标配 | 底部 + 动作按钮；`toast` 是角落浮层，语义不同 | S | P1 |
| C9 | `otpInput` | 验证码场景 | 定长格子、粘贴整串、自动填充 | S | P1 |
| C10 | `timeField` | 时间选择 | 与 `datepicker` 共用面板机制 | S | P1 |
| C11 | `statusBarStyle` | 沉浸式/浅色图标 | 深色背景下必需 | S | P1 |
| C12 | `fab` | Material 骨架 | 随滚动隐藏 | S | P2 |
| C13 | `colorPicker` | 设置类页面 | 色板 + 自定义 | M | P2 |
| C14 | `plot` | 数据展示 | 折线/柱/饼，`Graphics` 直画 | L | P2 |
| C15 | `textView` | 文档阅读 | Markdown → 文本 + 图片 + 代码块 | L | P2 |
| C16 | `calendar` | 独立日历 | 复用 `datepicker` 的月格 | M | P2 |
| C17 | `keyboardAccessory` | 表单常见 | 键盘上方工具条（iOS） | S | P3 |

**明确不做**：`editor` / `richEditor` / `diffView` / `dock` / `webView` / `video` / `shader` / CSS Grid
（网格用 `flexWrap + aspectRatio` 先验；`Style` 两者都有）。

---

## 6 具体 API 形状（照着写就行）

### 6.1 `Element` 新增（**不进 `Style`**：它们影响命中，不影响布局/绘制）

```as3
// kit/asaot/ui/Element.as —— 与 disabled / role 同一层
public var hitSlop:Number;        // 单值 pt；0 = 不扩（默认 0）
public var hitSlopEdges:Edges;    // 四边不同时用；两者都设则取并集
public var pointerEvents:String;  // "auto" | "none" | "box-none" | "box-only"
public var focusable:Boolean;     // Tab 环是否停在这里（桌面语义；触摸上无效果）
```

`pointerEvents` 直接映射 `mouseEnabled`/`mouseChildren`（§2.3① 的表格），在 `Widget.measure`
或一次性的绑定阶段写一次即可，**不要每帧写**。

### 6.2 输入层

```as3
// kit/asaot/ui/Pointer.as
public class Pointer {
    public var id:int;
    public var x:Number, y:Number;        // 根坐标
    public var phase:String;              // "down" | "move" | "up" | "cancel"
    public var isPrimary:Boolean;
    public var pressure:Number;           // 无压感设备恒 0.5
}

// kit/asaot/ui/InputConstants.as —— 触摸阈值唯一出处（禁止散落字面量）
public class InputConstants {
    public static const PRESS_DELAY_MS:int  = 130;  // 滚动容器内按下等待（NSH 文档值）
    public static const LONG_PRESS_MS:int   = 500;  // NSH delayLongPress 默认值
    public static const PRESS_SLOP_PT:Number = 8;   // 位移超过即视为拖动
    public static const MIN_HIT_PT:Number    = 44;  // iOS HIG 44pt / Material 48dp，取 44
}
```

> 上述默认值取自 NSH 文档与平台惯例，**未在本库上实测手感**（§10 末）。它们必须是描述符字段的
> **默认值**，作者可覆盖。

### 6.3 `Env`

```as3
// kit/asaot/ui/Env.as —— 读即订阅（复用 Observable/Subscription）
public interface Env {
    function get safeArea():Edges;          // 逻辑点，四边
    function get keyboardRect():Rectangle;  // 屏幕坐标；收起时全 0
    function get pixelRatio():Number;
    function get hasTouch():Boolean;
    function get hasHover():Boolean;        // 桌面 true；手机 false ⇒ hover 分支不跑
    function get reduceMotion():Boolean;
    function get appState():String;         // "active" | "background" | "inactive"
    function get isDark():Boolean;
    function get locale():String;
    function subscribe(fn:Function):Subscription;
}
```

桌面实现：`safeArea` 全 0、`keyboardRect` 全 0、`pixelRatio` 读 `Stage` 的物理/逻辑比、
`hasHover = true`、`appState = "active"`。**平台填充只改实现，不改接口。**

### 6.4 描述符新增字段（与 `Widget` 契约一致）

| 字段 | 加在 | 默认 | 谁读 |
|---|---|---|---|
| `pressDelay` | 所有可压元素（`Element`） | `InputConstants.PRESS_DELAY_MS` | `UiApp` 指针路由 |
| `longPress` | 同上 | `500` | 路由 |
| `onLongPress` | 同上 | `null` | 作者 |
| `hitSlop` / `hitSlopEdges` | 同上 | `0` | `Widget.measure`（画透明填充） |
| `pointerEvents` | 同上 | `"auto"` | 绑定阶段写 `mouseEnabled`/`mouseChildren` |
| `presentation` | `select` / `menu` / `popover` / `datepicker` | `"popover"` | 工厂：小屏选 `"sheet"` / `"fullscreen"` |
| `safeArea` | 根容器 | `"none"` | 布局前加 padding |
| `decelerationRate` | `scrollView` / `vlist` | 平台值 | 惯性积分 |
| `paging` | `scrollView` | `false` | 吸附 |

### 6.5 状态化样式（样式层扩容，便宜）

现有四态：`disabled` / `hover` / `pressed` / `focused`。补齐五个：
`checked` / `indeterminate` / `selected` / `expanded` / `pressed`(toggle)。
优先级按 NSH 的次序：`disabled` > `selected`/`checked`/`indeterminate` > `hover` > `focus` > `active`。

---

## 7 里程碑与验收

| 里程碑 | 交付 | 验收（必须可复现） |
|---|---|---|
| **M0 触摸可路由** | P1/P2/P5 + 合成 mouse 兼容层 | 新增 `probes/widgets/pointer-touch`：用**合成 touch 序列**驱动 chip/button/switch；现有 `probes/widgets/*` 在触摸驱动下全绿 |
| **M1 可滚** | S1/S2/S3 | 确定性回放：一次 fling 的位移曲线与手算表一致；越界回弹回位误差 < 1pt |
| **M2 有环境** | E1/E2/E7 | 模拟 `safeArea=(47,0,34,0)` + `keyboardRect` 后，根 padding 与「输入框滚入可见区」逐项断言 |
| **M3 有骨架** | N1–N5 | 三页栈：push/pop/系统返回/侧滑；页面状态保持；`navStack` 深度断言 |
| **M4 可输入** | E3/T1–T4 | 键盘矩形变化 → 焦点框滚入 → 收起复原；`setSelection` 生效 |
| **M5 像应用** | C4–C11 + E5/E8 | 下拉刷新 + 滑动删除 + 深色 + 后台不烧电 |
| **M6 可上架** | A1/A2 + B 组 + 真机走查 | TalkBack/VoiceOver 清单全过；签名包安装不崩 |

**V 组（验收工具，随里程碑一起建）**

| ID | 工具 | 说明 |
|---|---|---|
| V1 | 移动尺寸 tour | 390×844@3x、412×915@2.6x、768×1024；52 页逐页扫 |
| V2 | 触摸驱动探针 | 合成 tap/drag/fling（**不用鼠标**）；顺带做静态门「kit 内不得出现未声明的触摸阈值字面量」 |
| V3 | 性能预算门 | 帧时间 p95 < 16.7ms；触摸 move 零分配；滚动时 GC 不触发 |
| V4 | 手势录制回放 | 确定性时间轴（含 dt），惯性/回弹只能这样验 |
| V5 | 无障碍树 dump | 与 TalkBack/VoiceOver 手测清单配对 |
| V6 | 基准换锚 | `adl` 不再是手机基准（本机不可观测）；改为「平台语义表 + 真机录屏」 |

---

## 8 红线（都有代价依据）

1. **不要把 `adl` 当手机基准**。AIR 的移动运行时在本机不可观测；照搬桌面 adl 会把安全区/手势语义猜错。
2. **不要在手机上用 CPU raster 全屏**。390×844@3x ≈ 1170×2532，一帧 RGBA ≈ 11.8 MB。
3. **不要把 `hover` 当 `pressed`**。hover 是从 `MOUSE_MOVE` **派生**的（`UiApp.as:202–225`）；触摸没有
   move-without-down，直接复用会「按了不亮、松手才亮」。
4. **不要在触摸 move 里分配**。撞 AGENTS.md §2.4 的 GC 红线；触摸 move 频率是鼠标的 2–3 倍。
5. **不要给引擎加 `z-index` / `inset` 语义**。叠放靠 display order（`overlay.as:10`）；`Style.inset`
   已存在且是 CSS 定位语义，**同名不同义会咬人**。安全区用根 padding。
6. **不要在 asaotui 里改编译器**。B 组一律回 `compiler-gaps.md` 登记、由编译器项目开阶段。
7. **不要让手势识别长成第二个布局引擎**。识别器只回答「谁赢 + 位移」，手势期走 transform/`scrollRect`。
8. **不要为手机做 CSS Grid**。`flexWrap + aspectRatio` 先验，不够再谈。
9. **不要做第二套文本管线**。`TextField type="input"` 就是管线（`TextInput.as:1-6`）；
   也不要为了手机引入 Flutter 式镜像原生输入框——我们的输入本来就是「运行时自己的输入框 + 平台喂字符」。

---

## 9 与既有文档的关系

| 文档 | 分工 |
|---|---|
| `reviews/nsh-mobile-support-gap-2026-10-26.md` | 评估与证据留档（NSH 是什么、三条路线、七条借鉴） |
| **本文** | **可执行清单**：编号、API 形状、里程碑、验收 |
| `compiler-gaps.md` | B 组的唯一登记处（**已登记**：G2 无障碍 / G3 Tab 序 / G5 触摸无输入源；**拟新增、尚未写入**：G30 键盘与方向族 / G31 移动端打包 / G32 Skia+SDL 移动产物 / G33 Web 臂不接 pointer/keydown / G34 Android 字体 / G35 安全区与密度。⚠️ **编号已顺延一位**：原拟的 G29 已被 `overflow`「存了不画」占用（✅ 2026-10-30 结案：不是编译器缺口），评审文档 [`reviews/nsh-mobile-support-gap-2026-10-26.md`](reviews/nsh-mobile-support-gap-2026-10-26.md):376 里的 G29 按**旧编号**读，即此处的 **G30**） |
| `STATUS.md` | 库当前完成度（41 kind / 47 工厂 / 33 字段 / 58 门） |

---

## 10 证据与复核

```bash
cd asaotui
node tools/mobile-gap-scan.cjs          # 本文所有计数（只读，不编译、不写文件）
node tools/mobile-gap-scan.cjs --json   # 机读形态
node tools/compiler-fingerprint.cjs     # 复核 as3compiler/ 零改动
node tools/gates.cjs                    # 58 道门（本文未新增门）
```

> 本文**不给门的绿/红判断**（只做静态计数与代码事实）。上一次全绿落盘是 `reviews/gates-all-39.txt`
> （**58/58**）；此后工作树有并发改动（另有会话在改 `as3compiler/`），要引用门的结论请当场重跑。

编译器事实的**出处行号**（只读）：`as3compiler/src/emit.ts:19688–19747`（`mouseEnabled`/`mouseChildren`
被命中测试遵守）、`emit.ts:19611`（填充路径命中不看 alpha）、`as3compiler/vendor/window_glue.cc:2510`
（`SDL_StartTextInput`）、`:1498`（`SDL_SetTextInputRect`）、`as3compiler/vendor/web_glue.cc:375,458`
（`on_key` 被丢弃）。

**未实测声明（不得当结论引用）**

- 真机 / 模拟器**一次都没跑过**（本机无 iOS SDK / Android NDK 验证）。
- 浏览器「touch 合成 mouse」能否驱动现有 `scrollView`：**未实测**（glue 只挂 mouse）。
- 阈值 `130ms / 500ms / 8pt / 44pt`：取自 NSH 文档与平台惯例（`delayLongPress = 500`、`hitSlop` 默认 8、
  滚动容器内按下等待约 130ms；iOS HIG 44pt / Material 48dp），**未在本库上手感实测**。
- NSH 的元素清单以 2026-10-28 抓取的 `/elements` 页为准；该站若改版，§3 的对照表需要重抓。