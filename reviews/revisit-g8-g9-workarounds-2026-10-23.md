# G8 / G9 绕行复核：底层修好之后，当初「为了通过」的决定能不能撤？

> **⚠️ 后续状态（2026-10-23 同日）**：本文件写于 **G14 尚未修复**时，所以里面对
> 「style 层 `fromAny`/`fromArray` 拆分」的判定**已经过时**——G14 已由编译器
> **阶段二百五十三**修好，style 层那套拆分**已经回退**。
> **本文件按当时事实保留，不追改**；现行结论看
> [`revisit-g14-unlocks-2026-10-23.md`](revisit-g14-unlocks-2026-10-23.md)。两处差异：
> ① 下文 §1.3 与「不做」表里的 **H（合并 `fromAny`/`fromArray`，当时判「不能合并」）→ 已推翻并执行**；
> ② **10 处 `*` 的结论不变**，但理由从「装箱成本 + G14」收窄为「装箱成本」（`*` 仍是更便宜的正确答案）。

**2026-10-23** · 编译器 HEAD `a035645` / v0.4.216（含阶段二四七 G8 命名 / 二四八 G9 `Boolean` 解箱 / 二四九 G13 / 二五零 / 二五一 / 二五二）· AIR SDK 51.4.1
> 复核期间编译器又前进了一版（`c29ac62` → `a035645`，阶段二五二改构建清单未知键硬报错，与 G8/G9/G14 无关）。本工作区工作树常被并发会话改写 ⇒ 所有断言收尾时当场重测。
触发：用户指出「编译器问题已修复很多，重点看 G8、G9 —— 我们能不能优化/回退当初为了通过做的决定」，并要求说明 `Vector` 相对 `Array` 的性能。

---

## 0 结论先行

| # | 当初「为了通过」的动作 | 底层今天 | 能不能撤 | 处置 |
|---|---|---|---|---|
| **G8-a** | 设计文档写 `bind(owner, field)`，发出去的 API 改叫 **`bindTo`**（`bind` 撞 POSIX socket `bind(2)`，报 `conflicting types for 'bind'`） | **已修**（阶段二四七：保留名表机器生成，文件作用域改 `__` 后缀；`probes/name-collision/` 现在 **4 → 0 errors**） | **技术上能**（现在写 `bind` 编得过） | **不撤，但理由换了** —— 不再是「被逼的」，而是主动选择：不把公开 API 名押在 C 名剪辑上（机制一回归，错误文案会指向 socket），且 `bindTo` 读起来就是动词短语。`bindTo.as` 顶部注释已从「compiler limitation」改写 |
| **G8-b** | 探针里刻意回避 `stat` / `_time` 一类 libc 名做成员名 | 已修 | 技术上能 | **保留**。那不是绕行而是**测试数据**：保留它们才持续覆盖保留名表；上一条「修完了就把用例删掉」会让这条机制失去回归 |
| **G9** | **10 处**绑定读取声明成 `*` 而不是 `Object`（**6 处 `Boolean` 型 + 4 处 `Number` 型**） | **已修**（阶段二四八：`Boolean(<Object 槽>)` 不再做指针测试） | **技术上能且语义正确** | **不撤**。撤了会：① 每次读多一次**装箱**（`as_value_to_obj`，一次 GC 分配）；② 把值暴露在 **G14** 的 Array 身份毁灭面前。⇒ `*` 已从「绕过 bug」升格为**正确默认**。10 处注释已从「G9 是活缺陷」改成「为什么该用 `*`」 |
| **（新）G14** | —— | **未修**（本轮实测登记） | —— | `Array` 落进 `Object` 槽**不装箱** ⇒ `is Array` 恒假、`as Array` 得 `null`、`.length` 得 `undefined`、**`is <用户类>` 直接 `0xC0000005`**。见 §1.3 |

**一句话**：G8 与 G9 的「撤」在两处都**技术可行**，但**两处都不该撤** —— G8 撤了没有收益只有风险（把一个刚修好的机制重新变成 API 名的前置条件），G9 撤了是**净退化**（多一次装箱 + 重新暴露在 G14 下）。真正需要动作的不是这两条，而是本轮**新发现**的 G14（它让 style 层里那句看起来像防线的守卫变成了死代码）。

---

## 1 逐项复核

