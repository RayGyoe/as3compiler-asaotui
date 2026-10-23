# U1 实施计划：把 Yoga 接成 `asaot.ui` 的布局底座

> ### ⚠️ 状态：**已搁置（仅备查）—— 用户 2026-10-22 指示**
>
> 本文件写的是「**native（Yoga）路径**」的 file-by-file 步骤。用户已拍板：UI 库走**纯 AS3 实现**，
> 缺的底层支持只**登记**在 [`compiler-gaps.md`](compiler-gaps.md)，**不改编译器代码**。
> 因此：**本文件当前不执行**；纯 AS3 的实施/验收见 [`u1-scope.md`](u1-scope.md) 与
> [`seam/`](seam/)、[`layout-check/`](layout-check/)、[`diff-check/`](diff-check/)、[`air-check/`](air-check/)。
> 保留本文件的唯一用途：**若将来要 native 化**（需要改编译器，属项目级决定），照它做。
>
> （以下为原始计划正文）

> **状态：计划（未实施、不占阶段号、不升版本）**。本文件把
> [`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md)（前置测量，**Go（条件）**）、
> [`ui-toolkit-feasibility.md`](ui-toolkit-feasibility.md) §7 的 U1 行、以及
> [`u1-prototype/`](u1-prototype/)（原型，**只读**，另一个 agent 在写）落成**可照着做**的步骤。
>
> **硬约束（AGENTS.md，本文件不重复论证）**：生成 C 可读（§2.6）、每阶段收尾三件事（§2.7）、
> 第三方库**链接**不内嵌（§2.9）、新特性必须配 `examples/*.as` + 断言式回归、语义红线见 §2.4。
> `as3compiler/` 本文件**只读**，一列改动都还没做。
>
> **取证口径**：本文件的每个 `文件:行` 都是写本文件时**现读**所得（写本节时 HEAD 已是 `f688094`（阶段二百三十七），
> 而在写这份计划的过程中它还在往后走——**编号是活靶**，见 §1.1；
> `https://github.com/facebook/yoga` pin = `843dba8619420992e492bbb4b3d2f63d9ad6c683`）。
> 凡本机测不了的（macOS `-Wl,-dead_strip`、严格 `wasm32-wasip1`、任何 CI 结果）一律写**待 CI 验**，不臆造成结论。

---

## §0 一句话

把接缝画在**纯 AS3 接口** `asaot.ui.LayoutEngine`（[`seam/`](seam/) 已有契约骨架）上。

**当前适用的是纯 AS3 实现**：`As3LayoutEngine`（flexbox 子集）**已实现并通过三端验收**
（[`layout-check/`](layout-check/)、[`diff-check/`](diff-check/)、[`air-check/`](air-check/)），且**不改编译器**。

下面这条（native）是**备查的备选路径**（已评估、已实测前置闸门、**当前搁置**）：`NativeLayoutEngine`
（**内建类**，由 `emit.ts` 发射、`implements:['asaot_ui_LayoutEngine']`，方法体转发到 `u1-prototype/` 搬来的
**不透明 C 接缝** `as_ui_yg_*` → Yoga）。Yoga 源码随仓库入库、只在程序引用 `asaot.ui` 时才进链接
（`usesAsaotUi`，仿 `usesFlashData`），并配 `examples/ui-layout.as` + 单元组钉住。
**若将来启动 native：本机可验的部分（native Windows）先落地；两个 CI 阻塞项（wasip1 / macOS dead_strip）设成落地前的预检，任一红即退 AS3 子集。**

---

## §1 阶段号与版本号建议

### 1.1 实测到的编号现状

| 事实 | 值 | 证据 |
|---|---|---|
| `TODO.md` 自报的最后一个阶段节 | **阶段二百三十一** | `TODO.md:13774`（`### 阶段二百三十一：示例清单跨宿主 …（v0.4.202 → v0.4.203）`） |
| `TODO.md` 末端的非阶段小节 | 「### UI 工具链待定项（未排期）」 | `TODO.md:14086`（在 `### 增强待做` `:14060` 之后、`## 备注` `:14111` 之前） |
| `阶段二百三十二` 及以上的 `### 阶段` 节 | **`TODO.md` 里零命中** | `grep -noE "阶段二百(三十[二三四五六七八九]|四十)" TODO.md` 无输出 |
| `package.json` 版本 | **`0.4.203`** | `package.json:3` |
| `git log` 的 HEAD 提交 | 写本节时 `f688094 fix(textfield): …（阶段二百三十七）`；前三条为 `e798ef7`（二百三十五/二百三十六）、`80758ea`（二百三十三/二百三十四）、（二百三十二） | `git log --oneline -3` |

**结论：`TODO.md` 落后于提交序列**——它停在本节所引的阶段二百三十一，而工作树里已经落了
二百三十二~二百三十七（而且还在往后走）。因此「下一个空号」**远不是**二百三十二，而是
**在途系列之后**的那个号：

> **写这份计划的过程中，HEAD 从 `e798ef7`（二百三十五/二百三十六）走到了 `f688094`（二百三十七），
> 即编号是活靶。下面的「建议号」写的是一个**快照**，落地前**必须重取** `git log` 与 `TODO.md` 再定。**

### 1.2 建议

- **建议占用的阶段号：快照下的「下一个空号」= 阶段二百三十八**（**待确认**）——因为写本节时 `git log`
  实测最高在途阶段已是 **二百三十七**（`f688094`），而 `TODO.md` 自身末位仍是二百三十一。**这正是本项
  标「待确认」的原因**：在途系列仍在推进，落地时必须**重取** `git log`/`TODO.md`、把在途系列补进
  `TODO.md` 后以当时的实际空号为准（若那时已到二百三十八/三十九…就顺延）。**不要把 238 当定值。**
- **建议版本号**：`package.json` 当前 `0.4.203`；U1 占的 patch = **在途系列全部归位后的下一个 patch**
  （U1 落地时以 `package.json` 实际值 `+1`，不预先写死）。

### 1.3 两种走法的得失（先占号 vs 先预检）

| 走法 | 做法 | 得 | 失 |
|---|---|---|---|
| **A. 先占号做 native（建议）** | 立刻占「下一个空号」，**只落 native 可验部分**（vendor Yoga + 接缝 + `usesAsaotUi` + 内建类 + 示例 + 单元组）；wasm/WASI 与 macOS 只接线、不宣判 | native 红利先到；接缝 API 与示例对后续 U2~U5 立刻可用；回退代价小（回退只丢引擎，见 §4） | 若 CI 预检红，这个阶段号与版本要**回退**（改动本身大多是**纯增量**的 `vendor/` + 一个示例，回退便宜） |
| **B. 先不占号，先跑 CI 预检** | 在一次性 PR/分支里只做 CI 阻塞项 ①/② 的探针（Yoga 编 wasip1、macOS `-dead_strip` 剪枝），绿了再占号 | 绝不会落一个需要回退的阶段 | 阻塞 U1 一个 CI 周期；而 native 那部分本来就可独立为绿 |

**建议 A**，但**把 §4 的 CI 预检当成「落地前必过门」**：先占号、先落 native，CI 预检若红则回退到 AS3 子集
（回退时接缝 API、示例、单元组**保留**，只换掉引擎实现）。

---

## §2 顺序与每步的 Go/No-Go

| 步 | 做什么 | Go/No-Go |
|---|---|---|
| **S0** | CI 预检（**待 CI 验**）：① `WASI_SDK_HOME` 就绪的 runner 上 `clang++ --target=wasm32-wasip1` 编 Yoga；② macOS arm64 上 `clang -ffunction-sections -fdata-sections … -Wl,-dead_strip` 下 `yoga_one < yoga_min` | 任一红 ⇒ 走 §4 回退（但在 A 走法下，S1~S3 的 native 部分**可先合**） |
| **S1** | vendor Yoga 源码 + 把原型接缝搬进 `vendor/` + `build.ts` 的 C++ 标准/DCE 旗标（§3 第 2~4 项） | 本机 native 能编出 `libyoga.a` + `yoga_glue.o`，且 `yoga_min` 增量 ≈ 92 KiB（对齐 precheck §3.2） |
| **S2** | `usesAsaotUi` 引用才链 + runtime 两态桩 + [`seam/`](seam/) 纯 AS3 接口/实现 + `emit.ts`/`symbols.ts` 发射并注册 `NativeLayoutEngine` 内建类（§3 第 5~8 项） | 一个**不用** `asaot.ui` 的示例，其 `sources`/`linkLibs` 里**不出现** Yoga（零增量门 A）；用一个手写 AS3 探针能拿到 Yoga 矩形 |
| **S3** | 示例 `examples/ui-layout.as` + `ui-layout.build.json` + 单元组 + 登记点（§3 第 9~11 项） | `as-aot examples/ui-layout.as --run` 退出码 0；`node --test --test-name-pattern='ui-layout' test/unit/*.ts` 绿 |
| **S4** | 收尾三件事（§5） | **全量 `node test.ts` 全绿** + README 同步 + 升版本 |

---

## §3 改动清单（file-by-file）

> 每条写清「**文件 / 改什么 / 为什么 / 怎么验**」。行号是写本文件时现读值。

### 3.1 `as3compiler/vendor/yoga/`（新，**源码入库**）

- **改什么**：把 Yoga 的 `yoga/` 子树（**595 KB / 12,634 行 / 19 个 `.cpp`**，含 `Yoga.h` 等 9 个公开头、
  `algorithm/`、`config/`、`debug/`、`event/`、`node/`）原样拷进 `vendor/yoga/`，附 `LICENSE`
  与一份 `vendor/yoga/README.md` 记 pin（commit `843dba86…`，晚于 `v3.2.1`；`yoga/YGEnums.h` 是
  **checked-in 的 `@generated`**，构建**不需要**再跑 `enums.py`）。**整棵 15 MB 仓库树不入库**。
- **为什么（对照先例，去实际看过）**：
  - `vendor/sqlite/` 是**完整源码**（`sqlite3.c` 9.8 MB）入库，靠 `.gitignore` 的 `!vendor/**/*.c` 兜住——
    「手写/第三方 C 源是**被跟踪的构建输入**」（`.gitignore:24-30`，`!vendor/**/*.c` 在 `:30`）。Yoga 是 C++ 源，规模仅 595 KB，
    同属这类。
  - `vendor/skia/`（326 MB：`lib/` 292 MB 预编译 + `include/` 3.9 MB）与 `lib/bin/<host>/asaot.*`
    是**预编译产物**：前者因为要装下预编译 archive 且极大（AGENTS.md §2.9：真正可编源码在
    `build-tools/skia-src`），后者是宿主 FRE 库，**必须**预编成 dll/dylib 才能被扩展加载。
  - **决定**：Yoga 走**源码入库 + 每次构建编译**（同 sqlite），不走预编译 archive。理由三条：
    ①Yoga 需要在**三个形状**下被编（native clang++、web emcc、WASI clang++），预编译就要为每端
    各备一份 archive 并维护 `vendor/provision/*`；源码入库则一次写入、到处编译。
    ②CI 阻塞项 ① 要编 wasip1，预编译 archive 反而更难保证一致。
    ③体积小，且这正是「fresh clone 必须能构建」的先例（`!vendor/**/*.c` 的动机）。
- **怎么验**：`git status` 里 `vendor/yoga/**` 全部 new 且**未被 ignore**（`.gitignore` 只 ignore
  `*.c`/`*.o`/`*.wasm`，不动 `.cpp`/`.h`）；`git check-ignore vendor/yoga/YGNode.cpp` 无输出。

### 3.2 `as3compiler/vendor/yoga_glue.h` + `as3compiler/vendor/yoga_glue.cc`（新）

- **改什么**：把 `asaotui/u1-prototype/yoga_glue.{h,cc}` **搬过来**（原型是权威版：**不透明 C 接缝**，
  节点= `void*` 句柄，**枚举值是我们自己冻结的、绝不等于 Yoga 的**，`<yoga/Yoga.h>` 只在 `.cc` 里 include）。
  原型已把接缝从 precheck §6.3 的「~20 个草案」扩到**实际 30 个函数**（`yoga_glue.cc` 里 30 个顶层
  定义；`yoga_glue.h` 的声明用多行排布，`grep -c` 会因换行重复计数而虚高到 41/37，**以 `.cc` 的
  顶层定义数为准**），并纠正了两处草案偏差（measure 回调是**写 `out_wh[2]`** 而非单 float 返回；`Fraction` 0..1→0..100
  的换算归 AS3 侧）。**以原型为准**。
- **为什么**：这是三条接缝里的 `LayoutEngine` 接缝，学 `rust-text-backend.md` §1.1 的「15 函数不透明接缝」
  先例（`skia_text_glue.cc` 只暴露 15 个 `sk_text_*`，**不暴露任何 SkParagraph 类型**）。`asaot.ui` 永远
  只认这 30 个函数，引擎将来可整体替换。**`vendor/yoga_glue.cc` 是唯一 include `<yoga/Yoga.h>` 的 TU。**
- **怎么验**：`grep -n "Yoga.h" as3compiler/vendor/yoga_glue.cc` 有命中，`vendor/yoga_glue.h` 里
  `grep -n "YGNode\|YGValue\|Yoga.h"` **零命中**（opacity 的红线）；原型 `u1-prototype/build.sh` 的
  native/wasm 两种构建可作对照基线。

### 3.3 `as3compiler/src/build.ts`（关键，三处）

> 这是本计划**最容易低估**的一处：`build.ts` 的 C++ 路径目前**三处**与 Yoga 不兼容。
> 全部是现读实测，不是推断。

- **(a) C++ 标准：`-std=c++17` → Yoga 需要 C++20。**
  - 位置：`src/build.ts:1353`（native `buildCompileSteps`）与 `src/build.ts:1593`（web `buildWebCompileSteps`）
    都把 C++ 源硬编成 `-std=c++17`。
  - **实测**：`clang++ -std=c++17 -c yoga-src/yoga/YGNode.cpp` **失败** —— Yoga 用了 `concept`
    与 `std::bit_width`（`yoga/yoga/enums/YogaEnums.h:20/32/39`），是 C++20 特性；Yoga 自己的
    `cmake/project-defaults.cmake:6` 就是 `set(CMAKE_CXX_STANDARD 20)`。
  - **改法（建议）**：把这两处的 `-std=c++17` 提到 **`-std=c++20`**。**本机已实测**`vendor/skia_glue.cc`
    在 `-std=c++20` 下编过（仅一条 `fopen` deprecation warning），说明「全局提到 c++20」对现有最大
    C++ TU 是安全的。若在 macOS/emcc 上发现别的 `.cc`/`.mm` 不吃 c++20（**待验**），退路是
    **按源选标准**（`vendor/yoga/**` 与 `vendor/yoga_glue.cc` 用 c++20，其余保持 c++17）——加一个
    `cppStdFor(path)` helper 即可，不要改语义。
- **(b) DCE 旗标：`-ffunction-sections -fdata-sections` 目前**根本没发**。**
  - 位置/依据：`src/build.ts:511` 的注释明说「`--gc-sections` 家族**刻意关闭**：它需要编译期
    `-ffunction-sections/-fdata-sections`（包括每个预编译 archive 内）才省一个字节，现在发它只会
    得到一个**看着能用、实则无效**的旗标」。
  - **实测（precheck §3.2）**：Yoga 上 `-ffunction-sections -fdata-sections` 值 **≈ 34 KiB**
    （`-O2`：177,152 → 142,336 B），**且它是 DCE 的前提**；COFF 侧真正生效的是编译期分节，
    `/OPT:REF` 在 `lld-link` 上默认就开（加不加逐字节相同）。
  - **改法（建议）**：给 **Yoga 的 TU（以及 `yoga_glue.cc`）**加上 `-ffunction-sections -fdata-sections`；
    是否全局加**待定**（Skia 预编译 archive 没带分节，全局加也剪不动 Skia，只会改变自有 TU 的产物，
    收益/风险要单独量）。这一步是「拿回 precheck 实测的 92 KiB 而不是更肥的产物」的关键。
- **(c) `--target wasm` + C++ 源：`build.ts` 直接 throw。**（= CI 阻塞项 ① 的真正机制）
  - 位置：`src/build.ts:1322`：`throw new Error('C++ sources with --target wasm are not yet supported (use native + a C++ toolchain)')`。
  - **含义**：`--package web`（走 `buildWebCompileSteps`，`src/build.ts:1556`）**支持** C++ 源
    （`:1586-1593` 逐个编 `.cpp`/`.cc`）；但**严格 `--target wasm --package raw`（WASI）走
    `buildCompileSteps`，遇到任何 C++ 源就 throw**。所以「Yoga 上 wasm」目前 = **web 能、WASI 不能**。
  - **改法**：U1 先只承诺 **native + `--package web`**；WASI 侧把 `:1322` 放宽（用 `clang++` +
    `WASI_SDK_HOME` 的 libc++ 编 C++，与 `buildCompileSteps` 已有的「C/C++ 分开编、C++ 驱动链接」
    结构一致）列为 **CI 阻塞项 ① 的一部分**（**待 CI 验**）。若 CI 的 `WASI_SDK_HOME` 带不齐 libc++，
    就按 §4 回退。

### 3.4 `as3compiler/src/index.ts`（引用才链）

- **改什么**：在 `usesFlashData`（`src/index.ts:377`）/`usesTextEngine`（`:398`）旁加一个 `usesAsaotUi(texts)`，
  并在 `usesFlashData` 的调用点（`:931`）旁加 `if (usesAsaotUi(featureScanTexts)) { … }`，push：
  - `cfg.sources.push(vendor/yoga_glue.cc, …19 个 vendor/yoga/**/*.cpp)`（若走「源码入库」）
    或 `cfg.linkPaths.push(vendor/yoga/lib/${host})` + `cfg.linkLibs.push(${lib:yoga})`（若走预编译 archive，**不推荐**，见 §3.1）；
  - `cfg.includePaths.push(vendor/yoga)`；
  - `cfg.defines.push('ASC_HAVE_LAYOUT=1')`（对标 `ASC_HAVE_SQLITE`/`ASC_HAVE_TEXT` 的两态接缝）。
- **「引用才链」的判定条件**（对 `usesFlashData` 的照抄，`src/index.ts:370-381`）：
  - **扫描对象**：`featureScanTexts`（`:567` 起，装的是程序 AS3 源码 + bootstrap，`:657`/`:687` push）。
  - **过包含、不静默错**：一个**正则**同时匹配「import/限定名」与「裸类名」——即
    `/asaot\.ui\.|(?:^|[^A-Za-z0-9_.$])(?:UiApp|View|Node|LayoutEngine|As3LayoutEngine|NativeLayoutEngine|Style|StyleRefinement|Observable|ActionRegistry|FocusChain|UiRoot)(?![A-Za-z0-9_])/`
    （bare 名覆盖 `getDefinitionByName("asaot.ui.LayoutEngine")`）。
    - 误报的代价只是「多链了 Yoga」（体积，§8 已量证零头级）；漏报的代价是**响亮**的：
      `ASC_HAVE_LAYOUT` 未定义时 runtime 桩会像 `as_text_engine_absent`（`src/runtime.ts:8990` 的
      一次性 stderr 告警；`ASC_HAVE_TEXT` 两态见 `:8968`/`:8971+`）那样**在 stderr 报一次**并抛显式错，绝不静默假装布局可用（AGENTS.md §1.5）。
  - **幂等**：若清单已显式列了 `yoga_glue.cc`/Yoga 源，`usesAsaotUi` 必须像 `skiaGlue` 检查
    （`src/index.ts:958` `cfg.sources.some((p) => nameOf(p) === 'skia_glue.cc')`）那样**先查再 push**，
    否则同一源会被编两遍（重复符号 / 重复编译）。
- **为什么**：这是门 A「不用 UI 的构建零增量」的唯一机制——对标 sqlite 的 `usesFlashData`（`:931` 只在
  触 `flash.data` 时 push `sqlite3.c`）与文本引擎的 `usesTextEngine`（`:962`）。**不用默认清单硬链 Yoga**
  和本项目对体积的一贯态度（`size-optimization.md`、`rust-text-backend.md` §2.3/§2.4）。
- **怎么验**：一个不含 `asaot.ui` 的示例（如 `examples/hello.as`）跑
  `node src/index.ts examples/hello.as --dry-run`（或看构建日志），断言 `sources` 里无 Yoga、链接行无
  `-lyoga`；单元组 §3.11 钉住这条。

### 3.5 `as3compiler/src/runtime.ts`（两态接缝 + 桩）

- **改什么**：
  - 在 extern 接缝区（对标 `src/runtime.ts:8788–8810` 的 15 个 `sk_text_*` extern）加 `as_ui_yg_*`
    的 `extern` 声明；
  - 加一层 inline 转发（对标 `:8968` 的 `#ifdef ASC_HAVE_TEXT` 真实现 `:8971+`）与
    `ASC_HAVE_LAYOUT` 未定义时的**全桩**（对标 `:8998+` 的「未链文本」全 0 桩，其 absent 告警
    助手在 `:8990–8993`），桩里对一个 `as_ui_layout_absent` 一次性 stderr 告警。
  - **`ASC_HAVE_LAYOUT` 与「源在不在构建里」必须同一处决定**（同 `rust-text-backend.md` §2.4 的
    `ASC_HAVE_TEXT` 教训），否则二者会互相撒谎。
