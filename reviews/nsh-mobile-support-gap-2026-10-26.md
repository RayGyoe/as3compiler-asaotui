# NSH（nsh.dev）评估 + asaotui 手机端（iOS / Android）缺口与路线

> 日期：2026-10-26 · 工作树：`asaotui/`（未改 `as3compiler/` 一行）
>
> 本文分三件事，别混读：
> 1. **§1–§2 是评估**：`nsh.dev` 到底是什么、它和 GPUI 什么关系、它哪些决定值得我们借。
> 2. **§3–§4 是缺口盘点**：把「手机端能跑」拆成可立项的条目（B / I / S / E / C / A / V 七组），
>    每条标「证据」与「是否已实测」。
> 3. **§5–§7 是路线与红线**：三条可选路径、里程碑验收、以及**不要做**的事。
>
> 纪律（沿用 `compiler-gaps.md` §0）：区分「**AIR 遗留欠账**」（AIR 有、我们没有 ⇒ 缺陷）与
> 「**增强**」（AIR 无对应物）；区分「**已实测**」与「**仅代码事实**」。本文所有代码事实都在
> 2026-10-26 当场用扫描脚本复核过，命令见 §9。

---

## 0 一句话结论

> **NSH 不是 GPUI 的替代品，也不是我们该照抄的架构**（它把每个平台的**原生视图**当后端，
> 因此安全区、软键盘、手势、无障碍、列表复用全部由平台免费提供）。它的价值是**一张清单**：
> 它把我们自绘路线下必须自己做的每一件事都做了一遍，因此可以当「手机端验收表」用。
>
> 我们的真实短板不在控件数量（37 个 kind / 33 个样式字段 / 43 页文档站，比 NSH 的可移植部分
> 不弱），而是三条**地基**：
> **(1) 输入层根本没有触摸**（`TouchEvent` 类有、输入源没有，全库 0 命中）；
> **(2) 平台壳不存在**（`Target` 只有 `native | wasm`，`android-project` 直接 throw，Skia 无
>     ios/android 产物，SDL2 也无）；
> **(3) 移动端的环境事实拿不到**（安全区 / 软键盘矩形 / 屏幕密度 / 字号缩放，0 命中）。
> 控件缺的是**导航结构**（navStack / tabBar / appBar / bottomSheet / refresh / swipeable）与
> **滚动物理**（惯性 / 回弹 / 吸附），不是再攒一批按钮。

---

## 1 先厘清对象：`nsh.dev` 不是 GPUI

| 项 | 事实 | 出处 |
|---|---|---|
| NSH 是什么 | **Native Shell**：一套「Rust/TSX 写，逐平台原生视图渲染」的应用框架 | `nsh.dev/zh-CN/docs/` 首页 + `platforms.md` |
| 它与 GPUI 的关系 | **GPUI 是它的一个后端**（`gpui.md`），不是它的上位 | `docs/gpui.md` |
| GPUI 是什么 | Zed 的 Rust UI 框架（自绘 + Taffy 布局 + 自己的元素树） | 同页对照 |
| 我们与两者的关系 | `asaotui/reviews/` 里已有的 `ui-toolkit-feasibility{,-en}.md`、`u1-scope.md`、`gpui-borrow-map.md` 评估的是 **GPUI**（借 Style/refine、keyed identity、actions+keymap；不借每帧重建整棵树） | 工作区既有文档 |

⇒ **本次新增的是 NSH 这一份**：它和 GPUI 是「同族不同路」——GPUI 自绘（像我们），NSH 用原生视图
（不像我们）。所以读 NSH 的正确姿势不是「抄它的控件」，而是**抄它的清单与约束**：哪些事在手机上
必须有、原生后端免费给、自绘后端必须自己造。

---

## 2 NSH 值得我们借的 7 条（每条附我们的现状）

### 2.1 逐平台原生视图 ⇒ 成本转移表

NSH 的后端是 UIKit+CoreText / Android Views+StaticLayout / AppKit+CA / Win32+Direct2D+DirectWrite /
GTK4+Pango / 浏览器 DOM。**后端之上全部共享**（响应式图、渲染器、Taffy 布局、组件库、原生模块）。

它这样换来的是：滚动、软键盘、安全区、手势、无障碍、文本选择、列表复用 —— **全部由平台负责**。

我们自绘（Skia），所以同一张表在我们这里是**反向**的：

| 能力 | NSH 谁做 | 我们必须自己做的部分 |
|---|---|---|
| 滚动惯性 / 回弹 / 吸附 | UIScrollView / ScrollView 免费 | 物理 + 触摸拖动 + 与按压竞争（`ScrollViewWidget` 源码自述「no momentum / inertia / elastic overscroll」） |
| 软键盘弹出与顶起 | 平台自动 | 键盘矩形 → inset → 滚入视口 → 键盘工具栏 |
| 安全区 | 平台 view 自动 | 平台查询 → 环境值 → 布局/绘制多处消费 |
| 手势（拖动/捏合/旋转） | 平台识别器 | 识别器 + 仲裁 + 轴竞争 |
| 无障碍树 | 平台自动（真实视图层级） | **桥**（自绘树的语义树 → 平台 a11y 节点） |
| 文本选择/光标手柄/复制菜单 | 系统文本控件 | 自绘选区 + 手柄 + 菜单（或挂原生隐藏输入框） |
| 列表复用/吸顶/可见性回调 | 平台列表 | 已有行复用（`vlist`），**缺吸顶 / 分组 / 可见性 / 变高** |
| 页面栈 / 侧滑返回 / 预测性返回 | UINavigationController / 平台返回键 | 自建栈 + 过渡动画 + 返回键映射 |