### 1.1 G8 —— 符号名逐字进 C（保留名冲突）

**当初的动作**（`compiler-gaps.md` G8 条目）：设计文档的 `bind(owner, field)` 在 AOT 下编不过。
生成的 C 里包级自由函数名**逐字**出现，于是：

```c
static Binding asaot_ui_bind(...);          // 我们想要的
int bind(int, const struct sockaddr*, ...); // 系统头文件里的
// -> error: conflicting types for 'bind'
```

⇒ 改名 `bindTo`，并写下了「这条是被逼的，不要再改回去」。

**今天的实测**：阶段二四七把保留名表改成**机器生成**（`c-reserved.gen.ts`）、文件作用域改用 `__` 后缀。`probes/name-collision/` 的 `NamesMain.as`（`p.div` / `p.free` / `p.stat` / `p.time` / `p.open` / `p.close` / `p.read` / `p.exit`）现在 **4 → 0 errors**。

**判定：不撤。** 三条理由，都不是「麻烦」：

1. **撤了唯一收益是「公开名与设计文档一致」**。`bindTo` 已经进了 18 条贡献者契约、demo、`STATUS.md`，改名要动一片调用点，收益是零。
2. **撤了就把公开 API 名重新押在一个刚修好的机制上**。今天它靠「机器生成的保留名表 + `__` 后缀」才编得过；一旦回归，症状是 `conflicting types for 'bind'` —— 一条会把读者**引向 socket**的报错。不值。
3. `bindTo` 本身更可读（“bind to X”）。

**动作**：把 `kit/asaot/ui/bindTo.as` 顶部注释从「compiler limitation」改写为「命名选择 + 原因」。**这一步必须做** —— 留着原文就是让文档撒谎（`compiler-gaps.md` G8 行、`CONTRIBUTING-widget.md` §4 第 5 条同步）。

> **附带收获（反向利用）**：G8 修好之后，**不要**把 `NamesMain.as` 的保留名用例删掉。它们是**持续覆盖**那条机器生成表的唯一钉子；删了就等于「修完即失去回归」。这一条反过来也是给 G9 的答案：`tools/find-bound-truthy.cjs` 同样保留（见 1.2）。

### 1.2 G9 —— `Boolean(<Object 槽>)` 被降级成指针测试

**当初的动作**：`var x:Object = binding.get(); Boolean(x)` 里，一个**装箱的 `false`**（`as_value_to_obj` 产出的非空 `Object*`）被当成 **真**。绑定路径恰好就是这个形状，于是 **10 处**绑定读取改声明 `*`：

| 用途 | 位置 |
|---|---|
| `Boolean` 型（**真受害**，6 处） | `checkbox.as:17`、`radio.as:22`、`toggle.as:25`、`kind/CheckboxWidget.as:49`、`kind/RadioWidget.as:61`、`kind/SwitchWidget.as:54` |
| `Number` 型（**从来不受影响**，4 处） | `list.as:35`、`tabs.as:29`、`kind/ListWidget.as:59`、`kind/TabsWidget.as:108` |

> **计数更正**：此前 `compiler-gaps.md` G9 行写「共 6 处」，只数了 `Boolean` 型。实际 `:*` 本地变量共 **13** 个，其中 **10** 个是 `binding.get()` 读取（另 3 个与 G9 无关：`anim/Anim.as` 两个原始值、`kind/ListWidget.as` 的命中标记）。已更正。那 4 处 `Number` 型当时是**为口径一致**一起改的 —— G9 只污染 `Boolean()` 一个降级入口。

**今天的实测**：阶段二四八修了「`Boolean` 对 `Object` 槽做指针测试」。`Boolean(x:Object)` 现在正确。

**判定：不撤 —— 而且撤了是净退化。** 两条独立理由：

1. **省一次装箱**：`var x:Object = binding.get()` 会把读出来的标量经 `as_value_to_obj` 装成 `Object*` 包装体，**每次读一次 GC 分配**；`*` 不装。绑定每帧都在读（`arrange` 里），这条是真的落在热路径上。
2. **躲开 G14**（本轮新发现）：**一个 `Array` 落进 `Object` 槽会丢身份，其中 `is <用户类>` 会直接段错误**。而「绑定值」的静态类型恰恰是「可以是任何东西」。⇒ `*` 不是绕行，是**正确的默认类型**。

