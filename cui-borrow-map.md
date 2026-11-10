# CUI 借鉴映射表（每一条都指到 CUI 的具体文件与行号）

**规则**（与 [`gpui-borrow-map.md`](gpui-borrow-map.md) 同一口径）：本工作区任何「借鉴 CUI」的说法，
都必须落到下表的某一行，并给出 **CUI 仓库里的具体文件（尽量带行号）**。没有出处的不写；
写出处却对不上的，删掉。

> 上游：<https://github.com/yappologistic/CUI>（MIT，C99，约 170 个控件，纯即时模式，零第三方依赖）。
> 核实范围：`README.md`、`docs/{design,layout,performance,integration,custom-components}.md`、
> `src/cui_core.c`（848 行全文）、`src/cui_internal.h`（状态/arena 结构）。
> **未核实**：其余约 60 个 `src/cui_*.c` 的实现细节——凡涉及未读文件的说法，本表一律不写。
>
> **结论先说**：CUI 是**真即时模式**（每帧重建整棵树、无 retained 节点），我们是
> **retained 显示树 + keyed reconcile**。所以【功能清单没有可搬的东西】（我们的布局引擎已用三臂
> 逐值验证过，它的 170 个控件大半用不上）；可搬的是【机制】和【试验方法】。

---

## 0. 先对齐坐标系（为什么不是"抄功能"）

| 维度 | CUI（出处） | 我们（落点） |
|---|---|---|
| 树的形态 | 每帧重新描述，节点不复用 —— README「Components are functions … The screen is described again every frame」 | retained `DisplayObject` + `Reconciler` 按 key 复用（`kit/asaot.ui/Reconciler.as`） |
| 跨帧状态 | `cui_id` → 侧表，按 age 回收（`cui_core.c:391`） | `ElementState` / `UiNode.state` 挂在节点上 |
| 布局 | 帧末一趟（`cui_core.c:803-808`，`cui_end_frame` → `cui__layout`） | `As3LayoutEngine`，自家 AOT / Yoga / `adl` 三方逐值一致 |
| 重绘调度 | `needs_redraw` + `next_wakeup`，**整个事件循环可以睡**（`cui_core.c:283-284`） | `ENTER_FRAME` + `_pending`，无脏则跳过（`kit/asaot.ui/UiApp.as:982`），**但每帧仍醒** |
| 命中测试 | 用**上一帧**的矩形（`cui_internal.h:335` 的 `rect` + `has_rect`；`cui_core.c:372-385`） | 当前帧已解出的矩形 + `as_pick_hit`（与 `adl` 校准） |

⇒ 同一个问题（"不重建树怎么跨帧保持状态"）被两套解法回答。**我们的解法没错，它的解法也不必
照搬**；下面借的是它在这套解法里长出来的两件"配套设施"。

---

## 1. 借了，且已落地

| # | 借了什么 | CUI 出处 | 拿过来变成什么 | 落点 / 实测 |
|---|---|---|---|---|
| L1 | **增量帧 vs 全量重绘的逐像素差分** | `docs/performance.md`「How it is measured」：*"Every 1,500 frames it also checks the incremental software frame against a full repaint (a difference fails the run)"*；「Only what changed is drawn」（64 px tile 哈希） | 一道门（**20 checks**）：四个**纯装饰**场景 —— page background / card background+border / 兄弟节点 opacity / card cornerRadii，即 `Style.diffFlags` 归为 `4 = decor` 的那几个（`kit/asaot/ui/style/Style.as:288-295`）。每场景四条断言：(a) 这一帧**确实走增量**（`layoutSolves` 不变），(b) 变化在全量重绘里**可见**（灵敏度对照），(c) 增量画面 == 同状态的全量重绘（**逐字节**），(d) 无残留 `M_PAINT` 位。判据读的是 `BitmapData.draw(stage)`，即**显示树**而不是描述树——所以"描述对了但显示列表是旧的"躲不过去 | `ui-demo/RepaintDiff.as`、`run-repaint-diff.cjs`、`mutation-repaint.cjs`；跑批入口 `tools/gates.cjs` §6e（`--only repaint`，约 14 s 命中编译缓存）。实测 **PASS 20/20**；三条变异 18/20、14/20、12/20 |

**为什么值得借**：`UiApp.as:1147` 那段注释记录过一类真实事故——"the M_PAINT bits were never
consumed, and the change silently never reached the screen"。我们 `tools/gates.cjs:16` 有
redraw **变异**（人为改坏代码看门是否红），但**没有全量真值**：变异只能证明"我们想到的破坏会被抓"，
差分能证明"任何遗漏都会被抓"。这是唯一能自动抓"增量算漏了"的判据。

