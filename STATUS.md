# asaot.ui — 完成度实测表（STATUS）

> 回答一个问题：**「UI 库写完了吗？」**
>
> 结论：**核心做透了，表面层补了一轮，但还不是一个完整工具箱。**
> 深水区（布局引擎 + 三端差分）做透；**控件集从 4 个扩到 16 个 kind / 20 个工厂**；
> **样式面从 18 字段补到 31 字段**；**多页可切换 App 已跑起来**（`ui-demo/demo/GalleryMain.as`）。
> 两个 demo 现均用 **`--air-app`** 编译：窗口属性（含**高分辨率/HiDPI**）由 AIR 描述符当唯一真相源。
> 仍然缺的是：**键盘/焦点（0 处）**、覆盖层类控件（dialog/popover/toast/menu）、
> 滚动容器、以及动画只覆盖 3 个字段。
>
> 本表每一行都有可复核的命令。**不要采信本表，跑它。**

生成日期：2026-10-23（第二轮） · 对应 `kit/` **53 文件** · 一次性验收：`node tools/gates.cjs`（**18 道门**）

---

## 1 一句话分层结论

| 层 | 状态 | 判据 |
|---|---|---|
| L1 渲染（Skia + Stage3D） | ✅ 复用编译器运行时 | `layout-check/visual-check.cjs` 12 项像素断言；AOT ↔ AIR 两张 BMP **0 字节差异** |
| L2 布局引擎（flexbox 子集） | ✅ **做透** | `layout-check` **133 项手算断言全绿**；Yoga == AOT == AIR **105 行 0 差异** |
| L2 显示树 / 协调 / 数据流 | ✅ 可用（本轮修 3 个缺陷，见 §3.3） | keyed reconciler + `markLayoutDirty` 上传 + Observable/Binding |
| L2 事件 | ⚠️ **只有鼠标** | 悬停/按下/点击；**键盘 0 处**（见 §3.1） |
| L2 动画 | ⚠️ 只覆盖 3 个字段 | `opacity`/`background`/`borderColor` + `transitionMs/Ease`；`probes/widgets/anim` 14 项 |
| L3 控件库 | ⚠️ **20 个工厂 / 16 个 kind** | 见 §2；仍缺覆盖层与滚动容器 |
| L3 样式面 | ✅ **31 字段**（本轮补齐 13 个） | 见 §3.2；仅剩 `grid`/`boxShadow`/`cursor` 刻意缺席 |
| L3 组合能力 | ✅ **多页可切换 App** | `ui-demo/run-gallery.cjs`：4 页共用 body 槽位、控件驱动切页、手算矩形；**`--air-app` 构建 ⇒ 高分辨率已实测**（`ui-demo/check-dpi.cjs`：standard 700×560 / high 1050×840） |
| L3 可访问性 | ❌ 字段有、消费者无 | `role`/`ariaName`/`Control.tabEnabled` 只是字段 |

---

## 2 作者可见 API 全清单（53 个文件里**只有这些**）

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

配套（非控件）：`bindTo(owner, field)`、`Binding`、`Observable`、`Subscription`、
`Dirty`、`Theme`、`Style`/`StyleRefinement`/`Fill`/`Edges`/`LengthEdges`/`Corners`/`Length`/`Size`/`TextStyle`、
`Node`/`Element`/`ElementState`/`Control`、`Widget`/`Widgets`（控件扩展点）、`PaintKit`、
`Reconciler`、`UiNode`、`UiApp`、`View`、`Anim`/`Ease`/`Tween`/`AnimState`。

### 2.1 仍缺的控件（对照常见工具箱）

| 类别 | 缺什么 | 影响的界面 |
|---|---|---|
| 覆盖层 | `dialog`/`modal`、`popover`、`toast`、`menu`/`contextMenu`、`tooltip` | 任何「确认/提示/菜单」交互 |
| 滚动 | `scrollView`、`list` 的虚拟滚动与视口裁剪 | 长列表、长表单 |
| 选择 | `select`/`dropdown`、`datePicker`、`table`、`tree` | 表单、仪表盘 |
| 图形 | `image`/`icon`（当前无位图控件；`badge`/`avatar` 是文字近似） | 任何带图标的界面 |
| 反馈 | `spinner`、`skeleton` | 异步态 |
| 其它 | `accordion`、`breadcrumb`、`pagination` | 导航类 |