**这张表就是 §4 的骨架。** 它同时说明：手机端的成本**主要不在控件层**，而在「平台把什么免费给了
NSH、我们得自己补」的那 8 行。

### 2.2 主线程从不等待应用代码 ⇒ 所有「系统要同步答案」的问题都用**声明式属性**回答

NSH 明说不让平台等应用（JS/Rust）算一个答案再继续。凡是系统会同步问的问题，一律由**属性**回答：

| 系统问的问题 | NSH 的答案 |
|---|---|
| 还能再输入一个字符吗 | `maxLength` |
| 侧滑返回允许吗 | `popOnBack` |
| 点击空白是否收起键盘 | `keyboardShouldPersistTaps` |
| 触摸热区是否大于绘制区 | `hitSlop` |
| 手势轴冲突谁赢 | `panActivation` |
| 该元素是否存在于无障碍树 | `accessibilityElementsHidden` / `importantForAccessibility` |

**对我们的直接结论**：手机端的每一个阈值（触摸容差、按压延迟、长按时长、刷新阈值、滑动操作阈值）
**必须是描述符字段（有默认值、可被 Style/属性覆盖）**，不能藏在 widget 里的硬编码常量；也**不允许**
在触摸事件里回调应用代码再等它回答（那会在真实设备上掉帧）。这一条可以直接写成一条 **gate**：
「kit 内不得出现未在描述符里声明的触摸阈值字面量」。

### 2.3 触摸三层模型（这是 NSH 最有借鉴价值的一页）

| 层 | NSH 的做法 | 我们的等价物 |
|---|---|---|
| L1 按压 | `on_press` / `on_long_press` / `active` 反馈**由原生绘制** | 已有 `pressed`/`active`（但由 `MOUSE_DOWN` 驱动）；需补**触摸语义**：滑出取消、滚动容器内延迟、长按 |
| L2 原生手势 | 拖动/捏合/旋转在 UI 线程**直接驱动动画值**，应用忙也不掉帧 | 需要「手势 → transform 通道」：**手势期间不解布局**（我们已有 scrollRect/Anim 的雏形） |
| L3 原始触摸 | `on_touch` / `claim_touches` / 响应者链 / `PanResponder` | 需要 `TouchEvent` 路由 + 声明式夺取（claim） |

⇒ 我们不需要三层都做全，但**L1 与 L2 必须做**：只做 L1 会「点了没反馈、拖动不跟手」；只做 L3 会
「每个控件自己处理原始触摸」，这正是 NSH 明确避开的写法。

### 2.4 虚拟列表由原生驱动，且**行函数按位置重跑**（复用单元格）

NSH：`virtual_list(count, row)`，按单元格复用、`estimated_item_size`、多列、吸顶、倒置（聊天）、
横向、`onVisible`、`scrollTo`；复用带来两条规则（行内读位置处原地更新）。

我们：`vlist` 已有**行复用**（`RH_KEY`/`COUNT_KEY`/`OFF_KEY`，固定行高，滚轮 3 行/格），但扫描确认
**没有** `estimated`（变高）、`onVisible`、`scrollToIndex`、吸顶（`sticky` 仅 1 处且在表格）。

⇒ 手机列表的「必备四件」是：**变高估算 / 吸顶分组 / 可见性回调 / 程序化滚动**。这四件不做，
列表就只能当展示用。

### 2.5 导航栈 / 对话框 / 返回键是**平台语义**，不是自绘弹层

NSH：`nav_stack()` 在 iOS 就是 `UINavigationController`（标题栏、侧滑返回、大标题），Android 是页面栈 +
工具栏 + **预测性返回**；`dialog()` / `alert_dialog()` 是平台对话框；桌面与 Web 才自绘标题栏。

我们：**完全没有路由概念**（37 个 kind 里没有 navStack / page / appBar / tabBar）；`dialog`/`drawer`
是**第二棵保留树**里的浮层；`Keyboard.BACK`（0x01000016）在符号表里存在，但没有任何返回键处理路径。

⇒ 手机端第一结构缺口就是「页面」这个概念：标题栏、返回、页面过渡、每页状态保持、系统返回键 /
侧滑返回。文档站现在靠「换 `DocsModel` 的当前页 + 重建内容」模拟，这在桌面上够用，在手机上是
**没有返回栈**的。

### 2.6 设备与环境是**响应式访问器**，不是监听器 + 全局状态

