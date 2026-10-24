# GPUI 官方示例 vs asaotui：还缺哪些组件

日期：2026-10-25 · asaotui HEAD `ecf01e8` · 编译器 `as3compiler/` 只读
（`node tools/compiler-fingerprint.cjs` = **0 files**；其 HEAD 从 `480b81c` 前进到 `96935e4`
是并发会话提交的，不是本仓库写的）

本文件回答一个问题：**拿 GPUI 官方示例当清单，我们的控件库还差什么？**

先说破一个前提：*GPUI 官方示例里几乎没有「控件」*。`crates/gpui/examples`
的 44 个条目演示的是**原语**（`div` / `text` / `img` / `svg` / `canvas`）和**框架行为**
（窗口、拖放、焦点、动画）。Button / Checkbox / Tabs 那一层在 Zed 的 `ui` crate
或第三方 `gpui-component` 里，**不在官方 examples 里**。所以「照抄官方示例」抄不到新控件；
它能回答的是另一件事：**我们缺哪些能力型组件**。

---

## 0 扫描口径

| 项 | 数值 | 来源 |
|---|---|---|
| GPUI 官方示例 | 44 条目（40 `.rs` + 4 目录） | `gpui-src/crates/gpui/examples/` 目录列举 |
| 我们的 kind 工厂 | 41（本节写于 40 时；第十四轮加了 `textArea`） | `kit/asaot/ui/*.as` 里 `public function <小写>(` 的包级工厂 |
| 我们的文档页 | 42 | `ui-demo/demo/DocsCatalog.as` `GROUPS` |
| 我们的门 | 46 | `node tools/gates.cjs` |

**结论一句话**：40 个 kind 已经**超出**官方示例展示的范围（示例里那点控件我们都有）；
真正的缺口是 **9 个能力型组件 + 6 个视觉原语 + 5 项框架能力**，其中 **5 个组件的底层
（运行时/glue）已经就绪**，属于纯库侧工作。

---

## 1 全表（44 条目逐条）

状态：✅ 有 · ◐ 部分 · ✗ 缺 · n/a 不是组件

