# 下一批可做的缺口：第二轮盘点（2026-10-25）

as3compiler-aot/asaotui HEAD `6a5a692` · 编译器 `as3compiler/` **只读**（本轮未动一行）
接续 [`gpui-examples-gap-2026-10-25.md`](gpui-examples-gap-2026-10-25.md) §5/§6（第 1 批已落地）。

本文件回答：**第 1 批做完之后，还剩哪些「能做且值得做」的缺口？**
每一条都重新在**当前树**上复核过，不抄上一份报告的结论。

---

## 0 一句话结论

上一份报告把缺口分成「能力型组件 / 视觉原语 / 框架能力」。本轮把每条重新验证后，
**多出三类第 1 批没列的东西**：

1. **一条真缺陷**（不是缺功能）：AOT 产物里 **hover 根本不亮**，因为运行时从不派发
   `mouseOver`/`mouseOut`（G25），而库的 hover 只挂在 `MOUSE_OVER` 监听上。
   这条能**纯库侧**收口（运行时确实派发 `mouseMove`，且**冒泡**）。
2. **两条「零成本但没人用上」的运行时能力**：`Mouse.cursor`（指针形状，运行时已实现四种）、
   `TextFormat` 的 `getLineMetrics`（逐行几何，**对 adl 逐行实测过**）。
3. **一条被 glue 卡住的**：右键 / 上下文菜单 —— `window_glue.cc` 只转发
   `SDL_BUTTON_LEFT`（`:1406` / `:1425`），右键**到不了 AS3**。这一条只能登记，不能库侧绕。

---

## 1 真缺陷：AOT 下 hover 全死（G25 的**库侧**收口）

### 1.1 证据链（三个独立事实）

| # | 事实 | 证据 |
|---|---|---|
| 1 | 运行时鼠标派发**只发** `mouseDown`/`mouseUp`/`click`/`doubleClick`/`wheel` 与 Stage 的 `mouseLeave` | `src/emit.ts` 里字符串 `mouseOver` 出现 **0 次**；生成的 `ui-demo/air-gallery/GalleryApp.c` 里 `"mouseOver"` **只出现在常量定义** `MouseEvent_MOUSE_OVER = "mouseOver"`（`:61441`），无派发点 |
| 2 | 库的 hover 只来自逐对象 roll 事件 | `kit/asaot/ui/UiNode.as:262-263`：`listen(backing, MouseEvent.MOUSE_OVER/MOUSE_OUT, setHover)` |
| 3 | **`mouseMove` 是可用替代品**：它**冒泡**，且没命中任何对象时目标退化成 stage | `emit.ts` 派发点：`MouseEvent_new(type, true, false, …)`（bubbles=true）与 `if (target == NULL) target = _this;` |

⇒ 结论：**adl 里按钮悬停会亮，AOT 里永远不亮**。这就是 G25 记的
「所有 hover 反馈在 AOT 上是死的」，只是上一份报告把它归给编译器、没提库侧还有路。

### 1.2 库侧修法（不动 `as3compiler/`）

- `UiApp` 挂**一个** `stage.MOUSE_MOVE` 监听：`e.target` → 反查所属 `UiNode`
  （`backing → node` 用 `Dictionary`，节点 build 时登记、`destroySubtree` 时摘除）→
  把**祖先链**的 `state.hover` 置 1，把上一轮链条里剩下的置 0。
  祖先链而非单点，是因为 AIR 的 `mouseOver` **冒泡**：悬停子节点时祖先的 `:hover` 样式也该亮。
- `stage.MOUSE_LEAVE` → 清空整条链（指针出窗）。
- 摘掉 `UiNode` 上那两条 `MOUSE_OVER/MOUSE_OUT` 监听，让 **adl 与 AOT 只走同一条路径**
  （不是「AOT 打个补丁」，而是两边行为由同一段代码决定）。

**为什么不用几何自算**：`Stage_dispatchMouse` 用的就是点击用的那个 `as_pick_hit`
（尊重裁剪、`mouseEnabled`、绘制区域）。自己算矩形命中等于**第二套命中规则**，
迟早和点击不一致 —— 「hover 亮着但点不到」正是那类陷阱。