NSH（`device-and-environment.md`）：`window()/windowSize()`、`dark()/colorScheme()`、
`font_scale()/fontScale()`、`safe_area()/safeArea()` 与 `cx.insets()`、**`keyboard_height()` /
`keyboardFrame()`**、`locale()`、`reduce_motion()/screen_reader()` —— 读它的样式/文本/计算值
**自动更新**，无需挂监听。

我们：`Stage` 层面 0 命中（`softKeyboardRect` / `stageOrientation` / `autoOrients` /
`supportsOrientationChange` 在 `emit.ts` 全部为 0），kit 侧 0 命中（`safeArea` / `keyboardHeight` /
`pixelRatio` / `Capabilities`）。

⇒ 需要一个 `Env` 层（纯 AS3 接口 + 平台填充），并且要能被 **render() 直接读**（读即订阅），
否则每个控件都要自己挂 `Stage` 监听、自己记状态。

### 2.7 无障碍：真实视图层级 + 描述属性

NSH 的 a11y **几乎免费**（视图就是平台视图），只需补 `label`/`hint`/`role`/`accessibilityState`
（disabled/selected/checked/busy/expanded，`checked:"mixed"` 半选 + 一条独立样式）/`accessibilityValue`
/ `accessibilityActions` + `onAccessibilityAction` / `accessibilityElementsHidden` /
`importantForAccessibility`；纯文本自动朗读、带 press 处理器自动成为无障碍元素、字号跟随系统。

我们：`compiler-gaps.md` **G2** 已登记 `flash.accessibility.*` 整包缺失（= AIR 遗留欠账，非增强），
`u1-scope.md` 明确「不做 `flash.accessibility`」。kit 内 `accessibility` 仅 2 处（`Element.as`
的注释）。**这是手机上唯一「不做就等于残障用户不可用」的一组**，且它是**自绘路线最贵的一项**
（NSH 免费，我们全自建）。

---

## 3 我们现状（2026-10-26 当场核对）

### 3.1 库（`asaotui/kit`）

| 指标 | 值 | 复核 |
|---|---|---|
| `.as` 文件 | **163** | 扫描 |
| 注册 kind | **37**（accordion…vlist） | `Widgets.register("…")` |
| 样式字段 | **33**（flexbox 子集 + 视觉） | `style/Style.as` `public var` |
| 处理 `MouseEvent` 的文件 | **19 / 163**，引用 **129** 处 | `tools/mobile-gap-scan.cjs` |
| `hover` 相关引用 | **72** 处（悬停依赖遍布控件层） | 同上 |
| 文档站页数 | **43**（`new DocPage`），注释仍写 42 | `DocsCatalog.as` |
| 触摸 / 多点 / 安全区 / 键盘高度 / 密度 / 方向 / 无障碍 | **全部 0** | `tools/mobile-gap-scan.cjs` |
| 滚动物理 | 自述「no momentum/inertia/elastic overscroll」 | `ScrollViewWidget.as` |
| 列表 | 固定行高 + 滚轮；无吸顶/可见性/变高/scrollTo* | `VirtualListWidget.as`（202 行） |
| 导航 | 无 navStack/page/appBar/tabBar | kind 表 |
| 浮层 | 第二棵保留树（`renderOverlay()` + `overlayRoot`），**无 z-index**（`lifted` 改 reparent） | `overlay.as:11` |

### 3.2 编译器 / 后端（`as3compiler`，只读核对）

| 项 | 事实 |
|---|---|
| 目标 | `export type Target = 'native' \| 'wasm'`（`src/build.ts:24`）——**没有 ios/android** |
| 打包 | `raw \| xcode-project \| android-project \| web`；`android-project` 在 `index.ts` **直接 throw "not yet implemented"**；`xcode-project` 仅 macOS |
| 窗口后端 | SDL2（`vendor/window_glue.cc`，3320 行）：`SDL_FINGER*` **0**；无安全区/键盘矩形查询；IME 走 `SDL_TEXTEDITING` + `SDL_SetTextInputRect`（**桌面 IME 通道是通的**） |
| 帧时钟 | 全应用一个 frame clock，`SDL_RENDERER_PRESENTVSYNC`，`frameRate<=0` 跟随显示刷新率 |
| Web 后端 | `vendor/web_glue.cc`：只挂 `mousedown/mouseup/mousemove/mouseleave/wheel`；`on_key` 被 **丢弃**（`(void)on_key`）⇒ **浏览器里不能打字**；`touchstart/pointerdown/keydown` 全仓 0 |
| 字体 | `sk_platform_fontmgr()`：wasm = 注入字节；Windows = GDI+DirectWrite 双档；**其他一律 `SkFontMgr_New_CoreText`**（iOS 可用，Android 不可用） |
| 预编译产物 | `vendor/skia/lib`：`macos-arm64 / wasm / windows-x64 / windows-x86`；`vendor/sdl2` 同 —— **无 ios / android** |

### 3.3 现有验收工具的状态提醒

