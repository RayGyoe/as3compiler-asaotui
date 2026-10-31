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
   真正缺且该做 **9 个**、明确不做 **6 个**。我们 44 个 kind 里的绝大多数都能在 NSH 清单里找到直接对应。
2. **真正缺的是三层地基**：**输入层**（`TouchEvent` 类有、输入源没有：全库 0 命中）、
   **环境层**（安全区 / 键盘矩形 / 密度 / 屏幕阅读器：0 命中）、**导航结构**（`navStack`/`tabBar`/`sheet`：0 命中）。
3. **但有三块底座已经存在，只是库没用起来**（§2.3）：`pointerEvents` 语义（`mouseEnabled`/`mouseChildren`
   已被命中测试完全遵守）、`hitSlop`（透明填充即可命中）、软键盘通路（`SDL_StartTextInput` 启动时已调用）。
   **这三件事今天就能做，不需要编译器立项。**

### 0.1 先做哪六件（其余都可排在后面）

| 序 | 事项 | 为什么排第一 | 规模 |
|---|---|---|---|
| 1 | `Pointer` 抽象 + 合成 mouse 兼容层（P1/P2） | 不做则 41 个 kind 全部只能靠鼠标；兼容层让它们**不改就动** | M |
| — | ↳ **✅ 已落地（2026-10-31）** | `Pointer`/`PointerRouter`/`InputConstants` + `UiApp.pickAt` + 合成 mouse 兼容层；门 `probes/widgets/pointer-touch`，变异 7/7。**真触摸输入仍是 G5**（后端不出事件） | Done |
| 2 | 触摸拖动滚动 + 惯性（S1/S2/S3） | 手机上「滚不动」等于不可用 | M |
| — | ↳ **✅ S1/S2/S3 已落地（2026-10-31）** | `TouchScrollable` + `ScrollViewWidget` 的 1:1 拖动/轴锁/press 撒回 + 惯性（按 dt 积分，`momentum`/`decelerationRate`）+ **越界回弹**（`overscroll: "rubber"\|"none"`，iOS 曲线阻尼、释放后按 dt 弹簧回位、**作者态 `offsetY` 全程不出界**，拉伸另报 `overscrollY`）；门 `probes/widgets/touch-scroll`，变异 **14/14**。**S4 分页、S5 嵌套仲裁仍未做** | Done |
| 3 | `Env`（安全区 / 键盘 / 密度 / hasHover）（E1/E2） | 刘海与键盘一挡，界面就残；且 `hasHover` 决定 103 处 hover 是否该跑 | M |
| — | ↳ **✅ E1/E2 已落地（2026-10-31）** | `Env`/`EnvBase`/`DesktopEnv`/`SafeArea` + `UiApp.bindEnv`（订阅、`hasHover` 一处裁决）+ 根容器的 `safeArea:` 折进 **padding**；门 `probes/widgets/env`，变异 **7/7**。**键盘矩形、`appState`、`reduceMotion`、`isDark` 只有投递、没有消费者**（S7/E5/E7/E8） | Done |
| 4 | `navStack` + `appBar` + `tabBar`（C1/C2/C3） | 现在**没有"页面"概念**，手机上没有返回栈 | L |
| — | ↳ **✅ C1/C2/C3 已落地（2026-10-31）** | `navStack`（页常驻挂载 + `visible` 切换、每页 `absolute/inset:0/pct(1)` 由工厂强加、`onBack` 只表达意图）+ `appBar`（三槽 `row` 布局、`large` 标题按 `collapse` 一个数收进 compact 行、收的是 **CLIP**）+ `tabBar`（`flexGrow:1` 等分 cell、选中态是 cell 的 text-tint patch、每格报**自己的** index）；门 `probes/widgets/{navstack,appbar,tabbar}`，变异 **7/7 · 8/8 · 7/7**。**过渡动画、`safeArea` 底部实测、`tabBar` 指示条仍未做** | Done（骨架） |
| 5 | 触控态样式 + `hitSlop` + `pointerEvents`（P5/P6） | 触摸设备没有 hover；小目标点不中 | S |
| 6 | 列表四件 + 下拉刷新（S6/C4） | 列表只能当展示用，不能当列表用 | M |
| — | ↳ **✅ 一半已落地（2026-10-31）** | `onVisible(first,last)` + `scrollToIndex`（门 `probes/widgets/vlist`，26 项 / 变异 **10/10**）。**`estimated` 变高、`sticky` 吸顶、`refreshControl`(C4) 仍未做** | 部分 |

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
| 软键盘弹出与顶起 | 平台自动 | 键盘矩形 → inset → 滚入视口 | **只投递不消费**：`Env.keyboardRect` 有值有订阅，**没有消费者**（S7 未做）；`SDL_StartTextInput` 已调用 |
| 安全区 | 平台视图自动 | 平台查询 → 环境值 → 根 padding | **✅ 消费侧已落地**：`Env.safeArea` → 根容器 `safeArea: true` 的 padding（E2）；**平台查询仍缺**（B9，桌面全 0） |
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
| kit `.as` 文件 | **187** |
| 注册 kind / 作者工厂 | **41 / 47** |
| `Style` 字段 | **33**（flexbox 子集 + 视觉；**无 grid、无 z-index**） |
| 处理 `MouseEvent` 的文件 | **26 / 187**，**186 处**引用 |
| `hover` 相关引用 | **121 处**（悬停假设遍布控件层；**2026-10-31 起有了一处裁决点**：`UiApp.setHasHover` 由 `Env.hasHover` 驱动） |
| 文档站页数 | **53**（`new DocPage`） |
| 验收门 | **62**（`node tools/gates.cjs`；含 `probes/widgets/pointer-touch`、`touch-scroll`、`env`） |
| `VirtualListWidget` | **202 行**，固定行高 |