| # | GPUI 示例 | 演示什么 | 我们 | 说明 |
|---|---|---|---|---|
| 1 | `hello_world` | 最小窗口 | ✅ | — |
| 2 | `text` | 样式化文本 | ✅ | `text` + `TextStyle` |
| 3 | `text_layout` | 对齐 / 字重 / 字距 / 行距 / 下划线 | ◐ | 字重/字号/对齐/字距/行距有；**下划线、删除线无**（`TextStyle` 无此字段） |
| 4 | `text_wrapper` | 换行 + 截断 | ✅ | `TextStyle.whiteSpace:"normal"` / `textOverflow:"ellipsis"`（第十四轮补，见 §6）；两者**互斥**：换行只在测量期、截断只在绘制期 |
| 5 | `input` | 输入、选区、剪贴板、IME | ✅ | 真 `TextField`（`TextInput.as`），不比 GPUI 弱 |
| 6 | `uniform_list` | 虚拟化列表 | ✅ | `virtualList` |
| 7 | `list_example` | **贴底**列表 + 滚动条行为 | ◐ | 有 `list` / `virtualList`，**无 bottom-aligned（聊天流）** |
| 8 | `data_table` | 虚拟化表格 + 自定义滚动条 + 行选择 | ◐ | `table` 有，但 `TableNode.as:20` 自述「no sorting, no column resize, no virtualisation」 |
| 9 | `tree` | 深层嵌套 | ✅ | `tree`（扁平可展开） |
| 10 | `scrollable` | 裁剪 + 滚动 | ✅ | `scrollView`（覆盖式滚动条，比示例更完整） |
| 11 | `popover` | `deferred` + `anchored` 浮层 | ✅ | `popover` / `tooltip` / `menu` / `dialog` / `drawer` |
| 12 | `anchor` | 锚定定位 + 碰撞翻转 | ✅ | `PopoverNode.placement` + 碰撞回退 |
| 13 | `focus_visible` | 键盘才显示焦点环 | ✅ | 焦点环只在 Tab / `focusNode` 后出现，点击不聚焦（`UiApp.as:431`，无 click→focus） |
| 14 | `tab_stop` | Tab 序 | ✅ | `tabEnabled` / `tabIndex` + 浮层焦点陷阱；上限见 G3（64 / 扁平） |
| 15 | `a11y` | AccessKit 无障碍树 | ✗ | `flash.accessibility.*` **整包缺失**（`compiler-gaps.md` G2），运行时没有可发布的无障碍树 |
| 16 | `animation` | 动画组合子 / spring | ◐ | 有 `Anim` / `Ease` / `transitionMs`（按字段补间）；**无 spring，无 `Animation` 组合子** |
| 17 | `opacity` | 透明度 | ✅ | `Style.opacity` + `Anim` |
| 18 | `shadow` | box-shadow | ✅ | `Style.boxShadow`（第十四轮补，落 background 形状而非 backing；`spread`/`inset` 具名抛错）——§3.1 的判断当天就被兑现 |
| 19 | `gradient` | 线性渐变 + 色彩空间 | ✅ | `Fill.gradient([...])`（第十四轮补，N 站 linear + `angle`）；**色彩空间仍只有 sRGB**，非 linear（radial）与 `focalPointRatio != 0` 具名抛错，不近似 |
| 20 | `pattern` | 图案背景 | ✗ | 无 channel，渐变 + repeat 都没有 |
| 21 | `grid_layout` | 容器查询驱动的响应式布局 | ✗ | 无 grid，**也无 `container_query`**；示例正文用的是后者 |
| 22 | `painting` | `canvas` + `Path` 自绘 | ◐ | `Shape.graphics` 底层可用，**库侧无 canvas/path 组件** |
| 23 | `svg` | SVG 渲染 | ◐ | 运行时 `--features svg` 可解码（`compile.md:342`），**库侧无图标通道**，见 §3.3 |
| 24 | `gif_viewer` | GIF 动图 | ◐ | GIF 首帧能解码（SkCodec）；**无逐帧播放器** |
| 25 | `image` | 本地/远程图片、尺寸 | ◐ | `image({bitmapData})` 只吃现成 BitmapData |
| 26 | `image_gallery` | 图片缓存 + 远程加载 | ✗ | 无异步加载器 / 缓存；运行时 `Loader.load(http://)` 已就绪，见 §3.4 |
| 27 | `image_loading` | 加载中 / 失败态 | ✗ | 有 `skeleton` / `spinner`，但没有 loader 状态机可挂 |
| 28 | `drag_drop` | 拖放 | ✗ | 只有 slider / scrollbar 的指针捕获；**无通用 Draggable/DropZone** |
| 29 | `mouse_pressure` | 压感 | ✗ | 无输入源（且 `compiler-gaps.md` G5 已推迟触摸/压感） |
| 30 | `set_menus` | 应用菜单栏 | ✗ | glue 只有 Cocoa 分支（`window_glue.cc:2825` `#if defined(__APPLE__)`），`NativeMenu.display` 明确不支持（`emit.ts:9594`） |
| 31 | `system_notifications` | 系统通知 | ✗ | 实测 `supportsNotification = false`（`emit.ts:4189`），无 API |
| 32 | `window` | normal / dialog / popup / floating 子窗口 | ✗ | 运行时**有** `flash.display.NativeWindow`（`emit.ts:5865`，阶段八十九·七十一）；kit 只有一个 `UiApp` / 一个 stage |
| 33 | `window_positioning` | 窗口位置与尺寸 | ✗ | 同上（kit 无窗口层） |
| 34 | `window_movable` | 自定义可拖动标题栏 | ✗ | 同上 |
| 35 | `window_shadow` | 自定义窗口阴影 / 装饰 | ✗ | 同上 |
| 36 | `move_entity_between_windows` | 跨窗口移动实体 | ✗ | 同上 |
| 37 | `layer_shell` | Linux layer-shell | ✗ | 平台专属，且我们 Windows 为主 |
| 38 | `on_window_close_quit` | 关窗即退出 | n/a | 单窗口 ⇒ 天然如此，无需钩子 |
| 39 | `view_example` | 编辑器 / 多行输入 / 测试 | ◐ | `example_text_area` 对应**多行文本域** ⇒ 第十四轮的 `textArea` 已补；**编辑器**不做，测试走我们自己的探针协议 |
| 40 | `toggle_headless` | 无显示环境切换 | n/a | 平台/工程细节 |
| 41 | `testing` | `#[gpui::test]` | n/a | 我们有自己的探针协议 |
| 42 | `active_state_bug` | 按下态复现 | ✅ | `state.pressed` 在 `PaintKit` 里已消费 |
| 43 | `paths_bench` | 路径渲染基准 | n/a | 基准 |
| 44 | `ownership_post` | 所有权文档 | n/a | 文档 |