- **为什么**：可读 C 的 `RUNTIME_PREAMBLE` 是所有运行时助手的集中地（AGENTS.md §2.9），平台耦合点也在此；
  两态接缝是既有的、被 CI 钉住的做法。
- **怎么验**：编一个不用 UI 的程序，`grep ASC_HAVE_LAYOUT` 生成的 C **零命中**相关真实现；用 UI 的程序里
  extern 真名可见。

### 3.6 `as3compiler/src/emit.ts`（发射 native 内建类）—— 答问：**独立块，不塞进 `as_render_object`**

- **改什么**：加一个**新的发射块** `emitUiLayoutClasses()`（名字仿 `emitShellClasses`/`emitSqlClasses`），
  在 `run()` 的发射序列里、紧邻 `emitShellClasses()`（`src/emit.ts:629`）/`emitSqlClasses()`（`:640`）
  的位置调用；发射 `asaot.ui.native.NativeLayoutEngine` **内建类**（`implements:['asaot_ui_LayoutEngine']`，
  引用用户 `.as` 接口 `asaot.ui.LayoutEngine`），其方法体逐个转发到 `as_ui_*` 运行时助手（§3.5）→ `as_ui_yg_*`（§3.2）。
- **为什么是独立块、而不是放进 `as_render_object`（`src/emit.ts:22251` 的定义）附近**：
  1. **职责不同**：布局是对 **retained 节点树**求解（不透明 `void*` 句柄 + 读回 rect），
     与「把 retained 显示树画到 canvas」是两趟（API 设计 §3.1：`paint` 只更新 backing `DisplayObject`，
     真正上屏仍走现有 `as_render_object`）。塞进 `as_render_object` 会让「布局」与「绘制」耦合。
  2. **发射序列的既有约定**：内建类都在 `emitShellClasses`/`emitSqlClasses` 段发射（`:629`/`:640`），
     且必须在 `emitMain`（`:643`，`-O2` 调用图的根）**之前**、在 `staticizeTopLevelFunctions`
     （`:644`）之前——`emit.ts:635-639` 的注释原话就是「Before emitMain because -O2's call graph starts
     there and an unreferenced wrapper has to be visible to it as dead」——`-O2` 才能把「没被用到的
     `LayoutEngine` 方法体」当死代码剪掉，这正是
     `size-optimization.md` §3 讲的全量上界。
  3. **唯一的触点**：布局只**写** backing 的 `x/y`/变换，**不新增绘制路径**；`as_render_object` 已按
     `DisplayObject` 的变换绘制，无需改它。