**2026-10-31 复核（M0 + M1 前半 + E1/E2 落地后，命令不变）**：kit `.as` **187**；`MouseEvent` 耦合 **26 / 183 文件，186 处**（新增的四件都在输入层，没有把鼠标耦合摊到控件上）；`hover` **121**；`safeArea` **43**（消费侧已接线）；`TouchEvent` **18**；`inertia` **1**（滑行在 `ScrollViewWidget` 里，不再只是注释）。

### 2.2 移动端令牌：全 0

| 令牌 | 命中 | 含义 |
|---|---|---|
| `TouchEvent` / `Multitouch` / `TouchPhase` | **18** / 0 / 0 | **已订正（2026-10-31）**：库内**有**触摸**路由**了（`PointerRouter` 与 `UiApp` 的四个监听），但**平台仍不产生事件**（G5）——「有消费者、没有输入源」这一条要分清；多指与 phase 抽象仍为 0 |
| `safeArea` / `keyboardRect` / `keyboardHeight` | **43** / **8** / 0 | **部分订正（2026-10-31）**：安全区**有消费者**了（`Env.safeArea` → 根容器 padding，E2）；`keyboardRect` 只被**投递**（界面里还没有读它的控件，S7 未做） |
| `stageOrientation` / `Capabilities` / `pixelRatio` | 0 / **5** / **11** | **部分订正（2026-10-31）**：`DesktopEnv` 读 `Capabilities.language` 填 `locale`；`pixelRatio` 是**构造参数**而不是真值（`Capabilities.screenDPI` 在这个运行时是硬编码 96/72，**不可当密度用**）—— 方向仍读不到 |
| `hitSlop` / `pointerEvents` / `longPress` / `pressDelay` | **1** / 0 / **4** / 0 | **部分订正（2026-10-31）**：`longPress` 有常量与计时器（`InputConstants.LONG_PRESS_MS`），`hitSlop` 有 1 处常量（`MIN_HIT_PT`，**尚未接入命中**）；`hitSlop`/`pointerEvents` 的**描述符字段**仍缺，`pressDelay` 仍是常量而不是 per-control 默认值 |
| `navStack` / `appBar` / `tabBar` / `bottomSheet` | 0 / 0 / 0 / 0 | 手机骨架全缺 |
| `rubber` / `pinch` | 0 / 0 | 无回弹、无捏合 |
| `reduceMotion` / `appState` / `screenReader` | **9** / **10** / 0 | **部分订正（2026-10-31）**：`Env` 里**有字段有订阅**（`reduceMotion`/`appState`），但**没有消费者**（E8/E7 未做）；`screenReader` 仍为 0 |
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
| `List` | `vlist` | ~ | **`onVisible` / `scrollToIndex` 已有（S6 一半）**；变高、吸顶仍缺（S6） |
| `Canvas` | （用 `Graphics` 直画） | ✗缺 | 无「画布元素」形态；作者要自定义 kind 才行 |
| `Shader` | — | — | 不做 |
| `WebView` | — | — | 不做 |
| `Video` | — | — | 不做 |
| `Overlay` | `overlay` + `OverlayChrome` | ✓ | 叠放靠 display order（`overlay.as:10`，引擎无 z-index） |
| Safe area | `safeArea:` 选项 + `Env.safeArea` | ✓ | **E1/E2 已落地**：insets → 容器 padding（不缩盒子），桌面全 0；真实平台值仍缺（B9） |
| Keyboard inset | `Env.keyboardRect` | ~ | API 有、订阅有，**消费者没有**（S7：焦点框滚入可见区） |
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
| P1 | `Pointer` 抽象：`{id, x, y, phase, isPrimary, pressure}`，统一 touch/pen/mouse | 24 文件直接吃 `MouseEvent`（174 处） | 新增 `asaot.ui.Pointer` + `PointerRouter`；**合成 mouse 兼容层**（primary → `MouseEvent`）让 41 kind 不改就能被触摸驱动。**✅ 已落地（2026-10-31）**：`Pointer`/`PointerRouter`/`InputConstants` 三件 + `UiApp.pickAt`/`dispatchPointerMouse`；命中用引擎的 `hitTestPoint` 并与 `dispatchMouse` 的 hover 逐个点位对账 | **P0** |
| P2 | 按压语义：`pressDelay`(≈130ms) / `longPress`(≈500ms) / `pressSlop`(≈8pt) / 滑出取消 | `pressed` 由 `MOUSE_DOWN` 直接置位 | 字段进描述符（可覆盖），默认值集中在一处常量；滚动容器内自动走 `pressDelay`。**✅ 已落地（2026-10-31）**：常量集中在 `InputConstants`，滚动容器判定按 kind 走祖先链；**描述符字段覆盖还没做**（值是常量，不是 per-control 默认值） | **P0** |
| P3 | 手势识别器：tap / doubleTap / longPress / pan / swipe / pinch，含**仲裁**（同一时刻一个赢家） | 0 命中 | 识别器只回答「谁赢 + 位移/速度」，**不重解布局**（手势期走 transform / `scrollRect`） | P1 |
| P4 | `claim`（触摸抢占）：控件说「这次触摸归我」，滚动容器据此取消按压 | 现有「临时挂 stage 监听」是鼠标抓取 | 与 S1 同一处；`onStartShouldSetResponder` 的最小等价物 | P1 |
| P5 | 触控态样式：`Env.hasHover == false` ⇒ 103 处 hover 分支不触发；`pressed` 立即反馈 | `UiApp.as:202–225` 从 `MOUSE_MOVE` 派生 hover | **统一裁决**，不是逐控件加 `if`；`hover` 在触摸上转为 `pressed` 或禁用。**✅ 一半已落地（2026-10-31）**：`UiApp.setHasHover(false)` 一处裁决（清空 hover 链 + 合成 move 不许重新派生，探针两向断言）；**触控态样式（hover 转 pressed 的视觉）还没做** | **P0** |
| P6 | 最小命中 44pt + `hitSlop`（四边可不同） | `hitSlop` 0；新修 `numberInput` 是第一个热区 | 透明填充（§2.3②）；做成静态门：每个 kind 的命中矩形 ≥ 44×44 | P1 |
| P7 | 触摸热路径零分配 | AGENTS.md §2.4 的 GC 红线 | move 事件不 new 对象/字符串；指针状态复用同一实例。**部分落地（2026-10-31）**：每个 touch id 复用同一个 `Pointer`，路由判定本身不 new、不拼字符串；**但合成兼容层每派发一次仍要 `new MouseEvent`**（与引擎一次真实事件的量级相同），所以这不是「零分配」，而是「路由不额外分配」；**且本库没有分配计数探针**，因此它是实现约定，不是测量结论 | **P0** |