**代价与风险**：

| 项 | 说明 |
|---|---|
| 每帧成本 | 每次 `mouseMove` 一次 `Dictionary` 查询 × 深度（≈10），无分配 |
| 语义变化 | 悬停**透明容器**时 hover 落在**画出来的子孙**上（与点击一致）。想要「悬停整张卡片」，卡片必须有 `background` 或子树覆盖 —— 与现有命中口径同源，不是新坑 |
| 影响的既有探针 | `probes/lifecycle`（4 处）与 `probes/widgets/interact`（5 处）显式派发 `MOUSE_OVER`；改成派发 `mouseMove` 即可（更接近真实指针） |
| **不修 G25 本身** | 用户自己写的 `addEventListener(MOUSE_OVER, …)` 在 AOT 上**仍然不触发**。本项只让**库的** hover 与 AIR 一致，G25 保持登记 |

**这一条同时是下面两项的前置**（cursor 与 tooltip 都需要「当前悬停谁」）。

---

## 2 可以做的能力清单（按性价比）

工作量口径：**小** ≈ 一个文件 + 探针 + 变异 + 文档页；**中** ≈ 两三个文件 + 状态机 + 多组断言；
**大** ≈ 需要新的窗口算法/手势栈。

| # | 缺口 | 现状证据 | 层 | 量 | 价值 |
|---|---|---|---|---|---|
| A | **hover 死**（§1） | 见 §1.1 | 纯库 | 小 | **高：修缺陷** |
| B | **指针形状**（`cursor`） | 运行时已实现：`ASC_cursor_kind_of_name` 认 `auto/arrow/ibeam/hand/button`（`emit.ts:25005-25012`，即 `MouseCursor` 全集）、`window_glue.cc:2607` 映射到 SDL；`Mouse.cursor` 是**全局**静态量，且在**派发之后**采样（`emit.ts:25259`）⇒ 监听器里设立刻生效。库里 `buttonMode`/`useHandCursor` **0 处** | 纯库 | 小 | 中高：可点的地方应当变手型 |
| C | **异步/远程图片** | `ImageNode.as` 头注释：只吃 `BitmapData`；运行时 `Loader.load(http)` **已实现**（异步 job、`COMPLETE`/`ioError`，错误号 2035/2036/2124 与 AIR 同值，`emit.ts:13457+`） | 纯库 | 中 | 高：头像/图库/骨架屏都卡在这 |
| D | **图标通道**（`icon`） | 无 `icon*.as`；`--features svg` 只 native 且 **AIR 侧报 #2124**（`compile.md:393-415`）⇒ 走 SVG 会毁掉双臂验证；`Graphics.curveTo`（二次贝塞尔）有、`cubicCurveTo` **无** | 纯库 | 中 | 高：工具条/按钮图标 |
| E | **表格排序 / 列宽拖拽 / 虚拟化** | `TableNode.as:20` 自述「no sorting, no column resize, no virtualisation」 | 纯库 | 大 | 高：唯一撑大数据量的展示件 |
| F | **键盘导航 + 快捷键层** | `WidgetKeys.onKey(n, keyCode, shift)` **没有 ctrl/alt/cmd**；只有 menu/select/dialog/drawer/input 消费按键，`list`/`table`/`tabs` **没有**；设计文档 §6 的 `ActionRegistry`/`keymap`/`FocusChain` 在 `kit/` 里**出现 0 次**（未实现） | 纯库 | 中 | 高：可用性硬伤（只有鼠标能选行） |
| G | **贴底滚动 + 编程式滚动** | `ScrollViewNode` 有 `offsetY`（请求）/`contentH`/`maxOffsetY`/`onScroll`（`:48-55`），但**没有** `scrollTo`/`stick`；库内 `scrollTop`/`scrollTo` **0 处** | 纯库 | 小 | 中：聊天流、日志窗 |
| H | **下划线 / 删除线** | `TextFormat.underline` 字段在、**渲染器不画**（`vendor/skia_glue.cc` 里 `underline` **0 次**；`as_tf_html_emit_run` 明写 "not yet modeled"）；但 `numLines` / `getLineMetrics(i)` 是**逐行对 adl 实测过的真实现**（`emit.ts:20292-20331`，含 x/width/ascent/descent/leading）⇒ 库可自绘 Shape 线 | 纯库 | 中 | 中低：链接才需要 |
| I | **手风琴多开** | `AccordionNode.as:18` 自述 `mode:"multi"` 未实现（需要一个 Array 槽 + 索引集合） | 纯库 | 小 | 低 |
| J | `image` 的 `scaleMode:"cover"` | 头注释里明说没有（要裁剪，属 scrollView 的活） | 纯库 | 小 | 低 |

