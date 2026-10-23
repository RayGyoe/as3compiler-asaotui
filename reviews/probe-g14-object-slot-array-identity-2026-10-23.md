# 探针：`Array` 落进 `Object` 槽会不会丢身份？（G14 实测）

> **✅ 后续状态**：G14 已由编译器 **阶段二百五十三**（`54bda6d`, v0.4.217）修好，
> 26 格矩阵现为 **`deviations none`**（本文件记录的 8 条偏离已全部关闭）。
> 本文件是**修前**的登记与实测，按当时事实保留。
> 修后**能力面**的复核（以及 UI 库据此回退的拆分）见
> [`revisit-g14-unlocks-2026-10-23.md`](revisit-g14-unlocks-2026-10-23.md) 与探针
> [`probes/style-fromany/`](../../probes/style-fromany/)。

**2026-10-23** · 编译器 HEAD `a035645` / v0.4.216 · AIR 51.4.1（`mxmlc` + `adl`）
探针：[`probes/obj-array-identity/`](../../probes/obj-array-identity/) · **最小复现包（供转交编译器侧）**：[`probes/g14-minimal/`](../../probes/g14-minimal/) + [`reviews/handoff-g14-to-compiler-2026-10-23.md`](../handoff-g14-to-compiler-2026-10-23.md) · 登记：[`compiler-gaps.md`](../../compiler-gaps.md) **G14** · 门：`tools/gates.cjs` 第 9 道

```
node probes/obj-array-identity/run.cjs        # 26 条 × 两臂
node probes/obj-array-identity/mutation.cjs   # 4/4，逐字节还原
```

---

## 0 为什么做这个探针

复核 G9 时顺手问编译器一个相邻问题：**`Object` 槽到底会丢多少身份？** 动机很具体 —— style 层把每个入口都拆成「标量形参 + 数组形参」两套（`Size.fromAny(o:Object)` / `Size.fromArray(a:Array)`，`Edges`/`Corners`/`LengthEdges`/`Fill` 同形）。这套拆分**看起来就是那种「当年为了通过而写的绕行」**，正是本轮要清理的对象。

问之前先想清楚**不能怎么证**：只要在库内跑一圈「没崩」就宣布没问题，那是**假绿** —— 库里根本没有 `background: [...]` 这样的用例（demo/主题全传数字色值），跑绿是必然的。

⇒ 所以做**跨运行时差分**，而且**先验证参考**：AIR 那一臂的期望值不是「AIR 的输出」，是**手写下来的 AS3 规则**（`expect.json` 的 `truth`）。AIR 必须自己先符合规则（26/26），然后才有资格当参考。

---

## 1 结果

```
id  case                                          AS3 rule     AIR      我们的 AOT   AOT exit
 1  Object 槽 <- [1,2,3]   (is Array)              true         true      false        0        <-- DIFFERS
 2  Object 槽 <- [1,2,3]   (is Object)             true         true      true         0
 3  Object 槽 <- [1,2,3]   (is Marker)             false        false     (crashed)    0xC0000005  <-- DIFFERS
 4  Object 槽 <- 3         (is Number)             true         true      true         0
 5  Object 槽 <- 3         (is Marker)             false        false     false        0
 6  Object 槽 <- "x"       (is String)             true         true      true         0
 7  Object 槽 <- "x"       (is Marker)             false        false     false        0
 8  Object 槽 <- true      (is Boolean)            true         true      true         0
 9  Object 槽 <- true      (is Marker)             false        false     false        0
10  Object 槽 <- Marker    (is Marker)             true         true      true         0
11  * 槽 <- [1,2,3]        (is Array)              true         true      true         0
12  * 槽 <- [1,2,3]        (is Marker)             false        false     (crashed)    0xC0000005  <-- DIFFERS
13  Array 槽 <- [1,2,3]    (is Array)              true         true      true         0
14  Array 槽 <- [1,2,3]    (is Marker)             false        false     false        0
15  Object 槽 <- [1,2,3]   (as Array != null)      true         true      false        0        <-- DIFFERS
16  Object 槽 <- [1,2,3]   (length)                3            3         undefined    0        <-- DIFFERS
17  Object 槽 <- 3         (String)                3            3         3            0
18  Object 槽 <- [1,2,3]   (typeof)                object       object    object       0
19  guard(Object 槽 <- [1,2,3])                    array-guard  array-guard  (crashed)  0xC0000005  <-- DIFFERS
20  (动态读).size is Array                          true         true      true         0
21  guard(动态读)                                   array-guard  array-guard  (crashed)  0xC0000005  <-- DIFFERS
22  (动态读) as Array -> length                     2            2         2            0
```

**AIR 26/26 符合手写规则。我们的 AOT 偏离 8 条（`1, 3, 12, 15, 16, 19, 21, 26`），其中 5 条是进程崩溃（3/12/19/21/26）。**

> **「一条进程一个用例」不是风格选择**：3/12/19/21 会杀掉进程，单进程驱动会丢掉后面所有答案。runner 把 `0xC0000005` 记成值 `(crashed)` 继续跑 —— 这里**崩溃是数据**，不是 harness 失败。

---

## 2 机制：来自生成的 C，不是推测

```c
// var o:Object = [1,2,3];
o = (Object*)(as_array_make(...));   // 裸数组指针进 Object 槽 —— 根本没装箱
if (false) { ... }                   // o is Array     -> 常量折成 FALSE
as_is(o, &Marker_vt)                 // o is Marker    -> 把数组头当 vtable 读 => 0xC0000005
as_v_obj_val(o)                      // o as Array     -> NULL（Array 的 tag 不是 4）
as_dyn_get(o, "length", 0)           // o.length       -> undefined
as_str_from_bool(false)              // 而 typeof o    -> "object"（这一条是对的）
```