### 4.2 S —— 滚动与列表

| ID | 事项 | 现状证据 | 改法 | 优先级 |
|---|---|---|---|---|
| S1 | 1:1 触摸拖动 + 取消子项按压 + 抢占 | ~~`ScrollViewWidget.as:32` 自述无动量；`touchDragWords` 0~~ → **✅ 已落地（2026-10-31）**：`TouchScrollable` 三个回调由 `PointerRouter` 调用；拖动开始时**press 被撤回而不是等它变 click**；轴锁按「按下到越 slop 的主导方向」定一次 | 拖动期间把 `pressed` 置灰并取消点击（已做） | ✅ |
| S2 | 惯性（按 dt 积分，不假设 16ms） | ~~`inertia` 只在注释里（2 处）~~ → **✅ 已落地（2026-10-31）**：`getTimer()` 实测 dt，`v *= rate^(dt/16.667)`；glide 是**纯重绘**循环（`markPaint`，不抬布局位）；`momentum`/`decelerationRate` 进描述符（非法值**抛**） | `ENTER_FRAME` + 时间差（用帧驱动的 paint 自走代替，同一语义） | ✅ |
| S3 | 越界回弹（rubber-band）或 Android 拉伸/辉光 | ~~`rubber` 0~~ → **✅ 已落地（2026-10-31）**：阻尼用 iOS 那条 `f(x)=(x·dim·c)/(dim+c·x)`（c=0.55，渐近到视口尺寸），释放后指数弹簧（`SPRING_RATE` 0.72/60Hz 帧，按实测 dt 积分）**收到 <0.5px 即写 0**；`overscroll: "none"` 关掉；滚动条与滚轮**一律硬夹**（离散操作，桌面语义） | 越界阻尼 + 回位动画；终止条件用速度阈值 | P1 |
| S4 | 分页吸附（`paging` / `snap`） | `scrollView` 内 `paging` 只出现 1 次，且在「不做」清单里（`ScrollViewWidget.as:33`） | 轮播/引导页必需 | P2 |
| S5 | 嵌套滚动与轴锁 | 无 | 依赖 P3 仲裁：内层先声明轴，外层让位 | P2 |
| S6 | 列表四件：变高估算 / 吸顶分组 / `onVisible` / `scrollToIndex` | **两件已落地（2026-10-31）**：`onVisible(first,last)`（窗口变化时回调，含首次；惰性加载的钩子）与 `scrollToIndex`（**一次性请求**，改成 change-detection，轮子不会把窗口拽回去）；**`estimated` 变高与 `sticky` 吸顶分组仍为 0** | 剩余两件：变高估算要重写窗口算术（行高不再是常数），吸顶分组要一个**窗口之外**的定位层（当前 `vlist` 是纯裁剪，窗口里只有挂载的行） | P1 |
| S7 | 键盘焦点滚入可见区 | 无 | 依赖 E1 的 `keyboardRect` | P1 |
| S8 | 滚动条移动端化：不常显、滚动时淡入、可隐藏 | 现有 `auto/always/never`（桌面语义） | 加 `"fade"` 取值 | P2 |