**落地时实测到的两件事（都推翻了本表初稿的假设）**：

1. **`text` 不能当增量场景（2026-11-09 前）。** `diffFlags` 对 `text` 返回 `2 | 4`（"may need measure for
   auto-sizing controls"，`Style.as:287`），所以改文字颜色**会**重解布局，断言 (a) 直接红。
   第一版场景里塞了一个 `text.color` 变更，实测 13/15 才发觉 —— 判据本身没错，是场景选错了。
   **2026-11-09 子树级 measure 后作废**：`diffFlags` 把 text 拆成 metrics（字体/行高/字距/对齐/wrap/overflow，
   → bit 2）+ paint（含颜色，→ bit 4）两半，颜色变化不再重解布局（见 §3.8）。
2. **灵敏度对照守的是场景，不是调度器。** (b) 比的是"变化前的画面"与"变化后的**全量**重绘"，
   所以它只在"这个变化根本画不出像素"（两种颜色相同）时红。把 opacity 从 `diffFlags` 里删掉后
   —— 变化**依然画得出**，对照仍绿 —— 是 (c) 抓到的。两个断言的分工必须写在文件头，否则下一个
   人会以为 (b) 守着"增量路径真的画了"。

## 2. 明确**不借**的

| # | 不借什么 | CUI 出处 | 为什么不 |
|---|---|---|---|
| N1 | **每帧重建整棵元素树** | `README.md`（"The screen is described again every frame"）、`docs/performance.md`（"Steady frames allocate almost nothing"） | 与 [`gpui-borrow-map.md`](gpui-borrow-map.md) N1 同一条：我们的红线是「禁止在每帧/每循环热路径里产生进 arena 的临时分配」（`as3compiler/AGENTS.md` 内存管理红线；历史 `as_disp_key` 造成 ~39 KB/s 静默泄漏）。它敢每帧重建，是因为**它有一个按帧复位的 arena**——那正是我们要借的东西（§3.1），不是它重建树的行为。 |
| N2 | **`cui_id` 侧表替代节点身份** | `cui_core.c:217-240`（1024 桶 + free list）、`:296-341`（find/entry/rehash） | 我们的 `DisplayObject` 就是节点身份，`Reconciler` 已经按 key 复用；再造一张 id 表等于给同一件事加第二套真相。**仅**在"被回收的虚拟列表行"这种**没有持久节点**的地方有意义（`ui-demo` 的 `VirtualListNode` 已有自己的窗口计算）。 |
| N3 | **把 CUI 源码 vendor 进来 / 手工移植控件** | 整个 `src/*.c`（约 60 个文件，单文件 2–118 KB） | 三条硬理由：① 它必须挂在**它自己的**窗口+渲染器上（`docs/integration.md`：给输入与视口，还你顶点），我们是纯 AS3、必须挂 retained 显示树；② 它的控件外观会成为我们产品的视觉语言，而我们的 demo 是**逐像素对 `adl` 校准**的；③ 170 个控件手移到 AS3 是数人年，且大半用不上（AI chat / kanban / gantt / 终端 / 节点编辑器 / 火焰图）。 |
| N4 | **它的软件光栅器** | `src/render/`（未核实细节）、`docs/performance.md`「Software rasterization」 | 我们已经有 Skia 的 CPU 光栅路径；缺的是**选择逻辑**和**同产物内共存**，不是第二个光栅器（§3.4 只借这两点）。 |
| N5 | **它的 a11y 方案** | `README.md`「Status and limitations」：**"There is no accessibility tree yet. Keyboard navigation and focus are complete."** | 它明确没有无障碍树。我们连 `flash.accessibility.*` 整包都还没有（`compiler-gaps.md` **G2**），比它欠得更前一步；借一个"还没有"的设计没有意义。 |
| N6 | **它的 `cui_inflate` / `stb` 字体与图像栈** | `src/cui_inflate.c`、`src/cui_font_data.c`（360 KB 内嵌字体数据） | 我们的文本引擎已经与 `adl` 校准（阶段二百二十一之后是独立 object 文件）；换字体栈等于把已校准的东西推倒。 |
| N7 | **`##` 后缀式的隐式 ID 作用域** | `docs/custom-components.md`「Compose first」里的 `cui_push_id` / `"##toggle"` | 我们有显式 `key`（`Node`/`UiNode`），并且**重复 key 在同一个父下直接 throw**（`ui-demo/CheckUi.as` 第 5 节已钉）。隐式字符串 ID 会把"重复"从编译期/断言期推到运行期。 |

---

