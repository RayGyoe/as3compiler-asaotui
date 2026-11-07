# rune 借鉴评估（2026-11-07）

> 对象：`https://github.com/anomalyco/rune` → 克隆在 `temp/rune`（HEAD `bca4713`，浅克隆）。
> 口径与 [`gpui-borrow-map.md`](../gpui-borrow-map.md) 一致：**只借规格与语义，不借实现**；本表每一条都指到
> `temp/rune/` 的具体文件与行号，指不到的就不写。asaotui 侧的数字全部由
> `node tools/mobile-gap-scan.cjs` 当场重算（**不引用 MOBILE.md 的历史计数**，那些数已经漂移过两轮）。

---

## 0 一句话

rune 是「自绘 + 自有布局 + 把 IME/无障碍交给平台」这条路上，**唯一把「可观测性」做成了产品**的样本
（每帧可读、可 trace、可回放、可按 key 驱动）。但它**自己也没上手机**（PLAN.md:34 / :588，iOS 只到
预编译 metallib 与 `cfg` 桩），所以它给不了我们手机方案，只给四样东西：
**S6 变高列表与吸顶的规格、a11y 树的构建策略、headless 三件套的形状、以及两条数值/纪律校准**。
其余照旧不借。

---

## 1 核对口径

| 项 | 值 | 复核方式 |
|---|---|---|
| 仓库 | `anomalyco/rune` @ `bca4713`，162 MB（大头是 `demo/` 截图与视频） | `git -C temp/rune log --oneline -1` |
| 核心 `crates/rune` | 784 个 `.rs`，**176,691 行** | `find crates/rune -name '*.rs' \| wc -l` |
| 组件 `crates/rune-kit` | 149 个 `.rs`，**40,162 行** | 同上 |
| 子系统行数 | a11y 2,246 · `runtime/input` 6,889 · `runtime/scroll` 3,001 · `tooling` 7,123 · text 10,327 · edit 5,968 | 按目录 `wc -l` |
| 触摸本体 | `runtime/input/touch.rs` **211 行（含 5 个断言用例）**、`runtime/scroll/touch.rs` **184 行** | 见 §3 R1/R2 |
| asaotui 现状 | 199 个 `.as` / **45 个注册 kind** / 33 个 `Style` 字段 / mouse 耦合 26 文件 186 处 | `node tools/mobile-gap-scan.cjs` |

> 移动端令牌里**仍然全 0**的：`TouchPhase`、`softKeyboard`、`keyboardHeight`、`stageOrientation`、
> `bottomSheet`、`pointerEvents`、`pressDelay`、`screenReader`、`estimatedRowHeight`、`stickyHeader`。
> 后端仍然是 `SDL_FINGER` 0 处、`Stage.softKeyboardRect` 0 处（G5/B 组没动）。

---

## 2 rune 是什么，不是什么

| 维度 | rune 的真实状态 | 对我们的意义 |
|---|---|---|
| 语言/渲染 | Rust + `wgpu`（Apple 上 raw Metal）+ winit，自研 renderer、text、layout 包装（Taffy/Parley） | 架构不可搬（我们是 AS3 → C → Skia 单线程） |
| 目标平台 | README：「macOS, Windows, Linux and the web」 | **没有移动端** |
| 移动端证据 | iOS/Android **只出现在排除条件里**：`clipboard/native.rs:46,61`、`input/drop_pointer.rs:11,17,46,60` 全是 `#[cfg(not(any(target_os = "ios", target_os="android")))]`；iOS 只有预编译 `src/builtin_native_ios.metallib` 与 `gpu/metal/builtin.rs:30-32` 的 `cfg(target_abi="sim")` | 别指望「抄它的手机支持」 |
| 移动端计划 | `PLAN.md:34` 平台顺序 `… → web → iOS → Android`；`PLAN.md:588` `M6 — iOS` 尚为里程碑 | 它和我们**处在同一个缺口位置** |
| 风险自认 | `PLAN.md:215-217`：iOS `UITextInput`/`UITextInteraction`、Android `InputConnection`；「This is the single riskiest area; Flutter's iOS text shim is 3,400 lines and still feels off」 | 直接印证 MOBILE.md T 组的判断（**不要把文本输入当成小活**） |
| 无障碍 | AccessKit 平台适配（UIA/AX/AT-SPI），树在 AS3 侧不存在对应物 | 桥不可搬，**构树策略可搬**（§3 R5） |

---

## 3 借（R1–R12）