### 4.3 E —— 环境 / 键盘 / 文本度量

| ID | 事项 | 现状证据 | 改法 | 优先级 |
|---|---|---|---|---|
| E1 | `asaot.ui.Env`：`safeArea` / `keyboardRect` / `pixelRatio` / `hasTouch` / `hasHover` / `reduceMotion` / `appState` / `isDark` / `locale`，**读即订阅** | ✅ **已落地（2026-10-31）**：`Env`（接口）/`EnvBase`（可写 + compare-before-notify）/`DesktopEnv`（桌面地板）；`UiApp.env` + `bindEnv`（重绑退订、`bindEnv(null)` **抛**）；`hasHover` 接上 `setHasHover` 那唯一裁决点。门 `probes/widgets/env`，变异 7/7 | 平台填充留给 B 组；`pixelRatio` 是**构造参数**（运行时没有 DPR 真值） | ✅ |
| E2 | 安全区消费：**根节点 padding**（或 `safeAreaBox` 容器），不在引擎里散布 inset | ✅ **已落地（2026-10-31）**：`Element.safeArea`（`true` / `"top"` / `["top","bottom"]`，其余**抛**）→ `UiNode` 把 insets **折进 `resolved.padding`**（盒子不缩，背景铺到刘海下），只认声明过的边、不与作者 padding 打架；未声明的节点一行不动 | 只在一处消费（`UiNode.foldSafePadding`）；**没有**复用 `Style.inset` | ✅ |
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
| C1 | `navStack` + `navPage` | 没有页面就没有返回栈 | `pages` 数组 + 当前索引；header 由 appBar 提供；过渡动画独立于布局。**✅ 已落地（2026-10-31）**：`navStack(pages, opts)` + `NavStackNode`（`activeIndex`/-1=栈顶、`onBack` 接 `Keyboard.BACK`）；页面**全部常驻挂载**、只有栈顶 `visible`（这才是"页面状态不丢"的实现），代价写进注释：隐藏页每帧仍参与 measure/arrange | **P0** ；**补强（2026-10-31 第四十六轮）**：BACK 只在**可见**的栈上生效（`visibleChain` 沿 `parent` 查 `visible`） —— 否则「一个 tab 一个栈」的常态组合下一次返回会掀掉所有 tab 的历史；`pages: []` 是合法值（挂 0 个子节点）；**仍缺**：转场动画、边滑返回。 |
| C2 | `appBar` | 页面骨架 | 左/中/右三槽；`large` 变体随滚动收起；安全区顶部内边距。**✅ 已落地（2026-10-31）**：`appBar(opts)` —— `leading`/`title`（String 包成 text）/`trailing` 三槽，`large` 时多一行大标题、`collapse`(0..`largeExtra`) 把它**裁**进 compact 行；高度=56+extra 由 kind 拥有（作者别传 `style.height`） | **P0** ；**补强（2026-10-31 第四十六轮）**：`leading`/`trailing` 接受 **Node 或 Node[]**（>1 自动包成 row，非 Node **抛**） —— 之前 `as Node` 把数组静默丢掉，文档站自己的 `trailing: [icon(...)]` 从未上屏；`safeArea: "top"` 的折回 0 现在会重排（inset 变化显式标脏），bar 47→103→56 两侧都有断言。 |
| C3 | `tabBar` | 手机一级导航 | 底部、图标 + 标签、选中态、安全区底部内边距。**✅ 已落地（2026-10-31）**：`tabBar(opts)` —— `items` 定长、cell 等分（第 5 个 tab 让别的更窄而不是横滚）；String `icon` 是 SVG path 且**由 bar 染色**（Node icon 保留作者颜色）；点当前 tab **仍上报**（"回到本节顶部"才可表达） | **P0** ；**补强（2026-10-31 第四十六轮）**：`items` 缩短时删掉的格子**不在树上**（不是变透明）；Node icon 保留作者颜色（bar 只染字符串路径）；`safeArea: "bottom"` 34→90→56 两侧断言，且底部那条带是 **bar 自己的背景**（inset 是 padding，不是缝）；**仍缺**：指示条。 |
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

