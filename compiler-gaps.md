# 编译器底层支持缺口登记（asaotui 工作区）

> **本文档的定位（用户 2026-10-22 指示）**：`asaotui` 这套 UI 库走**纯 AS3 实现**；
> 在做库的过程中撞到的「**本项目（as3compiler）缺的底层支持**」，一律登记在**本文档**，
> **不去修改 `as3compiler/` 的代码**、**不去改 `as3compiler/TODO.md`**。
>
> 本文档是这些缺口的**唯一登记处**。将来若其中某一条要真正立项，按编译器项目自己的流程另起
> 阶段（占阶段号 + 升版本 + 全量回归），入口见 §5。
>
> **纪律（AGENTS.md §1.5）**：区分「**遗留欠账**」（AIR 有、我们没有 ⇒ 缺陷）与
> 「**增强/工具链**」（AIR 无对应物）；区分「**已实测**」与「**仅代码事实/待实测**」。
> 凭直觉入表会污染可信度，故每条都带证据与状态。

---

## 0 先说结论：纯 AS3 路径本身**不需要**任何编译器改动

| 事实 | 证据 |
|---|---|
| 库是**纯 AS3**，**零 `flash.*` 导入**（只有内部 `asaot.ui.*`） | `grep -rn "import" seam/asaot/` 只有 `asaot.ui.LayoutEngine` / `asaot.ui.LayoutConstants` |
| **自家 AOT** 已把库编成原生程序并跑通 | [`layout-check/`](layout-check/README.md)：文本半边 **133 checks, 0 failures**（`RESULT: PASS`）+ 视觉半边 **12 checks, 0 failures**；`kit` **十七组控件/交互探针**（19/41/48/41/14/43/43/77/65/25/54/23/26/44/14/26/18 checks）全绿；[`tools/gates.cjs`](tools/gates.cjs) 一条命令复现 **33/33** |
| **AIR**（`mxmlc`→`adl`）也能编能跑，且数值逐字符一致 | [`air-check/`](air-check/README.md)、[`diff-check/`](diff-check/README.md) |
| **真实用户缺陷**也在这条路上定位（不是猜测） | 2026-10-24 的两份截图报告：弹层被盖住 ⇒ **不是编译器问题**（引擎无 z-index，靠 `UiNode.lifted` 改 reparent，见 `STATUS.md` §3.3 第 19 条）；输入框提示文字/文字复制 ⇒ **一个是库缺陷、一个是本文件 G20** |

⇒ 布局（U1）**一个编译器改动都不需要**。下面这些缺口是「用自家编译器 dogfood 自家库」时
**顺带撞到的**，不该静默丢弃，也不该顺手改编译器，所以集中登记于此。


---

## 1 缺口清单

### G1 —— `flash.system.System.exit(code:uint):void` —— ✅ **已修（阶段二百四十五）**

> **先澄清「退出」这件事（用户 2026-10-22 指出）**：**惯用退出路径我们完全支持**——
> `import flash.desktop.NativeApplication; NativeApplication.nativeApplication.exit();`，已**实测跑通**
> （探针 `EXIT=0`；`src/symbols.ts:1233` 注册 `exit`、`src/emit.ts:10380` 发射）。
> 本项目的 AIR 侧驱动本来就用这条路径（[`air-check/AirMain.as`](air-check/AirMain.as):61、
> [`air-check/Hello.as`](air-check/Hello.as):28），`examples/native-window.as:207` 亦然且被
> `test/examples.ts:475` 回归覆盖。⇒ **这条 G1 不影响「程序能不能正常退出」**，
> 完整证据见 [`reviews/probe-exit-paths-2026-10-22.md`](reviews/probe-exit-paths-2026-10-22.md)。

| 项 | 内容 |
|---|---|
| 现象（我们的编译器） | `System.exit(0);` → `Codegen error at 3:1: undefined variable 'System' at top level` |
| 真因（代码事实） | `System` 是 `src/emit.ts` 里的**手写伪类**，只认 `gc` / `output` / `pauseForGCIfCollectionImminent` / `setClipboard` / `disposeXML` / `useCodePage` 与内存常量（`emit.ts:29446`、`:29801`、`:31799-31810`），**不含 `exit`**；落到通用路径后文案**误导**——读者会以为是 `System` 这个名字不可见，而不是「System 无 exit 成员」 |
| 真参考（**AIR 51.4.1 / `mxmlc` 实测**） | `System.exit()` → **错**「参数个数不正确。需要 1 个」；`System.exit(0)` / `exit(3)` → **过**；`System.exit(true)` → **错**「Boolean 值无法隐式转换为 uint」；`var f:Function = System.exit` → **过**；负对照 `System.definitelyNotAMemberXYZ()` → 错「方法尚未定义」 |
| ⇒ AIR 的签名 | **`flash.system.System.exit(code:uint):void`**（1 个必填 `uint`，无默认值） |
| 判定 | **已修（阶段二百四十五）**。⚠️ 分类在此更正：`mxmlc` 认得这个签名，但 AIR **运行时**对它抛 `#2018`（`The System.exit() method is not supported.`，`adl 51.4.1` 未打包实测，见 `TODO.md` 阶段一百二十五）⇒ 编译面按 `mxmlc` 对齐（1 个必填 `uint`），运行面是**增强**而非补齐：我们记录 `code` 并以它作进程状态码退出。跨端差异已显式登记（`docs/zh-cn/enhancements.md` **E18**） |
| 对 UI 库的影响 | **极低（近乎为零）**。惯用退出路径 `NativeApplication.nativeApplication.exit()` **已通且已实测**（见上框），纯 AS3 库本身不依赖 `System.exit`；AIR 侧驱动用的就是惯用路径（`air-check/AirMain.as:61`）。这条是「补齐 API 面」性质，不是可用性缺陷 |
| 证据落盘 | `air-check/SystemExitProbe.as`（刻意用 0 参数，把「需要 1 个参数」留在仓库里）+ `air-check/README.md` §dogfooding 1 |

> 附带的**独立缺陷**：即使不补 `exit`，把「伪类无此成员」错报成 `undefined variable '<类名>'`
> 本身就是误导性诊断（AGENTS.md §2.5「报错要能定位 + 能理解」）。这条与 G1 分开修也行。
> **对照实测**：`System.gc()` 的 codegen **通过**（一路走到 `[4/4] compile`）⇒ `System` 这个名字我们
> 是认得的，所以「`undefined variable 'System'`」确实是**错的**，真因是「该伪类无 `exit` 成员」。

> **✅ 2026-10-23 修复（阶段二百四十五）**：`System.exit(code:uint)` 已落地，`System` 的未知成员不再误报
> `undefined variable`。两条路都钉住了：`unit: emit/SystemExit`（7 条）+ `unit: diagnostics/Codegen`（2 条），
> 加 `examples/system-exit.as` / `examples/system-exit-status.as` + `test/examples.ts` 的串行用例（断言进程真的以 `7` 退出）。
> **注意分类更正**：这条原本记为「遗留欠账」，实测 `adl` 对该调用抛 `#2018` ⇒ 我们提供的是 **AIR 没有的能力**（增强，
> `enhancements.md` E18），不是对齐。上游说明见 `TODO.md` 阶段二百四十五。

---

### G2 —— `flash.accessibility.*` **整包缺失**

| 项 | 内容 |
|---|---|
| 现象 | `grep -rn "flash.accessibility\|AccessibilityProperties\|AccessibilityImplementation" src/*.ts` → **零命中**；`grep -rin "accessibility" src/*.ts` 只命中一处无关注释（`src/emit.ts:26272`，讲可见性测试的 `ACCESSIBILITY` 标记） |
| AIR 有的面 | `Accessibility` / `AccessibilityProperties` / `AccessibilityImplementation` / `ISearchableText` / `ISimpleTextSelection` |
| 判定 | **遗留欠账**（AIR 有、我们无） |
| 对 UI 库的影响 | **U6 才需要**；U1（布局）无影响。已在 [`ui-toolkit-feasibility.md`](ui-toolkit-feasibility.md) §7 记为 U6 |
| 证据落盘 | [`ui-toolkit-feasibility.md`](ui-toolkit-feasibility.md) §4 对照表、[`reviews/doc-verify-2026-10-22.md`](reviews/doc-verify-2026-10-22.md):158 |

### G3 —— Tab 序的**实现限制**：硬上限 64 / 扁平 / 每次按键全扫 / 无分组

| 项 | 内容 |
|---|---|
| 现象 | 可聚焦对象超过 **64** 个时，第 65 个起 Tab 不再可达 |
| 代码事实 | `src/emit.ts:10940`：`as_tab_scan((root != NULL) ? root : (DisplayObject*)ASC_root_stage, &ord, tabs, tords, &nt, 64, &focus_ord, &anchor_ord);` —— 上限 **64** 是**硬编码**的；`as_tab_scan` 定义见 `emit.ts:10914`；每次按键从根**全树扫描**重建环 |
| 判定 | **我们的实现限制**（不是「AIR 有我们无」）。**AIR 侧是否也有上限 / 分组语义——本机未实测**，不得凭直觉断言（AGENTS.md §1.5） |
| 对 UI 库的影响 | **U5**（键盘优先与焦点形态）才需要；U1 无影响。U5 的验收已写明「先测 `adl` 在 >64 个 tabbable 下的行为再定口径」 |
| 状态 | **代码事实已确认**；AIR 行为**待 `adl` 实测** |
| 证据落盘 | [`ui-toolkit-feasibility.md`](ui-toolkit-feasibility.md) §1 对照表 L2 行、§7 U5 行 |

### G4 —— C 编译器旗标（如 `-w`）—— ✅ **已修（阶段二百四十六）**

| 项 | 内容 |
|---|---|
| 现象 | 传 `-w` 报 `unknown argument: -w (see \`as-aot --help\` for the full list)`（`src/index.ts:255-256`） |
| 后果 | 生成的 C 会带 clang 的 deprecated 噪音，且**没有标准开关能压掉**（纯噪音，不影响正确性） |
| 判定 | **增强/工具链**（AIR 里没有「透传 C 编译器旗标」这个概念）。✅ **已修（阶段二百四十六）**：`--cflag <flag>` + `-w` 糖 + 清单 `c-flags`，落在**每个**编译与链接步骤上；默认空 ⇒ 不写旗标的产物与以前逐字节相同。`examples/any-add.as` 实测 **69 条 `warning:` → 0 条** |
| 对 UI 库的影响 | **低** |
| 状态 | **已实测** |
| 证据落盘 | [`layout-check/README.md`](layout-check/README.md) §dogfooding 2 |