`reviews/gates-all-33.txt`（最新落盘）是 **27/54 PASS** 的红跑（多门 `exit 2`），与 README 的「54/54」
不一致。按 `STATUS.md` §3.3 的既有教训，先怀疑**并发会话 / 编译器树被动过**，不要当成库的红，
也**不要**在本文的结论里引用它。今天没有重跑全量门（本任务只读核对），故本文不给出门的绿/红判断。

---

## 4 缺口清单（可立项条目）

编号规则：`B`=后端/编译器，`I`=输入与手势，`S`=滚动与列表，`E`=环境/键盘/文本，`C`=组件，
`A`=无障碍，`V`=验收工具。**P0**=不做则手机上跑不起来；**P1**=不做则「能跑但不像手机应用」；
**P2**=体验；**P3**=打磨。

### 4.1 B —— 后端 / 编译器（**不属于 asaotui，必须由编译器项目立项**）

| ID | 条目 | 现状证据 | 判定 | 优先级 |
|---|---|---|---|---|
| B1 | `Target` 增加 iOS / Android 交叉编译行（sysroot / `-arch` / `-isysroot` / NDK clang 路径） | `build.ts:24`；现有 `native` 行按宿主平台挑库 | 工具链缺口 | P0 |
| B2 | Skia 为 iOS（arm64 + sim x86_64/arm64）与 Android（arm64-v8a / armeabi-v7a / x86_64）产出静态库 | `vendor/skia/lib` 无对应目录 | 工具链缺口 | P0 |
| B3 | SDL2 为 iOS / Android 产出（或改走原生壳：`UIView`+`CAMetalLayer` / `SurfaceView`+`ANativeWindow`） | `vendor/sdl2/lib` 无对应目录 | 工具链缺口 | P0 |
| B4 | 平台 glue：iOS `UIApplicationDelegate` + `UIView`/`CAMetalLayer`；Android `ANativeActivity` + `ANativeWindow` + EGL；生命周期（前台/后台/内存警告/旋转） | 现有 glue 只有 Cocoa/Win32/X11 分支 | 工具链缺口 | P0 |
| B5 | 触摸输入：`SDL_FINGER*`（或原生 `touchesBegan/Moved/Ended/Cancelled`、`MotionEvent`）→ **`flash.events.TouchEvent` + `Multitouch`**，含 pointerId、pressure/size、`Multitouch.maxTouchPoints`、`mapTouchToMouse` 语义 | **G5** 已登记「类有、无输入源」；`TouchEvent` 形状在 `emit.ts:11987` 起 | **AIR 遗留欠账** | P0 |
| B6 | 软键盘：`Stage.softKeyboardRect`（AIR 有该 API）+ 键盘类型/回车键 + `SDL_SetTextInputRect` 的移动端等价 | `softKeyboardRect` 在 `emit.ts` **0** 命中 | **AIR 遗留欠账** | P1 |
| B7 | 安全区 / `Stage` 方向族：`safeAreaInsets`（AIR **无**此 API ⇒ 增强）、`stageOrientation` / `autoOrients` / `supportsOrientationChange`（AIR 有 ⇒ 欠账） | 三者 `emit.ts` 均 0 命中 | 混合（见判定） | P1 |
| B8 | 屏幕密度：`Capabilities.screenDPI` 已有（`emit.ts:33743`），但需在移动端**真值**（而非桌面近似）+ `Screen` 逻辑点数 | 代码有出口 | 欠账（实现未覆盖移动） | P1 |
| B9 | Android 字体管理器 `SkFontMgr_New_Android`（FreeType + 系统 fontconfig）或内置 Noto 兜底 | `sk_platform_fontmgr()` 三档：wasm 自定义（`skia_glue.cc:206`）/ Windows GDI+DirectWrite（`:448`）/ **其余一律 CoreText**（`:461`） | 工具链缺口 | P0 |
| B10 | 打包：iOS `.app`/`.ipa`（签名、Info.plist、启动图、方向、权限）、Android `.apk`/`.aar`（16 KB 对齐、manifest） | `android-project` 直接 throw；`xcode-project` 仅 macOS | 工具链缺口 | P0（能跑）/ P1（能发） |
| B11 | Web/mobile 浏览器臂：`pointerdown/move/up/cancel` + `touch-action` + `visualViewport` + `env(safe-area-inset-*)` + `keydown` | `web_glue.cc` 只挂 mouse/wheel，`on_key` 被丢弃 | 缺口（自绘 web 臂不自洽） | P1 |
| B12 | 返回键：Android back / iOS 侧滑手势 → `Keyboard.BACK`（符号已存在）或专有事件 | `Keyboard` 符号表有 `BACK`；无任何后端派发 | 缺口 | P1 |
| B13 | 触觉反馈（`HapticFeedback`） | AIR 无 ⇒ 增强 | 增强 | P3 |

> **纪律提醒**：`asaotui` 的既有规矩是「撞到编译器缺口只登记、不动 `as3compiler/`」。B1–B12 因此
> **不能**在 asaotui 里做；本表的用途是给编译器项目**开阶段**的清单（对应 `compiler-gaps.md` §5 的入口）。

### 4.2 I —— 输入与手势（库，纯 AS3）