- **接缝形态（已改为 AS3 interface 层）**：`asaot.ui.LayoutEngine` 是一条**纯 `.as` 接口**（[`seam/`](seam/) 骨架），
  控件层只依赖接口；`NativeLayoutEngine` 只是它的**一个实现**，方法体调 `as_ui_*` 运行时助手（§3.5）→ `as_ui_yg_*`（§3.2）。
  **为什么 native 实现必须是内建类**：AS3 **目前没有 FFI**（`enhancements.md` E11「FFI：声明并直调宿主 C 函数」
  **未排期**），普通 `asaot.ui.*.as` 源**无法**调到 C 函数；而**接口本身是纯 `.as`**，于是整个库（含 AS3 布局子集）
  都能 `mxmlc` 编译、在 `adl` 上跑（双端对照杠杆）。**「接口是纯 `.as`，native 实现才是内建类」**这条来自用户决定；
  它依赖「**内建类 implements 用户 `.as` 接口**」这条编译器能力——**2026-10-22 已实测成立**（见 [`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md)），§4 的回退不再需要、仅备查。
- **怎么验**：编一个用 `asaot.ui.LayoutEngine` 的程序，生成 C 里看得到 `LayoutEngine_*` 方法体；
  `nm`/体积对照：不用 UI 的程序里这些方法应被 `-O2` 剪掉（static 化后不可达）。
- **待确认**：内建类在 `symbols.ts` 的注册形状（§3.7）与 §10 未决 10「measure 闭包形态」耦合，
  U1 的 measure 回调可先只做「固定尺寸 / 空桩」，把文本 intrinsic measure 留给 U2/U4。

### 3.7 `as3compiler/src/symbols.ts`（注册 native 内建类）

- **改什么**：把 `asaot.ui.native.NativeLayoutEngine` 作为**内建类**注册（`ClassInfo`，
  与 `NativeWindow` 一类的内建面同法，`src/symbols.ts:1783` 起的 `NativeWindow` 是现成先例），
  `implements:['asaot_ui_LayoutEngine']`——引用**用户 `.as` 接口** `asaot.ui.LayoutEngine` 的 classMap key
  （`qualifiedName('LayoutEngine','asaot.ui')`，`symbols.ts:363`；接口 vtable `emit.ts:3962` 与一致性检查
  `symbols.ts:7383` 都遍历含内建类的全表）。**仅当 `ASC_HAVE_LAYOUT`/程序引用 `asaot.ui` 时其体才有用**
  （体由 §3.6 发射，`-O2` 自行剪）。
- **为什么**：符号表是两遍结构（AGENTS.md §2.3）里 Pass 1 的产物；新 API 必须先在符号层可解析。
- **怎么验**：`node --test --test-name-pattern='ui-layout' test/unit/*.ts` 里钉「发射出的 C 含正确签名」。
- **待实测**：内建类 implements **用户**接口这条模式（先例只有内建接口 `implements:['IGraphicsData']`）。

### 3.8 `as3compiler/examples/ui-layout.as`（新）

- **改什么**：一棵**手算期望**的 flex 树（如 `column` + `gap` + `padding` + 一个 `row`，混合
  point/percent/auto），逐节点 `trace` 出 `left/top/width/height`，并与常量期望**逐项 assert**；
  任一不等即抛错（`test/examples.ts` 以退出码判 PASS，`runExample`，`test/examples.ts:353`）。
- **为什么**：AGENTS.md §2.7 要求「一个示例覆盖该阶段全部特性」；本示例就是 U1 的验收物。
  只跑布局、**不开窗口**（纯 offscreen，无 Skia/SDL 依赖），CI 稳。
- **怎么验**：`node src/index.ts examples/ui-layout.as [--manifest examples/ui-layout.build.json] --run` 退出码 0。

### 3.9 `as3compiler/examples/ui-layout.build.json`（新）

- **改什么**：最小 native 清单：`target`/`c-compiler`/`opt`/`architecture`；
  **Yoga 本身由 §3.4 的 `usesAsaotUi` 自动挂**（清单无需重复列，避免重复编译；若列，须靠 §3.4 的幂等检查）。
  对齐既有清单的 `${host}`/`${lib:}`/`${win:}` 词法（`build.ts:864`，stage 231）。
- **为什么**：示例套件对「需要清单的示例」用 `EXAMPLE_ARGS` 显式挂（见 §3.11）；
  也让示例成为「一份清单讲清 UI 构建」的可读样例（`compile.md` §4 直接引若干清单为文档标准例子）。
- **怎么验**：`test/unit/build.ts` 的 `build/ExampleManifestHosts`（在**当前宿主**展开每一份 native 清单、
  断言无 `${...}` 残留、每条 path 存在、每个 `-lNAME` 找得到归档）应覆盖它。

### 3.10 `as3compiler/test/unit/ui-layout.ts`（新）—— 钉在**发射出的 C** 上

- **改什么**：新增单元组，至少钉：
  1. **门 A**：一个不含 `asaot.ui` 的程序，其 `BuildConfig.sources` **不含** `yoga_glue.cc`/Yoga 源，
     `linkLibs` 不含 `yoga`（零增量门的结构不变量）；
  2. **引用才链**：含 `asaot.ui.LayoutEngine` 时，`sources`/`includePaths`/`defines` 里出现 Yoga 项与 `ASC_HAVE_LAYOUT`；
  3. **内层 C 接缝不透明**：`vendor/yoga_glue.h` 里不出现任何 `YG*` 类型（`grep` 级结构钉）；
  4. **两态一致**：`ASC_HAVE_LAYOUT` 未定义时 runtime 桩存在且**会响亮报明**（对标文本引擎的 absent 桩）；
  5. **两后端差分**：native 构建里同挂 `As3LayoutEngine` 与 `NativeLayoutEngine`，同一输入逐项比对一致（`EPS=0.01`）。
- **为什么**：AGENTS.md §2.7——负例与结构不变量**只能**钉在 `test/unit/`（examples 只跑必须成功的程序）；
  门 A 是硬门，必须被机器钉住而不是靠人记得。
- **怎么验**：`node --test --test-name-pattern='ui-layout' test/unit/*.ts`。

### 3.11 登记点（两处，别漏）

- **`as3compiler/test/unit.ts`（barrel）**：加一行 `import './unit/ui-layout.ts';`——**这是现存的硬约定**：
  `test/unit.ts` 顶部注释即「Barrel for the unit-check modules: importing this file registers every unit
  group with node:test」（`test/unit.ts:1-2`）。不注册的单元组**不会**被 `node test.ts` 跑到。
- **`as3compiler/test/examples.ts`**：在 `EXAMPLE_ARGS`（`test/examples.ts:170`，注释在 `:163-169`）里加
  `'ui-layout.as': ['--manifest', join(dir, 'ui-layout.build.json')]`。示例 `.as` 由 `readdirSync` **自动发现**
  （`:24`/`:377`/`:416`），所以**只需要**登记额外 CLI 参数、以及（若需要）`EXAMPLE_REQUIRES`。
  目录型示例的 `[no-src-litter]` 快照断言（`test/examples.ts:414`）只对子目录示例生效，U1 是顶层 `.as`，不涉及。

### 3.12 `as3compiler/README-CN.md` / `README.md`（收尾同步）

- **改什么**：「支持子集 / 类型映射」与版本号；若 U1 让 `asaot.ui` 成为可用的增强面，按 §1.5 如实登记
  （**默认不改变任何 `flash.*` 行为**；`asaot.ui` 是**新命名空间**，用即 opt-in）。
- **为什么**：AGENTS.md §2.7 收尾三件事之一（更 README）。
- **怎么验**：人工核对「新增面 + 版本」两条。

### 3.13 `as3compiler/TODO.md`（仅真正实施时）

- **改什么**：在 `### 遗留待开发`（`:13824`）**之前**追加 `### 阶段二百三十八：…`（**号见 §1.2，落地前重取**），
  并同步把 `:14086` 的「UI 工具链待定项」里 U1 行从「卡在哪=前置测量未做」改为「已测 Go（条件）」。
- **为什么**：AGENTS.md §2.7 阶段推进 + TODO 备注「新阶段节追加到 `### 遗留待开发` 之前」的硬约束。
- **注意**：本文件与本次**都不改** `TODO.md`（不属于交付物范围，且 `as3compiler/` 只读）。

---

## §4 回退路径（CI 阻塞项 ①/② 变红时）

**不静默降级**（AGENTS.md §1.5）：回退是**显式**决定，且按 precheck §6.4 登记穷尽的子集边界。

| 红的项 | 触发 | 退到 | 边界依据 |
|---|---|---|---|
| **① wasip1** | CI 上 `clang++ --target=wasm32-wasip1` 编/链 Yoga 失败（缺 libc++ 头/库、`build.ts:1322` 放宽后仍编不过） | **AS3 侧 flexbox 子集**（`--package web` 仍可保留 Yoga，若只 WASI 红，可让 U1 声明「WASI 不链 Yoga、走子集」） | precheck §5.2 / §6.4 |
| **② macOS `-dead_strip`** | macOS arm64 上未引用的 Yoga **剪不掉**（`yoga_one` 与 `yoga_min` 体积接近）⇒ 违反硬门 A「不用 UI 零增量」 | **AS3 侧 flexbox 子集**（因为没有别的机制能恢复 macOS 的零增量；预编译 archive + `-dead_strip` 也是同一个问题） | precheck §4.2 / §6.4 |

**AS3 子集边界（照抄 precheck §6.4，回退时如实写进 README 与 `遗留待开发`/`增强待做` 判定）**：

- **支持**：`flex-direction`（row/column ± reverse）；`flex-wrap`（nowrap/wrap）；`gap`；`padding`/`margin`
  （per-edge + horizontal/vertical/all）；`align-items`/`align-self`/`align-content`；
  `justify-content`；`width/height/min/max` 三态（undefined / 点数 / 百分比一层）；
  `flex-grow/shrink/basis`（含 `auto`）；`position: absolute/relative`；`display: none`。
- **不支持（须响亮报明）**：`grid`；`baseline` 对齐；**嵌套百分比**；`aspect-ratio`；`box-sizing`；
  `max-content`/`fit-content`/`stretch` 关键词；measure 回调下的 min-content 两趟；
  `position: static` 的完整语义；所有 RTL/书写方向细节。

**回退时哪些改动可以保留**：

| 保留 | 理由 |
|---|---|
| `vendor/yoga_glue.h`（仅作**内层接缝契约文档**/或改名为 `layout_seam.h`） | 不透明接缝的**接口形状**对实现无关；AS3 子集也照这个函数面实现 |
| `asaot.ui.LayoutEngine`（纯 `.as` 接口）+ `emit.ts`/`symbols.ts` 的 `NativeLayoutEngine` 内建类 + §3.8 示例 + §3.10 单元组 | 它们钉的是 **AS3 API 与矩形语义**，与后端是 Yoga 还是 AS3 子集无关；示例改跑子集即可；**接口保留 ⇒ 整库仍能 `mxmlc`→`adl`** |
| §3.4 的 `usesAsaotUi` 门（无 Yoga 链接项可挂） | 门 A 仍需要（子集实现也只在引用 `asaot.ui` 时编入） |
| **丢弃**：`vendor/yoga/`、`vendor/yoga_glue.cc`、§3.3 的 `build.ts` 三处改动、§3.5 的 Yoga extern | 引擎换掉后不再需要 |

---

## §5 收尾三件事（AGENTS.md §2.7）

1. **全量回归**：`node test.ts`（= `npm test`），必须**全绿**；红了回局部定位、修完再全量。
   开发期只跑局部（`node --test --test-name-pattern='ui-layout' test/unit/*.ts`、
   `node --test --test-name-pattern='ui-layout' test/examples.ts`）。
2. **更新 README**：`as3compiler/README-CN.md` + `README.md`（支持面 + 版本），以及工作区
   `asaotui/README.md` 的目录表（把 `u1-implementation-plan.md` / `u1-scope.md` / `u1-prototype/` 登记进去）。
3. **升版本**：按 §1.2，以落地时 `package.json` 实际值 `+1` patch（一个阶段一个小版本号）。

---

## §6 风险与本计划新增的发现（除主文档 §8 已有项）

| 风险 | 形态 | 护栏 |
|---|---|---|
| **`build.ts` 的 C++ 标准（§3.3a）** | Yoga 需 C++20，`build.ts:1353`/`:1593` 硬编 c++17 ⇒ **不提到 c++20，Yoga 根本编不过**。precheck 的本机测量是用自带 `em++/clang++ -std=c++20` 绕过了 `build.ts`，所以这个坑**不在 precheck 数字里** | 提到 c++20（本机已验 `skia_glue.cc` 接受 c++20）；macOS/emcc 侧**待验**，退路按源选标准 |
| **`--target wasm` 拒 C++（§3.3c）** | `build.ts:1322` 对 C+++wasm 直接 throw ⇒ 严格 WASI 上 Yoga **今天不可能**进构建，与有无 sysroot 无关 | U1 只承诺 native + `--package web`；WASI 放宽列为 CI 阻塞项 ① |
| **DCE 旗标（§3.3b）** | `build.ts` 刻意不发 `-ffunction-sections -fdata-sections`（`:511` 注释）；不给 Yoga 加，`/OPT:REF`/`-dead_strip` 就剪不动 TU 内未引用函数，实测会**丢掉 ≈34 KiB 的收益** | 给 Yoga TU 加该旗标（是否全局待量） |
| **`__EMSCRIPTEN__` 下 `used`** | 主文档 §8 已加行；web 路径 DCE 弱于 native | 接受已计入的 120 KiB，或粘合层抑制 `used`（**待验**是否可行） |
| **重复编译（幂等）** | 若清单与 `usesAsaotUi` 都列 Yoga 源 ⇒ 同源编两遍 | §3.4 的「先查再 push」（仿 `skiaGlue` 检查 `index.ts:958`） |
| **AS3 无 FFI / 内建类 implements 用户接口（§3.6/§3.7）** | ① 纯 `.as` 源调不到 C 函数（`enhancements.md` E11 未排期）⇒ native 实现必须是内建类；② 「内建类 implements **用户** `.as` 接口」**2026-10-22 已实测成立** | 接口是纯 `.as`、native 实现是内建类；②已验（见 [`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md)）；§4 回退仅备查，**不静默** |
| **单元组不注册** | 新单元组不写进 `test/unit.ts` barrel 就**不会被跑到**（`test/unit.ts:1-2`） | §3.11 明确登记 |

---

## §7 待确认 / 未决

1. **阶段号**：本文件写作期间在途系列从 232 一路走到 237（HEAD 由 `e798ef7` → `f688094`），故这里的
   「238」只是**快照**。落地前必须**重取** `git log`/`TODO.md`，把在途系列补进 `TODO.md` 后再定实际空号（§1.2）。
2. **`-std=c++20` 全局化** 在 macOS/emcc 上是否对现有 `.cc`/`.mm`/Skia 头无副作用——**待验**
   （本机只验了 `vendor/skia_glue.cc`）。
3. **`-ffunction-sections -fdata-sections` 全局 vs 仅 Yoga**：全局会不会改变现有产物体积/objects 布局——**待量**。
4. ~~内建类 implements 用户 `.as` 接口这条模式未实测（native 路径前提）~~ —— **2026-10-22 已实测成立**
   （见 [`reviews/probe-builtin-implements-user-iface-2026-10-22.md`](reviews/probe-builtin-implements-user-iface-2026-10-22.md)）。
   其余待确认：`symbols.ts` 的注册形状与 API 设计 §10 未决 10（measure 闭包形态）耦合；
   U1 的 measure 回调先做固定/空桩，文本 intrinsic measure 归 U2/U4。
5. **WASI 侧 `buildCompileSteps` 放宽 C++** 的具体实现（libc++/`crt1.o` 从 `WASI_SDK_HOME` 哪里来）
   ——**待 CI 验**。
6. `u1-prototype/check-layout.md`（原型 header 引用了它）在写本文件时**尚未出现**；原型细节以
   `u1-prototype/yoga_glue.{h,cc}` 与 `test_layout.c` 的现读为准。

---

## §8 参考（本文件引用到的位置）

- **前置测量**：[`measurements/u1-yoga-precheck.md`](measurements/u1-yoga-precheck.md)
  （结论 §0、体积 §3.2/§3.3、DCE §4、wasm §5、预算门槛 §6.1、Go/No-Go §6.2、接缝草案 §6.3、回退边界 §6.4、修正假设 §7、未测清单 §8）。
- **原型（只读）**：[`u1-prototype/`](u1-prototype/)（`yoga_glue.h` 契约、`yoga_glue.cc` 30 个 seam 函数、`test_layout.c` 验收、`build.sh` 两种构建）。
- **主文档/设计**：[`ui-toolkit-feasibility.md`](ui-toolkit-feasibility.md) §6/§7/§8；[`ui-toolkit-api-design.md`](ui-toolkit-api-design.md) §0.3/§3/§9/§10。
- **`as3compiler/`（只读）**：
  - `src/index.ts`：`usesFlashData` `:377`（注释 `:370-376`）、`usesTextEngine` `:398`、`featureScanTexts` `:567`、
    调用点 `:931`/`:962`、`skiaGlue` 幂等检查 `:958`、sqlite push `:933`。
  - `src/build.ts`：`isCppSource` `:1222`、`cxxCompiler` `:1229`、C+++wasm throw `:1322`、
    `-std=c++17`（native `:1353` / web `:1593`）、`-ffunction-sections` 刻意关闭注释 `:511`、
    `linkTrimFlags` `:516`、`ManifestFields` `:189`（`sources` `:61`/`include-paths` `:74`/`link-libs` `:75`/`link-paths` `:76`/`objects` `:92`）、
    `${host}`/`${lib:}` 词法 `:864`、`hostVendorKey` `:890`、objects 链接位 `:1168`/`:1372`、
    `buildWebCompileSteps` `:1556`。
  - `src/emit.ts`：`run()` 序列 `:611-645`（`emitClassRegistry` `:626`、`emitShellClasses` `:629`、`emitSqlClasses` `:640`、
    `emitMain` `:643`、`staticizeTopLevelFunctions` `:644`）、`as_render_object` 定义 `:22251`、`as_render_object_content` 定义 `:22493`、
    `DisplayObjectContainer_addChild` `:10607`。
  - `src/runtime.ts`：`sk_text_*` extern `:8788–8810`、两态 `#ifdef ASC_HAVE_TEXT` `:8968`/真实现 `:8971+`、
    absent 告警 `:8990–8993`、未链文本全桩 `:8998+`。
  - `src/symbols.ts`：`NativeWindow` 内建面先例 `:1783` 起（`classMap.set` 注册工法）。
  - `test/unit.ts`（barrel，`:1-2`）、`test/examples.ts`（`EXAMPLE_ARGS` `:170`、注册 `:171+`、自动发现 `:377`/`:416`、`runExample` `:353`、`[no-src-litter]` 断言 `:414`）、
    `test/unit/build.ts`（`build/ExampleManifestHosts` 清单钉，`:2844`）。
  - `docs/zh-cn/size-optimization.md`（static 化与 `-O2` tree-shake）、
    `docs/zh-cn/rust-text-backend.md`（§1.1 15 函数接缝、§2.3 `usesTextEngine`、§2.4 `ASC_HAVE_TEXT` 两态）、
    `docs/zh-cn/compile.md`（清单字段）、`docs/zh-cn/enhancements.md`（§1.4 `--features`、E11 FFI 未排期）。
  - `TODO.md`（阶段二百三十一 `:13774`、`### 遗留待开发` `:13824`、`### UI 工具链待定项` `:14086`）、
    `package.json:3`（`0.4.203`）、`.gitignore:24-30`（`!vendor/**/*.c` 在 `:30`）。