### G5 —— 窗口后端**不产生触摸事件**（`TouchEvent` 有类、无输入源）

| 项 | 内容 |
|---|---|
| 现象 | `flash.events.TouchEvent` 的类形状是完整的（`emit.ts:12047` 起，含 `TouchEvent_new`/`createTouchEvent` 等），但窗口后端**不转发触摸输入** ⇒ 拿不到触摸事件 |
| 判定 | **后端缺口**（AIR 在触屏设备上有触摸输入；我们的桌面后端未接输入源）。**AIR 桌面端的确切行为——未实测** |
| 对 UI 库的影响 | UI 库「**不做手势识别**」这条设计决定的部分原因即在此（见主文档「明确不做」） |
| 状态 | 代码事实（后端不产生）；AIR 桌面行为**待实测** |

### G6 —— `--target wasm` + C++ 源**直接 throw**

| 项 | 内容 |
|---|---|
| 现象 | `src/build.ts:1322`：`C++ sources with --target wasm are not yet supported` —— 严格 `--target wasm --package raw`（WASI）走 `buildCompileSteps`，遇到**任何** C++ 源就 throw；而 `--package web`（`buildWebCompileSteps`）支持 C++ |
| 判定 | **构建层限制** |
| 对 UI 库的影响 | **纯 AS3 路径完全不受影响**。只有「将来要链 C++（例如把布局换成 Yoga）」时才撞到 |
| 状态 | **已实测**（代码事实） |
| 证据落盘 | [`u1-implementation-plan.md`](u1-implementation-plan.md) §3.3(c)、[`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md) |

---

### G7 —— AS3 的「一个文件只能有一个与文件名同名的 public 顶层定义」**我们不强制**（AIR 硬报错）

| 项 | 内容 |
|---|---|
| 现象 | 把一个公开**包级函数** `hello()` 和一个类 `Lib` 一起放进 `p/Lib.as`：**AIR `mxmlc` 硬错误**「`意外发现一个具有名称"p.hello"的外部可见定义`」并连带该文件**本该提供的类**也报「找不到类型」；**我们的 AOT 不报错**，直接 `Build successful` 且程序跑通（`EXIT 0`）。反证：同一函数放进同名文件 `p/hello.as`，AIR `MRC_EXIT 0` |
| 判定 | **遗留欠账**（AIR 拒绝而我们接受 ⇒ 静默的可移植性陷阱：在我们这里能编的代码到 AIR 上可能编不过，而我们从不提示）。按 `AGENTS.md` §1.5，这属于「错的是我们」的那一半 |
| 对 UI 库的影响 | **实在的**。工具链当前有 **7 个文件**踩中（AIR 侧全部不可编译）：`kit/asaot/ui/Factories.as`（8 个工厂函数、无类）、`Binding.as`（`bindTo`）、`style/Length.as`（`px/rem/pct/auto/rems`）、`style/Fill.as`（`fill`）、`style/Edges.as`（`edges`）、`style/Corners.as`（`corners`）、`style/TextStyle.as`（`textStyle`）。出路（择一）：每个 public 顶层定义一个同名文件，或收成类的 static 方法。**当前状态（实测）**：已按「一同名文件」改造，`ui/` 侧全部完成，`style/` 侧还剩 `Corners.as`/`Edges.as`/`Fill.as`/`TextStyle.as` 四个未改到小写名，`mxmlc` 对这 4 个报硬错 |
| 子规则（实测新增） | **文件名匹配是大小写敏感的，Windows 上也是。** `probes/case-rule/` 三格对照：`p/lower.as` 里放 `lower()` → `MRC_EXIT 0`；`p/Mixed.as` 里放 `mixed()`（仅首字母大小写不同）→ **`错误: 找不到定义 p.mixed`**；`p/Other.as` 里放 `unrelated()` → 同样硬错。（`probes/case-rule/Mixed` 那一格是**反直觉**的一半：文件系统本身不区分大小写，是 `mxmlc`/Java 这一层在拒绝。这条在 macOS/Linux 上更致命——那两个系统的文件系统也区分大小写。） |
| 状态 | **已实测**（两侧同一份输入；包级函数可达性由 `air-check/KitFns.as` 逐符号编出来） |
| 证据落盘 | [`reviews/probe-asmdef-and-name-collision-2026-10-22.md`](reviews/probe-asmdef-and-name-collision-2026-10-22.md)、探针源码 [`probes/asmdef-rule/`](probes/asmdef-rule/)、[`probes/case-rule/`](probes/case-rule/)、[`air-check/KitFns.as`](air-check/KitFns.as) | |

---

### G8 —— 用户符号名**逐字进 C**：保留名表不全，且**前缀改写挡不住 C 宏** —— ✅ **已修（阶段二百四十七）**

| 项 | 内容 |
|---|---|
| 现象 A | 公开包级函数 `bind()` ⇒ 生成的 C 里 `static int bind(int, int)` 与 socket `bind(2)` 冲突：`error: conflicting types for 'bind'` + `too few arguments to function call, expected 3, have 2` ⇒ **编译失败（EXIT 1）** |
| 现象 B | 我们**有**一套保留名改写（`div/free/time/open/close/read/exit` → `_div/_free/…/__exit`，都能编过），但 **`stat` 改写后仍炸**：`_stat` 被 MSVC 的 `stat → _stat64i32` **宏**展开成真声明 ⇒ `error: conflicting types for '_stat64i32'` |
| 判定 | **两个子问题**：① 保留名表是**手工列举**的，`bind` 漏在外面；② 「加下划线前缀」这条现有机制对 **`#define` 类冲突无效**（宏在预处理阶段就替换了） |
| 对 UI 库的影响 | 工具链设计文档里的 `bind(owner, field)` **实测不可用** ⇒ 已退为 `bindTo(...)`（见 `kit/asaot/ui/Binding.as` 顶部 NAME NOTE）。**2026-10-23 复核（G8 已修后）**：保留 `bindTo`，**不改回去**，但理由变了——它不再是「被逼的」而是**主动选择**：① 不再依赖编译器的 C 名剪辑（`bind` 现在是靠机器生成的保留名表 + `__` 后缀才编得过，这条机制一回归就又是 `conflicting types for 'bind'`，而错误文案会把人引向 socket）；② `bindTo` 对读者更像一个动词短语（“bind to X”）。⇒ 已修 + 不改回；`bindTo.as` 顶部注释原写作「compiler limitation」**属陈旧**，已改为「命名选择 + 原因」。（判据：`probes/name-collision/` 现在 4→0 errors；`examples/c-name-collision.as` + `unit: emit/CNameCollision` 16 钉看住） |
| 状态 | **已修（阶段二百四十七，v0.4.211）**——两个子问题分别收口：① 保留名表改为**机器生成**（`scripts/gen-c-reserved.ts` 用 `-Xclang -ast-dump` 取全部 `FunctionDecl` + `-E -dM` 取全部宏，产物 `src/c-reserved.gen.ts`，win32 面 7471 条）；② 文件作用域的消歧从「加 `_` 前缀」改为「加 `__` **后缀**」（C 只保留 `__` **开头**的标识符，`stat__` 不会被任何对象式宏命中）。块作用域的局部量/字段**刻意保持** seed + `_` 前缀——内置类的方法体是手写 C 字符串、字段名逐字写死，把新表并进块作用域会让 `struct ServerSocketConnectEvent` 与它自己的方法体脱节。回归：`examples/c-name-collision.as` + `unit: emit/CNameCollision`（16 钉）；两个探针各 **4 errors → 0**。 |
| 证据落盘 | [`reviews/probe-asmdef-and-name-collision-2026-10-22.md`](reviews/probe-asmdef-and-name-collision-2026-10-22.md) §3、探针源码 [`probes/name-collision/`](probes/name-collision/) |

---

### G9 —— `Boolean(x)` 在 `x` **静态声明为 `Object`** 时退化为指针测试 ⇒ **被装箱的 `false` 读成 `true`** —— ✅ **已修（阶段二百四十八）**

| 项 | 内容 |
|---|---|
| 现象 | `var s:Object = b.get();`（`Binding.get():*`，模型字段为 **`false`**）之后 `Boolean(s)` 得到 **`true`**。**同一份值**只把局部量声明成 `*` 就得到正确的 `false` |
| 机制（生成 C **逐行实读**，非推测） | `Object` 声明的变量落地为 **`static Object* g_sS = NULL;`**；赋值走 **`as_value_to_obj(...)`**，把箱装标量包成 `Object*` 包装体；随后 `Boolean(sS)` 被降级为 **`bool _once381 = (g_sS != NULL);`** —— 包装体非空 ⇒ **恒真**。对照：`as_value g_sA` 的 `Boolean` 走 **`as_v_truthy(g_sA)`**（正确），`bool g_sB` 亦正确 |
| 反证（同一段代码里） | 运行时**本来就会拆箱**：`s is Boolean` 降级为 `as_is_bool_obj(g_sS) \|\| (as_is_number_obj(g_sS) && as_number_obj_val(g_sS) != 0.0)`；而 `String(sS)` 得 `"false"`、`s == null` 得 `false`。四处里**只有 `Boolean()` 走了捷径** |
| 影响半径（**实测 17 格**） | 意外地窄。`Boolean(m.f)`（类型化字段）、`Boolean(m["f"])`、`Boolean(dyn.f)`（`Object` 接收者）、`Boolean(dynStar.f)`（`*` 接收者）、对象字面量、字面量下标、数组元素、`Number 0`、空 `String`、选项包 `Boolean(opts.f)`、**`if (opts.f)`**、**`if (q)`（`Object` 声明的局部量）** —— 15 格**全部正确**。唯一出错的是 **`Boolean(<静态 `Object` 声明的局部量>)`** |
| 判定 | **遗留欠账**（语义错误，不是平台边界；**已用真 AIR 51.4.1 实测确认**，原先是按 §1.5 推断）。`Boolean()` 是 AS3 定义的真值转换，而「`Object` 槽持有箱装标量」在 AS3 里是**常规状态**（`Number`/`Boolean`/`String` 都可以是 `Object` 值）⇒ 此处必须与 `as_v_truthy` 同口径。✅ **已修（阶段二百四十八）**：补齐至此 |
| 对 UI 库的影响 | **实在的**：kit 的绑定路径恰好就是「`*.get()` → 声明成 `Object` → `Boolean()`」。共 **6 处**踩中：`radio.as`/`toggle.as`/`checkbox.as`/`kind/{Radio,Switch,Checkbox}Widget.as`，其中 **`checkbox` 的 2 处是既有隐患**（早于本轮引入，只因从没有「绑定到 `false`」的用例才一直没暴露）。已全部改为 `*` 声明 + 就地注释；另建静态钉子 [`tools/find-bound-truthy.cjs`](tools/find-bound-truthy.cjs)（**已变异证明有牙**：重引入即报 `kit/asaot/ui/kind/RadioWidget.as:62` 并 `SCAN_EXIT=1`） |
| **G9 已修 ⇒ 那 10 处 `*` 声明能不能改回 `Object`？**（2026-10-23 复核） | **不改回去**，而且理由比原来更硬。① **实测计数更正**：全库其实是 **10 处**，不是 6 处——除上面 6 处 `Boolean` 型（`radio/toggle/checkbox` + `kind/{Radio,Switch,Checkbox}Widget`）外，还有 **4 处 `Number` 型**选段读取（`list.as:35`、`tabs.as:29`、`kind/ListWidget.as:59`、`kind/TabsWidget.as:108`）；那 4 处**从来不是 G9 的受害者**（G9 只污染 `Boolean()` 一个降级入口，`Number()` 一向正确），只是当时为了口径一致一起改了。② **`*` 现在有两条独立的好理由**：**（a）省一次装箱**——`var x:Object = binding.get()` 会把读出来的标量经 `as_value_to_obj` 装成 `Object*` 包装体，**每次读一次 GC 分配**；`*` 不装。**（b）躲开 G14**——见下一节：**一个 Array 落进 `Object` 槽会丢身份、继发的 `is <userClass>` 会 SIGSEGV**，而绑定值可以是任何东西。⇒ 即便 G9 修了，`*` 仍是「读绑定/动态来源」的**正确默认**；裁决由**拼写**担着，不靠行为（这也正是「示例绿 ≠ 规则没坏」那条教训的反面用法）。 |
| 回归网 | `probes/widgets/form/Main.as` 直接断言 `r2.checked == false`（模型为 `false` 的绑定），消息里点名 G9 ⇒ 该 bug 复现时会**自报成因**，而不只是表现为一处颜色不对 |
| 状态 | **已实测**（[`probes/bind-truthy/`](probes/bind-truthy/)：17 格真值矩阵 + 生成 C 逐行实读）· ✅ **已修（阶段二百四十八，v0.4.212）**：`src/emit.ts` 的 `Boolean` 分支在 `isRefType` 之前加一条 `className === 'Object'` ⇒ `as_v_truthy(as_obj_to_value((void*)(x)))`，与 `condExpr` 同口径；**具体子类/Array/String/bool/`*` 的发射拼写逐字不变**（子类槽永远不装箱标量）。修复后同一份 26 格用例 AOT 臂 **0 失败**（[`probes/g9-adl/aot-got-fixed.txt`](probes/g9-adl/aot-got-fixed.txt)）。钉子分工：行为归 `examples/object-truthy.as`，**拼写归 `unit: emit/ObjectTruthy`**（9 条）——把守卫放宽到所有 `object` 类型时示例仍绿、钉子红（实测），这正是「示例绿 ≠ 规则没坏」 |
| 与 AIR 的 A/B | **同一份 26 格用例，两条工具链**：修复前 AIR 51.4.1 **0 失败** / 我们 **7 失败**，七条全是 `Boolean(<静态 Object 槽>)`；同一值的 `typeof`/`String()`/`is`/`==`/`===`/`Number()`/`== null`/**`if`** 两臂逐字符相同 ⇒ 缺陷只在 `Boolean()` 一个降级入口。**修复后两臂 0 差异**（AOT 26/0）。附带：`new Boolean(false)` 在 AIR 上 `typeof` 是 `"boolean"`、`Boolean()` 是 `false`（非 ES3），我们两格均一致 |
| 证据落盘 | [`reviews/probe-g9-object-truthy-2026-10-23.md`](reviews/probe-g9-object-truthy-2026-10-23.md)（AOT 侧 17 格）、[`reviews/probe-g9-air-2026-10-23.md`](reviews/probe-g9-air-2026-10-23.md) + [`probes/g9-adl/`](probes/g9-adl/)（真 AIR 51.4.1 A/B 26 格，含原始输出） |

---

### G10 —— `Date.now():Number` **缺失**（但 `new Date().getTime()` / `getTimer()` 都正常）

| 项 | 内容 |
|---|---|
| 现象 | `Date.now()` ⇒ **`Codegen error: undefined static method 'now' on class 'Date'`**（`EXIT 1`）。它在**编译期**就报，属可定位错误，不是静默错 |
| 替代路径（**同一次运行实测两条**） | `new Date().getTime()` = 真 epoch 毫秒（`1792697006620`）；`getTimer()` = 自程序启动的**单调**毫秒。`getTimer()` 一开始读到 `0`，为了排除「是个桩」的可能，用 `new Date().getTime()` 自旋到真实经过 300 ms 再读 ⇒ **`0 → 300`**，证明它真的在走 |
| 判定 | **遗留欠账**（AIR 的 `Date` 有静态 `now()`）。因报错硬、且替代路径齐备，优先级低 |
| 对 UI 库的影响 | 无。反而更好：动画时钟刻意选 **`getTimer()`** —— 单调、不会因系统时钟跳变而回退，已写进 `View.tick` 的注释 |
| 状态 | 已实测 |
| 证据落盘 | [`probes/clock/Clock.as`](probes/clock/Clock.as)（一次运行同时量了三条路径 + 单调性） |

---

### G11 —— ~~同一份源码**两次构建产出不同的 C**：内建类字段被写成**文件作用域拼法**，与手写内建体对不上~~ —— ❌ **不是缺口：那两次构建之间，编译器源码正被另一个进程改写**（2026-10-23 结案）

> **结论先说**：不是「生成器不确定」，而是**在别人的半成品树上测量**。判据是三条互相独立的证据，
> 其中两条是**当时的产物**（不是回忆）：① 失败构建发生在 `阶段二四七` 提交前 **24 分钟**；
> ② 同一个坏法在**同一天 9 秒前后、另一个程序**的产物里原样出现，且两者在 84 秒内**收敛**
> （20 → 1 → 0 条 C 错）；③ 冻结树上连续 5 次构建**逐字节同一份 C**。
> 一条命令复现全部三条：`node probes/g11-nondeterminism/run.cjs`。

| 项 | 内容 |
|---|---|
| 现象（登记时） | `probes/array-scope` 的构建**第一次失败、随后同源同命令又通过**。失败时 `clang` 报的错指向使用者从没写过的生成代码：`no member named '_time' in 'struct Date'`、`no member named '___restrict' in 'struct TextField'`、`no member named 'socket' in 'struct ServerSocketConnectEvent'`。**注（结案时更正）**：当时记为「20 个错」，实际是 **19 条真错 + clang 自己的 `fatal error: too many errors emitted` 哨兵**（`-ferror-limit` 默认 20）；把哨兵当错误、把「上限」当「文件的属性」都是当时的读数误差 |
| 机制（**两份生成 C 逐行对读**，结论保留） | 失败的一份：`struct Date { Date_vtable* vtable; double **time\_\_**; }`，props 表也跟着写 `offsetof(Date, **time\_\_**)` —— 名字本身**自洽**，坏在 `emit.ts` 里**手写内建体**用的是拼接时的字面量 `o->_time` / `o->___restrict` / `o->socket`。通过的一份：`double **_time;**`、`___restrict` 两边一致 |
| 原本的推断（**已推翻**） | 当时推断为「有一趟把保留名表逐个按文件作用域命名并登记的过程跑了，**污染了块作用域的命名缓存**」⇒ 生成不确定。**错的**：真实机制是**改名策略被改到一半**——文件作用域改用 `__` 后缀的那次改动，把**结构体字段**也带上了文件作用域路径，而手写内建体的字面量仍是块作用域拼法。上游最终提交的正是**拒绝**这个中间态：`721e12f` 提交信息写明「`cIdent` **刻意不动** —— 内置类方法体是手写 C 字符串、字段名逐字写死，放宽块作用域会让 struct 与自身方法体脱节」（`src/symbols.ts` 的 `C_RESERVED_SCOPE` 注释给了同型的反例，就是 `socket`）。⇒ **「缓存污染」这个机制不存在** |
| 结案判据 ①：时间线 | 失败的构建 **2026-10-23 04:00:19 +0800**（`probes/array-scope/cc.txt` 的 mtime，同一份坏 C 就在同一目录）；上游 `阶段二四七` 提交于 **04:24:34 +0800**；我复建的通过版 **05:11:26 +0800**。⇒ 失败那次夹在「改名机制正被改写、尚未提交」的 **24 分钟窗口**里 |
| 结案判据 ②：同一状态的另一份产物 | `temp/gapprobe/nc-bind2.c`（**04:00:10**，比我早 9 秒，由**上游会话自己的探针**产出）：`struct Date { double time__; }` + `offsetof(Date, time__)` 而手写体是 `o->_time` —— 与我那份**同型的坏法**，hazard 集逐项相同（`Date._time` / `TextField.___restrict` / `ServerSocketConnectEvent.socket`）。它的兄弟 `nc-bind3.c`（04:00:50）只剩 `socket` 一处、`nc-bind4.c`（04:01:34）**0 错**（并产出 exe）。⇒ 同一程序在 **84 秒**内 20 → 1 → 0 条错：**人在改**，不是「有时会拼错」。三份都留档在 [`probes/g11-nondeterminism/`](probes/g11-nondeterminism/)（`temp/` 会被清理） |
| 结案判据 ③：冻结树上确定性成立 | 同一 HEAD + 同一 **92 份输入的输入哈希**连续 **5 次**构建 ⇒ 产出**逐字节同一份 C**（3698965 B，`sha256/16 = f0ac0ff461e604bf`）。⇒ 生成结果是 **(输入, 编译器源码树) 的确定函数**。「两次构建不同」只能意味着**其中一个因子变了** |
| 判定 | **不是缺口，已结案**。它是**测量在并发改写的编译器树上进行**的可见后果，不是生成器缺陷 |
| 对 UI 库的影响与处置（**已更正**） | 旧处置「**先原样重跑一次构建**」**已废止**：它把「上游树是脏的」这个真因说成随机，还会把真缺陷当偶发吃掉。现在的处置：这批 C 错（`_time` / `___restrict` / `socket`，**指向你没写过的代码**）出现时，**先看编译器树**——`git -C as3compiler status --porcelain`；有**已跟踪文件被修改**就是可复现条件，等它提交或换干净的树再测。两个 runner 的重试循环已按此换成**树状态报告**（不再重试：重试只会把真缺陷伪装成偶发）。一条命令给结论：`node probes/g11-nondeterminism/run.cjs` |
| 残余风险（如实记） | 中间态本身是危险的：**只要把结构体字段也路由到 `sanitizeFileCIdent`**，`struct` 与手写体立刻脱节。这条现在有**双面守卫**：设计注释（`C_RESERVED_SCOPE` 上方，含 `socket` 反例）+ **拼写钉子** `unit: emit/CNameCollision`（16 条，`阶段二四七` 变异实测：`suffix→prefix` 示例仍绿而钉子红）+ `docs/zh-cn/c-naming.md` §8。⇒ 缺口关闭，风险**转为有钉子的设计约束** |
| 复现 / 钉子 | `node probes/g11-nondeterminism/run.cjs`：A 树状态（含 `src/` 内容哈希）· B 5 次构建同一哈希 + **`src/` 内容哈希在每一次构建的紧邻前后各采一次**（首尾各一次看不见「改完又还原」的窗口，见下）· C 拼写钉子（struct / props 表 / 手写体字面量三处一致）· D 三份历史产物 20→1→0 · E 与本次登记失败**同 hazard 集**的交叉核对。变异 [`mutation.cjs`](probes/g11-nondeterminism/mutation.cjs) **10/10** 全抓（6 组：改名元凶单令牌注入 / props 指向不存在的字段 / 一字面改动必须改哈希 / 翻掉期望值必须变红 / **测量期间源码“动过”必须报 INCONCLUSIVE 而不能是绿** / **某次构建撞上在飞的改动时必须归因给「源码动过」而不是「生成器不确定」**），全部 `finally` 还原 + 哈希核对 |
| 状态 | **已实测 · 2026-10-23 结案（非缺口）**；作为一道门持续看住（`tools/gates.cjs` 的 G11 determinism 门）。结案过程中顺带证实了一件本工作区成立的事实：**上游工作树随时可能被另一个会话改写**——我这次测量期间亲眼见到它从 clean 变成 4 个 `M`，随后那 4 个文件被提交成 `1ac26b4`（阶段二五零），之后又被下一轮改动弄脏（`examples/air-native` 下的删除与 `com.zip`）。因此那道门的有效性判据是「**测量期间 `src/` 内容哈希有没有变**」（而不是「树脏不脏」）：稳定但脏的树照样能测（PASS 会点名内容哈希），**测量期间真在动**才报 `[SKIP]`（exit 3），不假绿也不假红。两个分支都有落盘证据：干净树 **16/16 PASS**（`reviews/gates-all-8.txt`）、强制走 SKIP 分支的集成钉子（`reviews/gates-skip-path.txt`） |

---

### G12 —— ~~先分配**大字节缓冲**，随后任何**堆分配**会**挂起**~~ —— ❌ **不是缺口：见证程序自身写错了声明顺序**（2026-10-23 结案）

> **结论先说**：不是运行时缺陷，也不是平台边界。见证程序把 `aBuf` / `aFresh` / `bigBuf`
> 三个脚本作用域变量声明在 `stage.showWindow(...)` **之后**，而该调用**不返回**（把主线程
> 交给帧/消息循环）⇒ 初始化语句永不执行 ⇒ 引用类型停在 `NULL` ⇒ `aFresh.push(1)` 抛
> `TypeError #1009`，`setTimeout` 回调在重新注册自己之前就死了，帧循环继续跑。
> 完整证据与三组 A/B：[`reviews/probe-g12-2026-10-23.md`](reviews/probe-g12-2026-10-23.md)；
> 变体源码 [`probes/g12-ab/`](probes/g12-ab/)。

| 项 | 内容 |
|---|---|
| 现象（登记时） | 进程**还活着**、窗口事件循环还在跑（后续帧号不前进）、日志停在该语句上、不再有任何输出 |
| 现象（实测真相） | 进程**确实活着且帧循环正常**（插桩计时：14 秒 346 帧 ≈24 fps）；停的是 `tick` 定时器回调。**「帧号不前进」是 tick 自己打的，tick 一死它当然不动** —— 当时把它当成「帧循环停了」是错的 |
| 最小触发（真实） | 与 `ByteArray` 大小**无关**。`churn 8: aFresh.push(1)` 只是**第一次读**一个被声明在 `showWindow` 之后的脚本作用域引用变量 |
| 决定性 A/B ①（去掉所谓成因） | `probes/g12-ab/nobuf.as`：删掉 `bigBuf.length = 134400`，全程无大分配 ⇒ 症状**一字不差**（仍停在 `churn 8 enter`，插桩里 `GCT_BYTES >= 128 KB` 分配次数为 **0**） |
| 决定性 A/B ②（保住成因、只改声明顺序） | `probes/g12-ab/fixed.as`：三个容器移到 `showWindow` 之前，134400 大缓冲原封不动 ⇒ `step 8/9/10` 全过 → `DONE`，`PASS` |
| 决定性 A/B ③（拿到真因） | `probes/g12-ab/trycatch.as`：原顺序 + `try/catch` ⇒ `PUSH THREW: 1009` / `TICK THREW: 1009` |
| 当时那条「产生解释」 | 「`gc_in_heap()` 只做地址范围检查，134400 字节 `malloc` 落进 GC 段区间 ⇒ 标记切片走垃圾 `gc_header` 死循环」——**已被推翻**：free-list 全程没有死循环（最长连续只走 113 个节点就命中），`gc_alloc` 的大小分级与 `gc_seg_range` 二分查找都是正常的 |
| 为何会被误判成挂起（**工具缺陷，已修**） | 运行时的未捕获错误行为是 AIR 式的：往 `stderr` 打 `Uncaught exception: …` 然后**不终止进程**。`tools/repro-array-scope.cjs` 当时 `stdio: 'ignore'`，见证程序自己又丢弃 stdout ⇒ 两路输出全没 ⇒ 一个 `TypeError` 长成了「静默挂起」。**现已转发 `stderr` 并新增 `REPRODUCED (uncaught)` 判定**（反证：`reviews/repro-g12-uncaught-branch.txt`） |
| 判定 | **不是缺口**（既非实现缺陷也非平台边界）：同一份源码在 AIR 上也会在 `showWindow` 之后继续执行顶层语句，所以这是**我们的窗口后端「`showWindow` 不返回」这一已知平台事实的后果**，而见证程序踩了它。该平台事实本身见下方"不是缺口"表 |
| 复现 | `node tools/repro-array-scope.cjs`（`asaotui/` 下运行）—— 修正后的见证程序 **`NOT REPRODUCED`**，`reviews/repro-g12-2026-10-23c.txt` |
| 状态 | **2026-10-23 结案**：见证程序已修正（容器移到 `showWindow` 之前，头注释写入真实结论与"日志停 ≠ 进程挂"），`probes/g12-ab/` 留三组变体，`compiler-gaps.md` 本条改为"不是缺口"。**`as3compiler/` 零改动**，无需版本号与回归 |

---

### G13 —— `--air-app` 的类引用闭包**曾不展开**「先被**强制文件**发现的类」⇒ 其父类与被引用类被裁掉，构建报 `unknown superclass`（✅ **阶段二百四十九已修**）

> **状态变更（2026-10-23，同一工作树内由编译器侧完成）**：本缺口已**修复**——
> `src/reach.ts` 把两趟「强制文件」处理**移到排空循环之前**，且非类顶层代码那趟从
> `reachable.add(n)` 改成 `enqueue(n)`。**本工作区独立复核**（只读测量，未改编译器）:
>
> | 测量 | 修前 | 修后 |
> |---|---|---|
> | `node tools/reach-dump.cjs probes/reach-freefn/src p.Main` | kept **3/5**，edges 1 | kept **5/5**，edges 3 |
> | `ui-demo` 的 gallery，`--air-app` 默认面（**不带** `--all-sources`） | `unknown superclass 'Control' of 'asaot_ui_AvatarNode'` | **94/97 reachable，建→链→跑 EXIT 0**（`RESULT: PASS`） |
> | `ui-demo` 的 login，同上 | 同错 | **建→链→跑 EXIT 0**（8 项断言全过，`RESULT: PASS`） |
>
> 两个 runner 已**移除** `--all-sources`（改动见 `run-gallery.cjs` / `build-and-run.cjs` 的
> `REMOVED（阶段二百四十九）` 注释）。探针语义**反转成回归钉**：`probes/reach-freefn/run.cjs`
> 现在断言 **kept 5/5 且默认面能建能跑**，`mutation.cjs` 则**把修法的两半各自撤回一次**
> （M1 `enqueue→reachable.add`、M2 两趟挪回循环之后）来证明钉子有牙。
> ⇒ 下面保留的是**修前**的完整记录（现象/机制/影响半径），作为这条缺陷的档案；
> 其中「当前处置：附加 `--all-sources`」**已被取代**。
>
> 那次修复现已**提交**：`5b47fc1`（阶段二百四十九，v0.4.212 → v0.4.213），改动
> `src/reach.ts` + `test/unit/reach.ts`（`unit: reach/forced` 9 条）；复核用的 `src/reach.ts`
> 哈希为 `sha256[:16] = 4e855c84951f9ecb`（提交后不变）。若后来重新出现
> `unknown superclass '(\w+)' of ...` 且那个 `.as` 就在 `src/` 里 ⇒ **是闭包回归**，
> 去修闭包，**不要**用 `--all-sources` 盖过去。
>
> **编号更正**：同一阶段的复核文档一度写作「阶段二百五十」；按 `TODO.md` 末尾小节
> （上一阶段 = 二百四十八）统一归位为 **阶段二百四十九**，本文件内 3 处已同步。

| 项 | 内容 |
|---|---|
| 现象 | 本工作区的多页 demo 改用 `--air-app` 编译（用户 2026-10-23 指示：让 **AIR 描述符**当窗口属性的唯一真相源，含 `<requestedDisplayResolution>high</requestedDisplayResolution>` 的高分辨率）后，构建在 **codegen** 阶段停住：**`Codegen error at 11:5: unknown superclass 'Control' of 'asaot_ui_AvatarNode'`**，且只读了 **76/96** 个源文件 |
| 机制（**逐行实读 `src/reach.ts` + 探针实测，非推测**） | 闭包的 `while (queue.length > 0)` **排空循环在 609 行就结束了**；紧跟其后的两趟「**强制文件**」处理（612~637 行）——① 把强制文件声明的类 `enqueue()`（推进队列，但**再没人排空队列**）、② 走强制文件的**非类顶层代码**（自由函数/模块语句）并把命中的类 **`reachable.add(n)`**——都**只把类标进可达集，从不展开它**。⇒ 「**首次**由这两趟发现的类」会被**发射**，但它自己的引用（`extends`、字段/参数/局部类型、`new X()`）**永不入队**，于是它的父类与被引用类全被裁掉 |
| 为什么本项目**必然**踩中 | 本工作区的 kit 里，**每个控件都是靠小写工厂自由函数进入的**（`chip.as` → `ChipNode`、`avatar.as` → `AvatarNode`…）⇒ **所有 `*Node` 类都只在「强制文件那趟」被发现**，于是 ① 它们的共同父类 **`Control.as`**、② 它们构造器里 `Widgets.register("chip", new ChipWidget())` 注册的 **`kind/*Widget.as`**、③ 控件绘制用的 **`PaintKit.as`** 全被裁掉。这不是「定位写错」，而是**闭包形状与「工厂自由函数」这种普遍写法不兼容** |
| 最小复现（5 个文件） | [`probes/reach-freefn/`](probes/reach-freefn/)：`src/p/{Main,Fac,Leaf,Base,Helper}.as`。`Main` **刻意不提任何类型**（连 `var l:Leaf` 都没有，否则 Leaf 会走主循环而掩盖缺陷），只调 `Fac.as` 里的自由函数 `make()`；`Leaf extends Base` 且构造器 `new Helper()`。**闭包：kept 3/5，`p/Base.as` 与 `p/Helper.as` 被裁**（`node tools/reach-dump.cjs probes/reach-freefn/src p.Main`）；**构建：同一条命令报 `unknown superclass 'Base' of 'p_Leaf'`** |
| 逃生通道（**同源 A/B，一次跑两只臂**） | **`--all-sources`**（documented：恢复「整包编译」，即阶段一百二十四之前的面）**同一份源码、同一个描述符，构建+链接+运行全过**（`EXIT 0`，`ReachFreeFn rendered`）。⇒ 缺陷在**闭包剪枝**，不在源码。`node probes/reach-freefn/run.cjs` 一条命令同时断言「默认臂必须红 + `--all-sources` 臂必须绿」 |
| 与 AIR/`mxmlc` 的对照 | **`mxmlc` 没有这道剪枝**（它编整包），所以「闭包 ⊇ mxmlc 的闭包」这条 `src/reach.ts` 自己写下的**健全性承诺被违反**：这里得到的闭包**不是超集**，而是**漏集**。⇒ 按 AGENTS.md §1.5 判为**遗留欠账**（AIR 能跑对我们跑不出），不是平台边界 |
| 影响半径 | 任何「**用自由函数当工厂/入口**」的 AIR 应用都会踩：只要某个类的**唯一入口**是自由函数（本项目 kit 的全部控件、以及任何 `createXxx()` 风格代码），它的父类就可能在编译期被裁掉，报错信息还指向一个**作者从没写过的类名** |
| 对 UI 库的影响与当前处置 | **（修前）**`ui-demo` 的 demo 现在**一律 `--air-app` 编译**（启用 HiDPI），因此**一律附加 `--all-sources`** 绕开本缺口。⇒ **（现在）** G13 已修，两个 runner **不再附加** `--all-sources`：**默认面能建，才看得见回归**。（用户指令：不修改编译器源码；修复由编译器侧完成） |
| 状态 | **✅ 已修**（阶段二百四十九，2026-10-23）：默认闭包 5/5（最小复现）/ 94/97（gallery）；两 runner 去掉开关后实测 `RESULT: PASS`。**修前**证据：闭包 3/5 + 构建报错文案 + `--all-sources` A/B + 变异有牙（见 `probes/reach-freefn/mutation-2026-10-23.txt`） |
| 证据落盘 | [`reviews/probe-g13-reach-forced-file-2026-10-23.md`](reviews/probe-g13-reach-forced-file-2026-10-23.md)（修前登记）、[`reviews/probe-air-app-hidpi-2026-10-23.md`](reviews/probe-air-app-hidpi-2026-10-23.md)（改用 `--air-app` 的全程与复核）、探针 [`probes/reach-freefn/`](probes/reach-freefn/)（`run.cjs` 回归钉 + `mutation.cjs` 双变异）、闭包转储工具 [`tools/reach-dump.cjs`](tools/reach-dump.cjs)；已在 `tools/gates.cjs` 作为一道门（`G13 air-app reach`）持续看住 |

---

### G14 —— `Array` 落进 `Object` 槽**不装箱**（Number/String/Boolean 都装）：`is Array` 恒假、`as Array` 得 null、`.length` 得 undefined、**`is <userClass>` 直接 SIGSEGV**（✅ **阶段二百五十三已修**）

> **一句话**：AS3 里 `Number`/`String`/`Boolean`/`Array` 都可以是一个 `Object` 变量里的值。我们的 AOT 把**前三个装箱**（`as_number_new`/`as_string_new`/`as_boolean_new`），却把 **`Array` 原样裸指针 cast 成 `Object*`**（`(Object*)(as_array_make(...))`）。于是凡是要问「这个值是什么」的操作，在 Array 上全错——最重的一条是 **`as_is(<数组指针>, &SomeClass_vt)` 把数组头第一个字当成 vtable 去走，进程 `0xC0000005`**。
>
> **两条臂都是实测**：同一份 **26** 条用例，我们的 AOT（**每条一个进程**，因为其中几条会崩）与真 AIR 51.4.1（`mxmlc`→`adl`）。
> 一条命令：`node probes/obj-array-identity/run.cjs`；变异 `mutation.cjs` **4/4**。
>
> **✅ 已修（阶段二百五十三，v0.4.217）**。修法**不是**把 Array 装箱（那会牵动 `Object*` 与
> `as_array*` 的全部既存隐式转换），而是**让 `Object` 接收者走 `*` 接收者早已走通的那条运行时通路**：
> ① 判定 —— `is Array` / `as Array` / `.constructor` 改发 `as_obj_is_array` / `as_obj_as_array` /
> `as_obj_class_of`（按 GC 堆种类分派，与 tag-6 的 `as_v_is_array` 同口径）；② 调用 —— `Object` 接收者的
> 成员调用**一律** `as_dyn_call`，运行时按堆种类走 `as_arr_call` / `as_vec_call_hook` / vtable，
> **不再**把数组头当 vtable 走；③ 读写删 —— `as_dyn_get` / `as_dyn_del` / `for each` 走
> `as_array_key_get` / `as_dyn_del` / `as_obj_to_value`；④ **两条不变量**兜住「野读」这一类：
> `as_is` / `as_iface_lookup` 先过 `as_has_vtable`（**白名单**：只有真带 vtable 的堆种类才读首字），
> `as_v_is_inst` 不再放行 tag 6 去 `as_is`。
> **验收**：26 格矩阵 0 偏离 0 崩溃；**扩展矩阵 59 例 / 55 行与真 AIR 51.4.1 逐字相同**（`temp/g14/ab.cjs`）；
> 新增示例 `examples/object-array-identity.as`（79 条断言，期望值全部是 adl 实测）+ 单元钉子
> `unit: object/array-identity`（23 条源级/发射级），**变异 8/8 被抓**、源码 sha256 逐字节还原。
> 顺带补齐同一族的其余面：`Dictionary`/`Vector` 也没有 vtable，`Object` 自有的四个方法
> （`toString`/`hasOwnProperty`/`propertyIsEnumerable`/`valueOf`）现在由 `as_dyn_object_builtin`
> **按堆种类**回答（record `[object Object]`、Dictionary `[object Dictionary]`、Vector 用 `join(",")`），
> `as_obj_to_str`/`as_obj_default_str` 也认得这两类——此前 `var o:Object = new Dictionary(); o.toString()`
> 同样是 SIGSEGV。**UI 库（style 层）当时那两处规避已经回退**：G14 一死，为它而做的
> `fromAny`/`fromArray` 形参拆分就没有理由了，已按实测合并（见下表「对 UI 库的影响」行）；
> G9 裁过的『*』读绑定**仍然保留**（那不是躲缺陷，是省一次装箱的正确默认，理由独立于 G14）。
> 修复本身只在编译器侧。

| 项 | 内容 |
|---|---|
| 判定 | **遗留欠账**（AIR 能做对而我们做不出，且不是平台边界——AIR **26/26** 与 AS3 规则逐条一致）。按 AGENTS.md §1.5 属「错的是我们」那一半。**（登记时的判定；已按此立项，阶段二百五十三修完）** |
| AIR 参考臂（**先验证参考本身**） | 期望值**手写**在 `probes/obj-array-identity/expect.json` 的 `truth`（按 AS3 语言规则），AIR 臂**26 条全部相符** ⇒ 「以 AIR 为准」这句话本身是被测过的，不是口号 |
| 现象（**生成 C 逐行实读**，非推测） | `var o:Object = [1,2,3];` 落成 `o = (Object*)(as_array_make(...))` —— **裸数组指针**。于是：① `o is Array` 被**常量折成 `false`**（`as_str_from_bool(false)`）；② `o is Marker` 落成 `as_is(o, &Marker_vt)`；③ `o as Array` 落成 `as_v_obj_val(...)`（Array 的 tag 不是 4 ⇒ **NULL**）；④ `o.length` 走 `as_dyn_get` ⇒ **`undefined`**；⑤ `typeof o` 却是正确的 `"object"` |
| 崩溃的真因 | `as_is(obj, target_vt)` 里读 `((as_object_header*)obj)->vtable` 再沿 `super` 走。运行时**自己知道**这个危险，注释写着「an Array/Vector/Dictionary 的第一个字是数据指针或 mark 回调，读它本身就是崩溃」——但那个守卫只挡 `target_vt == NULL`；`target_vt` 非空时照读 ⇒ 崩溃。`*` 槽也躲不过：`as_v_is_inst(v, vt)` 对 `tag == 6`（Array）**明确放行**去调 `as_is` |
| 影响半径（26 格矩阵，**8 条偏离**） | `Object` 槽：`is Array` **假** / `is <userClass>` **崩** / `as Array` NULL / `.length` undefined；`*` 槽：`is Array` **对**、`is <userClass>` **崩**；`Array` 直声明：`is Array` 对、`is <userClass>` **对**（不崩）；`Number`/`String`/`Boolean` 进 `Object` 槽：**全对**（`is <userClass>` 回 false 不崩；`is Number/String/Boolean` 也对）；真类实例：全对。⇒ 缺口**专属于 Array**，不是「Object 槽普遍丢身份」。**决定性格子 26**：把守卫改成「数组检查在前」**也没用**（`is Array` 照样折成 false，随后 `is Marker` 照样崩）⇒ **修复只能在调用点做**，不能在 `fromAny(o:Object)` 内部做 |
| 对 UI 库的影响 ①（**登记时**的判定） | 当时判「`Size`/`LengthEdges`/`Edges`/`Corners`/`Fill` 的 `fromAny`/`fromArray` 拆分**不能合并**」：`fromAny` 里第一句就是 `o is Length` / `o is Fill`（**用户类**），一旦有 Array 进来就 **SIGSEGV**。⇒ 拆分是**当时的安全要求**（不是省事的临时手段）。**这条判定只在 G14 存活期间成立**，见下一行 |
| 对 UI 库的影响 ②（2026-10-23 当日：**拆分已回退，`fromAny` 全能化**） | G14 修掉后，拆分的前提消失，实测两 runtime 后**合并**：① `Size/Edges/Corners/LengthEdges/Fill.fromAny` 自己 `if (o is Array) return fromX(o as Array);` 分派（**`fromArray` 保留**为显式入口——渐变那条路要它的 `Array` 形参，将来落地时 `.length` 才安全）；② `StyleRefinement.from` 里 6 处 `o.x is Array ? fromX.fromArray(...) : fromX.fromAny(...)` 全部收成 `fromX.fromAny(...)`（`size`/`size` 两组 + `padding`/`borderWidths`/`border`/`margin`/`inset`/`background`/`cornerRadii`），调用点不再知道形参形状；③ `Fill.fromAny` 里那句**曾被折成 `if (false)` 的死守卫**重新变成活代码（不是「加回保护」，是它现在真的会执行）；④ 10 处 `*` 读绑定的**理由注释**重写（G9/G14 均已修，`*` 作为「省一次装箱」的正确默认保留）。**证据**：`probes/style-fromany/`（19 格，AOT 与真 AIR 51.4.1 **逐字一致**，含 `is Array` 进 `Object` 形参这一机制格；变异 **4/4**，源码 sha256 逐字节还原）；库内 End-to-end 钉子 `ui-demo/CheckUi.as` §8（33 格）+ `ui-demo/mutation-checkui-array-bg.cjs` **2/2** |
| 与 G9 的关系 | 两个**不同**的缺陷，别混：G9 = `Boolean(<Object 槽>)` 读错（**已修**，阶段二百四十八，且只影响 `Boolean`）；G14 = `Object` 槽对 **Array 完全不装箱**（**已修**，阶段二百五十三，影响 `is`/`as`/动态属性，修前会崩）。G9 的修复（`Boolean` 分支加 `as_obj_to_value`）**治不了** G14——因为 Array 压根没被装箱，没有箱子可解；两条各自立项、各自修 |
| 状态 | **已实测 · ✅ 已修（阶段二百五十三，v0.4.217）**（登记 2026-10-23；见本条顶部修复记录）。作为一道门持续看住（`tools/gates.cjs` 第 9 道）：偏离集**恰好等于**登记集才绿；**新增**偏离、**消失**的偏离、**少跑**的用例都会红。消失时它会说「可能是真修了，去更新登记与期待值」——不假绿；**这条机制本次当场响了一次**（08:30 复测 ⇒ 偏离集变空） |
| 复现 / 钉子 | **三件**：① 26 格矩阵 `node probes/obj-array-identity/run.cjs` · 变异 `mutation.cjs` **4/4**（翻一条 AS3 规则 / 删一条已登记偏离 / 造一条不存在的偏离 / 砍掉后半段用例）；② **最小复现包**（供转交编译器侧）`node probes/g14-minimal/run.cjs` —— 13 行程序、两 runtime 并排，exit 0 = 复现成功、exit 1 = 已被修（并列出要更新的三处登记）、exit 2 = harness 失败或**参考臂自身与 AS3 规则不符**（此时拒绝下结论）；③ **修复后的能力面**（防「修了但没真解锁」）`node probes/style-fromany/run.cjs` —— 19 格问的是**库真正依赖的那个用法**（`Array` 进 `Object` 形参后 `is Array`），AOT 与真 AIR 逐字一致；变异 `mutation.cjs` **4/4**，全部 `finally` 还原并 sha256 逐字节核对 |
| 库内钉子 | `ui-demo/CheckUi.as` **§8**（5 条断言：数组背景**不崩**且无填充、`Fill.fromAny(Array)` **直接**调用也无填充、标量背景仍是实色、兄弟字段不被吞、`Fill.fromAny(标量)` 仍实色）；变异 `ui-demo/mutation-checkui-array-bg.cjs` **2/2** —— ① 把 `Fill.fromAny` 的数组分支改成返回 `solid(0x000000)` ⇒ 两条数组断言**按名**报红（**注意**：这条变异在 2026-10-23 之前是「改回调用点无分流 ⇒ 当场 `exit 3221225477` 崩溃」，G14 修好后崩溃已经不可能，故判据从**退出码**升级为**断言名**——否则它就成了假钉子）；② 把 `Fill.fromAny` 改成恒不实色 ⇒ 标量断言当场报错（证明它不是同义反复） |
| 证据落盘 | [`reviews/probe-g14-object-slot-array-identity-2026-10-23.md`](reviews/probe-g14-object-slot-array-identity-2026-10-23.md) · 转交材料 [`reviews/handoff-g14-to-compiler-2026-10-23.md`](reviews/handoff-g14-to-compiler-2026-10-23.md) · 探针 [`probes/obj-array-identity/`](probes/obj-array-identity/)（`Cases.as` 单一用例源、两驱动、两臂原始输出）与 [`probes/g14-minimal/`](probes/g14-minimal/) |

> **历史：当初的定位与转交材料**（阶段二百五十三已按此修掉，保留以便回溯）—— 完整转交材料见
> [`reviews/handoff-g14-to-compiler-2026-10-23.md`](reviews/handoff-g14-to-compiler-2026-10-23.md)：
>
> ① **静默假**：`src/emit.ts:32576` 的 `x is Array` 分支只给 `any` 槽发了正确的运行时测试（`as_v_is_array`），`Object` 槽直接落到 `return 'false'`——而**紧接其后的 `is Class`(`:32591`) 与 `is Vector.<T>`(`:32624`) 都有 `o.type.kind === 'object'` 分支**，形状相同（`as_v_obj((void*)(code))` 打箱后再问）；同文件 `is Object`(`:32561`) 还留着长注释说「这里曾经把静态已知的 scalar/array 折成 false，是错的」。⇒ 看起来是**同一类错误的漏网实例**。
> ② **崩溃**：`src/runtime.ts:1178` 的 `as_is` 注释就写着「Array/Vector/Dictionary 的第一个字是数据指针或 mark 回调，读它本身就是崩溃」，但那个守卫只挡了 `target_vt == NULL`；`is <用户类>`（`target_vt` 非空）是第二条路径。运行时**已有可用判据**：`gc_in_heap()`（`:2038` 正是这么区分 Class 值与真实例的）+ GC header 的 `GCT_*` 类型标记。
> ③ `*` 槽也崩：`src/runtime.ts:2026` 的 `as_v_is_inst` 对 `tag == 6` 放行去调 `as_is`。
> ④ 「不装箱」的明文在 `src/runtime.ts:3432`（`case 4: case 6: return v.ptr;`）⇒ `Object*` 与 `as_array*` 在 C 层**同型**。两条修法路线：**(A)** 让判定认得「裸容器指针」（改 ②③，① 顺势好）；**(B)** 让 Array 也装箱（与 `Object*` 的全部既存隐式转换都相关，面更大）。我们**不替他们选**（不了解其表示/性能约束），只报事实：`is Number/String/Boolean` 在 `Object` 槽上**今天是对的**，修法别弄坏它。
> 修完 `run.cjs` 的偏离集会变空 ⇒ 转成 `GAP-CHANGED` 叫我们更新登记（这条设计是故意的）。

---

### G15 —— `getQualifiedClassName(new Dictionary())` 返回 `"Object"`（AIR：`"flash.utils::Dictionary"`）

> 阶段二百五十三修 G14 时**顺带量到**的相邻缺口，**不是** G14 的衍生：`getQualifiedClassName` 不走
> 方法派发，与「Object 槽装 Array」无关。**已确认是既有缺陷**：同一程序在阶段二五二（`a035645`，
> G14 修复前的干净工作树）跑出同样的 `"Object"`。⇒ 单列，不夹带进 G14 的提交。

| 项 | 内容 |
|---|---|
| 现象 | `var d:Object = new Dictionary(); getQualifiedClassName(d)` ⇒ 我们 `"Object"`，AIR `"flash.utils::Dictionary"` |
| 同批对照（**都对**） | `[1]` ⇒ `"Array"`；`new Vector.<int>()` ⇒ `"__AS3__.vec::Vector.<int>"`；`{}` ⇒ `"Object"`（AIR 同） |
| 判定 | **遗留欠账**（AIR 能做对）。影响面：诊断/序列化里按『qcn』分流的代码会把这个 Dictionary 当普通 record |
| 机制（**已定位，未改**） | `as_obj_class_of`（阶段二百五十三新增）对 `dk==1`（Dictionary）返回 `null`，`getQualifiedClassName` 于是退到默认 `"Object"`；Dictionary 没有 vtable，`as_v_class_of` 那条路也拿不到类名 |
| 修法方向 | 与 `as_obj_is_array` 同型：给「无 vtable 的堆种类」一个按种类回答类名的入口（Dictionary 直接 `flash.utils::Dictionary`，另需覆盖 `ByteArray`/`String` 等），并在 `as_obj_class_of` 里接上 |
| 状态 | **已实测 · 未修** |
| 证据落盘 | `temp/g14/DictAot.as`（AOT 14 行）· `temp/g14/DictAir.as` + `temp/g14/dict-air.txt`（AIR 原始输出）· 驱动 `temp/g14/air-run.cjs` |
| 备注 | 同一批里 **13/14 行已与 AIR 逐字一致**，唯一不一致的就是本行 ⇒ 这张小矩阵可以当本条的验收网 |

---

### G16 —— 三元 `cond ? null : X` 条件为假时**丢值**：对象→`null`、数值→`0`、布尔→`false`（仅 **String** 免疫）

> 量这个方法的位置是一次库内小修：`ImageWidget` 里 `o == null ? null : Bitmap(o)` 每帧都重建 Bitmap、从不 fit。
> 我原以为是自己的 `arrange` 写漏了，**最小化到 17 格才看清是三元运算符本身**。它**不止影响 UI 库**：
> 任何 AS3 源码里 `cond ? null : <非 String 表达式>` 在条件为假时都丢值，且**数值/布尔是静默变成 `0`/`false`**
> ——比 `null` 更难发现。按 AGENTS.md §1.5 这属**遗留欠账**（AIR 全对），且是**通用语义缺陷**，不是 UI 特例。

| 项 | 内容 |
|---|---|
| 现象 | `x == null ? null : Bitmap(x)`（`x` 是活对象，条件为假）⇒ 我们返 **`null`**；AIR 返该 Bitmap |
| 触发面（**精确形状**） | **THEN 槽是字面 `null`**，ELSE 槽是**任何非 String** 的表达式，条件为假 ⇒ 结果被折叠成该结果类型的**零值** |
| 实测矩阵（17 格 × 双 runtime） | AOT **12 格偏离**（1,3,4,5,7,8,9,10,14,15,16,17）；AIR **17/17** 与 `expect.json` 的手算逐条一致 ⇒ 参考被检验而非假设。格 11/12/13 = 控制组（全对） |
| 结果类型分档（实测） | 对象型 → `null`（9 格：`Bitmap`/`Object`/属性读/数组元素/`bitmapData`/`{}` 槽读出/函数调用）；**`Number` → `0`**（格 15，期待 42）；**`Boolean` → `false`**（格 16，期待 `true`）；**`int` → `0`**（格 17，期待 7）；**`String` 免疫**（格 11 → `hi` ✓） |
| 根因（**已定位到两行**） | ① `src/emit.ts:28915-28937` `unifyType`（三元的结果类型）：`a` = **THEN 分支**的类型。`a.kind='null'` 与 `b.kind='object'/'int'/'bool'` 时：同 kind ✗、string 规则（`:28920`）✗、`any` 规则（`:28921`）✗、numeric 集合（`:28932`）**不含 `'null'`** ✗ ⇒ 落到 `:28936` 的 `return a; // fallback: keep the then-branch type` ⇒ **整个三元的静态类型被定成 `null`**。② `src/emit.ts` 的 `convert`：静态类型是 `null` 的表达式被当成「它**就是** null 值」直接发射成常量 —— `:33985-33997`（`number`→`0.0`、`int/uint/int64/uint64`→`0`、`bool`→`false`、`string`/`object`/引用族→`NULL`）+ `:34057`（`object` 槽 → `NULL`）⇒ **运行期真的会跑的那一支被整段丢掉** |
| 模型可预测性（自检） | 上面两行**精确预测了全部 12 格偏离与 5 格通过**，包括「String 免疫」「`then` 不是 null 就正常」「`x==null ? Bitmap(x) : null` 正常」三件反直觉现象 ⇒ 不是「碰巧」，是机制 |
| 为什么 String 免疫 | `unifyType:28920` 的 `if (a.kind === 'string' \|\| b.kind === 'string') return { kind: 'string' }` 在 fallback **之前**命中；引用/数值/布尔族没有这条规则 |
| 为什么格 12（`x == null ? 0 : 42`）正常 | 两侧都是 `int` ⇒ `:28916` 的 `a.kind === b.kind` 命中，根本没走到 fallback（它**不是** null 字面量用例，是「同一形状但不含 null」的对照） |
| 为什么格 2（`x == null ? Bitmap(x) : null`）正常 | `a` = object ⇒ fallback 返回 **object** ⇒ 类型对；null 侧转成 `NULL` 本来就对。⇒ 说明**故障与「null 是哪一支」强相关**，而不是「三元遇 null 就坏」 |
| 影响半径 | **不限 UI 库**：任何用户的 `cond ? null : <非 String>` 都丢值；对象型见 `null` 至少还会**崩**在 `#1009`，而**数值/布尔是静默 0/false**（最危险的一档：算出来的数悄悄变 0） |
| 对 UI 库的影响 | 全库审计命中 **1 处**：`kit/asaot/ui/kind/ImageWidget.as` 的 `bitmapOf(o)` ⇒ 已绕行 |
| 绕行（库内） | `if (o == null) return null;\n return Bitmap(o);`（**if/return 形式**，实测两臂都对——格 13 是同形对照）；注释指向本条 + `probes/g16-ternary-null/` |
| 修法方向（**不替他们选实现，只报事实**） | 首选 `unifyType` 补一条族规则：一侧 `null`、另一侧是**引用/数值/布尔**族 ⇒ 返回**另一侧**的类型（与 `:28920` 的 string 规则同型）。可复用的邻居：`:29005` 的 `fam()` 已把 kind 分成 `num/bool/str/null/ref`，同一个分类思想。**只改 `convert` 不够**：那只能保住值，三元的**静态类型**仍然错，后续 `is`/`as`/成员访问/参数类型仍会按 `null` 处理 |
| 状态 | **已实测 · 未修**（库内唯一命中点已绕行） |
| 证据落盘 / 复现 | [`probes/g16-ternary-null/`](probes/g16-ternary-null/)：`node run.cjs`（一命令两臂，exit 0=一致 / 1=不一致 / 2=构建错）；`NullCases.as` 17 格单一用例源；`expect.json` 手算规则（含逐格推导）；变异 `mutation.cjs` **4/4**（① 把格 1 改成 if/return 绕行形 ⇒ 该格必须**不再**报 NULL；② 改 `expect.json` 声称格 1 是 `NULL` ⇒ runner 必须报「参考与规则不符」；③ 把**能用的**格 6 改坏 ⇒ 该格必须**加入**失败集；④ 让格 3 两分支都返 null ⇒ 实测 **AIR 臂中途死掉**，runner 必须报「AIR 臂只写了 2/14 行」——这条顺带证明**崩溃检测也有牙**），全部 `finally` 还原 + sha256 逐字节核对 |

### G17 —— Windows 上**生成的 C 语法错**：`as_job_dir_push` 的 Win32 分支把 C 字符常量写坏 —— ✅ **已修（上游，2026-10-24）**

| 项 | 内容 |
|---|---|
| **判定** | **构建/工具链缺陷**（AIR 无对应物，但对**本机 Windows 构建**是硬阻塞，属「增强/工具链」类） |
| **症状** | 任何**走到 `File` 目录列举**的程序（两个窗口 demo 都用到）在 Windows 上 clang 报 `missing terminating ' character`——即**生成的 `.c` 本身不是合法 C**。macOS/Linux 不进该分支，所以上游 CI（arm64 macOS）看不见 |
| **根因** | `src/runtime.ts` 的 `RUNTIME_PREAMBLE` 是 **TS 模板字符串**，里面的 `'\\'` 经 TS 转义后交给 C 的是 **`'\'`**（单反斜杠 + 单引号）⇒ 未终止的字符常量。`'\0'` 同理在转义层被吃掉 |
| **本地改法** | 3 处加倍：TS 源写 `'\\\\'`（C 得 `'\\'`）、`'\\0'`（C 得 `'\0'`）；`git -C as3compiler diff src/runtime.ts` 可逐字核对 |
| **证据** | 本工作区 `ui-demo/build-air.cjs` 与 `probes/widgets/overlay` 的窗口臂在本机全链路可建可跑；回退该补丁即回到 clang 语法错 |
| **状态** | ✅ **已修（上游，2026-10-24）**：本地补丁已从工作树撤除；`node tools/compiler-fingerprint.cjs` 在 HEAD `480b81c` 报 **`0 files`（CLEAN）** |

### G18 —— 非 Cocoa 后端的**应用菜单钩子未定义** —— ✅ **已修（上游，2026-10-24）**

| 项 | 内容 |
|---|---|
| **判定** | **后端缺口占位**（`sk_menu_supported()` 返回 0 是刻意的，但两个钩子--**帧循环上的 `sk_menu_ensure()`** 与 **事件循环里的 `sk_menu_flush()`**--是无条件调用的） |
| **症状** | Windows clang 链接 `window_glue.cc` 报未定义符号；**任何**窗口程序都链不上（与 P1 是两道独立的闸） |
| **根因** | `vendor/window_glue.cc` 的 `#else`（非 Cocoa）分支只定义了 `sk_menu_supported` / `sk_menu_install_app` / `sk_menu_install_dock`，漏了两个无参钩子（Cocoa 分支有，第 2967/2978 行） |
| **本地改法** | 在 `sk_menu_supported` 前补两个显式空桩（带注释说明为何是 no-op） |
| **证据** | `git -C as3compiler diff vendor/window_glue.cc`；调用点：第 807 行（帧）与第 1263 行（事件循环） |
| **状态** | ✅ **已修（上游，2026-10-24）**：同上，工作树 CLEAN；本机窗口程序仍可全链路构建（`ui-demo/build-air.cjs`、八道窗口门全绿） |

> **这两条的来历值得留着**：2026-10-23 本工作区为了让 Windows 上能构建窗口程序，在编译器树里
> 打了两个补丁，并如实披露「`asaotui` 不动 `as3compiler/` 一行」这句话**当时不成立**。2026-10-24
> 上游并发会话把两条都修好并提交，本地补丁随即撤除，`node tools/compiler-fingerprint.cjs` 在
> HEAD `480b81c` 报 `0 files`——**这句话现在重新成立（零个文件）**。
> 修之前本机无法构建任何窗口程序（浮层与六页画廊的验收全都跑不了），所以这不是排版洁癖。

---

### G19 —— `Graphics.drawRoundRect` **静默丢弃两个椭圆半径**，只画直角矩形（AIR 画圆角）

| 项 | 内容 |
|---|---|
| **判定** | **遗留缺陷**（AIR 能跑对我们跑不对，符合 AGENTS.md §1.5 的硬判据）——而且是**静默**的：不报错、不提示后端不支持，圆角就这么消失 |
| **症状** | 任何带 `cornerRadii` 的样式（`asaot.ui` 的按钮、卡片、对话框面板、输入框……**几乎每一个控件**）在 AOT 产出的原生窗口里都是**直角**；同一份 `.as` 用 `mxmlc`+`adl` 跑出来是圆角。探针侧的具体表现：`probes/widgets/motion` 把 `cornerRadii` 从 0 动画到 12，帧缓冲里 `(20,20)` 全程是 `#3366cc`（方角），而样式侧 `resolved.cornerRadii.topLeft` 确实是 `12` |
| **根因** | 生成的内建方法是个**桩**（`as3compiler/src/emit.ts:18186`）：`void Graphics_drawRoundRect(void* _this, double x, double y, double w, double h, double ew, double eh) { (void)ew; (void)eh; Graphics_drawRect(_this, x, y, w, h); }` |
| **为何是「静默」而不是「未支持」** | 相邻的 `drawCircle`/`drawEllipse` 都走 `as_skia_path_add_*`（真几何），只有圆角矩形是直角回退；调用方（我们的 `PaintKit`）**无从得知**，它按 AIR 语义传了半径 |
| **证据** | ① 代码：上一行 `drawRect` 用 `as_skia_path_add_rect`、下一行 `drawEllipse` 用 `as_skia_path_add_oval`，本该有 `as_skia_path_add_round_rect` 的位置是空的；② 实测：`probes/widgets/motion`（`(20,20)` 恒为 `#3366cc`，半径 0→12 像素无变化），`motion.samples.txt` 的 `rest radius=0` / `final radius=12` 与像素对照即为反证 |
| **本地怎么办** | **不改编译器**（本工作区边界）。库侧只做两件事：① 本文件登记；② 探针把这件事**钉成可见事实**——`probes/widgets/motion` 的 `(20,20)` 期望值写 `#3366cc` 并注明「若此像素变白说明 G19 已修」，于是上游修好那天这道门会**当场变红**并指出该改期望值，而不是让圆角静默复活 |
| **影响面** | 纯视觉。布局、命中、事件均不受影响（圆角从不参与 flexbox 与拾取）。若将来要做像素级 AIR 对齐，这是第一优先 |
| **状态** | ❌ **未修**（2026-10-24 发现于 `probes/widgets/motion` 的编写过程） |

---

### G20 —— `TextField.setTextFormat()` **追加** run 而不替换范围 ⇒ 重画 N 次就把字符串画 N 份

| 项 | 内容 |
|---|---|
| **判定** | **遗留缺陷**（AIR 上 `setTextFormat` 替换目标范围，我们追加）——而且**不用改任何几何断言就能看到**：`textWidth` 自己就跟着重画次数线性长 |
| **症状** | 输入框里敲 `1111`，字宽是 **28.88**；失焦再聚焦、或任何一次重绘之后变成 **56.73**（两倍），再重绘变 84（三倍）；屏幕上字形挤成一串往外长，用户报的是「输入过的字被复制一遍」。症状与字体无关，可稳定复现（`probes/widgets/typing` 变异 M3） |
| **根因** | 生成的内建方法只**追加**：`as3compiler/src/emit.ts:20417` 的 `TextField_setTextFormat` 往 `tf->_runs` 追一条、`_runs_gen++`，**不按 beginIndex/endIndex 裁剪旧 run**（`TextField_set_text` 则会 `_runs_gen++; _runs = NULL`，所以重赋 `.text` 能清掉累积）。排版侧 `vendor/skia_text_glue.cc:495` 的 `sk_textlayout_new_runs` 对**每条 run** 都 `pushStyle/addText/pop`，于是模型里的同一个字符串被 `addText` N 遍 |
| **为何很难自己发现** | 单次调用是对的（第一次 `setTextFormat` 后宽度正常），**只在多次重绘后**才暴露；而用 `dispatchEvent(new Event(Event.CHANGE))` 直接改模型的探针（早期 `probes/widgets/interact` 相位 E）根本不经过这条路径，于是**同时盖住了两个缺陷**（本缺口 + 缺口 20 的 ghost），直到用真实文本管线（`Stage.dispatchText`）写 `probes/widgets/typing` 才看见 |
| **证据** | ① 代码：`emit.ts:20417`（只追加）+ `skia_text_glue.cc:495`（每 run 一遍字节）；② 实测：`probes/widgets/typing` 变异 M3（把 `setTextFormat` 放回 `paint`）⇒ `blurred: textWidth is 56.7265625 for '1111', a fresh field measures 28.8828125 (runs accumulated)`、`the glyphs run to x=84, past one copy's 57.8828125`；原样运行时真实字段与现场新建的干净字段逐字相等（`28.8828125`） |
| **本地怎么办** | **不改编译器**（本工作区边界）。库侧规避很干净：**单格式字段一律不调 `setTextFormat`**——`defaultTextFormat`（新建字段时生效）+ `textColor` 就够，`paint` 里**不碰 run**。只有真要做「一行多种格式」时才需要它，那时必须先在上游修掉本缺口 |
| **影响面** | 任何**在重绘路径里**调 `setTextFormat` 的代码（本库目前为 0 处）。`defaultTextFormat` 不受影响（只写默认值，不进 `_runs`） |
| **状态** | ❌ **未修**（2026-10-24 由用户报告定位；库侧规避已钉死，见 `probes/widgets/typing`） |

---

## 2 不是缺口：已澄清 / 已关闭

| 事项 | 结论 | 证据 |
|---|---|---|
| **AS3 无 FFI**（纯 AS3 源调不到 C 函数） | **是我方设计前提，不是缺口**。正因如此，UI 库坚持纯 AS3 就**不需要** FFI。若将来要把布局换成 native Yoga，才需要「内建类 implements 用户 `.as` 接口」 | `as3compiler/docs/zh-cn/enhancements.md` E11（未排期） |
| **内建类 implements 用户 `.as` 接口** | **已实测通过**（正例 `x=120`、`is` 为真；反证报 `does not implement method 'bogus'`）⇒ 若走 native 路径，架构也无需回退 | [`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md) |
| **`System.exit` 是否 AIR 也没有** | **不是「也没有」**：用真 AIR（51.4.1）判清，AIR **有** `exit(code:uint):void` ⇒ 归 G1（欠账），不是「平台边界」 | `air-check/SystemExitProbe.as` |
| **「退出要调 `System.exit`、所以我们缺了就没法退出」** | **前提就不成立**：惯用路径是 `NativeApplication.nativeApplication.exit()`，**我们已支持且实测跑通**（AOT `EXIT=0`；AIR 侧驱动一直这么写） | [`reviews/probe-exit-paths-2026-10-22.md`](reviews/probe-exit-paths-2026-10-22.md) |
| **「本机无 AIR SDK」** | **旧结论已推翻**：本机装有 **AIR SDK 51.4.1**，`mxmlc`（Java 正常）与 `adl.exe` 均可本地运行 | [`air-check/README.md`](air-check/README.md)、[`README.md`](README.md)「本机环境」 |
| **`-w` 之外，库用到的写法** | **全部原生支持、无需绕路**（见 §3） | [`layout-check/README.md`](layout-check/README.md) §dogfooding 3 |
| **G12「大字节缓冲后堆分配挂起」** | **不是缺口，已结案**：实证是见证程序把三个脚本作用域容器声明在 `showWindow()` 之后（该调用不返回 ⇒ 初值永不执行 ⇒ 引用变量停在 `NULL` ⇒ `push` 抛 `#1009`）。去掉 134400 大缓冲症状不变；把声明顺序修好后带大缓冲也能跑完 | [`reviews/probe-g12-2026-10-23.md`](reviews/probe-g12-2026-10-23.md)、[`probes/g12-ab/`](probes/g12-ab/) |
| **G11「同源两次构建产出不同的 C」** | **不是缺口，已结案**：不是生成器随机，而是**测量在另一个进程正改写的编译器树上进行**。失败构建在 `阶段二四七` 提交前 **24 分钟**；同一个坏法在**同一分钟、另一个程序**的产物里原样出现，且两者 84 秒内**收敛**（20→1→0 条 C 错）；冻结树上 5 次构建**逐字节同一份 C**。旧处置「先重跑一次」已废止，改为**先看编译器树状态** | [`reviews/probe-g11-nondeterminism-2026-10-23.md`](reviews/probe-g11-nondeterminism-2026-10-23.md)、[`probes/g11-nondeterminism/`](probes/g11-nondeterminism/) |
| **`Array(x)` 是「复制数组」吗** | **不是缺口，是 AS3 事实**：`Array(3)` 得长度 3 的空位数组、`Array([1,2])` 得**长度 1** 且 `[0]` 就是那个数组、`Array(a) === a` 为 false。双臂实测一致（8 格 AGREE；门 §7b）⇒ 库内**禁止**用 `Array(v)` 做「单值/列表归一」，一律 `OptionSupport.list(v)` | [`probes/array-coerce/`](probes/array-coerce/) |
| **`stage.showWindow()` 不返回**（而是把主线程交给帧/消息循环） | **是我方窗口后端的已知平台事实，不是缺口**（要改成非阻塞得动整个事件循环架构）。但它的后果必须写明：**顶层语句在 `showWindow` 之后永不执行，包括 `var x = …` 的初值**；`setTimeout` 也必须在它之前注册。AIR 桌面端不阻塞 ⇒ 同一份源码在 AIR 里这些变量会被正常初始化。⇒ 写窗口程序时**所有 setup 前置** | `probes/array-scope/Main.as` 头注释（SETUP ORDER）、`examples/*window*.as` |

---

## 3 正面结论：库用到的写法**全部原生支持、无需绕路**

（用自家编译器编自家库时逐项确认，见 [`layout-check/README.md`](layout-check/README.md)）

- 接口 `implements` + 经接口变量分派；接口 vtable 与一致性检查都覆盖（含内建类）
- `Boolean(obj.prop)` **动态属性读** —— ⚠️ **此条曾被写得过宽**：17 格真值矩阵实测后收窄为「作者侧各种拼写全对」，唯独 **`Boolean()` 用在*静态声明为 `Object` 的局部量*上**会退化成指针测试 ⇒ **见 G9**（✅ 阶段二百四十八已修，26 格 A/B 现 0 差异）
- `Math.*`、`isNaN`、`toFixed`
- 数组字面量 / `push` / 下标；**数组进 `Object`（或 `*`）槽后仍保持身份与派发**（`is Array` / `as Array` / `.length` / 下标 / `join` / `String()`）—— ✅ 阶段二百五十三已修（修前 `is Array` 被折成 `false`、`is <用户类>` 直接崩，见 G14；回归钉 `probes/style-fromany/`）
- `switch`、`for` / `while`、`?:`、`&&` 值语义
- 字符串 + 数字拼接
- `as` 转换、顶层脚本、多文件编译
- `flash.filesystem.File` / `FileMode` / `FileStream`（AIR 侧驱动写结果文件用；编译器 stage 64 已支持）

---

## 4 与编译器仓库的边界

- 本文档位于 **`asaotui/`（工作区）**，**不是** `as3compiler/` 仓库的一部分。
- 本文档只**登记**。登记的缺口一旦立项修复，**代码改动落在 `as3compiler/`（含 `TODO.md`、版本号、全量回归）**，本文档只回写判定与状态（G1/G4/G8/G9 均按此办理）。

## 5 将来若某条要立项（备查，不进编译器仓库）

登记项的立项入口按 AGENTS.md §1.5 的硬判据分流：

| 判定 | 入口（`as3compiler/TODO.md`） |
|---|---|
| **遗留欠账**（AIR 有、我们无）——G1、G2 | `### 遗留待开发` 表（附「`adl` 实测证据」一栏） |
| **增强 / 工具链**——G4、G6 | `### 增强待做` 表（须 opt-in、绝不静默、跨端差异显式列出） |
| **实现限制 / 后端缺口**——G3、G5 | 先补 `adl` 实测，再按上两行之一归类（**不得凭直觉入表**） |

立项 = 占阶段号 + 升版本 + 全量回归，属**项目级承诺**，须先取得项目负责人同意。