| ID | 条目 | 现状 | 说明 | 优先级 |
|---|---|---|---|---|
| I1 | `asaot.ui.Pointer` 抽象：统一 touch / pen / mouse 为 `{id, x, y, phase, isPrimary}`，控件按需订阅 | 20 个文件直接吃 `MouseEvent` | 迁移期允许「touch→合成 mouse（primary）」兼容层，让 37 个 kind 先不改 | P0 |
| I2 | 按压语义：`pressSlop`（≈8dp）、`pressDelay`（≈100ms，滚动容器内）、滑出取消、`longPress`（≈500ms） | 现在 `MOUSE_DOWN` 即 pressed | 必须**声明式**（§2.2） | P1 |
| I3 | 手势识别器：tap / double-tap / long-press / pan / pinch / rotate / swipe / edge-swipe；含**仲裁**（同一时刻只有一个赢家） | 0 命中 | 先做 tap/pan/long-press/swipe 四个 | P1 |
| I4 | `claim`/捕获：控件声明「这次触摸归我」，滚动容器据此取消按压 | 现有「临时挂 stage 监听」是鼠标抓取；无触摸抢占 | 与 S1 同一处 | P1 |
| I5 | 触摸态样式：`pointer: coarse` ⇒ 无 hover、pressed 立即反馈、focus ring 只在外部键盘出现 | kit 内 `hover` 引用 **72** 处；`Style` 无 hover 能力查询；`hover` 由 `UiApp` 从 `MOUSE_MOVE` 派生（`UiApp.as:191-214`） | 需要 Env 提供 `hasHover`/`hasTouch`；触摸设备上这些 hover 分支**全部不触发** | P1 |
| I6 | 最小命中尺寸（44×44pt / 48×48dp）+ `hitSlop` | 无 | 可做成 gate（kind 覆盖率报告） | P2 |
| I7 | 触摸热路径零分配（move 事件不得 new 对象/字符串） | 撞 GC 红线（AGENTS.md §2.4） | 触摸 move 频率是鼠标的 2–3 倍 | P0 |

### 4.3 S —— 滚动与列表

| ID | 条目 | 现状 | 说明 | 优先级 |
|---|---|---|---|---|
| S1 | 触摸拖动滚动（1:1 跟手）+ 取消按压 + 抢占用手指 | 现为「临时挂 stage 的 MOUSE_DOWN/UP/MOVE」；`wantsPress()` 返回 false | 手机上手势第一入口 | P0 |
| S2 | 惯性与衰减（`decelerationRate` 语义，iOS 0.998/ms 量级；按 dt 积分，不假设 16ms） | 自述「no momentum」 | 需 dt 驱动（`ENTER_FRAME` + 时间差） | P1 |
| S3 | 边界回弹（rubber-band，越界阻尼）+ 越界回位 | 无 | 可选：Android 风格用拉伸/辉光替代 | P1 |
| S4 | 分页吸附（`paging` / `snap`） | 无 | 轮播/引导页必需 | P2 |
| S5 | 嵌套滚动（外层 page 内的横向 carousel / 内层长列表） | 无 | 依赖 I3 的仲裁 | P2 |
| S6 | 列表：变高估算、吸顶分组头、`onVisible`、`scrollToIndex`、加载更多钩子 | `vlist` 202 行，固定行高、无上述四项 | 手机列表的四件套（§2.4） | P1 |
| S7 | 键盘焦点滚动：输入框获得焦点时滚入可见区 | 无 | 依赖 E1/E2 | P1 |
| S8 | 滚动条移动端化：默认不常显、滚动时淡入淡出、可隐藏 | 现有 `auto/always/never`（桌面语义） | 小改 | P2 |

### 4.4 E —— 环境 / 键盘 / 文本

| ID | 条目 | 现状 | 说明 | 优先级 |
|---|---|---|---|---|
| E1 | `asaot.ui.Env`（纯 AS3 接口）：`safeArea`、`keyboardRect`、`fontScale`、`pixelRatio`、`isDark`、`locale`、`rtl`、`hasHover`、`reduceMotion`；**读即订阅** | 全 0 | 平台填充由后端做（B6/B7/B8）；桌面实现读 `Stage`/`Screen` 回退 | P0 |
| E2 | 布局消费安全区：安全的做法是给根节点 padding（或 `safeAreaBox` 容器），**不要**在引擎里散布 inset | 无 | 避免「引擎级 inset」污染 flexbox 语义 | P1 |
| E3 | 文本输入移动化：键盘类型 / 回车键 / 自动大写 / 自动更正 / 密码 / 多行自适应；光标与选区手柄；长按选择菜单 | 现自绘 textField + 桌面 IME 通道 | 两条路：**(a)** 隐藏原生输入框镜像文本（Flutter 路线，拿全平台能力）；**(b)** 只用 `SDL_TEXTINPUT`（快，但无手柄/自动填充）| P1 |
| E4 | 字号缩放（动态字体）：`fontScale` 参与文本度量与行高，改变后重排 | 无 | 与 `DocSection.height()` 那一类「手算高度」逻辑冲突 ⇒ 需一起改 | P2 |
| E5 | 深色跟随系统 | 现在只有库内 `Theme` | 读 Env 即可 | P2 |
| E6 | RTL / locale | 无 | 与 flexbox `row` 方向耦合，建议单独立项 | P3 |
| E7 | 前后台与降频：进入后台停 `ENTER_FRAME`/动画，回来补 delta | 无 | 否则后台烧电、回来「跳帧」 | P1 |
| E8 | 减少动效（`reduceMotion`） | 无 | 读 Env | P2 |