| # | 借什么 | rune 出处 | 我们现状（当场核对） | 落地建议 | 挂到 MOBILE.md |
|---|---|---|---|---|---|
| **R1** | **触摸状态机**：`Pending → Drag / Pan` 一次定轴；pan 抢先**取消** press；按下的元素自身可拖则拖它而不是滚页；第二指忽略；`Cancelled` 不点任何东西 | `runtime/input/touch.rs:1-6`（头注释就是完整规格）、`:9` `TOUCH_SLOP = 8.0`、`:11` `FLING_HOLD = 0.1`、`:96-119`（up/cancel）、`:114`（`press_drags`）、`:121-211`（5 个断言） | **已同构**：`PointerRouter`（`isPrimary` 过滤在 `:137`，`cancel()` 在 `:252`）+ `InputConstants`（`PRESS_SLOP_PT 8`:26、`PRESS_DELAY_MS 130`:18、`LONG_PRESS_MS 500`） | **不搬代码，搬断言**：把那 5 个用例逐条翻成我们的探针断言（tap 不点/held 不甩/drag 元素优先/第二指无效/cancel 不点）。我们 8pt 与他们的 8.0 **独立同值**，可作为「这条阈值不是拍的」的旁证 | P1/P2/S1 验收补强 |
| **R2** | **滚动物理**：衰减常数直接写「iOS normal 0.998/ms」；fling 速度 `clamp ±8000`；越界阻尼 `over*0.55/(1+over*0.55/300)`；回弹是**临界阻尼精确积分**（可变 dt 也精确） | `runtime/motion/tracks.rs:4-5`（`SCROLL_DECAY = 2.002`）、`runtime/scroll/touch.rs:78`（0.55 项）、`:15-23`（`rebound`，λ=14）、`:91`（fling 速度 clamp ±8000） | 我们：`OVERSCROLL_RESIST 0.55`（**独立得到同一条 iOS 曲线**）、`SPRING_RATE 0.72/60Hz 帧`、`decelerationRate` 默认 **0.95/帧** | **唯一一条数值冲突**：0.95/帧 = `0.99693/ms` ⇒ λ≈3.08/s，滑行距离只有 iOS normal（λ=2.002）的 **65%**。iOS normal 的等价帧值是 **0.967**。建议把 `0.967` 立为默认、`0.95` 降为 fast 档，用 V4 回放做 A/B | **S2 校准** |
| **R3** | **变高虚拟行的完整算术**：未访问行用估计高度；**测量值按 key 记忆**；测量后**保持可见锚点**；屏外行没有布局/文本/场景节点；只挂载视口±两块，越界新行**每帧最多半视口**；handler 必须按 key 找 item（拿 `i` 会错） | `el/virtual_rows.rs:13-28`（`virtualize` 的承诺：估计高度 / 测量保持锚点 / 屏外无节点）、`:41-75`（`virtual_rows` 契约：半视口节流、只有挂载行对 inspector/a11y/Tab/选择可见、handler 禁止拿 index）、`:76`、`:105` | `VirtualListWidget.as:1-20` 自述「**THIS WIDGET MOUNTS NOTHING**」，固定 `rowHeight`，作者侧挂载；`estimatedRowHeight` / `stickyHeader` 仍 0 | **借算术，不借所有权**：挂载仍归作者（不动 retained 树契约），但搬进三件事：(a) 估计表 + 按 key 记忆测量，(b) 插入/变高后**锚点保持**（读者那一行不动），(c) 越界挂载的半视口节流 | **S6（变高）** |
| **R4** | **吸顶在绘制期做，不动布局**：位移在 paint pass 用当帧 offset 算（「stuck header never trails a scroll」），布局不变，只有绘制/命中/工具读的值动；吸顶元素在兄弟之后绘制；`SHADOW_RAMP 8pt` 淡入阴影 | `runtime/scroll/sticky.rs:1-7`（策略）、`:15`（`SHADOW_RAMP = 8.0`）、`:32`（`Hold`） | `vlist` 是**纯 clip**（`VirtualListWidget.as:11-16`），窗口里只有挂载行 | 这是自绘路线的甜点：sticky = (i) 绘制加 `-min(offset - rowY, cap)` 位移，(ii) 命中同一偏移，(iii) 组头锚点在窗口外时仍挂载。**不改布局、不改窗口算术** | **S6（吸顶）** |
| **R5** | **a11y 树策略**：只在 assistive client 在场时构树（「free until asked」）；一次遍历 + fingerprint（commit/scroll/focus/animating 的 stamp），只发变动节点；**滚动把 offset 当视口自己的 transform**，滚 1 个节点而不是每行；默认值从元素本身推导（role/label/文本/key 即 AutomationId）；**无 key/label/role 的纯布局盒并入父树**；动作走真实 handler | `a11y/tree.rs:1-8`（缓存与 stamp）、`:33-43`（`Stamp` 字段）、`a11y/roles.rs:4-40`（`RoleCtx` 按 pressable/input/scrolls/modal 推 role）、`README.md:2268-2305` | `Element.as` 只有 `role`/`ariaName`/`ariaValue` **形状字段**（scan：`accessibility` 3 处），G2 缺整包 | **拆成 A1a/A1b**：A1a 与 G2 无关、今天可做——把语义树建成 AS3 侧纯数据（role/name/value/state/order/bounds），默认值由 45 个 kind 的既有事实推导（能不能按 / 是不是输入 / 会不会滚 / 是不是 modal），并让它成为 `--tree` 的唯一来源；A1b 平台桥等 G2 | **A1 → A1a/A1b** |
| **R6** | **headless 三件套**：`--snap`（单帧 PNG）/ `--script`（时间戳事件，**可按 key 或 key 路径**定位如 `slider/knob`）/ `--tree`（key/path/role/label/text/rect/target/opacity/hover/press/moving）/ `--trace`（JSONL 逐帧几何）/ 固定虚拟时钟（`--at 0.4`、`mark:end+0.5`） | `README.md:2339-2440`（命令与事件表）、`:2405-2430`（markers/video） | probes + `pngread.cjs` + `frame-perf.cjs` + 58 门；**没有**语义树 dump、没有确定性时钟、脚本按像素坐标 | **V 组新增三项**（都不依赖后端）：V2′ `--tree`；V4′ 虚拟时钟（`getTimer()` 抽成 Clock seam，headless 下由脚本推进，先只服务惯性/回弹回放）；V2″ 输入脚本按 **key 路径**定位（我们已有 `Node.key`/`keyContext`，够用） | **V2/V4 规格** |
| **R7** | **观测面字段表**：`ElementInfo` 每个字段都是「跑一次就能读到的真相」 | `runtime/elements.rs:7-45`（`inert`/`exiting`/`visible[4]`/`revealing`/`scrolling`/`scrolled[2]`/`virtual_extent`/`moving`/`hover`/`press`/`caret`/`help`/`selected`/`level`/`position_in_set`…） | 我们的 dump 还没有（V2′） | **直接沿用这些字段名**（省掉命名争论，且以后能与 rune/GPUI 生态对照阅读）。注意 `hover`/`press` 是 **0..1 的插值**而不是 bool ——我们 hover 121 处、press 由 `MOUSE_DOWN` 置位，正好能对上 | **V2′ schema** |
| **R8** | **commit 诊断**：滚动不该产生 commit，产生了就指名道姓（哪个 handler、在哪一行设的、60 帧里中了几帧）+ `RUNE_COMMIT_BUDGET_MS` 按阶段拆时间 | `README.md:752-771`（含示例文案） | `UiApp.invalidate(dirty)` 有 **dirty 位**与 `invalidateCalls` 计数（`UiApp.as:257-262`、`:62`），**没有「是谁 invalidate 的」** | 采集 `source`（枚举/常量字符串，**热路径不许拼串**），在 headless 门里断言「滚动 60 帧内 `invalidateCalls ≤ N`」。这能直接抓住我们历史上「滚动每帧重绘」那类回归 | **V3/V5** |
| **R9** | **motion gate 的规则分类**：逐帧记录每个元素 presented rect/可见部分/opacity + 绘制属性（OKLab 颜色/圆角/模糊/阴影）+ 整窗几 pt 一格的粗栅格；规则名 `snap`/`flash`/`changes-twice`；刻意变更由 `Tx::instant`/`motion_intent`/`Spring::NONE` 豁免 | `motion_gate/mod.rs:1-12`（用法与豁免语义） | 无 | **只取几何一条**：逐帧 dump（R6 的 trace），断言「非动画期元素 rect 变化 >1pt 必须是脚本事件引起」「滚动期间 row 的 rect 只能整体平移」。全量（`check.rs` 47 KB + 逐帧栅格）不抄 | **V4** |
| **R10** | **反模式审计脚本**：88 行 awk 的 grep 级 checklist，`--strict` 下 findings 即非零退出；一条 finding 是「去看一眼」，不是判决 | `scripts/app-audit:1-4`（自述）、`:20-88` | 我们有 58 门（结构不变量）与变异测试，**没有**「反模式扫描」这一层 | 写 `tools/ui-audit.cjs` 查我们的红线：`new` 在 move 热路径、`hover` 分支里 invalidate、vlist 挂全部行、frame 内阻塞 IO、有 `scrollToIndex` 却无估计高度。**与 58 门同层，不并进 `gates.cjs`** | **V5** |
| **R11** | **契约型结构的加字段纪律**：`AppSpec`/`Env`/`TextStyle`/`ScrollSpec`/`LayerSpec`… 是应用侧**字面量构造**的，加 `pub` 字段会破坏调用方 ⇒ **一律加 builder 方法** | `AGENTS.md`（"Apps build these types as literals…"）；配套 `scripts/file-size.sh`、`folder-shape.sh` | 我们刚加的 `Env` 正是这种契约（`Env.as` 接口 + `EnvBase` + `DesktopEnv`） | 把这条写进我们的规范/门：**契约型 interface/struct 只准加带默认实现的成员**。文件行数阈值**不抄**（`AGENTS.md` §2.8 明确「不设行数拆分阈值」） | 规范/门 |
| **R12** | **reduced motion 由平台偏好驱动，且默认真用**：宿主创建与窗口焦点变化时填充；headless 默认 `false`，测试可 `set_system_reduced_motion()` | `README.md:1147-1155`、`platform/preferences.rs` | `Env.reduceMotion` **有字段、有 notify、没有消费者**（`UiApp.as:553` 自己写着 "reduceMotion needs E8"） | 消费者只留一个裁决点（`Anim`/过渡起点），headless 默认 false、探针可注入——口径与 rune 对齐即可 | **E8** |