## 3. 借了，**待落地**（本次决定，按价值排序）

### 3.1 帧 arena：按帧复位、按峰值定容

| 借什么 | CUI 出处（核实过的行） | 拿过来变成什么 | 落点 |
|---|---|---|---|
| 一个**只活一帧**的分配区：帧内 bump 分配，帧边界整体复位；溢出块在下一帧释放；容量按上一帧的**峰值**增长；长期过大才缩容 | `src/cui_core.c:26-44`（主块 + 溢出链）、`:46-96`（`cui__frame_arena_reset` 与缩容判据 `cap > 65536 && cap > peak*4 && !overflow`）、`:64`（`peak_arena`） | 运行时增加**第三个**分配器 `as_frame_alloc`，与 `gc_alloc`（可回收）、`as_alloc`（进程级 bump，永不归还）显式三分 | 设计见 [`frame-arena-design.md`](frame-arena-design.md)（本轮只出设计，不改 `src/`） |

**为什么值得借**：我们拒绝 GPUI 每帧重建树的理由是"每帧分配会静默泄漏"——那是一起**真实事故**
（`as_disp_key`，~39 KB/s）。CUI 说明这个风险可以被机制消灭而不是靠纪律：帧内临时对象在帧末被
整体作废，泄漏的成因（忘记 free）在结构上不存在。借到之后，"禁止每帧分配"可以从**人肉红线**
降级为**机制保证**。

**代价（必须写进 ADR）**：新增分配器 = 新增一类生命周期错误（把帧 arena 指针存到帧外）。
缓解手段只能是断言与毒化填充，不是类型系统。

### 3.2 增量 vs 全量重绘的**差分判据**

| 借什么 | CUI 出处 | 拿过来变成什么 | 落点 |
|---|---|---|---|
| 定期把**增量帧**与**全量重绘**逐像素比对，不一致即判失败 | `docs/performance.md`「How it is measured」：*"Every 1,500 frames it also checks the incremental software frame against a full repaint (a difference fails the run)"*；`docs/performance.md`「Only what changed is drawn」（64 px tile 哈希） | 一道门：同一状态下，`paintDirty`（只有 `M_PAINT` 位）产生的画面必须与 `paintAll`（全扫）**逐像素相同**；并且要求这个变化**确实改变了像素**（灵敏度对照），否则门是假绿 | `ui-demo/RepaintDiff.as` + `ui-demo/run-repaint-diff.cjs`（**已落地**，见 §1 L1） |

**为什么值得借**：`UiApp.as:1147` 那段注释记录过一类真实事故——"the M_PAINT bits were never
consumed, and the change silently never reached the screen"。我们 `tools/gates.cjs:16` 有
redraw **变异**（人为改坏代码看门是否红），但**没有全量真值**：变异只能证明"我们想到的破坏会被抓"，
差分能证明"任何遗漏都会被抓"。这是唯一能自动抓"增量算漏了"的判据。

### 3.3 软件光栅检测 + 同产物运行时选后端（Win7 单产物问题的直接证据）

| 借什么 | CUI 出处 | 拿过来变成什么 | 落点 |
|---|---|---|---|
| 同一个二进制里两条渲染后端都在，**运行时**挑；检测到软件光栅（llvmpipe / softpipe / SwiftShader / Microsoft Basic Render）就切软件 | `README.md`「Platforms」表（Windows 7+：OpenGL 3.3 / GDI software fallback）；`docs/performance.md`「A real window」末段（检测与 `CUI_RENDERER` 覆盖）；同段给了 10× 差距的实测（Mesa llvmpipe 27–35% 一核 / ~105 MB，软件 2–3% / 11 MB） | ① 把"编译期 `#define` 三选一"（`window_glue.cc:2942-2946`）改成 GL + CPU 光栅**都编进一个产物**、运行时挑；② 把当前遇到 `GDI Generic 1.1.0` 就**报错退出**改成"识别为软件光栅 → 可回退"；③ D3D12 仍然必须排除（Win7 加载不到 `d3d12.dll`） | 设计口径见 `as3compiler/docs/zh-cn/win32.md` §6 的后续补充（本轮只记录证据，不动窗口后端） |

**为什么值得借**：这是上一轮"Win7 用户 + 单产物"问题的正解形态，而且它给了**可引用的实测数字**
说明为什么"有 GPU 就走 GL、没 GPU 就走软件"不是妥协而是更省。诚实的边界：它的软件光栅是
**自己写的**（永远可用），我们的 CPU 光栅是 Skia 的（也可用），所以这条对我们是可实施的；
它没有的正是我们最擅长的（`adl` 对照）。

