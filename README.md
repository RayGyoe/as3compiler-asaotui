# asaotui —— 自研 UI 库工作区

本目录是「给 as3compiler 配一套自己的 UI 库」这条工作线的**工作区**，与
`as3compiler/`（编译器主体）分离：**编译器仓库不被评估/测量产物污染**，
只有真正进入实施的阶段（占阶段号、升版本）才把代码落进 `as3compiler/`。

## 实施路径（2026-10-22 口径）

**UI 库走纯 AS3 实现**——接缝是纯 `.as` 接口，唯一实现 `As3LayoutEngine`（flexbox 子集）**已落地**，
并在三条工具链上逐值一致（自家 AOT / Yoga(C) / AIR）。

**需要改动主机编译器（`as3compiler/`）的 native 路径（如把布局换成内联 Yoga）已搁置**；
做库时撞到的**编译器缺口一律登记在 [`compiler-gaps.md`](compiler-gaps.md)**，
**不动编译器代码、不改 `as3compiler/TODO.md`、不占阶段号、不升版本**。

## 克隆后的准备

本工作区是**独立仓库**（`as3compiler-asaotui`，根目录就是本目录），脚本一律用**相对路径**
引用编译器仓库（`../as3compiler`），且窗口后端的运行时数据不入库，故克隆后先做三件事：

```sh
git clone https://github.com/RayGyoe/as3compiler.git ../as3compiler   # 必须同级目录
cp ../as3compiler/vendor/skia/lib/windows-x64/icudtl.dat ui-demo/     # 文字引擎数据（已 ignore）
node tools/gates.cjs     # 已增至 62 道门，62/62 PASS 才叫绿（最新落盘 reviews/gates-macos-2026-10-31c.txt）
```

两个第三方检出**故意不入库**（它们自带 `.git`，入库会退化成 gitlink 而丢内容），按需取回：

| 目录 | 取回方式 | 本机这份的版本 |
|---|---|---|
| `gpui-src/` | zed 的 sparse checkout，命令见 §「GPUI 源码参考」 | `5447804`（2026-10-21） |
| `measurements/yoga-src/` | `git clone --depth 1 https://github.com/facebook/yoga measurements/yoga-src` | `843dba8`（2026-10-21） |

AIR SDK（`mxmlc` / `adl`，探针的**参考臂**要用）按 §「本机环境」以 `AIRSDK_HOME` 指向。
什么进库、什么不进库的判据写在 [`.gitignore`](.gitignore) 头部的注释里。

**跑出来的东西写哪儿**：一次运行的日志、截图、抽查文件一律写本仓的 `temp/`
（已忽略、可随时删），例如 `node tools/gates.cjs > temp/gates-$(date +%F).txt 2>&1`。
**不要写到工作区根**（`../temp`）或本仓根——根目录只放文档与构建输入。三个目录的分工：
`temp/` = 运行证据（人和 agent 产生，可丢弃）；`.scratch/` = 工具自己的暂存树
（`publish-pages` 的 `pages`、`buildsh-web` 的假 emsdk）；`reviews/` = 被文档按路径引用的
**归档**证据（不可再生，才进库）。

## 交付（2026-10-25，第十七轮：图标通道 `icon()`）—— 一条命令复核

```sh
node tools/gates.cjs     # 已增至 62 道门，62/62 PASS 才叫绿（最新落盘 reviews/gates-macos-2026-10-31c.txt）
```