---

## 4 不借（N1–N8）

| # | 不借什么 | rune 出处 | 为什么不 |
|---|---|---|---|
| N1 | **每帧重建整棵元素树 + diff**（`view()` 每帧返回新 `El` 树） | `PLAN.md:228-256`（State 一节，含 "Rejected: fine-grained signals / immediate mode"） | 我们是 retained 显示树 + keyed reconcile；`AGENTS.md` 内存红线禁每帧 arena 分配。**要的是它的 key 身份纪律，不是 diff 机器**（已在 `gpui-borrow-map.md` B4 落地） |
| N2 | **Taffy / Parley / HarfRust / AccessKit 依赖** | `PLAN.md:80`（tenet 6「Owned, not wrapped」）、`:198-227`（Text/IME/Layout 三节怎么用它们） | Rust 生态；我们的对应物是自研布局引擎、`TextField`、以及**尚无**的 `flash.accessibility`（G2）。依赖换成「自己写桥」成本结构完全不同 |
| N3 | **渲染线程 + 可序列化命令通道**（tree diff/spring targets ↔ hits/settles/presented ids） | `PLAN.md:100-135`（架构图与理由） | 架构级改动；我们是单线程 Skia 直绘。它换来的是「动画不经过应用代码」，我们已用 `markPaint` 纯重绘近似（S2） |
| N4 | **双进程 iPhone 热重载 / 热补丁 / live literals** | `PLAN.md:279-330`（§5）、`:313` | 形态完全相反：我们是编译期 AOT，没有「运行时换代码」这条路。真要做是另一门工程 |
| N5 | **motion_gate 全量**（47 KB `check.rs` + 120 Hz 逐帧栅格 + OKLab 绘制属性差分） | `motion_gate/check.rs` | 收益/成本比不成立；我们连一帧时间都没在真机上量过，先做 R9 的几何子集 |
| N6 | **`--video` / ffmpeg / ProRes 录屏** | `README.md:2432-2450` | 我们文档站截图 + tour 已够；引入 ffmpeg 依赖违反 §3.1 零依赖（连工具链也算负担） |
| N7 | **`Live<T>` 高频线程→值通道**（音频电平、光标位置直绑渲染属性） | `README.md:1187-1199` | 我们的对应问题（拖动手势 1:1、glide 纯重绘）已经用「不走布局」解决；再引一条跨线程值通道 = 新的一类生命周期 bug，收益为零 |
| N8 | **「按计数而非墙钟」的性能门整套** | `AGENTS.md` 的 Performance 段、`procwatch`（计数分配器） | 纪律要（**应有分配计数**），整表不抄；`frame-perf.cjs` 已经是我们的口径 |