**处置**：10 处注释全部改写（原文写「see compiler-gaps.md G9 -- Boolean(x) with x declared `Object` lowers to a pointer test, so a bound FALSE would read as true」，读起来像活的缺陷）。新注释说清三件事：`*` 因为**装箱成本**与 **G14**；G9 的降级已修；`Number` 那 4 处本来就没被 G9 咬到。

**同时确认静态钉子是对的**：[`tools/find-bound-truthy.cjs`](../../tools/find-bound-truthy.cjs) 报 `91 files, 34 Object-typed locals, 0 risky use(s)` —— 34 个 `:Object` 本地变量里没有一个当条件用，说明这 10 处没有漏网的同类。**这道门此前形同虚设**（见 §3 D），本轮已修。

### 1.3 G14（新）—— `Array` 落进 `Object` 槽不装箱

复核 G9 时顺手问编译器一个相邻问题：「`Object` 槽会丢身份，那丢到什么程度？」——得到的答案比 G9 更严重，而且**它正是 style 层那套 `fromAny`/`fromArray` 拆分看起来像绕行的原因**。

一条命令：`node probes/obj-array-identity/run.cjs`（26 条用例 × 两个 runtime）。实测：**AIR 26/26 与手写 AS3 规则一致；我们的 AOT 有 8 条偏离，其中 5 条是进程崩溃**。

来自生成的 C（不是推测）：

```c
// var o:Object = [1,2,3];
o = (Object*)(as_array_make(...));   // 裸数组指针进 Object 槽 —— 没装箱
if (false) { ... }                   // o is Array     -> 常量折成 FALSE
as_is(o, &Marker_vt)                 // o is Marker    -> 把数组头当 vtable 读 => 0xC0000005
as_v_obj_val(o)                      // o as Array     -> NULL（tag 不是 4）
as_dyn_get(o, "length", 0)           // o.length       -> undefined
as_str_from_bool(false)              // 而 typeof o    -> "object"（对的！）
```

**对照组说明缺口专属 `Array`**：`Number`/`String`/`Boolean` 进 `Object` 槽会被装箱（`as_number_new`/`as_string_new`/`as_boolean_new`），**全部正确**；真类实例全部正确；`Array` **直声明**也全部正确。⇒ 缺口是「**Array 没有被装箱**」这一个决定，不是「Object 槽普遍丢身份」。

**对库的直接后果**（这条才是要害）：

- style 层的 `Size.fromAny(o:Object)` / `fromArray(a:Array)` 这类**拆分是承重的，不能合并** —— `fromAny` 第一句就是 `o is Length` / `o is Fill`（用户类），正是会崩的形式。
- 但 `Fill.fromAny` 里那句 `if (o is Array) return null;` 被编译成 **`if (false)`，是死代码** —— 它读起来像防线，实际一句都没挡到。
- 更关键：`StyleRefinement.as:77` 的 `Fill.fromAny(o.background)` 是 style 层**唯一**没有 `is Array` 分流就转发进 `fromAny` 的调用点（`size`/`padding`/`margin`/`inset`/`border`/`cornerRadii` 都有）。⇒ **`background: [...]`（数组）会崩**。本仓库自己的 demo / 主题全传数字色值，所以**当前不可达**，属**潜伏**缺陷。

**处置**：登记为 G14（`compiler-gaps.md`），加为第 9 道门（26 条 × 两臂，偏离集必须**恰好等于**登记的 8 条；新增/消失/少跑都红），变异 **4/4**。**改不改库内那两处，见 §4 —— 需要你拍板**（属行为取舍，不是纯文档）。

---

## 2 `Vector.<T>` vs `Array`（实测，两个 runtime）

一条命令：`node probes/vec-vs-arr/run.cjs`。**同一份 `BenchCore.as`**（同 N、同循环、同 `getTimer`）编两次 —— 一次我们的 AOT、一次 `mxmlc`→`adl`。差值是**运行时**差值。

`N = 1,000,000`，best of 5，ms（两次独立运行一致到 ±1~3 ms）：