### 4.5 C —— 组件

**C-a 必须新增（手机骨架，现 0 命中）**

| ID | 组件 | 为什么必须有 | 优先级 |
|---|---|---|---|
| C1 | `navStack` / `page`（栈、标题栏、返回、页面过渡、每页状态保持、与系统返回/侧滑返回联动） | 现在**没有路由**；文档站靠换 model 模拟 | P0 |
| C2 | `appBar`（标题/大标题/左返回/右动作/随滚动收起/与安全区联动） | 页面骨架 | P1 |
| C3 | `tabBar`（底部标签栏；现有 `tabs` 是顶部分段控件，语义不同） | 手机一级导航 | P1 |
| C4 | `bottomSheet`（拖拽把手、半开/全开吸附、下滑关闭、scrim、与安全区） | 现在的 `drawer bottom` 是静态版 | P1 |
| C5 | `refreshControl`（下拉刷新：阈值、阻尼、释放触发、与列表联动） | 列表标配 | P1 |
| C6 | `swipeableRow`（左滑删除/右滑归档、阈值、回弹、与滚动竞争） | 列表标配 | P2 |
| C7 | `actionSheet`（动作列表 + destructive + 取消，底部呈现） | 现有 `dialog` 缺这套语义 | P2 |
| C8 | `searchBar`（输入 + 取消 + 清空 + search 键 + 搜索态覆盖） | 首页标配 | P2 |
| C9 | `snackbar`（底部提示 + 动作；`toast` 是角落浮层，语义不同） | 反馈标配 | P2 |
| C10 | `fab`（浮动按钮 + 随滚动隐藏） | Material 骨架 | P3 |
| C11 | `grid` / 瀑布流（2–4 列，宽度响应） | `Style` 刻意无 grid；可用 `flexWrap`+`aspectRatio` 近似，**需实测确认** | P2 |
| C12 | `keyboardAccessory`（键盘上方工具栏） | iOS 表单常用 | P3 |
| C13 | `statusBarStyle`（沉浸/浅色图标） | 深色背景下必需 | P2 |

**C-b 已有、但必须「手机化」（不是新增）**

| kind | 需要的改造 |
|---|---|
| `scrollView` | S1–S5；滚动条淡出；拖动时取消子项按压 |
| `vlist` / `list` | S6；行内的 `hover` 改 pressed；触摸行高不低于 44pt |
| `textInput` / `textArea` | E3；焦点态与键盘联动；选择手柄；`TextEvent`（`TEXT_INPUT`） |
| `select` / `combo` / `menu` / `datePicker` | 手机上「锚定气泡」不是原生做法 ⇒ 需要**呈现策略**：小屏自动转底部面板/全屏页（同一份 descriptor，不同 `presentation`） |
| `tooltip` / `popover` | hover 语义在触摸上不存在 ⇒ 长按触发或直接禁用（Env.hasHover） |
| `table` | 手机上横向表基本不可用 ⇒ 建议「列优先级 + 折叠」，不是硬塞 |
| `drawer` | 侧边抽屉在有手势的页面上要先抢边缘 ⇒ 与 I3 的 edge-swipe 仲裁 |
| `button` / `chip` / `switch` / `slider` / `checkbox` / `radio` | I2 的按压反馈 + 44pt 命中区 + 触摸态样式 |
| `toast` | 不接指针（现在也不接）— 与 safe-area 底部避让 |

### 4.6 A —— 无障碍（最贵的一项）

| ID | 条目 | 现状 | 判定 |
|---|---|---|---|
| A1 | 语义树：`role` / `label` / `hint` / `state`（disabled/selected/checked/busy/expanded）/ `value` | G2 整包缺失；kit 0 消费者 | **AIR 遗留欠账**（`flash.accessibility`） |
| A2 | 平台桥：iOS `UIAccessibility`（`accessibilityElements` 自建树 / `accessibilityFrame`）/ Android `AccessibilityNodeProvider`（虚拟视图）+ 朗读/焦点/动作回调 | 无 | 增强（自绘路线特有） |
| A3 | 焦点序与朗读序与 Tab 序共享一份排序（G3 的扁平/64 上限问题会在这里再爆一次） | G3 在册 | 欠账 |
| A4 | `accessibilityActions` + 自定义动作（"删除"、"标为已读"） | 无 | 增强 |

> 结论：A 组不是「加个字段」，而是**一棵并行树的桥**。若手机端要交付到可上架，A1+A2 的工作量
> 大概与「控件层新增 6 个组件」相当。建议**单独立项**，不要塞进手机端首版。