---

## 2 按「成本 / 收益」重排的缺口

### 2.1 能力型组件（9 个）

| 组件 | 底层就绪？ | 工作量 | 价值 |
|---|---|---|---|
| **dataTable**（虚拟化 + 排序 + 列宽拖拽） | 库里已有 `virtualList` 的窗口算法可复用 | 中 | 高：唯一能撑大数据量的展示组件 |
| ~~**textArea**（多行 + 换行 + 滚动）~~ → **已做（第十四轮）** | `TextField.multiline` 运行时支持，`PaintKit` 只是写死 false | 小 | 高 |
| **贴底列表**（聊天流） | `scrollView` 有，只缺「锁底」策略 | 小 | 中 |
| **拖放**（Draggable / DropZone） | 指针捕获已用手势方式绕出来了 | 中 | 中 |
| **image 异步/远程**（`src` + 加载态 + 缓存） | ✅ `Loader.load(http)` + `AS_JOB_IMAGE_URL` 已实现 | 小 | 高 |
| **SVG 图标通道** | ✅ `--features svg` 可解码 | 小 | 高：图标是控件库的刚需 |
| **GIF 播放** | 首帧可解，逐帧要自写定时器 | 中 | 低 |
| **多窗口 shell** | ✅ `NativeWindow` 在 | 大 | 低（本库定位单窗口） |
| **应用菜单栏** | ✗ 仅 macOS glue | 大 | 低（Windows 无后端） |

### 2.2 视觉原语（6 个，全是「运行时能画、库侧没字段」）

| 原语 | 底层就绪？ | 证据 |
|---|---|---|
| ~~**box-shadow**~~ → **已做（第十四轮）** | ✅ 运行时真的渲染 `DropShadowFilter` | `emit.ts:24086 as_render_filtered` / `:24100` DropShadow 分支 / `:24085 as_filter_sigma`（按 AIR 的 box blur 校准过 sigma） |
| ~~**渐变填充**~~ → **已做（第十四轮）** | ✅ N 站 linear 已实现（radial 仍显式报不支持） | `emit.ts:18186 Graphics_beginGradientFill` / `:18195` 报告分支 |
| **下划线 / 删除线** | 需查 `TextField` 面；现 `TextStyle` 无字段 | `style/TextStyle.as` 10 个字段无 decoration |
| ~~**文本换行 / 截断**~~ → **已做（第十四轮）** | ✅ 运行时 `TextField.wordWrap`/`multiline` 都在 | `PaintKit.measureField(..., wrapW)` / `PaintKit.ellipsize` |
| **cursor 样式** | 需 `Mouse.cursor` 通道 | `Style.as` 头注释：cursor 故意 ABSENT |
| **图案背景** | 无 | — |

### 2.3 框架能力（不是组件，登记即可）

无障碍（G2）· 压感（G5）· 容器查询 · spring 动画 · 跨窗口实体。

---

## 3 四个值得单独说的发现

### 3.1 box-shadow 不是「做不了」，是「没暴露」

`Style.as` 头注释把 box-shadow 列为「故意缺席，seam 会大声报错」。但运行时**已经实现了
滤镜渲染**：`as_render_filtered` 按 `filters[]` 顺序递归 `saveLayer`，其中
`DropShadowFilter` 分支是完整的，`as_filter_sigma` 还专门按 adl 实测的 box blur 标定过。
⇒ 库侧只需要一条 `Style.shadow` → 给 backing 挂 `filters`，就能补上 GPUI `shadow.rs` 的效果。

### 3.2 渐变缺的只是 `Fill` 的一个工厂