| 基准 | 我们的 AOT | AIR 51.4.1 (`adl`) |
|---|---|---|
| `Array` fill+sum（`push` + 下标读） | 11 | 36 |
| `Vector.<int>` fill+sum | **2** | 33 |
| `Vector.<Number>` fill+sum | **2** | 41 |
| `Array` prealloc（`a.length=N` + 下标写） | 5 | 20 |
| `Vector.<int>` prealloc（`new Vector.<int>(N)` + 下标写） | **1** | **3** |

**比值：AOT `Vector.<int>`/`Array` = 0.18x，`Vector.<Number>`/`Array` = 0.18x；AIR 同两项 = 0.92x / 1.14x。**

**机制（读生成的 C，不是推测）**：`Vector.<int>` 被**单态化**成 `typedef struct { void (*mark)(void*); int* data; int length; int capacity; bool fixed; } as_vector_int` —— 元素是裸 `int*`，`as_vector_int_push(v, i)` 收裸 `int`，`as_vector_int_get(v, k)` 返回裸 `int`。`Array` 是 `as_array`：一格一个**装箱** `as_value`（16 字节带 tag），`as_array_push(a, as_v_num(i))` 每格造一次 tag，`as_v_to_number(as_array_get(a,k))` 每格拆一次 tag。

⇒ 快的**不是「Vector 是魔法」，是「不装箱」**。

**AIR 为什么几乎没差、以及唯一有意思的那一行**：AVM2 的 JIT 已为 `Array` 做了内联缓存/整数特化，两者同量级（33~41 ms）。但 **prealloc 行**：AIR 的 `Vector.<int>` 用 `new Vector.<int>(N)` + 下标写只要 **3 ms**（它自己的 `Array` 20 ms，**6.7x**），而 `new Vector.<int>()` + `push` 要 33 ms。⇒ **AIR 上 Vector 的收益全在「避开 push/增长」**，我们这边两条路径都快（增长已摊销）。

**实用规则**（全文见 [`CONTRIBUTING-widget.md` §4c](../../CONTRIBUTING-widget.md)）：持久容器优先 `Vector.<T>`、元素类型越窄越好；长度已知就 `new Vector.<int>(n)` 预分配；`Array` 留给异质/动态/稀疏数据；**不要为了这条去重写现有的小 `Array` 用法** —— 5~6x 是**百万格**才显形的效应，布局/样式层是几十项的规模。`getTimer` 分辨率 1 ms，所以 ≤3 ms 的格子只取数量级意义，门也只钉 **≤0.5x**。

**有一条差点把自己的结论证伪的插曲值得记下**：mutation 跑完后磁盘上的 `bench-aot.exe.c` 是**被变异的**产物，读它会让 `Vector.<int>` 看起来落成了 `as_array` —— 那正好**证伪**「单态化」这个机制。数字没错，文件是陈的。⇒ **读生成物之前先重建**（这也是那道门坚持重建、不复用产物的原因）。

---

## 3 可改动点清单

### 已改（本轮，均为文档/仪器，无行为变更）

| # | 改动 | 值不值的依据 |
|---|---|---|
| **A** | `bindTo.as` 顶部注释：`compiler limitation` → 命名选择 + 原因 | 原文让文档撒谎（G8 已修） |
| **B** | 10 处 `:*` 绑定读取注释：`G9 是活缺陷` → 为什么该用 `*`（装箱 + G14） | 同上；10 处都写了「bound FALSE 会读成 true」，那是过去式 |
| **C** | `compiler-gaps.md`：G9 行「6 处」→ **10 处**（分类列出）；新增 **G14** 条目；G8 行改为「已修 + 不回退的理由」 | 计数错误会让后来者找错地方 |
| **D** | **修了一道假门**（`tools/gates.cjs` 第 7 道）：它数的是字符串 `Boolean-CALL`，而工具**从来没打印过**这个串 ⇒ `bad` 恒空 ⇒ **这道门无论 kit 里有什么都不可能变红**。改为消费工具的**退出码**（+ 打印的 `G9-RISK` 作为第二信号）；变异 `tools/mutation-bound-truthy.cjs` **4/4**（在 `kit/` 植一个 `:Object` 条件用法 → 工具 exit 1） | 一道**不可能失败**的钉子等于没有钉子，而且比没有更坏：它对外宣称「已看住」 |
| **E** | 新增两道门（`tools/gates.cjs` 第 9/10 道）：**G14 身份矩阵**（26 条 × 两臂）、**Vector vs Array**（两臂 + `≤0.5x` 声明）。各自配变异（**4/4**、**2/2**，逐字节还原并哈希核对） | 「记下来」若没有牙，下一次编译器改动会静默带走这个结论 |