**⇒ 现在能舒适写出的是「多页表单 / 设置页 / 列表详情」，写不出「对话框 + 滚动列表 + 图标」类界面。**

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
| **虚拟滚动** | ❌ `list` 对**每个 item 都建一个真实 UiNode** 并参与布局；万级列表会建万级节点 |
| **视口裁剪 / 滚动** | ❌ 没有 `overflow:hidden` 的滚动容器；`list` 超出自身高度的行会溢出（不裁剪、不可滚） |
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
cd asaotui && node tools/gates.cjs                           # 18 道门，含 layout-check 133 项
```

### 3.3 本轮定位并修复的 3 个框架缺陷（每个都有钉子）

| # | 症状 | 根因 | 修法 | 钉子 / 变异证据 |
|---|---|---|---|---|
| 1 | **纯装饰变更永不上屏**（改 `background` 后画面不变） | `UiApp.reflow()` 的绘制闸门只看 `layoutRan`/`_needsPaint`，而 `Dirty.ALL==15` **不含** `M_PAINT==64` ⇒ reconcile 跑过但没绘制 | `reflow()` 里加局部 `reconciled`（本轮 `_pending != 0` 跑过 reconcile 即为真），绘制分支改 `else if (root != null && (this._needsPaint \|\| reconciled))` | `probes/redraw`（14 项）。**变异**：去掉 `reconciled` 项 ⇒ 3 像素 FAIL / exit 1；还原绿 |
| 2 | **子树里的布局变化永不解算**（多页 demo 里换页后只有容器有矩形，子节点全 `0,0,0,0`；`layoutSolves` 永远 1） | `UiApp.reflow()` 的布局闸门**只读根节点**的 `M_MEASURE\|M_ARRANGE`；深层新建/重排/删除/改样式只在本节点置位 | `UiNode.markLayoutDirty()`：置两位后**沿 `parent` 上爬到根**，遇「已同时带两位」的祖先即停；`applyPayload`(relayout)、`resolveStyle`(f&1 / f&2)、`Reconciler` 新建节点 / 顺序变化 / `destroyMounted` 后父节点 —— 共 6 处调用。**PAINT 位刻意不上传**（祖先自己装饰没变就不该重绘，且纯 paint 变更仍不得重解布局） | `ui-demo/run-gallery.cjs`（第 11 道门）。**变异**：`applyPayload` 里去掉 `directionOverride` 变化时的重解 ⇒ body 沿用**上一页的方向**布局，`colA/colB` 手算矩形 FAIL |
| 3 | **keyed 重排后节点不移动**（CheckUi 的 `reorder moved 'a' down` / `'b' up` 两红） | `Reconciler.reconcileChildren` 在 `n.children = next` **之后**调 `orderChanged(n, next)` ⇒ 两个引用指向同一个数组，比较自我、恒返回 false ⇒ 从不重解 | 把 `orderChanged` 提到赋值**之前**（紧邻仍需要旧数组的销毁扫描） | `ui-demo CheckUi` 23 项。**证据是本轮真红真绿**：修前 `2 of 23 failed`（两句原话见 `reviews/checkui-fail.txt`），修后 `23 checks, 0 failures`（`reviews/checkui-fixed.txt`） |

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

---

## 4 已完成且**可复现**的部分（不是意图，是跑过的）

一条命令跑全部 **18** 道门：

```sh
cd asaotui && node tools/gates.cjs        # 18/18 PASS 才叫绿；参考 reviews/gates-all-9.txt
```

> 那道 G11 determinism 门在「**测量期间编译器源码真的在动**」时会给 `[SKIP]`（exit 3）而不是假红/假绿：
> 稳定但脏的树照样可测（PASS 会点名 `src/` 内容哈希），动了才算测不了。那分支自己也做过集成钉子
> （`reviews/gates-skip-path.txt`：`15/16 PASS, 1 SKIPPED`，exit 0 —— 那份记录是 **16 道门**时代跑的，机制与判据未变）。

| 验收 | 命令 | 期望 |
|---|---|---|
| **多页 App（本轮核心交付）** | `cd asaotui/ui-demo && node run-gallery.cjs` | 4 页 tour 全绿 + 4 张 `gallery-page*.png` + `RESULT: PASS` |
| **高分辨率（HiDPI）自证** | `cd asaotui/ui-demo && node check-dpi.cjs` | `standard` 700×560(1×) vs `high` 1050×840(1.5×)，且两次 tour 文本**逐字节相同** |
| **单页登录 App** | `cd asaotui/ui-demo && node build-and-run.cjs` | 8 项手算断言 + `750×563` 截图（1.5×）+ `RESULT: PASS` |
| **`--air-app` 闭包回归钉（G13，已修）** | `node probes/reach-freefn/run.cjs` | 默认闭包 kept **5/5** 且默认面**能建能跑**（修前是：红 + `unknown superclass 'Base' of 'p_Leaf'`） |
| 工具箱自检 | `cd asaotui/ui-demo && node run-check.cjs` | `23 checks, 0 failures / RESULT: PASS` |
| 控件探针 ×5 | `node tools/probe.cjs probes/widgets/{chip,form,display,nav,anim}` | 19 / 41 / 48 / 41 / 14 checks，全 0 failures |
| 重绘钉子 | `node tools/probe.cjs probes/redraw` | 14 checks，0 failures |
| 布局文本半边 | `tools/gates.cjs` 里的 layout-check 门 | `133 checks, 0 failures` |
| 布局视觉半边 | `cd asaotui && node layout-check/visual-check.cjs` | `12 checks, 0 failures`，EXIT 0（弹真窗 + 读帧缓冲 + 断言） |
| 三端差分 | `diff-check/`（Yoga / AOT / AIR） | 105 行逐字符相同 |
| AOT ↔ AIR 像素 | `air-check/` | 两张 200×120 BMP **0 字节差异** |
| 静态钉子（原 G9 扫描） | `node tools/find-bound-truthy.cjs kit seam` | `0` 命中 / 34 个 `:Object` 局部变量无一当条件用。**这道门曾经不可能变红**（它数一个工具从没打印过的字符串），已修为消费退出码；变异 `tools/mutation-bound-truthy.cjs` **4/4** |
| 「未碰编译器」的仪器自身 | `node tools/fingerprint-parse-check.cjs` | 20 项（含两条前导空格回归断言）；变异 `tools/mutation-parse.cjs` |
| **G11 结案（生成器确定性）** | `node probes/g11-nondeterminism/run.cjs` | 同源 **5 次**构建 → **1** 份生成 C（`f0ac0ff461e604bf`）+ 拼写三处一致 + 三份历史产物误差 20→1→0；变异 `mutation.cjs` **8/8** |
| **G14（新）`Array` 进 `Object` 槽的身份** | `node probes/obj-array-identity/run.cjs` | 26 条×两臂：**AIR 26/26 符合手写 AS3 规则**；AOT 偏离 **8** 条（`is Array` 假 / `as Array` null / `.length` undefined / 5 条 **`0xC0000005`**）；变异 `mutation.cjs` **4/4** |
| **`Vector.<T>` vs `Array`（两 runtime）** | `node probes/vec-vs-arr/run.cjs` | N=1M：AOT `Vector.<int>` fill+sum **2ms** vs `Array` **11ms**（**0.18x**）；AIR 同两项 33/36ms（0.92x）。门只钉 AOT **≤0.5x**；变异 `mutation.cjs` **2/2** |

**每道门都做过变异测试**（改一个单位就让门变红并给出非 0 退出码），清单与每道门的
变异配方写在 `tools/gates.cjs` 头部注释里；落盘结果见 `reviews/gates-all-*.txt`。

---

## 5 结论

- **深水区（布局引擎）**：做透了，且有三端交叉验证——这是本项目最有说服力的资产。
- **中水区（协调/数据流/样式面/控件扩展点）**：本轮补齐并**修掉 3 个真缺陷**——
  其中 2 个（纯 paint 不上屏、子树布局不解算）只有在**多页 App** 这种形态下才暴露，
  单页探针永远看不见。这条经验比这 3 个 bug 本身更值钱：**探针要配一个真实应用。**
- **表面层（交互 / 覆盖层 / 滚动）**：仍是骨架。当前可交付上限约「多页表单 / 列表详情」。

### 补齐优先级建议

1. **键盘 + 焦点 + 输入回写**（§3.1）——投入最小、解锁最大；现在输入框一重绘就擦字。
2. **覆盖层**（dialog / toast / popover）——需要「浮层 + 命中测试优先级 + 模态遮罩」三件事，
   是第一个需要新布局语义（脱离父链的绝对定位）的控件族。
3. **滚动容器 + 列表虚拟化**（§3.1.1）——需要引擎侧支持 `overflow` 的裁剪与滚动偏移。
4. **布局动画**（§3.4）——需要先定义「布局动画为什么要重解布局」。

> 本表所有「缺」项均为**登记**，不是对编译器的修改要求——`asaotui` 侧对 `as3compiler/` **没有做任何修改**；
> 复核：`node tools/compiler-fingerprint.cjs`（快照 `reviews/compiler-tree-fingerprint.json`）。
> 本轮开工时编译器是 `92a1239`/`0.4.208`；收尾时已到 **`1ac26b4`（阶段二五零）**，工作树 **clean**。
> 期间的提交全部是并发会话的（阶段二四九 G13、阶段二五零 `--as-class-path`），**没有一个是我的**；
> 我在本轮只做只读复核与测量（见 §3.5）。
> 全量 **18 道门**在该 clean 树上跑绿（`reviews/gates-all-9.txt`）；另有一份强制走 `[SKIP]` 分支的
> 运行做钉子（`reviews/gates-skip-path.txt`）—— 编译器侧这些提交没有弄坏本工作区。
> 编译器侧缺口登记处仍是 `asaotui/compiler-gaps.md`（G1/G4/G8 上游已修；**G13 已修（阶段二四九）**；
> **G11 已结案为非缺口**（不是生成器随机，而是**在另一个进程正改写的编译器树上测量**，
> 见 `reviews/probe-g11-nondeterminism-2026-10-23.md`）；**G12 已结案为非缺口**（见证程序自身声明顺序）；
> **G9 已修（阶段二四八）但 10 处 `*` 保留**（装箱成本 + G14）；**G14 新登记、未修**
> （`Array` 进 `Object` 槽不装箱，26 格矩阵中 **5** 条直接 `0xC0000005`；转交编译器侧的**最小复现包** `node probes/g14-minimal/run.cjs`）；G8/G9/G14 的复核与可改动点清单见
> `reviews/revisit-g8-g9-workarounds-2026-10-23.md`。