> **后续（2026-10-25 第十四轮）**：这一节描述的是**当时**的现状；结论已落地，见 §6。实际采用的正是
> 这里建议的那种形状，只差一步：`fromArray` 从「返 `null`」改成 **委托给 `gradient`**（名字保留，
> 语义落实），于是 `background: [a, b]` 直接可用；`StyleCases` 的 case 12/18 也从「是不是 `null`」
> 改问「几站、什么类型、什么角度」——只钉「非 null」会放过「退化成首站纯色」那个静默失败。

`Graphics.beginGradientFill` 在 `emit.ts:18186` 是真实现（2-stop 线性；radial / >2 stop /
非 pad 会通过 `as_gradient_general_report` 报一次而不是画错）。而 `Fill.fromArray` 现在
**故意返回 null**（保持与 AIR 对 Array 的答复一致）。⇒ 想开渐变，应该是
`Fill.gradient([...])` 新入口，而不是改 `fromArray` 的语义。

### 3.3 SVG 是「开关级」差距

`--features svg`（= `-D ASC_USE_SVG=1`）已能 `Loader.load("x.svg")` 解码成功，
`<text>` 走平台字体（`compile.md:342`、`skia_glue.cc:1220`）。默认关闭是刻意的：
AIR 从不支持 SVG（报 `#2124`），属增强须 opt-in。⇒ 库侧 `icon()` 只需在开着该增强时
走 SVG 解码，关着时退回报 `#2124`——正是 §1.5 要的形状。

### 3.4 远程图片：运行时比库超前

`Loader.load` 对 `http(s)://` 走 `AS_JOB_IMAGE_URL`（取回 + 解码，帧边界回调），
`URLLoader` / `URLStream` 也都在。而 `image()` 只接受 `BitmapData`。
⇒ 「远程图片 + loading/error 态 + LRU 缓存」是**纯库侧**的新组件，不用动编译器一行。

---

## 4 明确**不做**（避免以后又当缺口重报）

| 项 | 理由 |
|---|---|
| CSS grid / grid 字段 | `Style.as` 明确 ABSENT；flex 已覆盖 demo 全部布局，加 grid 等于第二套布局引擎 |
| 容器查询 | 窗口 resize 已有 `RESIZE → invalidate(STRUCTURE)`，够用；查询语法收益低 |
| 编辑器（语法高亮 / LSP） | 不是 UI 库范围 |
| Linux layer-shell / 压感 | 无硬件/平台可验证（G5 同口径） |
| 多窗口 | 本库定位单 `UiApp`；`NativeWindow` 在，但不是本轮目标 |

---

## 5 建议批次（若继续推进）

1. **一批小活，全部纯库侧**：`textArea` + `text_wrap/truncate` + `Style.shadow` + `Fill.gradient`
   → 4 个缺口，底层全就绪，能同时消掉 `text_wrapper` / `shadow` / `gradient` / `view_example` 四条。
2. **图标 + 远程图片**：`icon()`（吃 `--features svg`）+ `image({src})`（走 `Loader`），
   消掉 `svg` / `image` / `image_gallery` / `image_loading` 四条。
3. **dataTable**：复用 `virtualList` 窗口算法 + 列宽拖拽 + 排序；工作量最大、收益最高。
4. 其余（拖放、贴底列表、GIF、a11y、多窗口、菜单、通知）按需，且 a11y / 菜单 / 通知
   需要先动编译器或 glue，不属于「库补组件」。
---

## 6 第十四轮：§5 第 1 批已落地（2026-10-25）

§5 排的第 1 批（「一批小活，全部纯库侧」）已做，四个缺口一次消掉 `text_wrapper` / `shadow` /
`gradient` / `view_example` 四条。**编译器一行未动**（`node tools/compiler-fingerprint.cjs` = 0 files）。