---

## 5 与 `MOBILE.md` 的挂接

| 组 | 受影响 ID | 本次结论 |
|---|---|---|
| P（输入） | P1 · P2 | **无需改实现**；补 R1 的 5 条断言当验收（我们已有 `PointerRouter`/`InputConstants`） |
| S（滚动/列表） | **S2 · S6** | S2 校准默认衰减（0.95→0.967，或改文档口径）；**S6 剩余两件拿到可直接实现的规格**（R3 算术、R4 绘制期吸顶） |
| E（环境） | **E8** | `reduceMotion` 有字段无消费者，照 R12 补那一个裁决点 |
| N（导航） | — | rune 无移动导航，**无输入**（我们的 `navStack`/`appBar`/`tabBar` kind 已注册，见 scan 45 kinds） |
| T（文本输入） | T3 · T5 | rune 只在 `PLAN.md:215-217` 给了**风险定价**（iOS/Android 走各自原生协议；Flutter 的 iOS shim 3400 行仍不自然）⇒ 坚持「字符与组字走运行时，只有手柄/长按菜单自绘」 |
| A（无障碍） | **A1 → A1a/A1b** | A1a（AS3 语义树，与 G2 无关）可立即开工；A1b 平台桥仍挡在 G2 后 |
| B（后端） | — | rune 没有移动后端，**不提供任何输入**（G5 不动） |
| V（验收/工具） | **V2′ · V4′ · V5** | 新增三项，见 §6 第 1、2 条 |