### 4.7 V —— 验收与工具（改变「怎么证明它对」）

| ID | 条目 | 现状 | 说明 |
|---|---|---|---|
| V1 | 移动尺寸 tour：390×844@3x、412×915@2.6x、iPad 768×1024；含安全区/键盘遮挡场景 | 现有 tour 是桌面尺寸 | 文档站 43 页在全屏手机上逐页扫 |
| V2 | **触摸驱动**探针：合成 `TouchEvent` 序列（tap/drag/fling/pinch），不用鼠标 | 现有探针全走 mouse | 现有 `probes/widgets/*` 各一道门，加倍 |
| V3 | 性能预算门：帧时间 p95 < 16.7ms、触摸 move 零分配、滚动 60fps 下 GC 不触发 | 无 | 手机是「性能可测」的第一现场 |
| V4 | 手势/滚动**录制回放**（确定性时间轴，含 dt） | 无 | 惯性/回弹只能这样验 |
| V5 | 无障碍审计：树 dump + TalkBack/VoiceOver 手测清单 | 无 | |
| V6 | 参考基准换锚：`adl` 不再是手机基准（AIR 的 Android/iOS runtime 存在，但本机跑不了）；改为「平台原生语义表 + 真机录屏」 | 现有三臂（AOT/AIR/Web）都以 adl 为锚 | 这是方法论变化，要先写进文档 |

---

## 5 三条路线

| 路线 | 做什么 | 得到什么 | 代价 | 适合 |
|---|---|---|---|---|
| **R1 先让 Web 臂在手机上可用** | B11（pointer/touch + `touch-action` + `visualViewport` + safe-area env + keydown）、S1–S3 的触摸分支、E1 的 Web 填充 | 手机浏览器里**能点、能滚、能打字**的 43 页文档站；无安装、无签名 | 小（1 个后端文件 + 输入层 + 少量布局）；拿不到原生手感/无障碍 | 「先给手机看」/ 验收渠道 |
| **R2 真原生（SDL2 复用）** | B1–B5、B9、B10 + I1/I2/I7 + S1/S2 + E1/E2/E7 + C1 | 真 `.app` / `.apk`，触摸与键盘可用 | 大（编译器立项 + Skia/SDL 双平台产物 + glue）；iOS 签名/上架另算 | 「要交付 App」 |
| **R3 先做纯 AS3 的可移植层** | I1（Pointer 抽象 + 合成 mouse 兼容层）、I2/I3（声明式阈值 + tap/pan/long-press）、S1/S2（物理）、S6、E1 接口 + 桌面实现、C1/C2/C3/C4 的**桌面可跑版本** | 桌面上就能测的「手机行为」，等后端就位即插即用 | 中；好处是**今天就能开工、不依赖编译器**；风险是阈值在真机上要重调 | 推荐起点 |

**推荐：R3 与 R2 的 B 组并行**——asaotui 做 R3（纯 AS3、桌面可验、不碰编译器），同时把 B 组整理
成编译器项目的一个新阶段。R1 作为「一周内就能给别人看」的旁路，成本极低，可以顺手做。

一个必须早定的架构选择：**E3 文本输入走（a）还是（b）**。
- 走 (a) 隐藏原生输入框镜像 → 拿到键盘类型/自动填充/选择手柄/拼写，但引入「原生视图与自绘视图
  重叠、光标位置同步、点击穿透」三类长期 bug（Flutter 也在这上面栽过）。
- 走 (b) 只用后端的文本输入通道 → 简单，但手机用户的期望（选择手柄、长按复制、密码键盘）拿不到。
> 建议：**(b) 起，E3 的 (a) 只在「密码/邮箱/搜索」三类输入上按需升级**，而不是全局改。

---

## 6 里程碑与验收（建议写进 `ROADMAP.md`）

| 里程碑 | 交付 | 验收（必须可复现） |
|---|---|---|
| **M-0 可跑** | iOS 模拟器 + Android 模拟器各跑通 `DocsMain` 首页 | 两平台截图 + `docs.txt` 与桌面逐项一致（除像素比） |
| **M-1 可点** | B5 触摸 → I1 路由（含合成 mouse 兼容层） | 全部 37 kind 的现有探针改「触摸驱动」仍全绿（V2） |
| **M-2 可滚** | S1/S2/S3 + 列表 S6 | 确定性回放（V4）：一次 fling 的位移曲线与手算表一致；越界回弹回位误差 < 1pt |
| **M-3 可输入** | B6 + E1 + E3(b) + S7 | 真机：软键盘弹出 → 输入框自动滚入 → 键盘收起复原；候选窗贴光标 |
| **M-4 有骨架** | C1/C2/C3/C4 + B12 | 三页栈：push/pop/系统返回/侧滑；状态保持；无障碍之外全绿 |
| **M-5 像应用** | C5/C6/C7/C8/C9 + E5/E7/E8 | 下拉刷新 + 滑动删除 + 深色 + 后台不烧电 |
| **M-6 可上架** | A1/A2 + B10 + V5 | TalkBack/VoiceOver 走查清单全过；签名包安装不崩 |