### 3.4 懒状态：被 touch 才分配

| 借什么 | CUI 出处 | 拿过来变成什么 | 落点 |
|---|---|---|---|
| `cui__state_lazy(ui, id, size, want)`：只有 `want`（被 hover/按下）时才真正分配状态 | `cui_internal.h:345`（声明注释："NULL while untouched"）；`docs/performance.md`：「What the soak found and fixed」——*"Buttons and links took state on first draw. They now take it only when touched, which cut Chat's allocations per frame from 0.27 to 0.09"* | hover fade / press 这类**瞬态**状态延迟分配；结构性状态（key、居中、layout id）仍随节点走 | `kit/asaot.ui/UiNode.as`（`ElementState` 的惰性化），待做 |

**诚实评估**：收益比 CUI 小——我们的节点生命周期本来就跟着 `DisplayObject` 走，不是每帧新建。
真正有收益的只有"大列表里从没被摸过的行"。

### 3.5 动画即查询（API 形状，不是能力）

| 借什么 | CUI 出处 | 拿过来变成什么 | 落点 |
|---|---|---|---|
| `cui_animate(ui, id, target)` 直接返回**平滑后的值**；`cui_animate_spring(ui, id, target, duration, bounce)`；运动中自请求帧，静止即停，reduced motion 直接吸附 | `src/cui_core.c:704-708`；`docs/custom-components.md`「Animation」 | 作者侧从"建 `Tween` 对象 + 管 `dispose`"变成"值 = f(key, target)" | `kit/asaot.ui/anim/`（`Anim`/`Tween` 已有），待做 |

**诚实评估**：功能我们**不缺**，而且已经解决它没提的问题（哪些属性可动画——只 POINT 长度，gradient
不动画，见 `UiNode.as:761`）。这是**作者 API 的简化**，收益是可读性与"忘记 dispose"这一类 bug 消失。

### 3.6 `design.md` 里那张「什么看起来像模板」的清单

| 借什么 | CUI 出处 | 拿过来变成什么 | 落点 |
|---|---|---|---|
| 一张**反模式**清单（不是"要好看"，是"这些具体做法会读成没人选过的默认值"）+ 一张**正面 token 表** | `docs/design.md`「What generic looks like」（Color/Surfaces/Type/Status/Words/Charts/Coherence 七组）、同文「Tokens」「Spacing」「Motion」三张表 | 我们 52 页文档站与 demo 的视觉审查清单；正面 token 与 `ThemeTokens` / `Theme` 逐项对表 | [`theme-tokens-vs-cui.md`](theme-tokens-vs-cui.md)（本轮产出） |

### 3.7 测试方法学的三个小件

| 借什么 | CUI 出处 | 拿过来变成什么 |
|---|---|---|
| `--storm`：每 10 帧换窗口尺寸与显示缩放，跑完报告峰值内存 | `docs/performance.md`「Checks」（Gallery 峰值 22 MB） | HiDPI / 重排压力门。我们有 `requestedDisplayResolution=high` 的约定（`check-dpi.cjs` 已做 A/B），但没有**连续扰动** |
| 文档截图由测试生成，视觉改动与其文档同时移动 | `README.md`「Development」末段（`tests/component_shots.c`） | 我们有 `demo-options.cjs` 抓选项漂移、`visual-check.cjs` 抓像素，但**文档图**没有像素级门 |
| 体积上限对**固定上游参照**，永不被当前值替换 | `docs/integration.md`「Optional Arabic-script text shaping」末段（MSVC `hello.exe` 必须落在冻结参照 +46,080 B 内） | 我们的体积回归容易按上一次构建漂移；对**冻结参照**才能防温水煮蛙 |

### 3.8 子树级 measure：颜色与固定尺寸文本内容变化不再重解布局

| 借什么 | CUI 出处 | 拿过来变成什么 | 落点 |
|---|---|---|---|
| 「只有改变测量结果的字段才触发重新测量」，颜色不动字形、固定尺寸文本内容不改变 intrinsic size，都只该走 paint | `docs/performance.md`「Only what changed is drawn」（64 px tile 哈希，颜色归为纯绘制变更）、「What the soak found and fixed」（把不必要的每帧失效颗粒拆细） | ① `Style.diffFlags` 把 text 拆成 **metrics**（fontFamily/fontSize/fontWeight/fontStyle/leading/letterSpacing/textAlign/whiteSpace/textOverflow → bit 2）+ **paint**（含 color → bit 4）两半；② `TextWidget` 固定尺寸且非 wrap 的文本内容变化只标 `M_PAINT` 不 `markLayoutDirty`，arrange/paint 共用 `placeRun` 定位 | `kit/asaot/ui/style/Style.as`（`textMetricsEq`）、`kit/asaot/ui/kind/TextWidget.as`（`payload`/`isFixedSize`/`placeRun`） |