| 能力 | 作者面 | 落在哪 | 不可回退的约束 |
|---|---|---|---|
| 盒阴影 | `style: { boxShadow: { x, y, blur, color, alpha } }`（也可 `{offset:[x,y]}` / 数组堆叠） | `style/BoxShadow.as` + `UiNode.applyShadow()` | 落 **background 形状**（`shapeA`），不落 backing——backing 上的滤镜会连 label/图标/子节点一起投影；无 `shapeA` 时退到字段自身，两者皆无则**抛错**。`spread != 0` / `inset == true` **抛错**（`DropShadowFilter` 没有那个旋钮，近似 = 画了作者没要的阴影）。幂等靠 `Style.shadowsEqual`（按值），否则每次 re-describe 都重建 filter 列表 |
| 渐变背景 | `background: ["#111", "#fff"]` 或 `{ colors: [...], angle: 90 }` | `style/Fill.as` + `PaintKit.beginBackground()` | N 站 + `angle`；每节点一个 `Matrix` 缓存在 `n.extra`（零每帧分配）。**非 linear / 少于 2 站 / `focalPointRatio != 0` / 非法 ratio 抛错**。**hover/pressed 不染色**（多站混白无意义）且**不参与动画**（`toBg = NaN`，回落到首站纯色才是静默回退）。`argb` 仍是「首站」的读法 |
| 文本换行 | `style: { text: { whiteSpace: "normal" } }` | `TextWidget.wrapWidth()` + `PaintKit.measureField(..., wrapW)` | 只有**测量期**能换行；宽度必须是解析好的 POINT，百分比/auto 一律**抛错**（要等 solver，猜就是错） |
| 文本截断 | `style: { text: { textOverflow: "ellipsis" } }` | `PaintKit.ellipsize()`（二分前缀 + `\u2026`） | 只有**绘制期**能截断（需要最终盒宽）；只在未换行时生效——两件事结构上互斥 |
| 多行输入 | `textArea({ key, rows, placeholder, value, onChange, onCommit })` | `TextAreaNode` + `kind/TextAreaWidget.as` | **独立 kind**，不是单行文本框上的开关：Enter 的契约是**反过来**的（单行提交、多行插入），所以它**不吃 13**，让运行时自己插换行；高度是 `rows × 行高`（真测量，不是猜）；`onCommit` 只在 blur 时、且值真变才发 |

### 6.1 验收

| 项 | 证据 |
|---|---|
| 行为 | 新探针 `probes/widgets/textfx`（**18 checks**，窗口 460×520）。阴影用 `blur 0 + (0,8)` 把断言变成**精确像素**：盒面上方必须 `#ffffff`、面 `#ffffff`、下方 4px `#808080`；渐变量三点（左近黑 / 中严格居中 / 右近白）；换行对**同串未换行参照节点**比高度（≥ 2.5 行）；截断要求「变短 + 含 U+2026 + `textWidth ≤ 120`」；多行输入要求「`ab` + Return + `cd` 真出现换行、`onCommit` 仍为空、`onChange ≥ 4」，blur 后才轮到 commit |
| 变异 | `probes/widgets/textfx/mutation.cjs` **5/5**：滤镜不赋值 / 渐变画首站 / wrap 宽度置 NaN / 截断条件置 false / Enter 加进消费集。每个被改文件在 `finally` 还原并 sha256 逐字节核对 |
| 参考编译器 | `mxmlc` 编译同一份源（`tools/mxmlc-check.cjs`，87766 bytes） |
| 文档站 | 42 页（新增 `textArea` 页）+ box 页加「Box shadow」「Gradient background」、text 页加「Wrapping」「Ellipsis」 |
| 门 | `node tools/gates.cjs` **46/46**（新增 `probe widgets/textfx`） |

### 6.2 这一批里唯一一次「静态门抓到真问题」

`tools/demo-options.cjs` 在写完 demo 后立刻变红，报 `DocsControls.as:129 textField -> "multiline"`。
它扫的是**字符串字面量**，而那句话是我写在**说明文字**里的 `textField({multiline:true})` ——
正是这一批要反驳的写法。没有把它当误报屏蔽，而是改写措辞：文档站的说明文字本身也在「教」。

### 6.3 顺带确认的一条语义

探针第一版断言「省略号是最后一个字符」，跑出来 `ends with 0xA6` —— 本运行时的字符串是 **UTF-8 字节**，
`charAt(length-1)` 只拿到 U+2026 的续字节。断言改成 `indexOf("\u2026") >= 0`。**这不是缺口**，
是「字符串下标 = 字节偏移」的既有语义，但它意味着：任何「取最后一个字符」的写法在非 ASCII 上都是错的。