### 2.1 两条「运行时已就绪、库侧没接线」的细节

- **B 的坑**：`Mouse.cursor` 是**进程级全局**。悬停离开时必须回到 `"auto"`，
  否则「设过一次 ibeam，整个窗口永远是 ibeam」，并且会**压掉运行时的 AIR 规则**
  （`ASC_window_update_cursor` 只在 `Mouse.cursor == "auto"` 时才走
  「可选中文本→ibeam / `buttonMode`→hand」）。所以契约是：**只在节点明确要形状时设，
  其余一律 `auto`**。
- **H 的坑**：`TextField` 的 `y` 是首行顶，行的基线要用 `getLineMetrics` 的
  `ascent/descent/leading` 逐行累加；用「字号估一个」就是典型「看着像」的错。

---

## 3 只能登记的（需要 `as3compiler/` 或 glue）

| 缺口 | 判据 | 证据 |
|---|---|---|
| **右键 / 上下文菜单** | glue 只转发左键 | `vendor/window_glue.cc:1406`（down）/`:1425`（up）都带 `e.button.button == SDL_BUTTON_LEFT`；`"rightClick"` 在 `emit.ts` 只用于**托盘图标**（`:9936`），stage 侧没有 |
| **逐对象 roll 事件**（G25 本体） | 运行时无派发点 | §1.1 |
| **GIF 逐帧** | 只有首帧可解（`SkCodec`） | 上一份报告 §1 #24 |
| **无障碍树** | `flash.accessibility.*` 整包缺（G2） | `compiler-gaps.md` G2 |
| **应用菜单栏 / 系统通知** | 只有 Cocoa glue；`supportsNotification=false` | `emit.ts:9594` / `:4189` |
| **多窗口 shell** | `NativeWindow` 在（197 处），但库只有单 `UiApp`/单 stage | 上一份报告 §2.1 |

---

## 4 仍然明确不做（避免又被当缺口重报）

CSS grid / 容器查询 / 编辑器 / Linux layer-shell / 压感 / 多窗口 / `Array→Vector` /
String 的 `toLowerCase` / 滚动条 momentum 与键盘翻页 / `textArea` 内部覆盖式滚动条
（运行时 wheel 已直接滚 `TextField`，见 `emit.ts:22685-22694`，不需要库再做一层）。

---

## 5 三个可选批次

| 批次 | 内容 | 一次消掉的缺口 | 风险 |
|---|---|---|---|
| **一·指针真实感** | A（hover 合成）+ B（cursor） | G25 的库侧影响 + `text_layout` 以外的全部悬停类 | 低；需改两个既有探针的派发方式 |
| **二·真实内容** | C（异步图片）+ D（图标） | GPUI `image` / `image_gallery` / `image_loading` / `svg` 四条 | 中；C 的测试要起本机 HTTP 服务，D 要写 path 解析器（`A` 弧先明确抛错） |
| **三·大数据量** | E（表格排序/列宽/虚拟化）+ G（贴底滚动） | `data_table` / `list_example` 两条 | 高；虚拟化要动 item 复用与 GC 写屏障（设计文档 §10 第 2 条仍未决） |

F（键盘）跨一、三：`list`/`table` 的上下键依赖行是「真节点」还是「复用节点」，
建议跟 E 一起做，或先只做**独立**的快捷键层（`Ctrl/Alt` 修饰键在 `UiApp` 层截获，
不动 `WidgetKeys` 的签名 —— 那个接口加参数会撞 AVM2 的 `#1063` 实参契约）。