桌面实现：`safeArea` 全 0、`keyboardRect` 全 0、`hasHover = true`、`hasTouch = false`、
`appState = "active"`、`isDark = false`、`reduceMotion = false`、`locale = Capabilities.language`。
**平台填充只改实现，不改接口。**

**落地口径（2026-10-31）**：上面这份形状是 `kit/asaot.ui.Env` 的**逐字实现**，另有
`EnvBase`（九个值 + 九个 compare-before-notify writer + `Observable` 订阅）和 `DesktopEnv`
（桌面地板）。三处与本节的原始设想不同，都是**实测后改的**：

- `pixelRatio` **不是**「读 `Stage` 的物理/逻辑比」——运行时没有这个 API 可读：
  `Capabilities.screenDPI` 是硬编码 96（Windows）/72（其余）常量，窗口后端的 `ASC_win_scale`
  是 C 侧全局。所以它是**构造参数**，默认 1；拿 `screenDPI` 反推等于编一个数。
- `hasTouch` 同理：`Capabilities.touchscreenType` 在这个运行时也是硬编码 `"none"`。
- `DesktopEnv` 只有 `locale` / `appState` / `hasHover` 三个**真值**，其余是**诚实默认**，
  写在这份文档里而不是藏进注释（见 `DesktopEnv.as` 头部）。

**消费侧今天只有两条**：`hasHover` → `UiApp.setHasHover`（103 处 hover 分支的唯一裁决点）；
`safeArea` → 根容器 padding（E2）。其余七个**只投递**：`keyboardRect`(S7)、`appState`(E7)、
`isDark`(E5)、`reduceMotion`(E8)、`locale`(E6)、`pixelRatio`/`hasTouch`（B9/B5）。