---

## 7 不要做的事（红线，全部有代价依据）

1. **不要试图让 `adl` 当手机基准**。AIR 的手机运行时行为在本机不可观测；照搬桌面 adl 会把
   「AIR 的手势/安全区语义」猜错。手机端基准必须是**平台原生语义 + 真实设备录屏**。
2. **不要在手机上用 CPU raster 全屏**。390×844@3x = 1170×2532，一帧 RGBA ≈ 11.8 MB；桌面
   raster 路径在真机上撑不住 60fps。必须走 GPU（Metal / GLES）。
3. **不要把 `hover` 当 `pressed`**。库里 hover 是由 `MOUSE_MOVE` + `as_pick_hit` **派生**的
   （`UiApp.as:191-214`）；触摸没有 move-without-down，直接复用会「按了不亮、松手才亮」。
4. **不要在触摸 move 里分配**。撞 AGENTS.md §2.4 的 GC 红线（每帧/每循环热路径禁止 arena 分配）。
   触摸 move 的频率是鼠标的 2–3 倍，泄漏会被放大。
5. **不要给引擎加 inset/z-index 语义**。安全区用「根 padding / `safeAreaBox`」，层级用「显式层」
   —— 现状 `lifted` 改 reparent 已证明能撑住浮层；给 flexbox 加 `inset` 名字（`Style.inset` 已存在，
   是 CSS 定位那个 inset）会**撞名**。
6. **不要在 asaotui 里改编译器**。B 组一律回编译器项目开阶段（`compiler-gaps.md` §5）。
7. **不要让「手势识别」长成第二个布局引擎**。识别器只回答「谁赢了、位移多少」，**不重解布局**；
   手势期间的效果走 transform / scrollRect。
8. **不要为手机端加整套 CSS Grid**。网格用 `flexWrap + aspectRatio` 先验；真的不够再谈。

---

## 8 建议新登记到 `compiler-gaps.md` 的条目（**本文未写入，待确认**）

现有 G5（触摸无输入源）已覆盖 B5 的一半。建议新增/扩写：

| 拟编号 | 标题 | 判定 |
|---|---|---|
| G5（扩写） | 窗口后端不产生触摸 / `Multitouch` / `TouchPhase` 输入源 | AIR 遗留欠账 |
| G29 | `Stage.softKeyboardRect` / `stageOrientation` / `autoOrients` / `supportsOrientationChange` 全缺 | AIR 遗留欠账（仅移动端可观测） |
| G30 | `--package android-project` 直接 throw；`xcode-project` 无 iOS 变体 | 工具链缺口 |
| G31 | Skia / SDL2 无 iOS / Android 预编译产物 ⇒ 移动端无法链接 | 工具链缺口 |
| G32 | Web 臂不接 `pointer*`/`touch*`/`keydown` ⇒ 浏览器里不能打字、手机不能拖 | 缺口（自绘 web 臂不自洽） |
| G33 | Android 字体管理器缺失（`sk_platform_fontmgr` 的 `#else` 恒走 CoreText） | 工具链缺口 |
| G34 | 安全区 / `devicePixelRatio` 无 API（AIR 也无 ⇒ 需自定接口） | **增强** |

> ⚠️ **2026-10-30 更新（编号顺延）**：拟编号 **G29 已被 `overflow`「存了不画」占用**（✅ 结案：
> **不是编译器缺口** —— `scrollRect`/`mask` 编译器早就有，缺的是库侧消费，见
> [`compiler-gaps.md`](../compiler-gaps.md) G29）。本表这些**尚未写入**的条目因此整体顺延一位：
> G29→**G30**、G30→**G31**、G31→**G32**、G32→**G33**、G33→**G34**、G34→**G35**。新编号已落到
> [`MOBILE.md`](../MOBILE.md) §9 的对照表。

---

## 9 证据与复核命令

本文所有数字都出自**一个只读工具**（bash 无 coreutils，故用 `node`）：

```bash
cd asaotui
node tools/mobile-gap-scan.cjs         # kit 计数 + 移动端令牌零命中 + 编译器事实
node tools/mobile-gap-scan.cjs --json  # 同上，机读
```

它只**读** `kit/`、`ui-demo/` 与 `as3compiler/src`、`as3compiler/vendor`（`asaotui` 不改编译器，
这里也只「看」），不写任何文件、不跑编译器。退出码：`0` 量到了，`2` 源树缺失/不可读。

**未实测项（不得当成结论引用）**：
- 真机 / 模拟器上本轮**一次都没跑**（本机无 iOS SDK / Android NDK 验证）。
- 手机浏览器的「touch 合成 mouse」是否足以驱动现有 `scrollView`：**未实测**（代码只挂 mouse，
  合成事件的行为依赖浏览器）。
- 手势阈值（8dp / 100ms / 500ms）取自平台习惯值（Android `ViewConfiguration` / iOS 手势默认），
  **未在本库上实测手感**。