三条独立证据钉住「没装箱」这个根因：

1. **`Number`/`String`/`Boolean` 进 `Object` 槽全部正确**（4/5/6/7/8/9/17 行）—— 它们**被装箱**（`as_number_new` / `as_string_new` / `as_boolean_new`），所以身份活着。
2. **`Array` 直声明（`Array` 槽）也全部正确**（13/14 行）—— 因为它不需要装箱，`is Array` 直接比类型标记。
3. **`typeof` 却是对的**（18 行）—— `as_v_typeof` 对 `anything*` 走的是另一条判据，不依赖 vtable。

⇒ 缺口是「**`Array` 这一个类型没有被装箱**」，不是「`Object` 槽普遍丢身份」，也不是「`is` 整体坏了」。

### 崩溃的真因

`as_is(obj, target_vt)` 会读 `((as_object_header*)obj)->vtable` 再沿 `super` 走。运行时**自己知道**这个危险，注释写着「an Array/Vector/Dictionary 的第一个字是数据指针或 mark 回调，读它本身就是崩溃」—— 但那个守卫只挡 `target_vt == NULL`；`target_vt` 非空（`is <用户类>` 就是）时照读 ⇒ 崩。

`*` 槽也躲不过（12 行）：`as_v_is_inst(v, vt)` 对 `tag == 6`（Array）**明确放行**去调 `as_is`。

### 为什么 `Array` 槽不崩、`Object` 槽崩

`o is Marker` 的三种落法：

| 槽的声明 | 落成的 C | 结果 |
|---|---|---|
| `Array` | 类型标记比较 | 正确（false，因为 `Marker` 不是 `Array`） |
| `*` | `as_v_is_inst(v, &Marker_vt)` → tag 6 放行 → `as_is` | **崩** |
| `Object` | `as_is(o, &Marker_vt)` | **崩** |

---

## 3 对库的影响（这条才是要害）

### 3.1 `fromAny`/`fromArray` 拆分是**承重的**，不能合并

`Size.fromAny(o:Object)` 第一句就是 `o is Length` / `o is Fill` —— 正是会崩的形式。任何「合并两套入口」的清理都会把 `Size("100%")`-类调用路径换成一条能段错误的路径。**拆分保留。**

### 3.2 `Fill.fromAny` 里那句守卫是**死代码**

```as
if (o is Array) return null;   // Fill.as:44
```

生成的 C 是 **`if (false) { return "array-guard"; }`**（就是上面的常量折叠）⇒ 它**一句都没挡到**，下一句 `is Fill` 照样崩。**一个不能触发的守卫比没有守卫更坏**，因为它读起来像保护。

### 3.3 `background: [...]` 会崩（潜伏）

`StyleRefinement.as:77` 的 `Fill.fromAny(o.background)` 是 style 层**唯一**没有 `is Array` 分流就转发进 `fromAny` 的调用点（`size`/`padding`/`margin`/`inset`/`border`/`cornerRadii` 都有）。⇒ 传数组色值会崩。

**当前不可达**（本仓库 demo / 主题全传数字色值），所以是**潜伏**而非活跃缺陷。处置待定（属行为取舍）。

### 3.4 动态读路径是对的 —— 而且 style 层真的在用

20/22 行：`(动态读)` 即 `n.extra["size"]`，`is Array` **正确为真**、`as Array` 后 `length` 也对。这解释了 `StyleRefinement` 的判别方式为何能工作：它先做**动态读**拿到值，再 `is Array` 分流 —— 走的不是 `Object` 槽那条坏路。

⇒ 结论：**style 层当前的调用方式是安全的**，唯一例外是 §3.3 那个没分流的 `background`。

---

## 4 两臂的比对方式不同（刻意的）

- **AIR 是参考，而这件事本身被测过**：`expect.json` 的 `truth` 是**手写规则**，AIR 必须 26/26 符合它。AIR 一旦不符，探针**先**说参考不自洽，**再**去比 AOT —— 没被验证过的参考只是第二个意见。
- **AOT 与 AIR 比，差异必须恰好等于登记集**（`1,3,12,15,16,19,21`）。新增偏离 = 红；偏离**悄悄消失**也 = 红，且文案说明「可能是真修了（`GAP-CHANGED`），去更新登记」—— 不假绿。

## 5 牙

`mutation.cjs` **4/4**，每条都要求**特定的红**：

| 变异 | 应触发的分支 |
|---|---|
| M1 翻一条 AS3 规则（`truth['1'] = false`） | 「参考与手写规则不符」 |
| M2 删一条已登记偏离（id 1） | 「出现了未登记的偏离」 |
| M3 造一条不存在的偏离（id 2） | `GAP-CHANGED` |
| M4 砍掉后半段用例（`count = 15`） | `GAP-CHANGED`（16/19/21 从没跑） |

`expect.json` 在 `finally` 里逐字节还原，并把哈希印在输出里（`6938b59d2b87f405`）。

## 6 未做 / 做不到

- **没有修 G14**（编译器侧，本工作区不动 `as3compiler/src/`）。
- **门报绿 ≠ 行为正确**：绿只表示「偏离集没变」。G14 是**遗留欠账**（AIR 能做对而我们做不出），这一点在门的文案与 `compiler-gaps.md` 都写明。
- 26 条用例只覆盖「一个值 + 一个问题」的独立格；**组合**（例如先 `as Array` 再改元素、再 `is`）没测 —— 若要穷尽，用例数会爆，而现在的 8 条偏离已足以定位根因。
- `Vector`/`Dictionary`/`ByteArray` 进 `Object` 槽**没测**（同型机制，第一个字也不是 vtable，推测同样崩）—— 推测写在这里，不作为结论。