**在线 demo（零构建）**：<https://raygyoe.github.io/as3compiler-asaotui/> —— 就是下面那张
53 页文档站，由 `web` 臂编成 wasm 后放在 `gh-pages` 分支。8 个文件 / 8.70 MB，与构建
产物**逐字节相同**（`tools/publish-pages.cjs --check` 可复核）；刷新它是
`node tools/publish-pages.cjs --push`，见 [`ui-demo/README.md`](ui-demo/README.md#publishing-the-online-demo)。

| 交付 | 内容 |
|---|---|
| **有环境了：`Env` + 安全区当 padding（第四十三轮 · MOBILE E1/E2）** | 移动端第三件地基，仍然**只动 `asaotui/`**：`Env`（九个只读答案 + 订阅）/ `EnvBase`（可写端：九个 `set*`，每次**先比较再通知**）/ `DesktopEnv`（桌面地板：全 0 安全区、有鼠标、`locale` 镜像 `Capabilities.language`）/ `SafeArea`（`safeArea:` 选项 → 位掩码）；`UiApp.env` 永不为 null，`bindEnv(e)` 换 env 时**退订旧的**、`bindEnv(null)` **抛**。消费端只两处，都是「一处裁决」：`env.hasHover` → `UiApp.setHasHover`（**103 处 hover 分支此前没有任何调用者**，这个开关是真的接上了电源）；`env.safeArea` → **声明了 `safeArea: true` 的那个容器的 padding**（`UiNode.foldSafePadding` 把 inset 折进 `resolved.padding`，所以引擎、画笔、动画读的是同一个数；盒子不缩 ⇒ 背景铺到刘海下，只把内容让开；加在作者 padding 上、不继承、只认声明过的边）。`pixelRatio` 是**构造参数**而不是真值 —— 这个运行时没有可读的 DPR（`Capabilities.screenDPI` 是硬编码 96/72）。门 `probes/widgets/env`（43 checks）变异 **7/7**，文档站新增 `env` 页（第 53 页）。**键盘矩形/appState/reduceMotion/isDark/locale 只投递、不消费**（S7/E7/E8/E5/E6） |
| **手指能滚：1:1 拖动 + 惯性（第四十二轮 · MOBILE M1 前半）** | 接在 M0 后面的第 2 件（S1/S2），同样**只动 `asaotui/`**，41 个 kind 仍一行未改：新 `TouchScrollable`（可选能力接口，`touchDragBegin/To/End/Cancel`，走 kind 注册表解析而不是 `kind == "scrollView"`）；`PointerRouter` 越过 press slop 且落在视口里 ⇒ **press 被撤回（发 `MOUSE_UP` 不发 `CLICK`）**，后续 move 全部转发给视口，`cancel` 不滑行；`ScrollViewWidget` 实现 **两套坐标**（按下点定轴、越 slop 点定锚，所以判“这是拖动”的 8pt **不滚内容**）+ 轴锁（选中轴不能滚 ⇒ 消费但不移动）+ 滑行（`getTimer` 实测 dt，`v *= rate^(dt/16.667)`，**纯重绘**自走，不抬布局位）；`ScrollViewNode` 新字段 `momentum`（默认 true）与 `decelerationRate`（默认 0.95，(0,1) 越界**抛**）；**程序化滚动取消滑行**（作者写 `offsetY=0` 必须赢过动量）。门 `probes/widgets/touch-scroll`（26 checks）变异 **10/10**；写探针抽出两个真缺陷：整个位移被吞（`startDrag` 没把“越 slop 的那一点”交给接口）、作者的程序化滚动在滑行中看不见（`payload` 只在 describe 跑）。**回弹/分页/嵌套仲裁仍未做** |
| **触摸可路由（第四十一轮 · MOBILE M0）** | 移动端第一块地基落在**协调者层**，41 个 kind 一行未改：`Pointer`（可变指针状态；路由判定不额外分配，兼容层每派发一次仍要 new 一个 `MouseEvent`）+ `PointerRouter`（滚动容器内 `pressDelay` 130ms、slop 8pt、长按 500ms、取消序列）+ `InputConstants`（阈值唯一出处），`UiApp` 新增 `pickAt`/`dispatchPointerMouse`/`setHasHover`。**合成 mouse 兼容层**让 touch 序列走进既有的 `MOUSE_DOWN/UP/CLICK` 通路；**命中不是库自算矩形** —— 用引擎的 `hitTestPoint(x,y,true)`，再拿真引擎指针在同一点派生 hover **逐点对账**（4 点，含根 padding 的反向断言）。门 `probes/widgets/pointer-touch`，变异 **7/7**（其中一条**第一次是绿的**：同一个 slop 判决被 `move()` 和 `end()` 各写了一遍，删任一处仍有另一处兜着）。**真触摸仍挂 G5**（窗口后端不产生 `TouchEvent`），本轮只验路由与按压语义，不假装平台输入 |
| **`overflow` 从「存了不画」变成真的裁剪窗口（第四十轮 · G29 结案）** | 样式字段 `overflow` 从第一版起就被接受、被校验、也进了布局引擎，但**没有任何画笔消费它** —— 120px 的 `overflow:"hidden"` 盒子里塞 200px 子件，子件照旧画满 200 并盖住邻居（登记 G29）。编译器侧先取证再动手：`adl 51.4.1` 与我们 AOT 十格**逐像素相同**（子树/孙件/跨界描边/滤镜外溢/`cacheAsBitmap` 烘焙/嵌套/`TextField` 子件/半透明遮罩全一致）⇒ **不是编译器缺口**，缺的是库侧消费。落地 `UiNode.applyOverflowClip()`（在 `arrangeSelf` 里写 `backing.scrollRect`，`hidden`/`scroll` ⇒ `rect(0,0,absW,absH)`，矩形缓存在 `extra` 里**只在边长变化时重写**：`scrollRect` 的 setter 存的是拷贝，读回来比对根本检测不出未变）。三处口径都在代码与样式页写清楚：**边界是边框盒而不是 padding 盒**（底色/描边画在同一颗 sprite 里，按 padding 盒裁会让表面明显内缩；CSS 能按 padding 边裁是因为它把这两样画在裁剪之外）、**命中测试跟着裁**（溢出到盒外的子件不再可点，与 CSS `overflow:hidden` 一致）、**节点自身的 box shadow 也被裁**（阴影是 backing 内的滤镜，两者都要就挂在 wrapper 上）。判据 `probes/widgets/clip`（已进门名单：三行同尺寸盒子，`hidden`/`scroll`/`visible` 对照组，窗内像素 + **窗外 4px 像素** + 子件 rect + `scrollRect` 恰好 `(0,0,120,28)` + 缓存同一性 + **窗内点击到达 / 窗外点击不到**），变异实测删掉那一行调用 **6 条断言全红**；`style` 页那一节从「accepted, not yet painted」改成「画到哪儿停」，两格演示**真的不一样**了 |
| **组件文档站（53 页，控件 100% 上站）** | `ui-demo/demo/Docs*.as`（18 个文件）+ `demo/DocsMain.as`：左侧 **10 组 / 53 页**索引（可滚动），右侧每页 = 标题 + 摘要 + meta + 若干节，每节 = 标题 + 说明 + **live demo** + **产生它的源码**（示例与源码出自同一次 `render()`，所以不会漂移）；侧栏切页由 `model.pick` 驱动，页面矩形**先手算再断言**，并落 8 张截图；**每个注册过的 kind 都在某一页上看得见**（`tools/kind-coverage.cjs` 覆盖门 **41/41**，变异 4/4）；tour 把「无 engine 节点 / 零矩形 / backing 未挂」**升级为判据**（变异自证），并在浮层页额外钉「切页后 `stage.numChildren` 回基线 + `findByKey(ovlDlg)==null`」；**`--air-app` 构建（描述符即窗口真相源，已开高分辨率）** |
| **输入类三件 + 只挂窗口的列表（第三十四轮）** | `numberInput`（数字框 + 步进器，**唯一写点 `commit()`**：clamp→round→回调，打不进字的文本**回滚而不是当 0**）、`rangeSlider`（一轨双拇指，倒置区间在**工厂里交换**，契约是 `onRange(lo, hi)` 而不是 Binding）、`multiSelect`（**勾选后菜单不关**，`values` 归作者）；`list`/`tree` 的 **`virtual: true`** 抄 `virtualList` 的契约（`offsetY` + `onScroll(y)`，mounted = `ceil(视口/行高)+1`，纯裁剪，选中行是**绝对行号**），并**主动拒绝** `separator` 与「视口高度不是显式点值」两种写法。判据 `probes/widgets/inputs`（**50 项**，变异 **8/8**）；写探针逼出两个**摸不到/点了没反应**的库级缺陷：行只画文字 ⇒ 命中链落到根（修法 alpha-0 铺满整行），以及点击 `mouseDown` 把 `stage.focus` 清空 ⇒ 键盘死（修法控件自己 `focusNode`）。 |
| **运行时主题切换（第三十六轮）** | `Theme.setTheme(ThemeTokens.dark())` 之后**整棵树在下一帧变暗**，默认亮色**逐字节不变**。四条取色通路都要接上，缺一条就有控件留在上一套配色：**paint-time**（`Theme.tokens()` 在绘制时读，18 个自绘控件 + 5 个节点类）、**factory-baked**（`table.as` 之类烘死的 `StyleRefinement` ⇒ 必须重新 describe）、**每 kind 基线**（`setTheme` 重建 `_defaults`）、**浮层 chrome**（`OverlayChrome.rebuild()`）。`setControlDefault` 改成 **override 层**：跨 swap 存活，主题一换再也不静默抹掉作者定制。暗色的状态混合方向与亮色相反（press 比 hover 更亮，否则按下去看不见），`knob` 保持纯白。判据 `probes/widgets/theme`（**75 checks**：一棵树画三个相位、12 个采样点 × 3、15 个矩形前后比对、6 条契约；第三个相位是**真点击**——`onClick` 里调 `setTheme`，也是文档站 demo 走的那条路）；变异 `tools/mutation-widget-theme.cjs` **8/8**；记 `reviews/theme-2026-10-27.md` |

| **非指针输入 + 可拖分隔 + 键位表（第三十五轮）** | 三件「界面里一定有、库里却没有」的东西，都不加绘制型控件： ① **右键**：`Element.onRightClick(x, y)`（用的是**本帧事件坐标**，不是节点局部坐标），`menu({ atX, atY })` 让它成为一个点锚菜单（点哪儿弹哪儿）， `Control.doubleClickEnabled`/`Element.onDoubleClick()` 同步接上——**双击必须显式打开**，与 AIR 一致； ② **`splitPane(first, second, opts)`**：两段是普通子节点，控件只拥有「主轴份额」与「拖拽」，份额是**一个 `ratio`** 而不是两个尺寸（窗口变了它仍然成立）， `minSize` 是**两侧地板**且 `measure` 与拖拽**两处都夹**（只夹一处时作者写的 `ratio` 能穿过去，探针用 `ratio: 0.02` 才打到）； ③ **键位系统**：`ActionRegistry`（`register` 动作 + `setKeymap` 整表安装，**首条命中即赢**，修饰键**精确匹配**）+ `KeyStroke`（`"ctrl-shift-s"` 解析）+ `ContextExpr`（`"editor > modal"` 这类上下文谓词，`a > b` 即 a 是 b 的祖先）+ `Control.action`（有动作时 Enter/Space 走动作而**不再**走 `onClick`）与 `Control.tabIndex`（`-1` = 没有显式序，不是「不可 Tab」）。判据 `probes/widgets/actions`（**73 项**，变异 **11/11**）。 写探针逼出一个真缺陷（缺陷 #29）：**`tabIndex` 从声明起就是死字段**；实现时第一版拿复用数组当 visited 表，**第二次调用起丢项**， 于是 Tab 在 `btn3` 与 `btn` 之间弹跳——最终改成「输出向量自己当 visited 集」。同一轮还拆了两个「只报条文、不报代码」的门： `kind-coverage` 把**字符串里**的工厂调用当成真调用，`demo-options` 的共享键表是**手抄副本**（`applyOpts` 一扩容就开始冤枉正确代码），现都改成从源码派生。
| **控件集 4 → 41 个 kind / 47 个工厂** | 第一批：`radio`/`toggle`/`slider`/`progress`/`divider`/`badge`/`avatar`/`card`/`chip`/`tabs`/`list`（`probes/widgets/{chip,form,display,nav,anim}`：19/41/48/41/14）；第二批：`image`/`scrollView`/`spinner`/`skeleton`/`tooltip` + `table`/`accordion`/`breadcrumb`/`pagination`（`probes/widgets/{media,feedback,data}`：43/43/77）；**第三批浮层六件**：`dialog`/`drawer`/`popover`/`menu`/`toast`/`select` + `overlay`/`toastHost` 宿主（`probes/widgets/overlay`：**65**）。**每个都配手算断言的端到端探针，且每个探针都做过变异测试**。**第四轮**补的不是新控件，而是把已有控件「点亮」：`disabled` + `hover/pressed/focused` 四态绘制（18 个绘制型控件自动受益）、`textField` 编辑回写、键盘/焦点管线、浮层翻转/子菜单/入场动画。**第五轮**补了两块空白：**动画深度**（`Anim` 分 paint 5 字段与 **layout 字段**——`width`/`height`/`padding`/`gap` 的动画会**每帧重解布局**；浮层加 **120ms 退场**）与**四个选择类控件**：`virtualList`（千级列表只挂 9 个节点；`probes/widgets/vlist` 26 项 / 变异 6/6）、`tree`、`combobox`、`datePicker`（三者同在 `probes/widgets/choice`：**44 项** / 变异 9/9） |
| **浮层系统（第二棵保留树）** | `View.renderOverlay()` + `UiApp.overlayRoot`：主树 describe/reconcile 完后**再**解浮层树、最后画、置顶；锚定弹层读锚点**本帧**矩形；`OverlayChrome`（调色板/风格常量）与 `OverlayList`（菜单/下拉共用行几何 + `localYIn`）集中复用；可选的 `WidgetTeardown` 销毁钩子（`Widget` 接口不加方法）。证据 `probes/widgets/overlay` **65 项**、变异 **9/9**（其中 5 例是把真缺陷重新植入）。**第四轮**加了三样：**越界四向翻转 + 夹回窗口**（`probes/widgets/flip` 54 项 / 变异 5/5）、**子菜单**（`menu` 的 `submenuIndex` 挂一个普通 `menu`，先 `isInside` 排掉被子菜单吃掉的点击）、**入场动画**（`OverlayMotion`，140ms 墙钟，落地即停零重画） |
| **样式面 18 → 33 字段** | `justifyContent`/`alignItems`/`alignSelf`/`alignContent`/`flexWrap`/`margin:LengthEdges`/`inset:LengthEdges`/`position`/`overflow`/`display`/`aspectRatio`/`boxShadow`(数组)/`cursor`（**树内继承**，最终写进程级 `Mouse.cursor`）+ 动画两字段；非法字符串**抛错** |
| **动画** | `anim/`（`Ease`/`Tween`/`Anim`）+ `Style.transitionMs/Ease` + 每帧 `View.tick(nowMs)`（时钟用单调 `getTimer()`） |
| **键盘 / 焦点 / 输入（第四轮，全新）** | `UiApp` 接 stage 的 `KEY_DOWN`/`FOCUS_IN`/`FOCUS_OUT`：**Tab / Shift+Tab 焦点环**（遍历保留树，不用运行时 `as_tab_scan`；浮层内是**焦点陷阱**）、`Esc`、方向键、`Enter`/`Space` 激活（`TextField` 除外）；控件通过**可选接口** `WidgetKeys`/`WidgetFocus` 参与（`Widget` 契约不动）。`textField` 的 `Event.CHANGE` 回写 `Binding`/`onChange`，`Enter`/失焦提交 `onCommit`，`Esc` 回滚，占位符是**独立文本层**、重绘不擦字（`probes/widgets/interact` **25 项** / 变异 **8/8**） |
| **修掉 28 个真框架缺陷** | 纯 paint 变更不上屏；子树布局变化永不解算；keyed 重排不重解；**auto 文本节点忘加自身内边距**；**浮层树永不再解**；**面板无 shapeA**；**`width` 选项撑坏 layer**；**`e.localY` 是 TARGET-relative**；**可见性翻转不上屏**；**销毁的弹层仍监听 stage（`#1009`）**；**浮层宿主留在 stage 上**；**旋转 spinner 只画一次**（被「每帧误判窗口尺寸」遮住）；**输入框一重绘就擦字且 `onCommit` 永不触发**；**翻转定位读到上一帧的 parent 尺寸**（缩窗后永久偏出 80px）；**入场动画在手泵帧的 tour 里永不落地**（整层 3% 透明，所有矩形断言却全绿）；……**滚动条被内容盖住**（`internalCount` 把条层算成内容基点 ⇒ 条只在「这一帧恰好重绘」时才回到上面；改成 `UiNode.aboveContent` 后不再依赖重绘）——**都带钉子与变异证据**，详情 [`STATUS.md`](STATUS.md) §3.3 |
| **验收文化** | **62 道门每道都做过变异测试**（改 1 个单位必须变红）；探针协议与「会咬人的事实」见 [`CONTRIBUTING-widget.md`](CONTRIBUTING-widget.md) |
| **逐个 demo 审计（第三十二轮）：能力要么演出来，要么写清楚做不到** | 拿「每个 kind 的每个 option / 每个横切能力」对照 52 页的每一个 live demo，补齐 **9 节**：容器的 `onClick`（`box` 就是按钮）、`textAlign`/`italic`/`letterSpacing`/`leading`、`spinner` 的 `spin:false` + `phase`、`icon` 的 `viewBox`（同一份数据有无 viewBox 差在哪 —— 被切掉的那个 glyph 才是证据）、`image` 的 `smooth`（必须是**渐变**源，硬边两种设置像素相同）、`table` 的 `grid` 细线、`scrollView` 的 `offset`（“出生就滚过”要看得出是被裁）+ 条宽/条色/轨色、`pagination` 的 `page` 接 `Binding`（写值在 `onSelect` **之前**，点当前页两者都不发生）、以及四个浮层各一节（`closeOnScrim` / `side:"bottom"` / `closeOnOutside` / `submenuIndex`）；**横切能力单独成组**（第十组 `System`：`style`/`theme`/`state`/`keyboard`）。审计顺手掏出两个真缺陷：① **`text` 节点根本没有 paint box**（`TextWidget` 不建 `shapeA` ⇒ `PaintKit.paintBox` 早退 ⇒ `background`/`borderColor` 被接受却什么都不画）—— 已修 + 探针第 7 面 + 变异 **M9**（9/9）；② **`overflow` 没有任何画笔消费**（布局存了、也进了 Yoga，但两侧 painter 都不裁剪）⇒ 文档页照实写成 “accepted, not yet painted”，登记 **G29**，并指出今天真能裁剪的两条路（`scrollView` 的 viewport、`image` 的 `cover`）—— 「画不出来就明说」胜过一张会骗人的图 |
| **滚动条 + 流体外壳（第七轮）** | `scrollView` 现在自带**纵/横滚动条**：thumb 按比例算长（地板 24px）并 1:1 跟手拖拽；点轨道翻一屏；`scrollbarX/Y` 的 `auto`/`always`/`never`（非法值**抛**）；`offsetX` 现在**真的进 `scrollRect`**；无竖向可滚时滚轮**回落横向**。条是**覆盖层**（不参与布局 ⇒ 不改变任何矩形，也避免 scrollbar-gutter 反馈环）。新增门 `probes/widgets/scrollbar`（手算 thumb/track 几何与像素）与变异 4/4。文档站外壳改成**流体**（`ROOT` 百分比 + 两列 `flex:1`），tour 里加一段真实的**尺寸变化**（写 stage 宽高 + 发 `Event.RESIZE`，即窗口 glue 所做的两件事）并断言 `side/main/docScroll/nav` 四块矩形、再变回去 |
| **文档站不再教错用（第八轮补）** | 点击 `toastHost` 页的 “Show two toasts” 会把控制台刷满 `asaot.ui.toast: unknown tone 'info'`：页面示范了 chip 的语气词，而 `toast` 只认 `default/success/danger` 且**按契约抛错**。顺着这条做了一次源码扫描（`tools/demo-options.cjs`：工厂**真的读**的键 vs 页面传入的键），又抓到两页同类：`tooltip` 把 `tone` 传成字符串（`Number("info")` = NaN ⇒ 每帧重绘、填充色 0）与 `arrow: "bottom"`（不在 up/down/left/right/none 里 ⇒ 不画箭头却白占 6px）；`progress` 传了它根本不读的 `tone`。三页已修；tour 新增 **`6d toastHost`** 阶段（真按 stage 坐标点按钮，断言两条 toast 的角栈矩形 x=764 / 下沿 684 / 间距 8，再翻回 `open` 断言全卸载）并加「切换页面那一帧条层必须是 backing 的最后一个子件」，变异 **3/3**（`tools/mutation-docs-tour.cjs`，含用户遇到的那个回植）；新门 `tools/demo-options.cjs`，变异 3/3。截图变化顺带揭出**滚动条被内容盖住**这个从第七轮就存在的老缺陷（§3.3 第 25 条，修法 `UiNode.aboveContent`） |
| **滑块拖不动、一点就报错（第九轮补）** | 用户报告：拖一下滑块，控制台一行 `#1063 Argument count mismatch`，滑块不动。两个缺陷叠在同一个控件上：四个开关类控件（slider/checkbox/toggle/radio）调 `onChange()` **不传参**，而文档站每页都声明 `function (v:Number)` —— AVM2 上**参数个数不符就抛 #1063**，帧守卫接住 ⇒ 回调从未运行、模型未变；并且 `SliderWidget` 本身**没有拖动机制**（按下设值，移动无效）。修法：四个调用点补参数 + `SliderWidget` 重写（按下设值，拖动期间在 **stage** 上临时挂 `MOUSE_MOVE`/`MOUSE_UP`，`endDrag` 幂等 + `teardown` 摘除，单一写入点 `commit()` 且值没变不报）。**两层钉子**：行为门 `probes/widgets/callback`（24 项、变异 8/8，唯一会点**未绑定**控件的探针 —— 旧 `form` 探针只点绑定的，走 `Binding` 分支压根不经过 `onChange`；像素断言取在**拖动中间那一帧**，否则松手时 pressed 态的重绘会掩盖「没自抬重绘」）+ 静态门 `tools/callback-arity.cjs`（**双向**扫描：kit 调用点恰好 1 实参、文档站/探针声明恰好 1 形参，`onClick` 两边 0；变异 6/6） |
| **死节点上的监听器：`#1009`（第十二轮补）** | 用户第四次报告「**多点了几次报错**」：`TypeError #1009 … at asaot.ui::UiNode/setHover()`。`destroySubtree()` 摘得掉显示对象、**摘不掉自己挂在那张 backing 上的匿名监听器**，而 AIR 的 `mouseOut` **晚一拍**才投递（先结束帧、再重算指针目标）⇒ 闭包落到已置空的字段，`accordion`/`dialog`/`drawer`/`menu` 四页中招。库侧加 `UiNode.listen()` 登记三元组 + `destroySubtree` **先** `releaseListeners()`，全库 **24 处 / 16 个文件**改造。**AOT 侧结构上看不见**：`emit.ts` 里 `mouseOver` 出现 **0 次**（逐对象 roll-over/roll-out 从未发出）⇒ 登记缺口 **G25**。**新门三道**：`probes/lifecycle`（10 种 kind × 5 事件，销毁后派发不抛且不污染活节点，9 项）、`tools/listener-wiring.cjs`（禁止裸 attach，扫到 0 处也算失败，29 wired / 0 raw）、以及给 `air-sweep` 加的**指针钻**（离开每页前悬停该页**每个叶子**，切页后**下一拍**投递 roll-out：3107 hovered / **348 真的已销毁** / 0 错）。变异 4/4 + 3/3 + **5/5** |
| **`setChildIndex` 越界：AIR 报错、我们静默放行（第十一轮补）** | 用户第三次报告：`select`/`combobox`/`datePicker` **一点下拉就每帧招 `#2006`**、页面冻住。真因一层在库（`fixDisplayOrder` 用**描述下标**算显示位，而弹层把属主 `lifted` 出去后“占描述槽不占显示槽”⇒ 下标多算一），另一层在**编译器**（`emit.ts:11635` 对越界索引直接**夹紧**、对非孩子直接 `return`，而 AIR 抛 `#2006` / `#2025`）。夹紧到末尾恰好是正确落点 ⇒ **像素一模一样**：42 页截图、全部 AOT 探针、41 道门都看不见。库侧改成**只数“在用”孩子**的槽位计数器（结构性不可能越界）；编译器侧**未动**，登记为缺口 **G24**（含“为什么值得修”：修好后任何 AOT 探针碰到同样错法就会**具名变红**）。**新门 `tools/air-sweep.cjs`**：本仓第一道真跑参考运行时的门（`mxmlc` → `adl` → 42 页 × 每页开关 10 个弹层 → 读应用自己写的 `air-trace.txt`），变异 **3/3**（把槽位计数改回 `internalCount + i` 就报 `#2006`；去掉打开弹层就缺 `OPENED`；少走一页就红） |

| **pointer realism + images that actually load（第十五轮补）** | 两件都不是「缺功能」而是**语义差**。① **hover 在 AOT 里从来是死的**：库只挂 `MOUSE_OVER`/`MOUSE_OUT`，而 `emit.ts` 里那个串**出现 0 次**（G25）⇒ `adl` 里亮、我们自己的产物里永远不亮，而 42 页截图、全部 AOT 探针、整套像素对比全绿——**因为没任何东西让指针动一下**。修法：`UiApp` 接**一个** stage `MOUSE_MOVE`，命中判定**复用运行时的 `as_pick_hit`**（自算矩形就是第二套规则 —— “亮着但点不到”正是它的后果），再经 `backing → UiNode` 字典把**整条祖先链**置 hover（AIR 的 roll-over 会冒泡），`Mouse.cursor` 每次从链上重推、否则回落 `auto`。新探针 `probes/widgets/pointer`（23 项，变异 **5/5**）。② **`image()` 的 `src`**：控件自己持 `Loader`（COMPLETE→采纳 Bitmap 并**重新测量**；IO_ERROR→写 `UiNode.loadError` + `onError(msg)`，**不画自造的错误 chrome**）；`onLoad()` 零参、`onError(msg)` 一参走已有的 arity 契约；`scaleMode` 未知值**抛错**（文档页过去写的 `letterbox`/`zoom` 从未合法，`zoom` 一直静默渲染成 contain ⇒ 页已重导）。新探针 `probes/widgets/imaging`（27 项，变异 **5/5**）；顺带按新语义重导了 `probes/widgets/callback` 的滑块像素钉（指针停在滑块上就是 hover 态：裸轨道 #E5E7EB → #E7E9ED = 8% 提亮） |
| **table 三件（排序/列宽/虚拟化）+ 滚动贴底（第十六轮补）** | 四件里第一件是**缺陷**不是缺功能：**这个表几乎点不到** —— 运行时按**绘制区域**取命中目标，而表只画 1px 网格线与字形 ⇒ 在一个空单元格中间点一下，目标是**表背后的根**，行根本选不中（只有恰好压在网格线上才行）。旧 `data` 探针看不见，因为它用 `clickLocal` **直接向 backing 派发**、绕过了命中测试。修法：`shapeA` 先画一个**全透明命中矩形**（alpha 0 仍是区域，命中测试不看 alpha；运行时注释里写的就是这条 Flash 惯用法），不动一个像素。② **排序**：`onSort(column, descending)` **只报意图**，秩序归作者的 `sortColumn`，箭头从它画（表头不可能声称行不具备的秩序）；循环是浏览器那套（另列→升序、同列→降序、再点→**-1 无序**）；`TableNode.sortRows` 排**拷贝**（qsort 不稳定 ⇒ 原始下标做 tie-break，且**在降序翻转之后**才加），数字比数字、文本比文本（Qty 排得出 1,2,10）。③ **列宽**：拖拽只画 1px 预览、**release 时调一次** `onColumnResize(index, width)`、**从不回写 `columns`**；松手后窗口 glue 补的那个 CLICK 被吞掉，否则“调列宽”会顺手排序；坐标走 `localX/localY` 而不是 `stageX/stageY`（手工构造的事件 stage 坐标恒 0）。④ **虚拟化**：只挂可见窗口 + 一行被 `scrollRect` 裁掉的半行，header 不滚、body 高 = `height - rowHeight`（所以必须 POINT 高度）、行 key 用**绝对下标**。⑤ `scrollView.stickToBottom`：**每帧问一次“上一帧我在末尾吗”** —— 更新 `maxOffsetY` 之后再问永远是否；新视图算末尾（日志开屏即最新一行）；0.5px 余量不是容差（滚一格就该撒手），滚回末尾自动重粘；自动滚动是**真的移动**（`onScroll` 发、`offsetY` 写回）。判据：`probes/widgets/table2`（变异 **6/6**）、`probes/widgets/stick`（变异 **5/5**）。顺带发现 `gates.cjs` 的探针名单是**手写枚举**，上一批的 `pointer`/`imaging` 一直**没人在跑** ⇒ 四道全接上，门 46 → **50 道** |
| **icon：图标通道，以及它撞上的那条底层缺口（第十七轮补）** | `icon(svgPathData)` 表面是“加一个控件”，底下先撞到 **G26**：`Graphics.cubicCurveTo` 与 `Graphics.drawPath` 在 `emit.ts` 里**一个字都没有**（17 个 `Graphics_` 成员只有**二次** `curveTo`，Skia 桥也没有 `cubic_to`），而图标集（Lucide/Material/Feather）的曲线**绝大多数是三次**——放在编译器侧修要动 `as3compiler/`，本工作区不碰，于是**绕行放在 AS3 侧**：`M L H V Z` 与 `Q T` 直译，`C S` **自适应细分转二次段**（偏差上界 `(√3/36)·|P0−3P1+3P2−P3|`，超容差就 de Casteljau 二分；容差 = **四分之一渲染像素**换算成 viewBox 单位），`A`（椭圆弧）**抛错并自报 G26**——把弧画成弦会得到“看着对、形状错”的图标，正是本项目拒绝的那类失败。转换在 AS3 侧 ⇒ 两个臂跑**同一串二次段**、跨臂逐像素一致，代价是对原 SVG 有可量化偏差（探针采三次曲线 **t=0.5** 那一点：它恰是第一次二分的分割点，所以精确；若是弦那里是空白）。顺带推翻一条**堵了整条路**的过期实测：5 处注释写着"本后端 `lineStyle` 描边宽度不生效"，重测为**假**（`lineStyle(2/4/6/8/12)` 在直线/二次曲线/圆 r=7,14,20/矩形上**精确等于声明宽度**）⇒ 描边方案可用，但那批 1px 填充**保留**、理由从"后端做不到"改成"这是选择"。判据：`probes/widgets/icon`（**57 项**，变异 **6/6**，其中 3 个是**负例**：`A` 抛、未知命令抛、`icon()` 在 describe 期抛）+ 文档站新增 `icon` 页；门 50 → **51 道** |
| **第三条臂：`./build.sh web`（第十八轮）** | 同一份 AS3 树编到**浏览器**（`--target wasm --package web`，Emscripten 3.1.44），一条命令：建 → 起服务（`.wasm` 必须带 `application/wasm`）→ 打开。窗口是「一个可执行文件」而页面不是，所以它有自己的运行器（`web-gallery.cjs`：暂存到独立的 `air-gallery-web/`、逐字节复制描述符、随页发一个字体）和**自己的入口类**（`DocsWeb`；`DocsAir` 用了本编译器没实现的 `UncaughtErrorEvent` ⇒ wasm 编不过，`DocsMain` 用 `Stage.render` 测试钩子）。底下撞到 **G27**：`as-aot` 直接 spawn `<EMSDK_HOME>/upstream/emscripten/emcc`（`#!/bin/sh` 脚本、PATH 还是 `:` 拼的）——Windows 上实测 `ENOENT`，而换成 `emcc.bat` 是 `EINVAL`（Node 裸跑 .bat），只有 `cmd /c` 能跑。当时编译器侧未动，绕行是 `tools/emcc-launcher.c` 编出的 4.5 KB PE 转发器；**G27 已在 v0.4.240 修掉，该转发器与 `.scratch/emcc-shim/` 已整体删除**，`--check` 改问 `as-aot doctor`（同一个 `webToolchainError()`）。像不像（v0.4.239 抗锯齿后重测）：**canvas 1500×1050、标题相同、48 点采样 46 点逐点相同**、墨量差 0.85% —— 两个不同点与最大的颜色计数差（按钮蓝 −5.1%）都出在文字上，因为页面**自带字体**（wasm 读不到宿主字体）而原生臂用系统字体。门 `tools/buildsh-web.cjs`（**26 项**，~5 s：编译器说能起 emcc **且**那个程序就在 `$EMSDK/upstream/emscripten/` 里，再加一条「存在但退出 1 的 emcc 必须被判不可用」、钉 argv、钉拒绝、钉「暂存目录仍在库外」）+ 变异 **7/7**（含「门不再相信编译器的结论」与「又把 SDK 外面的 emcc 报出来」）；门 51 → **52 道** |

| **G24/G25/G26 修好之后：把妥协编码撤掉（第十九轮补）** | 三条缺口在编译器侧一次修完（阶段二百七十五，v0.4.239：`setChildIndex` 的三条 AIR 判据与判据顺序、逐对象 `rollOver`/`rollOut`/`mouseOver`/`mouseOut`、`cubicCurveTo`/`drawPath`/`GraphicsPathWinding` + Skia `cubic_to` + 抗锯齿），于是把库侧当初为它们写的东西逐条重判：**近似撤**（`C/S` 自适应细分 → 原生三次；`parse` 的 `tolerance` 参数随之取消）、**拒绝撤**（`A` 弧实现：SVG 1.1 端点→圆心 + ≤90° 切段 + `4/3·tan(d/4)` 手柄，误差 ≤ 2.7e-4·r；紧凑弧标志按**单字符**读）、**自算留**（hover 仍由一条 stage `MOUSE_MOVE` 合成，但现在的理由是**设计与一致**——命中必须与 click 同源、一个窗口一个监听器——而不是缺能力）、**绕路留且现在被运行时守卫**（`Reconciler` 槽位计数器，越界已由引擎抛 `#2006`）。12 处「因为引擎做不到」的陈旧注释改写。探针侧：`probes/widgets/icon` 57 → **66 checks / 变异 7/7**（旧 t=0.5 采样点对「原生 vs 细分」**无区分度**，新增 **t=0.789** 那一点才咬得住降阶；`A` 从负例变**几何正例**：两条弧拼整圆），`probes/widgets/pointer` 新增**跨流对账**（在 stage 接引擎自己的 `MOUSE_OVER`，用**原始 `e.target`** 比对库的 hover）/ 变异 **6/6**。两件**有意不做**已登记（填充仍用 `beginFill` 而非 `drawPath(nonZero)`，理由见缺口表；hover 不改成逐对象事件）。全表见 `compiler-gaps.md`「库侧妥协编码审计」、`STATUS.md` §3.17b |

| **G27 修好之后：把工具链绕行删干净（第二十轮补）** | G27 在编译器侧修完（阶段二百七十六，v0.4.240：`emccPath()` 在 win32 选 `emcc.bat` 并走上 `cmd /d /s /c`、`PATH` 用 `path.delimiter`、子进程环境继承宿主、诊断区分「不在」与「在但起不来」），库侧当初为了绕行写的东西就只剩成本，于是逐处删除：`tools/emcc-launcher.c`（4.5 KB PE 转发器）、`shimHomeForWindows()`、`EMSDK_HOME -> .scratch/emcc-shim/` **全部移除**，`EMSDK_HOME` 重新就是真 SDK。同时把三处「拷贝了一份待测逻辑」的地方改掉：`--check` 不再自己 spawn `emcc`（旧版还故意用 `:` 拼 PATH 复刻坏环境），改问编译器自己的 `doctor`（同一个 `webToolchainError()`）并报告它**实际会启动的那个程序**；`findEmsdk()` 由「`emcc` 或 `emcc.bat`」改为**按平台只认一个**；门 A1 由「能打印版本号」改为「编译器说 ok **且**那个程序就在 `$EMSDK/upstream/emscripten/` 里」（反 shim）+「**存在但退出 1** 的 `emcc.bat` 必须判不可用」。门 25 → **26 项**、变异 6/6 → **7/7**（旧 M3 的 launcher 变异退役，换「门不再相信编译器的结论」，新增 M7「又把 SDK 外面的 emcc 报出来」）。验证不靠推理：**无 shim** 真编译 `./build.sh web --no-serve` ⇒ exit 0，页面在 Chromium 里真画出 Getting started 页；48 点采样重测 **46/48**、墨量差 0.85%（差异全在文字：页面自带字体）。全表见 `compiler-gaps.md` G27、`STATUS.md` §3.11c |

| **在线 demo（第二十一轮）** | 文档站不再需要「先克隆 5.4 GB 再编四分钟」才能看见：`web` 臂的产物发布到 `gh-pages` 分支，GitHub Pages 直接服务 <https://raygyoe.github.io/as3compiler-asaotui/>。发布器 `tools/publish-pages.cjs` 只做搬运，并守三条不变量：**逐字节**（暂存时每个拷贝 sha256 不符就拒、树没变就不建提交、`--check` 比的是部署后的字节数而非状态码——「200 + 过期 7 MB wasm」与「200 + 正确 wasm」在状态码上长得一模一样）、**分支而非 `main` 下八个文件**（`.gitignore` 的口径是「输入与不可再生证据入库、可再生产物不入库」，`air-*/` 属后者；`gh-pages` 正是 GitHub 的服务来源，于是口径不必破例，克隆 `main` 的体积也不变）、**走 plumbing 而非 `git checkout --orphan`**（工作树带着 5.4 GB 被忽略的产物，切分支会先重写所有被跟踪文件）。发布内容只有 8 个文件：`index.html`（= `GalleryApp.html` 改名）、`GalleryApp.{js,wasm,data}`、`fonts/arial.ttf`、`app.xml`、`.nojekyll`、`README.md`；**不**发布 `air-gallery-web/` 现有内容，因为那里还有 `GalleryApp.c`（5.6 MB）、`src/`（19 份 `demo/*.as` 拷贝）与 `GalleryApp.build.json` |

| **四件「有槽位、没行为」的空缺（第二十二轮）** | 不加控件，只把**早就在、却做不到事**的四处补上 —— ① **键盘导航**：`list`/`table`/`tabs` 三者都 `implements WidgetKeys`（实现者 8 → **11**）。`list`/`table` 用 **CLAMP**、`tabs` 用 **WRAP**（listbox/grid 是**序列**，tab strip 是**环**，这是 ARIA 语义不是口味），且**端点也消费按键**，否则键会落到滚动祖先；virtual table 选中后 `reveal()` 把行滚进**已挂载窗口**（否则 index 对、模型动了、屏幕上什么都没有）。② **`accordion` 多开**：`mode` 收 `single`/`multi`，multi 走 `openIndices`（一组）、single 走 `activeIndex`（一个），**互斥且错配直接抛**；集合**升序重建**、比较与顺序无关；header key 带上本 accordion 的 key 前缀（同页两处 accordion 过去都出 `h0`）。③ **`image` 的 `cover`**：`scrollRect` 开窗裁剪，窗口必须**除以缩放系数**（renderer 把窗口 clip 在对象自身矩阵里，24 单位的盒子在 3x 图上等于 72 设备像素 ⇒ 图被裁没，实测三个采样点全 `#ffffff`），**退出 cover 必须清窗口**。④ **下划线/删除线/上划线**：`TextStyle.textDecoration` + `getLineMetrics()` **逐行自绘** —— 因为 renderer 从不画 `TextFormat.underline`（`as_tf_html_emit_run` 第一句就是 `(void)underline`），已登记为缺口 **G28**。证据：探针新建 `keys`（**36 项**）/`accordion`（**18 项**），扩充 `textfx`（18）/`imaging`（31）；变异 **keys 4/4、accordion 4/4、textfx 8/8、imaging 8/8**，全部逐字节还原；门 52 → **54**，54/54 PASS。 |

| **同一轮的下半场：文档站把四件事演出来（第二十二轮补）** | 探针是给变异机用的，读者打开文档站看到的还只是「已支持」一句话 —— 所以同一轮给六个页面各加了节，每节 = 说明 + **能上手试的 demo** + **产生它的源码**：`list`/`table` 的「Focus it 之后按方向键」（末行仍停住 ⇒ CLAMP 可见）、`table` 的「virtual 选中行滚进窗口」（200 行表按 Down 到窗口边缘后偏移才开始走，End 到底 = `of 4312`）、`tabs` 的「Billing 上按 Right 回到 Overview」（列表会停、条带会绕，一眼看清两种形状）、`accordion` 的「Every header has its own key」（`demoAccM:h0` 的前缀不是装饰）、`image` 的「cover: fill the box, then crop」（同一条 16×8 双色带、同一个 96×96 盒子：`fit` 上下留白，`cover` 铺满并裁掉两侧；顺手删掉上一版那句如今已变错的 **「There is no cover/fill」**）、`text` 的「下划线/删除线/上划线」（含一条换行长句 —— 换行后**每行各自一条线**，这就是「线来自 `getLineMetrics`」的直接证据）。键盘 demo 一律带 **Focus it** 按钮，而不写「点一下再按方向键」：AIR 的 `mouseDown` **不会**把焦点给普通 Sprite（只有 `TextField` 会，编译器的 `as_focus_from_mouse_down` 就是这么实测的），焦点来自 Tab 环或 `app.focusNode()`。验收：`run-gallery` PASS（43 页 / `badPages=0` / `overflowingBlocks=0`）、`mxmlc-check` `OK -- 103111 bytes`、`gates` **54/54**。 |

**写 demo 时暴露的三件事**：① **我们的编译器接受尾逗号，mxmlc 不接受** —— 生成的小节里每行说明都带逗号，AOT 全绿、`run-gallery` 也 PASS，只有 AIR 臂的 `mxmlc` 报 `应为 BRACKET_CLOSE，而实际为"new"`，而且**指向下一个元素**（真凶在它上面 25 行）；没有那道门，这个文件会以「AOT 绿」的状态合进去，AIR 臂从此编不过。② **tour 的「子件不许跑出自己的块」看不见控件自己的溢出** —— multi 示范给 accordion 150px，三个 header 加两个展开面板要 160px，面板画到盒子外面，而所有块级断言仍是绿的（溢出的部分没出 demo 面）。③ **`button` 收的是 `(opts)`，不是 `(label, opts)`** —— 写成 `button("Focus it", {...})` 时前端报的是**外层那句** `column(...)` 参数过多，一眼看去像是 `column` 的问题；写新 demo 前先读工厂签名，比猜错误信息快。

**经验（比这些 bug 本身更值钱）**：前两个缺陷在**单页探针里永远看不见**——只有
「多页共用槽位、换页时换掉整棵子树」这种形态才会暴露；最后两个（销毁的弹层还在监听 stage、
浮层宿主留在 stage 上）只有**建了再拆**的程序能看见——**探针从不拆树**。
⇒ **探针要配一个真实应用，而且要让它换页。**
第四轮又添一条：输入框的「一重绘就擦字」只有**真的去敲字**才看得见；入场动画的「永不落地」
只有**截图**才看得见（它把所有矩形断言都躲过去了，因为位置是对的、只是不可见）。
⇒ **断言要打像素，不能只打矩形。**
第十二轮又添一条最贵的一课：**一个没有指针的 UI 门，等于没测指针类缺陷。**AIR 不能脚本化点击，
那就自己 `dispatchEvent` —— 门需要的从来不是 OS 指针，是**事件**。上一轮的 `air-sweep` 自称「真跑参考
运行时」，却一个指针事件都没发过，于是 hover / press / leave / 监听器寿命这一整类缺陷从它旁边整齐地走过去。
⇒ **门要能说「我这次到底咬到了什么」**（`destroyed` 348 就是钻头是热的证据），而不是只说「没报错」。
第十六轮又添三条：① **一个控件“能点”不是布局属性，是绘制属性** —— 透明的地方就是点不到的地方
（运行时按绘制区域取命中，而表只画 1px 网格线）⇒ **像素全对、矩形全对、点击全失效**；而旧探针用
`clickLocal` 直接向 backing 派发，恰好永远绕开命中测试 ⇒ **能绕开命中测试的夹具抓不住命中测试的 bug**。
② **一个控件“看着在动”也不等于它在动**：`stickToBottom` 要问的是“上一帧我在末尾吗”，
问晚了每帧都是否 —— 而这种错在截图上看就是“没跟着滚”，和“写了但没生效”长得一模一样。
③ **探针名单是手写枚举就是探针不存在**：`gates.cjs` 里的数组没人追加，上一批的两道探针就一直绿在门外。
⇒ **“全绿”要先问“谁在跑”**。
第十七轮再添两条：① **注释里的“实测”会过期，而它一旦过期就会替后来者做决定** —— 五处注释说描边宽度不生效，于是图标只能走“离线 flatten 成填充”这条贵得多的路，而那条路本来**不需要被走**；一条旧测量把整条通道堵死了。⇒ **凡是“这个后端做不到”的判断，必须带一条能重跑的命令**。
② **变异漏了先怀疑夹具，不要先怀疑变异** —— I3（忽略 viewBox）第一次没咬住，因为字形是**居中**的：缩放从 4 变 2 之后路径**仍落在同一条 y 上**，只有**描边厚度**变了。补一个“带子最上一行”的采样点才红。⇒ **对称性会把一半的错误藏起来，采样点要挑在“对/错两态不同”的那个像素上**。

## 目录内容

| 路径 | 是什么 | 状态 |
|---|---|---|
| `ui-toolkit-feasibility.md` | **主文档**：GPUI 借鉴评估（中文，技术裁决） | 评估（已回灌 U1 实测） |
| `ui-toolkit-feasibility-en.md` | 主文档英文镜像 | 评估（已回灌 U1 实测） |
| `ui-toolkit-api-design.md` | `asaot.ui` 的 AS3 侧 API 草案（L3 作者模型，1352 行） | 草案 |
| `u1-scope.md` | U1 范围一页纸（做/不做/DoD/已知边界） | 计划 |
| `u1-implementation-plan.md` | U1 实施计划（阶段号与版本号、file-by-file 改动清单、回退路径）——**已搁置，仅备查**（原文是 native/Yoga 路径；当前走纯 AS3） | 计划（搁置） |
| `MOBILE.md` | **移动端（iOS / Android）支持分析与改造清单**：拿 [`nsh.dev/elements`](https://nsh.dev/elements/) 的 48 个 element 逐项对表（✓19 / ~14 / 缺 9 / 不做 6）+ **P/S/E/N/T/A/B 七组机制缺口**（每条带 文件:行 证据）+ **17 个新增组件**（`navStack`/`appBar`/`tabBar`/`sheet`/`refresh` …）+ **可直接照抄的 API 形状**（`hitSlop`/`pointerEvents`/`Pointer`/`Env`）+ 里程碑与红线；证据一条命令 `node tools/mobile-gap-scan.cjs` | 计划 |
| `compiler-gaps.md` | **编译器底层支持缺口登记（G1~G29）**：`System.exit` / `flash.accessibility` / Tab 上限 64 / `-w` / 触摸 / wasm+C++ / **定义规则不强制** / **符号名冲突**（**已修**） / **`Boolean(Object)` 退化**（**已修**） / `Date.now` / ~~生成不确定~~（**非缺口**）/ ~~大分配后挂起~~（**非缺口**）/ **`--air-app` 闭包**（已修）/ **`Array` 进 `Object` 槽（G14，✅ 已修）** / **`getQualifiedClassName(Dictionary)`（G15，未修）** / **`cond ? null : X`（G16，✅ 已修——库内 if/else 绕行已撤）** / **G17 Windows 生成的 C 语法错** 与 **G18 非 Cocoa 菜单钩子未定义**（✅ **两条上游已修，本地补丁已撤，编译器树 CLEAN**） / **`drawRoundRect` 圆角（G19，✅ 已修）** / **`setTextFormat` 追加 run（G20，✅ 已修）** / **`getTextFormat` 忽略 run 表（G21，✅ 已修）** / **闭包内静态读丢 `_cinit()` 守卫（G22，✅ 已修）** / **`setChildIndex` 越界夹紧而不抛错（G24，✅ 已修——库侧槽位计数器成为第二层守卫）** / **AOT 侧从不向对象派发 `mouseOver`/`mouseOut`/`rollOver`/`rollOut`（G25，✅ 已修——库侧 hover 合成保留，理由改为设计与一致）** / **`Graphics.cubicCurveTo` 与 `drawPath` 整条缺失（G26，✅ 已修——库侧自适应细分与 `A` 抛错均已撤，改用原生三次与真弧）** / **Windows 上 `--package web` 起不来 `emcc`（G27，✅ 已修——库侧 PE 转发器已删）** / **`TextFormat.underline` 与 `htmlText` 的 `<u>` 只解析不绘制（G28，✅ 已修 v0.4.303——按 `adl` 实测的 1 设备像素口径自绘，不用 Skia `TextDecoration`；库侧 `textDecoration` 保留：`line-through`/`overline` 是 AIR 没有的增强）** / **`overflow`「存了不画」（G29，✅ **不是编译器缺口**——`scrollRect`/`mask` 编译器早就有，缺的是库侧消费，2026-10-30 已落地 `UiNode.applyOverflowClip()`）**；含实测证据与判定；另把「修好后库侧怎么处置」逐条记下（哪处回退、哪处保留）；**这是唯一登记处** | 登记 |
| `STATUS.md` | **完成度实测表**：分层结论 + 47 个工厂全清单 + 仍缺的控件 + 样式面 33 字段 + **修掉的 29 个框架缺陷（带钉子与变异证据）** + 交互/键盘管线（§3.1）+ **57 道门**的复核命令；§3.9 记着「文档站教错用」的三页修复与两道新钉子；§3.12 记着**参考运行时门**为何必须存在 | 已更新（2026-10-25 第十六轮） |
| `CONTRIBUTING-widget.md` | **控件贡献者契约**：三件套配方（`XNode.as` / `x.as` / `kind/XWidget.as` + 探针）、`Widget` 7 方法逐条 + **`WidgetTeardown` 可选销毁钩子（§2b）** + **`WidgetKeys`/`WidgetFocus` 键盘/焦点钩子（§2c）**、值类型与 unset 哨兵、**会咬人的编译器/平台事实**（§4 通用 14 条 + **§4a 浮层/工厂 14 条** + §4b `--air-app` 专用 6 条 + §4c 集合选型）、稳态零分配、验证方式、报告格式 | 契约 |
| `probes/` | **编译器行为证据探针**（不依赖推理）：`asmdef-rule/`（G7）、`case-rule/`（G7 子规则）、`name-collision/`（G8）、`clock/`（G10）、`bind-truthy/`（G9）、`array-scope/`（G11+G12）、`g11-nondeterminism/`（**G11 结案**，变异 7/7）、**`obj-array-identity/`（G14：26 条×两臂，偏离集现为空，变异 4/4）**、**`style-fromany/`（19 格×两臂，变异 4/4）**、**`g14-minimal/`（最小复现包）**、**`vec-vs-arr/`（两 runtime 对照，变异 2/2）**、**`g16-ternary-null/`（20 格×两臂，偏离集为空，变异 4/4）**、**`g19-roundrect/`（圆角逐行 A/B，0 行分歧）**、**`g20-settextformat/`（run 表替换，12 格关系式）**、**`g21-gettextformat/`（30 格读回矩阵）**、**`g22-closure-statics/`（生成 C 审计，10 格）**、**`widgets/scrollbar`（44 条滚动条例，变异 4/4）**、**`array-coerce/`（`Array(x)` 恒 wrap：8 格 AGREE）**、`arrpush/`、`redraw/`、`widgets/{chip,form,display,nav,anim}`、`widgets/{media,feedback,data}`、**`widgets/overlay`（浮层 65 项，变异 7/7）**、**`widgets/pointer`（指针真实感 23 项，变异 5/5）**、**`widgets/imaging`（`image` 的 `src`/scaleMode 27 项，变异 5/5）**、**`widgets/table2`（排序/列宽/虚拟化 22 项，变异 6/6）**、**`widgets/stick`（贴底滚动 15 项，变异 5/5）**、`kit-crash/`、`graphics-order/`、`silent-null/`、`kit-fill/`、`compiler-crash/`、`reach-freefn/` | 已验（一处入口：`node tools/gates.cjs`） |
| `gpui-borrow-map.md` | **GPUI 借鉴映射表**：每条借鉴都指到 `gpui-src/` 的**具体文件**（尽量带行号）；另列**明确不借**的 6 项及原因。本工作区任何「借 GPUI」的说法必须能落到此表某一行 | 核对口径 |
| `u1-prototype/` | **U1 接缝原型**：`yoga_glue.h`/`.cc` + 手算矩形验收测（17 项全绿） | 已验 |
| `seam/` | **布局接缝契约**：纯 AS3 接口 `asaot.ui.LayoutEngine` + `As3LayoutEngine`（纯 AS3 子集，**已实现 P1~P8**）+ `NativeLayoutEngine` 内建类形态说明 | 契约已定；AS3 侧已实现 |
| `layout-check/` | **纯 AS3 子集验收 harness（文本 + 视觉两半边）**：`CheckMain.as` **133 项**手算断言；`VisualDemo.as` 把布局特性画成真窗口，`visual-check.cjs` 一条命令跑完「建 → 弹窗 → 读帧缓冲 → 断言 → 关窗」 | 已验（**133 + 12 项**全绿） |
| `tools/` | 跨臂通用小工具：`gates.cjs`（**一次跑完 62 道门**，每道都做过变异测试）、**`buildsh-web.cjs`（`build.sh web` 的门：问编译器能否起 emcc + 钉 argv，变异 7/7）**、**`publish-pages.cjs`（把 `web` 臂产物发布到 `gh-pages`：`--stage`/`--serve`/`--check`/`--push`，逐字节校验 + 树未变不建提交）**、**`air-sweep.cjs`（唯一真跑参考运行时的门：`mxmlc` → `adl` → 全目录每一页（当前 53 页，页数从 `DocsCatalog.as` 推导，不手写）开/关弹层 + **指针钻**（悬停每页叶子、切页后投递 roll-out）→ 读应用自写的 trace）**、**`listener-wiring.cjs`（禁止裸 `addEventListener`，且 `destroySubtree` 必须释放；扫到 0 处也算失败）** + `mutation-listener-wiring.cjs`（3/3）、`probe.cjs`（探针运行器：建→弹窗→等证据→比对→退出码）、`bmpdiff.cjs`（报**像素**差异并定位坐标）、`pngread.cjs`（**零依赖 PNG→RGBA**，含 `runs` 行/列颜色游程）、`text-metrics.cjs`（量渲染文字的**字形间距**，把「看着不对」变成测量）、`mxmlc-check.cjs`（源树交给真 AIR 参考编译器）、`demo-options.cjs`（**文档站示范的选项键 vs 工厂真的读的键**，门）+ `mutation-demo-options.cjs`（3/3）、`mutation-docs-tour.cjs`（**文档站 tour 的变异机**：用户报的那个 tone、toast 间距、条层被当成内容基点，3/3）、`as3-index.cjs`、`ls.cjs`（本机 bash 无 coreutils）、`clean-probes.cjs`、`find-bound-truthy.cjs`（`*`/`Object` 静态钉子，**已修「不可能变红」的接线缺陷**）、`mutation-bound-truthy.cjs`、`compiler-fingerprint.cjs`（**复核 `as3compiler/` 零改动**）、`repro-array-scope.cjs`（G11/G12 复现器） | 已验 |
| `diff-check/` | **布局差分测试**：同一份冻结规格（`spec/cases.txt`）喂 Yoga 与纯 AS3 引擎，逐行比对；含单侧变异证明 harness 有牙 | 已验（**三方 105 行逐字符相同**） |
| `air-check/` | **「库能否在 AIR 上跑」的实测**：`mxmlc` 编整个接缝库 + `adl` 运行；`verify-air.cjs` 一键跑完并自动 diff 三臂；`AirKitProbe.as` / `KitFns.as` = 「每个公开类型/每个包级工厂能不能被真 AIR 解析」的逐符号编译探针 | 已验（**105 项**一致）；KitFns 当场抓出 4 个未解析工厂（G7 子规则） |
| `kit/` | **L3 工具链本体**（借鉴 GPUI 的作者模型：`Style` / `Node` / `UiNode` / `Reconciler` / `View` / 控件），纯 AS3，命名空间 `asaot.ui.*`：**47 个工厂 / 41 个 kind**、**33 个样式字段**、`anim/`（paint 5 字段 + **layout 字段每帧重解**）、**浮层（第二棵保留树）**、`WidgetTeardown`/`WidgetKeys`/`WidgetFocus` 三个可选钩子、四态绘制（`PaintKit`） | 建设中（分层结论见 `STATUS.md`） |
| `ui-demo/` | **可运行窗口 demo：组件文档站**（`demo/DocsMain.as` + `DocsModel`/`DocsView`/`DocsCatalog`/`DocsStyle`/`DocsStart`/`DocsLayout`/`DocsText`/`DocsControls`/`DocsPickers`/`DocsData`/`DocsNav`/`DocsFeedback`/`DocsOverlay`/`DocsDemo`/`DocsSystem`/`DocPage`/`DocSection`：**47 页 / 10 组**、每页两个 live 示例 + 源码、手算矩形断言、落 8 张 PNG、含浮层页与 anchored 弹层段）；用 **`as-aot --air-app`** 编译；`run-gallery.cjs` / `build-and-run.cjs` 一条命令建→跑→断言；`check-dpi.cjs` 自证高分辨率成因 | 已验（`RUN: PASS`） |
| `reviews/doc-verify-2026-10-22.md` | 主文档事实校验记录（18 处行号修正、10 处断言证伪） | 已验 |
| `reviews/probe-builtin-implements-user-iface-2026-10-22.md` | 前置闸门探针：**内建类 implements 用户 `.as` 接口**（正例 `x=120` + 反证 `does not implement`）⇒ 架构无需回退 | 已验 |
| `reviews/probe-exit-paths-2026-10-22.md` | 退出路径探针：惯用路径 `NativeApplication.nativeApplication.exit()` **我们已支持且实测跑通**；`System.exit` 才是 AIR 有我们无（G1，影响极低） | 已验 |
| `reviews/probe-pixel-dump-2026-10-22.md` | **像素取证探针**：原生窗口能把自身显示列表落盘成 BMP；**AOT 原生与真 AIR 两张图逐字节相同（0 差异）** | 已验 |
| `reviews/probe-demo-fill-2026-10-22.md` | **demo 底色消失事件**：四次假设、**三次被自己的测量否证**，最后定位为**过期产物（假红）**；沉淀出「先重建再测 / 把变量钉到只剩一个」两条做法与 ASan 取证法 | 已验（无新缺口） |
| `reviews/probe-asmdef-and-name-collision-2026-10-22.md` | **同一输入两侧同编**：AIR 硬拒「一个文件里的异名 public 定义」而我们放行（**G7**）；`bind` 碰撞与 `stat` 被单宏吃掉（**G8**） | 已验 |
| `reviews/compiler-tree-fingerprint.json` | 开工时 `as3compiler/` 工作树脏文件的**指纹**（sha256/16）——用于末次复核「我零改动」；复核器 `node tools/compiler-fingerprint.cjs` | 证据 |
| `reviews/gates-all-9.txt` | **全量 18 道门一次跑绿**的落盘输出（2026-10-23；含新加的 **G14 身份矩阵**与 **Vector vs Array** 两道）；`gates-all-10.txt` 是**改完 G11 窗口钉之后的复跑**；`gates-all-8.txt` 是加门前的 16 道历史留档；`gates-all-11/12.txt` 是**第三轮（组件目录页 + auto 文本缺陷）之后的两次复跑**（**23 道门**）；**`gates-all-13.txt` 是上一轮（浮层六件 + 六页画廊）的定稿（**25 道门**，含 overlay 探针与 `Array(x)` 两臂门）**；**`gates-all-14.txt` 是第四轮（交互动线）的定稿（**27 道门**，新增 `widgets/interact` 与 `widgets/flip` 两道）**；
**`gates-macos-2026-10-31c.txt` 是最新一次完整跑**（**62 道门**：46 PASS / 15 FAIL / 1 SKIP，2026-10-31，第四十三轮新增 `widgets/env`）。15 道红分三类：**9 道是本机没装 AIR SDK**（G14/G19/G20/G21/G22/Vector 吞吐/fromAny/Array(x)/AIR-arm mxmlc，起手 `exit 2`）；**2 道（G13 air-app reach、descriptor DPI A/B）是并发会话正在改 `as3compiler/` 导致的构建失败** —— 生成的 C 报 `static declaration of 'RangeError_new' follows non-static declaration`，而那些程序（`probes/vec-vs-arr`、`probes/array-coerce` 等）**一行 `asaot.ui` 都不含**，与本轮改动无关（同一次并发改动在 `as3compiler` 侧留下 4 个 `M` 文件：`src/emit.ts`/`src/runtime.ts`/`src/symbols.ts`/`test/unit/reflection.ts`）；`G11 determinism` 因树脏报 `0/0 hashes`；其余 3 道（`widgets/choice` 1 项、`widgets/imaging`、`build.sh --gpu` 2 项）是既有红。**上一版 `gates-macos-2026-10-31b.txt`** 是**61 道门**：47 PASS / 13 FAIL / 1 SKIP（2026-10-31，第四十二轮新增 `widgets/touch-scroll`）。13 道红里 **9 道是本机没装 AIR SDK**（G14/G19/G20/G21/G22/Vector 吞吐/fromAny/Array(x)/AIR-arm mxmlc，起手就 `exit 2`），另有 4 道既有红（`widgets/choice` 44 项 1 红、`widgets/imaging`、`build.sh --gpu` 2 项、G11 确定性）；SKIP 是 `docs app on AIR (adl)`（exit 3：测量期间编译器源码被另一会话改到）。`gates-macos-2026-10-31a.txt` 是一次**被截断**的跑（无汇总行，不能引用）；`gates-all-39.txt` 是上一版完整落盘（**58 道门**，第二十六轮新增 `probe perf` 计时门）；`gates-all-37.txt` 是上一版（**57 道门**，第三十六轮新增 `probe widgets/theme`(75) 之后复跑）；`gates-all-36.txt` 是第三十五轮的定稿（**56 道门**）；`gates-all-33.txt` 是第二十二轮的定稿（**54 道门**）；`gates-all-32.txt` 是 G24/G25/G26 妥协编码审计与 G27 收口那次（**52 道门**）；**`gates-all-31.txt` 是第十八轮（第三条臂 `build.sh web`）的定稿（**52 道门**，新增「`build.sh web` 每一条臂都在跑」一道）；**`gates-all-30.txt` 是第十七轮（图标通道 `icon()`，G26 库侧绕行）的定稿（**51 道门**，新增 `widgets/icon` 一道）；**`gates-all-29.txt` 是第十六轮（table 排序/列宽/虚拟化 + 滚动贴底 + 表格命中矩形）的定稿（50 道门，新增 `widgets/pointer`/`widgets/imaging`/`widgets/table2`/`widgets/stick` 四道）；**`gates-all-28.txt` 是第十四轮（阴影 / 渐变 / 换行与截断 / 多行输入）的定稿（**46 道门**，新增 `probe widgets/textfx` 一道）；**`gates-all-26.txt` 是第十二轮补（`#1009` 监听器寿命 + `air-sweep` 指针钻 + G25）的定稿（**44 道门**，新增 `probe lifecycle` 与 `kit listeners are all releasable` 两道）；**`gates-all-25.txt` 是第十一轮补（参考运行时门 `air-sweep` + G24）的定稿（**42 道门**，新增 `docs app on AIR (adl): every page, popups open, no runtime error` 一道）；**`gates-all-24.txt` 是第十轮（`build.sh` 默认臂 + 门 6b5）的定稿（**41 道门**）；**`gates-all-23.txt` 是第九轮（滑块拖动 + 回调参数个数）的定稿（**40 道门**，含 callback 探针与 `callback-arity` 扫描门）；****`gates-all-22.txt` 是第八轮补（文档站教错用 + `demo-options` 门）的定稿（**38 道门**，新增 `docs demos pass only options the factories read` 一道）；**`gates-all-21.txt` 是第八轮（G16/G19/G20/G21/G22 绕行审计）的定稿（**37 道门**，新增 `G21` / `G22` 两道——这两个修复以前**只有探针、没有门**）；**`gates-all-19.txt` 是第七轮后半（滚动条 + 流体外壳）的定稿（**35 道门**，新增 `widgets/scrollbar`；编译器 HEAD `07ed035`）；`gates-all-18.txt` 是第七轮前半（组件文档站：41 页、anchored 弹层段、真点击链路）的定稿（**34 道门**；上一版 `gates-all-17.txt` 是第六轮的 33 道门，新增 `widgets/popup`、`widgets/typing`）；`gates-all-15.txt` 是第五轮（动画深度 + 三个选择控件）的 30 道门留档**；另 `gates-skip-path.txt` = 强制走 `[SKIP]` 分支的集成钉子 | 证据 |
| `reviews/probe-g11-nondeterminism-2026-10-23.md` | **G11 结案**：不是「生成器不确定」，而是**在另一个进程正改写的编译器树上测量**；三份历史产物 + 5 次构建同一哈希 + 变异 10/10 | 已验（非缺口） |
| `reviews/g11-false-red-window-2026-10-23.md` | **G11 的一次假红**：端点哈希对看不见「写入→还原」窗口（并发会话的 mutation harness 恰好保证逐字节还原）⇒ 改为**逐次构建**采样 `src/`、把差异归因给「源码动过」（exit 3 `[SKIP]`），并把**归因本身**做成变异目标 **M6b** | 已修 |
| `reviews/revisit-g8-g9-workarounds-2026-10-23.md` | **G8/G9 绕行复核（本轮）**：底层已修后，当初「为了通过」的决定能不能撤？→ 逐项给出**不能撤**的理由（装箱成本、G14、不把公开 API 名押在 C 名剪辑上），并列出**可改动点清单**；另含 **`Vector` vs `Array` 实测**（AOT 0.18x / AIR 0.92x）。本轮改动：7 处陈旧绕行注释、1 道「不可能变红」的门、2 道新门 | 已验 |
| `reviews/air-sweep-2026-10-24.md` | **只有 AIR 才看得见的 `#2006`**（用户第三次报告）：根因两层（库的显示位算法 + 编译器的越界夹紧）、复现夹具（`air-mode.txt` 驱动器、应用自写 trace、只读 app 目录）、修法（槽位计数器）、三道变异的锚点与结果；并记下 `air-sweep` 这道门**看不见**什么 | 已验 |
| `reviews/listener-lifetime-2026-10-24.md` | **死节点上的监听器：`#1009`**（用户第四次报告「多点了几次报错」）：根因两层（`destroySubtree` 摘不掉匿名监听器 + AIR 的 `mouseOut` 晚一拍）、AOT 为何结构上不可能看见（**G25**：逐对象 roll-over/roll-out 从未发出）、修法（`UiNode.listen`/`releaseListeners`，24 处 / 16 文件）、四道新门与变异结果；核心教训：**一个没有指针的 UI 门，等于没测指针类缺陷** | 已验 |
| `reviews/docs-demo-option-drift-2026-10-24.md` | **文档站的示范与工厂不同步**（用户报告：点 `toastHost` 页的按钮就刷屏 `unknown tone 'info'`）：三页在教工厂不接受的取值/键 → 逐页修；tour 新增「真点击 toastHost」阶段（角栈矩形先推导再断言，变异 2/2）+ 新门 `tools/demo-options.cjs`（变异 3/3），并写明这道门**看不见取值**、那半边只能靠行为发现 | 已验 |
| `reviews/slider-drag-and-callback-arity-2026-10-24.md` | **拖一下滑块就报错、滑块也不动**（用户第二次报告）：4 个开关类控件 `onChange()` **不传参**（AVM2 上实参少于形参 = `#1063`，帧守卫接住 ⇒ 回调从未运行）+ 滑块`没有拖动机制` → 逐项修；新探针 `probes/widgets/callback`（24 项 / 变异 8/8，唯一会点**未绑定**控件的探针）+ 新扫描门 `tools/callback-arity.cjs`（双向，变异 6/6）+ tour 新增「真拖拽滑块」阶段。另记下三个会把夹具做成假绿/假红的坑：手势必须包 `try/catch`（否则 #1063 掀掉派发 ⇒ 不透明 TIMEOUT）、文件作用域初始化按源码顺序发（写在 `showWindow` 之后就永不执行）、像素采样必须取在**单独一次 move 之后那一帧** | 已验 |
| `reviews/web-arm-2026-10-25.md` | **第三条臂 `./build.sh web`**（第十八轮）：同一棵树编到浏览器（wasm32/Emscripten）——为什么它不能复用 `run-gallery.cjs`、为什么需要第三个入口类、**G27**（Windows 上 spawn 不了 `emcc`：`ENOENT`/`EINVAL` 两次实测；当时用 4.5 KB PE 转发器绕行，**v0.4.240 修复后已于同日晚整体删除**）；「像不像」的测量（尺寸/标题/48 点采样 46 同/墨量差 0.85%/差值全在文字，因为页面自带字体）；门 `tools/buildsh-web.cjs` 26 项 + 变异 7/7；**这道门看不见什么**（不编译、不截图、只测过 Chromium） | 已验 |
| `reviews/probe-g14-object-slot-array-identity-2026-10-23.md` | **G14 实测**（**修前登记**，现已成为修复的绊线）：`Array` 进 `Object` 槽不装箱 ⇒ `is Array` 恒假、`as Array` null、`.length` undefined、`is <用户类>` **`0xC0000005`**（**26 条**×两臂；AIR 先自证 26/26 符合手写规则）；`Fill.fromAny` 的 `is Array` 守卫是**死代码** | ✅ **已修**（阶段二百五十三） |
| `reviews/revisit-g14-unlocks-2026-10-23.md` | **G14 修好之后，UI 库能拿回什么（本轮）**：逐项复核 12 处受 G14/G9 影响的库内形状 → **style 层 `fromAny`/`fromArray` 拆分已回退**（`fromAny` 全能化）、**10 处 `*` 与 `bindTo` 不撤**（理由改窄）；含一条已变成假钉子的变异（`mutation-checkui-array-bg.cjs` 的 `M1`）的**重写**与两 runtime 19 格实测 | 已验 |
| `reviews/handoff-g14-to-compiler-2026-10-23.md` | **G14 转交材料**（给编译器侧会话）：一条命令复现 + 期望/实际并排 + 三处根因（`emit.ts:32576` 的 `is Array` 少一个 `object` 分支【邻居 `is Class`/`is Vector` 都有】· `runtime.ts:1178` 的 `as_is` 只挡 `target_vt==NULL` · `runtime.ts:2026` 对 `tag==6` 放行）+ 两条修法路线 + 「修完我们的门会故意变红」的说明 | ✅ 已交付并被采纳 |
| `reviews/revisit-g16-g22-workarounds-2026-10-24.md` | **G16/G19/G20/G21/G22 修好之后的临时应对审计（本轮）**：逐条复核当初为这些缺口写的绕行 → **4 处 if/else 换回三元**、**3 处选项守卫保留**（理由：`if (x != null)` 是「作者给了值才覆盖默认」的最短写法）、`InputWidget` 的「不调 `setTextFormat`」由**禁令变设计选择**、`typing` 探针的 **M3 已随 G20 修复失去牙**（重指后 4/4）、`motion` 与 `compiler-gaps` 的两处陈旧注释改写；含「哪些能撤/哪些不该撤」的逐条结论与全量重跑证据 | 已验 |
| `reviews/mutation-markdirty.txt` | 变异 M1：`markLayoutDirty` 不上爬祖先 ⇒ gallery tour 变红（`colA is at x=0 w=0`，`solves=1`） | 证据 |
| `reviews/mutation-direction.txt` | 变异 M2：`payload` 改方向不同帧重解 ⇒ `colA is at x=24 w=652`（沿用上一页的方向） | 证据 |
| `reviews/checkui-fail.txt` / `checkui-fixed.txt` | `orderChanged` 自我比较缺陷的**真红 → 真绿**记录（`2 of 23 failed` → `23 checks, 0 failures`） | 证据 |
| `gpui-src/` | GPUI 源码本地参考（sparse checkout，只取 `crates/gpui` 等） | 参考 |
| `measurements/` | U1 前置测量产物（Yoga 体积 / wasm 可编性 / DCE 相容性） | 已测 |
| `measurements/u1-wasip1-report.md` | 严格 `wasm32-wasip1` 的诊断与缓解报告（CI 阻塞项 ① 已本机关闭） | 已测 |
| `measurements/wasi-probe/` | wasip1 工具链探针：`build-u1-wasip1.sh`、`wasip1-size.sh`、`run-wasi.mjs` | 已验 |

> **接缝形态（改定：画在 AS3 interface 层）**：布局接缝是**纯 AS3 接口** `asaot.ui.LayoutEngine`
> （契约骨架见 [`seam/`](seam/)），两实现：`As3LayoutEngine`（纯 AS3 flexbox 子集，`mxmlc`→`adl` 可跑）
> 与 `NativeLayoutEngine`（**内建类**才碰得到 C；转发到 Yoga 的不透明 C 接缝 `as_ui_yg_*`）。
> `As3LayoutEngine` **已实现 P1~P8**：**133 项**手算验收全绿（含 config 默认方向成对断言，
> 以及对齐/换行/margin/inset/position 等新字段），
> 与 Yoga **差分 105 项逐字符一致**、并在 AIR 上复现同一批，见 [`layout-check/`](layout-check/)。
> 布局验收基准是 **W3C flexbox / 浏览器**（AIR 无 flexbox，不是 `adl`）；两实现必须**差分测试一致**。
> **实施路径 = 纯 AS3**（`As3LayoutEngine`，已落地）；`NativeLayoutEngine`（Yoga 内建类）**已搁置**——
> 它需要改编译器，按用户 2026-10-22 指示只备查。它所依赖的「内建类 implements 用户 `.as` 接口」
> **2026-10-22 已实测通过**（[`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md)）
> ⇒ 将来若要 native 化，架构也无需回退。

### U1 前置测量的关键数字

| 项 | 实测 | 判定 |
|---|---|---|
| Yoga 链接后增量（native，最优配置） | **94,208 B（≈92 KiB）** | ✅ 通过 |
| Yoga 链接后增量（wasm，emcc 3.1.44） | **123,180 B（≈120 KiB）** | ✅ 通过 |
| Yoga 链接后增量（**严格 `wasm32-wasip1`**，已 strip） | **113,502 B（≈110.8 KiB）**；接缝验收测 134,646 B（≈131.5 KiB） | ✅ 通过（≤192 KiB 门） |
| 未引用 Yoga 时能否整块剪掉 | COFF `-ffunction-sections` + `/OPT:REF` 实测可剪；wasm 侧 `yoga_min−yoga_one = 82.6 KiB`（DCE 在动） | ✅ 通过（macOS `-Wl,-dead_strip` 待 CI） |
| 严格 `wasm32-wasip1` 能力（编→链→**跑**） | `node:wasi` 实跑 U1 接缝验收测 **17 checks, 0 failures** | ✅ 通过 |

**结论：Go（条件）**。**CI 阻塞项 ①（严格 `wasm32-wasip1`）已在本机关闭**——装了`build-tools/wasi/`（wasi-sysroot-34 + libclang_rt）后，能力与预算两项都过。只剩
**CI 阻塞项 ②**（macOS arm64 上 `-Wl,-dead_strip` 剪枝）本机不可测；它红了就退回 AS3 侧 flexbox 子集
（边界见 `measurements/u1-yoga-precheck.md` §6.4）。

> **度量口径警告（踩过的坑）**：wasm 的体积必须按**项目默认口径**量，即
> `wasmStripFlags()`（`as3compiler/src/build.ts:484`，`target==='wasm' && !debugInfo` 时上
> `-Wl,--strip-debug`）。**不 strip 的原始链接会多出 ~205 KiB 的 DWARF**（来自 wasi-sdk 预编译的
> `crt1.o`/`libc.a`，不是我们的代码）——照那个口径量会把 `yoga_min` 读成 321 KiB，从而误判「超预算」。

### 已知被实测推翻/修正的假设

1. 主文档 §8 把「体积」列为首条风险 ⇒ **实测推翻**（零头级，< 3%）。
2. 「接缝需要 CMake 生成配置头」⇒ **不需要**，19 个 `.cpp` + 一个 `-I`。
3. `-DYG_NDEBUG` 在原码里**零引用**，是空开关；关断言只靠 `-DNDEBUG`（省 ≈27 KB）。
4. `__EMSCRIPTEN__` 下 `YG_EXPORT` 带 `__attribute__((used))` ⇒ web 路径 API 全量保留，DCE 弱于 native。
5. 百分比基准口径**实测**为**父的 content box**（非 border box）：`200 − 2×(padding20 + border10) = 140`，`50%` ⇒ `70`。
6. **C⇄C++ 接缝本身只花 2 B**（`floor_cpp − floor_c`）——接缝设计不是体积问题的根源。
7. wasi-libc 的 `vfprintf` + `dlmalloc` 是**任何** Yoga 程序的固有地板（连不做布局的 `yoga_one` 都会拉进来），
   属平台成本而非我们的实现缺陷，按 AGENTS.md §1.5 如实报明、不静默降级。
8. 「`use_web_defaults` 只是配置开关、与默认 flex-direction 无关」⇒ **错**：
   `yoga_glue.h:246-249` 明确 `!= 0` → 默认 **row**（对齐 CSS / GPUI `style.rs`）、`0` → Yoga 自带的
   **column**。AS3 侧原先收下该标志却**忽略了它**（恒 column），已修并在 [`layout-check/`](layout-check/)
   的 f/g **成对钉住**（单方向写错会在对 Yoga 的差分测试里才暴露，a~e 全显式设向故看不见）。
9. 「本机（Windows）跑不了原生窗口，所以只能靠 AIR 验证」⇒ **错**：
   `vendor/{skia,sdl2,curl}/lib/windows-x64` 齐备，`--manifest examples/window.build.example.json`
   直接编出可弹窗的 `.exe`（实测弹出多个真窗口；`stage.showWindow()` 阻塞至窗口关闭）。
   ⇒ 本机可以**用我们自己的 AOT 跑图形界面**，不必借 AIR。
10. 「UI 库还没动手」⇒ **错**：布局层已是可跑代码（101 项验收 + 三方差分），
   L3 工具链与窗口 demo 见 [`kit/`](kit/) 与 [`ui-demo/`](ui-demo/)。

## 三方一致 + 像素一致（2026-10-22 实测）

同一份 `.as` 源码 + 同一组用例，三条工具链输出 **逐字符相同**的 **105** 个矩形：

| 臂 | 工具链 | 引擎 | 入口 |
|---|---|---|---|
| Yoga | clang → native | Yoga（C） | `diff-check/yoga-driver` |
| AOT | 我们的 AOT → C → native | `As3LayoutEngine`（纯 AS3） | `diff-check/as3-driver` |
| AIR | `mxmlc` → `adl`（AIR SDK 51.4.1） | `As3LayoutEngine`（纯 AS3） | `air-check/AirMain.as` |

一键复现 AIR 臂并自动 diff：`cd air-check && node verify-air.cjs`。

这同时验证了两件此前只是**设计承诺**的事：① 整库（含布局）真的能在 AIR 上跑；
② 布局接缝的两套实现没有 drift。细节见 [`diff-check/`](diff-check/) 与 [`air-check/`](air-check/)。

### 再往下一层：**像素也一致**

「同样一份绘制序列」在两条工具链上各自光栅化并落盘成 BMP ——
**我们 AOT→native（Skia+SDL2）与真 AIR（`mxmlc`→`adl`）产出 0 字节差异的同一张图**
（200×120，96054 字节，`differing bytes = 0`）。
⇒ 「同一份 `.as` 源码，两条工具链」的对照从**布局数字**一路钉到**像素**。
取证：[`reviews/probe-pixel-dump-2026-10-22.md`](reviews/probe-pixel-dump-2026-10-22.md)。

> 尤其是 ②：两个**手写** harness 各断言同一组数字是不够的，它們可能两边数字都对、却引擎上分歧。
> 所以 `diff-check/` 让 Yoga 臂与 AS3 臂**读同一份** `spec/cases.txt`；并且做过**单侧变异**
> （把纯 AS3 引擎默认方向钉死 column）—— 差分当场抓到 `f.child1` 不一致。默认方向那个 bug
> 正是这样活下来的：a~e 全部显式设向，默认方向写错也照样全绿。

## 浮层怎么用（`renderOverlay` 第二棵树）

浮层**不写在 `render()` 里**，而是写在 `View.renderOverlay()` 里；返回 `null` 就表示「本页不浮任何东西」，
整棵树会被 `destroyRoot` 拆掉（**不是隐藏**）。`open` 一律归作者的模型所有：

```as3
// 主树照常写；页面不需要知道弹层存在
override public function render():Node
{
    return column({ key: "root" }, [
        button({ key: "ask", label: "Delete", onClick: onAsk }),
        text("…")
    ]);
}

// 第二棵树：只在需要浮层的那一页返回非 null
override public function renderOverlay():Node
{
    if (!model.confirming && model.toasts.length == 0) return null;
    return overlay([
        dialog({ key: "dlg", open: model.confirming, width: 300, title: "Delete?",
                 closeOnScrim: true, onClose: onCancel,
                 footer: [ button({ key: "yes", label: "Delete", onClick: onConfirm }) ] },
               [ text("This cannot be undone.") ]),
        toastHost({ key: "toasts" }, [
            toast({ key: "t1", open: true, message: "Saved", tone: "success" })
        ])
    ]);
}
```

四个必须知道的事实（都有探针与变异钉着，详见 [`STATUS.md`](STATUS.md) §3.6）：

1. **子序列 = 堆叠序**：没有 `z-index`，后写在数组里的在上。
2. **弹层的 `open` 不会自己改**：点遮罩只会调 `onClose`，要你把 `open=false` 并 `invalidate`。
3. **锚定弹层用 key 字符串**：`menu({ anchorKey: "ask", placement: "bottom" })` 在本帧解析锚点矩形；
   不做越界翻转（锚点靠边会出窗）。
4. **关掉不等于销毁**：`open=false` 只是 `visible=false`（保留行/滚动态、不吃点击）；
   只有整棵 `renderOverlay()` 返回 null 才拆节点，而拆时**挂在外部的监听/定时器**由 `WidgetTeardown` 释放。

## 命名空间硬约束

新 API 一律落在**独立命名空间 `asaot.ui.*`**，**不碰 `flash.*`**。
理由见主文档 §6：`flash.*` 是与 `adl` 逐值对齐的面，AGENTS.md §1.5 要求
「增强不得改写任何 AIR 已定义行为」，混进去会让「AIR 同构」失去可判定性。

## GPUI 源码参考（`gpui-src/`）

GPUI 已并入 Zed 单体仓库，故用 sparse checkout 只取需要的 crate：

```bash
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/zed-industries/zed.git gpui-src
cd gpui-src
git sparse-checkout set crates/gpui crates/gpui_macros crates/util crates/refineable
```

体积 8.4 MB（`crates/gpui` 的 Rust 源码约 90k 行）。关键文件：

- `crates/gpui/src/element.rs` —— `Element` 四趟（render / request_layout / prepaint / paint）与「整棵树每帧丢弃」语义
- `crates/gpui/src/taffy.rs` —— 布局接缝（`TaffyLayoutEngine`，`Style → taffy::style::Style` 逐字段转换）
- `crates/gpui/src/style.rs` —— `Style` 扁平值表与 `#[refineable]` 继承
- `crates/gpui/src/tab_stop.rs` —— `TabStopMap`（`Insert`/`Group`/`GroupEnd` + SumTree）
- `crates/gpui/src/keymap.rs`、`key_dispatch.rs` —— actions / key context / 绑定表
- `crates/gpui/src/scene.rs` —— 图元表（`Primitive` / `Quads(Range)` / `bounds_tree`）
- `crates/gpui/src/_accessibility.rs` —— AccessKit 集成
- `crates/gpui/src/_ownership_and_data_flow.rs`、`docs/contexts.md` —— `App`/`Entity`/`Context` 与 `notify`
- `crates/gpui/docs/key_dispatch.md` —— 键盘分派权威说明
- `crates/gpui/examples/` —— 40+ 个可运行示例（`tab_stop.rs`、`grid_layout.rs`、`tree.rs`、`data_table.rs` …）

## 本机环境（测量口径的前提）

- Windows 10.0.26200，clang 23.1.3（`x86_64-pc-windows-msvc`），emcc 3.1.44，node v24.15.0
- **AIR SDK 51.4.1 已装**（`/d/Adobe/Flex_Sdk/AIRSDK_51.4.1`，用环境变量 `AIRSDK_HOME` 引用；不把机器路径写进文档）
  —— 早前「本机无 AIR SDK / 无 adl与mxmlc」的说法**已被推翻**：`mxmlc`（Java 正常）与 `adl.exe` 均可本地运行。
  两个坑：`adl` 默认**常驻不退出**（必须调 `NativeApplication.exit()`）；`trace()` 进不了 Windows 上 `adl.exe` 的 stdout
  ⇒ AIR 侧结果要**写文件**。
- bash 的 PATH 缺 coreutils，**每条 bash 命令前需** `export PATH="/d/Program Files/Git/usr/bin:$PATH"`
- **WASI 工具链**（自组装，供严格 `wasm32-wasip1` 测量）：`build-tools/wasi/`
  - `wasi-sysroot-34.0/` —— wasi-sdk 34 的 sysroot（libc / libc++ / crt1.o）
  - `resource-dir/` —— clang 23 的 `include/` + `lib/wasm32-unknown-wasip1/libclang_rt.builtins.a`（本机 clang 自带的 wasm builtins 缺失）
  - 编译形状：`clang++ --target=wasm32-wasip1 --sysroot=<sysroot> -resource-dir=<rd> -L<sysroot>/lib/wasm32-wasip1/noeh`
    —— **必须用 `noeh`**（用 `eh` 的 libc++abi 会因 `__cpp_exception`/`_Unwind_RaiseException` 链接失败）
  - 运行：`node --no-warnings asaotui/measurements/wasi-probe/run-wasi.mjs <f.wasm>`（`node:wasi`；本机无 wasmtime/wasmer）
- 交叉编译口径以 `as3compiler/docs/zh-cn/compile.md` 与实际 CI 目标（macOS arm64 / wasm32-wasip1）为准
- **wasm 体积必须按 strip 后口径量**（项目默认 `-Wl,--strip-debug`，`src/build.ts:484`）