---

## 6 建议动手顺序（全部纯 AS3，不依赖 B 组）

1. **V2′ `--tree`**：`Node`/`UiNode` 树 → JSON，字段照 R7 抄。今天能做完，后面所有断言都长在它上面。
2. **V4′ 虚拟时钟**：`getTimer()` 收进一个 Clock seam，headless 由脚本推进；第一版只服务「惯性/回弹回放」。
3. **S6 变高**：估计表 + 按 key 记忆 + **锚点保持** + 越界挂载半视口节流（R3）。
4. **S6 吸顶**：绘制期位移 + 命中同偏移 + 窗口外组头仍挂载（R4）。
5. **S2 校准**：`decelerationRate` 默认 0.967，用第 2 条的回放做 0.95/0.967 两态 A/B（**不许用肉眼判**）。
6. **R8 commit provenance** + 「滚动 60 帧不重绘」门。
7. **A1a 语义树**：45 kind → role/name/value/state 推导表，先只喂 `--tree` 与手测清单。
8. **`tools/ui-audit.cjs`**（R10），挂进 58 门的同层。

> 顺序理由：1、2 是所有后续断言的基座（没有树 dump 与可控时钟，3–6 都只能靠肉眼看）；
> 3、4 是 S6 的两件，规格已到可写代码的粒度；5 依赖 2；7 是 A 组唯一能先走的部分；8 是防复发。

---

## 7 证据与复核

```bash
# rune 侧（每条 R 表结论的出处）
sed -n '1,23p'      temp/rune/crates/rune/src/runtime/input/touch.rs      # R1/R2 状态机与常数
sed -n '1,23p'      temp/rune/crates/rune/src/runtime/scroll/touch.rs     # R2 rebound / 0.55
sed -n '1,70p'      temp/rune/crates/rune/src/el/virtual_rows.rs          # R3 变高行契约
sed -n '1,20p'      temp/rune/crates/rune/src/runtime/scroll/sticky.rs    # R4 绘制期吸顶
sed -n '1,45p'      temp/rune/crates/rune/src/a11y/tree.rs                # R5 树缓存与 transform
sed -n '2268,2310p' temp/rune/crates/rune/README.md                       # R5 无障碍默认值
sed -n '2339,2440p' temp/rune/crates/rune/README.md                       # R6 headless
sed -n '752,771p'   temp/rune/crates/rune/README.md                       # R8 commit 诊断
sed -n '1,60p'      temp/rune/crates/rune/src/runtime/elements.rs          # R7 ElementInfo

# asaotui 侧（现状计数一律现算）
node tools/mobile-gap-scan.cjs
grep -n 'PRESS_SLOP_PT\|OVERSCROLL_RESIST\|FLING_FRESH_MS' kit/asaot/ui/InputConstants.as
grep -n 'isPrimary\|public function cancel'               kit/asaot/ui/PointerRouter.as
grep -n 'THIS WIDGET MOUNTS NOTHING'                      kit/asaot/ui/kind/VirtualListWidget.as
```

**已知不确定**：本机没有移动后端（G5），所以 R1/R2 的所有阈值**只能当规格，不能当实测**；
rune 的这些常数同样来自 iOS 惯例而非我们的设备。§6 第 5 条做完之前，任何「手感对了」的结论都不成立。