**为什么值得借**：live 每 tick 都重建文本 style（`C_CHG.withPatch(...)` 每帧新建 StyleRefinement 对象）
导致 `resolveStyle()` 每帧跑；而旧 `textEq` 把 **color 也算进 `2|4`**，涨跌变色（tone 翻转）就 `markLayoutDirty`
→ 全树 measure + `engine.calculate` + arrange。这与 `PaintKit.measureField` 自己的注释自相矛盾——
它明确写着「Colour is deliberately NOT in the key (it cannot move a glyph)」。失效传播层和测量缓存层的
口径不一致，是本次的根因。

**实测**（`probes/live/scan-rows.cjs`，AOT native，每 tick ~30 次平均）：

| 行数 | measure 前→后 | solve 前→后 | total 前→后 |
|---|---|---|---|
| 22 | 2.6→0.25 | 0.41→0 | 4.02→2.67 |
| 100 | 5.29→0.35 | 1.37→0.06 | 9.98→8.72 |
| 200 | 10.46→0.40 | 3.77→0.28 | 21.32→16.87 |
| 500 | ~26→0.18 | —→0.19 | 60.58→43.62 |

measure 与 solve 几乎归零，但 total 只降 20–28%——因为文本每 tick 真变，**整形成本刚性**转移到
paint（200 行 paint 从 0.35→11.59ms）。这一步只消除了「不该 measure 的失效」，没消除「必须重整形」的
刚性成本。

**后续 dissect（`probes/live/dissect-paint.cjs`，2026-11-09）**：paint 相位的 **89% 是 TextField 整形**
（`field.text=` + `setTextFormat` + `textWidth` 读，M1 摘除后 11.61→1.22ms），sparkline 命令记录只占
10%（M2 摘除后省 1.23ms）、paintbox 占 3%（M3 摘除后省 0.39ms）。runtime 侧 `ASC_PASS_TRACE` 显示
`live=444 cached=23723`——已有 cacheAsBitmap 增量 re-bake（G30），没有「没变却重画」的浪费。
⇒ **「增量光栅化」不是下一步的正确杠杆**：瓶颈是文本整形（语义刚性成本），优化它在编译器 runtime
侧（run table 复用 / 布局缓存 / 短数字串轻量 shape），或库侧虚拟化（gallery 已做）。登记为
[`compiler-gaps.md`](compiler-gaps.md) **G41**。

**门**：`redraw`（14）、`typing`（18）、`textfx`（18）、`display`（48）、`choice`（44）、
`anim`（14）、`feedback`（43）、`layout-check`（133+12）全部 PASS。全量跑在编译器 `bf30a16` 上是
**74/75**（唯一 `interact` 是并发池的时序问题，单跑即绿 25/0）；把编译器换成 `9324353`
（上游 G41 HarfBuzz 快路径）后一度 **73/75**，新增的两道红 `typing` / `tabbar` 是**上游**的
（`kit/` 回滚到 Git HEAD 也原样红，A/B 已证），登记
[`compiler-gaps.md`](compiler-gaps.md) **G42**，证据在
[`reviews/compiler-9324353-asaotui-ab.txt`](reviews/compiler-9324353-asaotui-ab.txt)。
**G42 修好（v0.4.367）后复跑 75/75 PASS（561.3 s）** →
[`reviews/gates-windows-2026-11-10.txt`](reviews/gates-windows-2026-11-10.txt)；剩下的
纵向 ~1.2pt 位移登记为 **G43**（不在门里）。

---

## 4. 与本表的自检

```bash
# 本工作区里所有提到 CUI 的地方（应全部落在上表）
grep -rn "CUI\b\|cui_core\|yappologistic" asaotui --include=*.md --include=*.as
```

> 本机 bash 无 coreutils（无 `grep`），实际用内置 grep 工具或 `node` 脚本执行。
> 每次改动本表后跑一遍，确认没有**无出处**的借鉴声明。

**与 `gpui-borrow-map.md` 的关系**：两张表正交，不合并。GPUI 给我们的是**作者模型**
（Style/refine、keyed identity、notify、Tab 分组）；CUI 给的是**运行时便利设施**
（帧 arena、重绘差分、后端选择）与**视觉纪律**。同一件事出现在两表时（例如"元素身份"），
以本表 §2 的"不借"为准——我们的身份来自 `DisplayObject`，不来自 id 表。