### 6.4 描述符新增字段（与 `Widget` 契约一致）

| 字段 | 加在 | 默认 | 谁读 |
|---|---|---|---|
| `pressDelay` | 所有可压元素（`Element`） | `InputConstants.PRESS_DELAY_MS` | `UiApp` 指针路由 |
| `longPress` | 同上 | `500` | 路由 |
| `onLongPress` | 同上 | `null` | 作者 |
| `hitSlop` / `hitSlopEdges` | 同上 | `0` | `Widget.measure`（画透明填充） |
| `pointerEvents` | 同上 | `"auto"` | 绑定阶段写 `mouseEnabled`/`mouseChildren` |
| `presentation` | `select` / `menu` / `popover` / `datepicker` | `"popover"` | 工厂：小屏选 `"sheet"` / `"fullscreen"` |
| `safeArea` | 根容器（任何 Element 都接受） | `"none"` | ✅ **已实现**：`true` / 边名 / 边名数组 → 折进 padding；`UiNode.foldSafePadding` |
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
| **M0 触摸可路由** | P1/P2/P5 + 合成 mouse 兼容层 | 新增 `probes/widgets/pointer-touch`：用**合成 touch 序列**驱动 chip/button/switch；现有 `probes/widgets/*` 在触摸驱动下全绿。**2026-10-31：前半已达成** —— 探针在门里，驱动 button 的 tap / 拖拽 / scroller 延迟 / 取消 / hover 两态，变异 7/7；**「现有全部探针改触摸驱动」还没做**（它们仍走 `dispatchMouse`） |
| **M1 可滚** | S1/S2/S3 | 确定性回放：一次 fling 的位移曲线与手算表一致；越界回弹回位误差 < 1pt。**2026-10-31：S1/S2/S3 全部达成** —— S3 的「回位误差 < 1pt」是**字面成立**（弹簧在 0.5px 处直接写 0，误差为 0，不是「小于 1」），且拉伸本身有像素证据（回弹时视口底部露出的是**视口自己的背景**，不是内容）。原 S1/S2 说明：**2026-10-31：S1/S2 已达成** —— `probes/widgets/touch-scroll` 钉 1:1 位移（20pt→20px 精确）、slop 不滚动、轴锁、press 撒回、`momentum:false` 停在释放点、拖动越界钉在 180、程序化滚动取消滑行，变异 10/10；**S3 回弹（2026-10-31）已补上**，「回位误差 < 1pt」现按字面验收；位移曲线只用「更远 / 不越界 / 最终停下」三条粗断言（精确距离是帧时钟的函数，钉死它等于钉死机器的忙闲） |
| **M2 有环境** | E1/E2/E7 | 模拟 `safeArea=(47,0,34,0)` + `keyboardRect` 后，根 padding 与「输入框滚入可见区」逐项断言。**2026-10-31：E1/E2 已达成** —— `probes/widgets/env` 用 FakeEnv 把同一棵树推过 47/0/34/0 → 全 0 → 仅底 34 → 再回 47，逐项断言根 padding（51/4/38/4）、盒子不缩、未声明的子节点不动、只认声明过的边，并钉「一次平台改动 = 一次通知」与重绑退订；变异 7/7。**`keyboardRect` 与「滚入可见区」没做（S7）**，`appState` 停帧也没做（E7），所以这条**只算三分之二** |
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
node tools/gates.cjs                    # 65 道门（含本文 M0 的 pointer-touch、M1 的 touch-scroll、M2 的 env）
```

> 本文**不给门的绿/红判断**（只做静态计数与代码事实）。上一次全量落盘是
> `reviews/gates-all-39.txt`（**58/58**，尚未含这两道新门）；此后工作树有并发改动
> （另有会话在改 `as3compiler/`），要引用门的结论请当场重跑。

**M0 的落地证据（2026-10-31，`asaotui/` 内，未改编译器一行）**

| 项 | 结果 |
|---|---|
| `probes/widgets/pointer-touch` | **PASS / 0 failures**。合成 touch 序列驱动 button（press + click）、scroller 内 button（130ms 延迟 press 后仍可点）、取消序列（不留 press 槽）、hover 两态（`hasHover=false` 无 hover；`true` 时恢复，且合成的 move 不许自我确认） |
| 变异 `probes/widgets/pointer-touch/mutation.cjs` | **7/7 全中**：合成事件改投 stage / 每个 press 都延迟 / 不延迟 / slop 不再否决点击 / 去掉 synthetic 守卫 / `pickAt` 不问引擎 / 取消后不释放 press 槽 |
| pick 与引擎对账 | 4 个点位（三个控件中心 + 根 padding）上 `UiApp.pickAt(x,y)` 必须等于引擎 `dispatchMouse` 派生出的 hover 节点 —— 这是「触摸不许自造第二套命中规则」的**测量**，不是声明 |
| 仍然缺的 | 真触摸（G5：后端不出 `TouchEvent`）、`hitSlop`/44pt 最小命中（P6）、触控态视觉（P5 后半）、`Env`（E1）、手势仲裁（P3）、多指（P4） |

**M2 前半的落地证据（2026-10-31，仍未碰编译器）**

| 项 | 结果 |
|---|---|
| `probes/widgets/env` | **PASS / 0 failures**（43 checks：8 条矩形 ×4 + 8 个像素点 + 程序内 30 余条状态断言）。树的根是 `column(padding 4, safeArea: true)`，绑定 FakeEnv `(47,0,34,0)` 后再 `mount` |
| 根 padding | `4+47=51` / `4` / `4+34=38` / `4`，且**盒子仍是 320×240**（inset 进 padding，不是缩小窗口） |
| 只认声明过的边 | `safeArea: ["top"]` 的节点在**只有底边**变化时一行不动；`safeArea: false` 的节点始终是作者 padding |
| 平台改动的往返 | 47/0/34/0 → 全 0 → 仅底 34 → 47/0/34/0，每一步都落到矩形上；**一次平台改动只产生一次通知**（`EnvBase` 的 compare-before-notify） |
| 重绑 | `bindEnv` 换 env 后退订旧的（旧 env 再 `notify` 打不到 app）、重复绑同一个不叠订阅；`bindEnv(null)` **抛** |
| `hasHover` | `false` ⇒ 链接清空、指针移动不许复活、整棵树的 hover 态归零；`true` ⇒ 恢复（复用了 `pointer-touch` 那条钉子） |
| 变异 `probes/widgets/env/mutation.cjs` | **7/7 全中**：不折 inset / 每个节点都宣称四条边 / inset 落到错误的边 / 不从 Env 取 `hasHover` / 重绑不退订 / 改动不唤醒帧 / 桌面地板编一个安全区 |
| 仍然缺的 | 真平台数值（B9）、`keyboardRect` 的消费者（S7）、后台停帧（E7）、`reduceMotion`（E8）、`isDark`（E5）、locale/RTL（E6） |

**M1 的落地证据（2026-10-31，同一轮继续，仍未碰编译器）**

| 项 | 结果 |
|---|---|
| `probes/widgets/touch-scroll` | **PASS / 0 failures**（26 checks）。六行 40px 内容装 60px 视口（range 180）：20pt 手指 → **20px** 内容（精确）、越 slop 的那 8pt **不滚**、拖动开始时 press **被撒回**、横向滑动**不动竖向列**、`momentum:false` 停在释放点（精确 20）、拖动越界钉在 180、程序化滚动**取消滑行**、手指落下**冻住**滑行、滑行最终**自己停下** |
| 变异 `probes/widgets/touch-scroll/mutation.cjs` | **10/10 全中**：半速拖动 / 反向拖动 / 锚在按下点 / 不撒 press / 忽略 momentum / 强制 momentum / 不锁轴 / 不夹边界 / 程序化滚动不取消滑行 / 手指落下不停滑行 |
| 刻意的粗断言 | 滑行的**距离**不钉（它是帧时钟的函数）；只钉「更远 / 不越界 / 最终停下」+
`momentum:false` 的**精确相等**。把距离钉死等于把探针焊在机器的忙闲上 |
| 仍然缺的 | 真触摸（G5）、分页吸附（S4）、嵌套轴仲裁（S5）、`hitSlop`（P6）、触控态视觉（P5 后半）；**回弹越界（S3）已补（2026-10-31）** |

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