### 不建议改（复核后否决）

| # | 候选 | 否决依据 |
|---|---|---|
| **F** | `bindTo` → `bind` | 撤了唯一收益是与设计文档同名；代价是把公开 API 名重新押在 C 名剪辑上（回归症状指向 socket）+ 动一片调用点。见 §1.1 |
| **G** | 10 处 `*` → `Object` | 净退化：多一次装箱/读，且重新暴露在 G14 下。见 §1.2 |
| **H** | 合并 style 层 `fromAny`/`fromArray` | **不能合并**：`fromAny` 开头的 `o is <用户类>` 正是 G14 会崩的形式。拆分是承重的安全设计 |
| **I** | 现有 `Array` 用法改 `Vector.<T>` | 规模不匹配：收益是百万格量级，库内是几十项；改动面大而收益不可观测 |

### 待你拍板（行为取舍）

| # | 候选 | 两个选项 |
|---|---|---|
| **J** | `Fill.fromAny` 里那句死守卫 `if (o is Array) return null;` | 删掉（承认它不工作）／留着并注明「被常量折叠，不构成防线」 |
| **K** | `StyleRefinement.as:77` 的 `Fill.fromAny(o.background)` —— style 层唯一没做 `is Array` 分流的调用点，`background: [...]` 会崩 | 补一个 `is Array` 分支（与 `size`/`padding` 等一致）／只登记不改（当前不可达） |

---

## 4 验证

- **编译器零改动**：`node tools/compiler-fingerprint.cjs` —— 快照 `6121b30`（3 文件）→ 现在 `a035645`（**0 modified/untracked + 353 deleted/renamed**）。那 353 项全在 `examples/air-native/src/com/**`（并发会话的未提交删除，被快照记为「已不在磁盘上」而无法哈希），**没有一项是本工作区工具会写的文件**。本轮与编译器的交互只有**读**：源码文本、`git log/status`，以及把生成的 C 当**产物**读（`probes/*/` 下）。
- **门**：`node tools/gates.cjs` → **18/18 PASS**，exit 0（落盘 [`reviews/gates-all-9.txt`](gates-all-9.txt)）。
  两道新门的具体读数：
  - `G14 array-in-Object-slot identity (26 cases, AOT vs AIR) -- deviations 1, 3, 12, 15, 16, 19, 21, 26`
  - `Vector vs Array throughput, both runtimes (AOT ratio 0.18x)`
  - 另外两道被改动/修复的门也当场复核：`style scan: no Object-typed local is used as a condition (0 found)`、`G11 determinism … (1/5 hashes)` —— G11 那道门**在本次跑中没给 `[SKIP]`**，说明测量的那段时间里编译器 `src/` 内容未变动。
  控件探针同一轮全绿（`chip 19 / form 41 / display 48 / nav 41 / anim 14`，0 failures），确认那 7 处注释改动**没有改变任何行为**。
- 探针各自的变异：`probes/obj-array-identity/mutation.cjs` **4/4**、`probes/vec-vs-arr/mutation.cjs` **2/2**、`tools/mutation-bound-truthy.cjs` **4/4**，全部 `finally` 逐字节还原 + 哈希核对。

> **一处必须记下的时效风险**：写这份文档期间编译器 HEAD 从 `c29ac62` 走到 `a035645`（并发会话又提交了一版）。
> 上述 18/18 与本页所有数字都是 **`a035645` 上当场重测**的结果，不是从草稿里抄的。

## 5 未做 / 做不到

- **G14 没有修**（属编译器侧，本工作区不动 `as3compiler/src/`）。只登记 + 加门看住。
- **没有把 G14 的偏离集当「可接受行为」**：它是**遗留欠账**（AIR 能做对而我们做不出）。门报绿只表示「偏离集没变」，不表示「行为正确」；门的文案与 `compiler-gaps.md` 都写明了这一点。
- `Vector` 基准的 ≤3 ms 格子受 `getTimer` 1 ms 分辨率限制，只取数量级；没有做微秒级计时（那需要改运行时，越界）。
- §3 的 **J / K** 未动，等决策。
