# 转交：G14 —— `Array` 落进 `Object` 槽不装箱（`is Array` 恒假 / `is <用户类>` 段错误）

**收件人**：编译器侧会话（`as3compiler/`）
**来源**：`asaotui/compiler-gaps.md` G14（本工作区**不动** `as3compiler/src/`）
**测量时 HEAD**：`a035645` / v0.4.216 · AIR SDK 51.4.1
**严重度**：高 —— 两个独立症状，一个**静默错误**、一个**进程级崩溃**；AIR 两端都做对。

---

## 1 一条命令复现（最小程序，两个 runtime 并排）

```sh
node asaotui/probes/g14-minimal/run.cjs
```

实测输出（原样粘贴，`exit 0` = 复现成功）：

```
--- our AOT (exit 3221225477)                        --- AIR 51.4.1 (reference)
    is Array  = false     (AIR: true)                   is Array  = true     (AS3 rule: true)
    (never got here)                                    is Marker = false     (AS3 rule: false)
    (never got here)                                    REACHED THE END (no crash)

[g14] reference agrees with the AS3 rule (is Array = true, is Marker = false, no crash)
[g14] REPRODUCED on our AOT: `is Array` answered false and the process died (3221225477) on `is Marker`.
```

程序本体只有两句（`probes/g14-minimal/ReproAot.as`）：

```as
var o:Object = [1, 2, 3];
trace("is Array  = " + (o is Array));    // AIR: true   我们：false（静默）
trace("is Marker = " + (o is Marker));   // AIR: false  我们：0xC0000005
```

参考臂是**真 AIR**（`mxmlc` + `adl`），不是「我们觉得 AIR 会怎样」；`run.cjs` 会**先**校验 AIR 是否符合 AS3 规则，不符合就拒绝下结论（exit 2）。

## 2 症状矩阵（26 格，`node asaotui/probes/obj-array-identity/run.cjs`）

只有「值 = Array」这一族错，其余全对 —— **缺口专属 Array，不是「`Object` 槽普遍丢身份」**：

| 槽的声明 | `Number`/`String`/`Boolean` | `Array` |
|---|---|---|
| `Object` | **全对**（会被装箱：`as_number_new`/`as_string_new`/`as_boolean_new`） | `is Array` **假** · `is <用户类>` **崩** · `as Array` **null** · `.length` **undefined** · `typeof` 对 |
| `*` | 对 | `is Array` **对** · `is <用户类>` **崩** |
| `Array` | — | **全对** |
| 真类实例 | 对 | — |

已知偏离（8 条）：`1, 3, 12, 15, 16, 19, 21, 26`。

## 3 根因（三处，都是「Object 槽里的数组是裸 `as_array*`」的后果）

```c
// var o:Object = [1,2,3];
o = (Object*)(as_array_make(...));   // 裸数组指针，没有包装体
if (false) { ... }                   // o is Array   -> 编译期折成 false
as_is(o, &Marker_vt)                 // o is 用户类  -> 把数组头当 vtable 读 => 0xC0000005
as_v_obj_val(o)                      // o as Array   -> NULL（tag 不是 4）
as_dyn_get(o, "length", 0)           // o.length     -> undefined
as_str_from_bool(false)              // typeof o     -> "object"（这条对，另一条判据）
```

### 3.1 静默错：`is Array` 少一个 `object` 分支 —— `src/emit.ts:32576`

```ts
if (expr.typeName === 'Array') {
  if (o.type.kind === 'array') return { code: 'true', ... };
  if (o.type.kind === 'any')   return { code: `as_v_is_array(${o.code})`, ... };   // 正确的运行时测试
  // ...arrayBacked 用户类...
  return { code: 'false', ... };      // <-- Object 槽落这里，静默假
}
```

**注意紧邻的下面两个分支都处理了 `object`**，而且用的是同一种形状：

- `is Class`（`:32591`）：`as_v_is_class(as_v_obj((void*)(code)))`
- `is Vector.<T>`（`:32624`）：`as_vec_is_name(as_v_obj((void*)(code)), ...)`
- 甚至同文件的 `is Object`（`:32561`）也留着长注释说「这里曾经把静态已知的 scalar/array 折成 false，是错的」

⇒ `is Array` 看起来是**同一类错误的漏网实例**，修法与邻居一致即可（`as_v_obj` 打箱后再问，或直接问动态类别）。

### 3.2 崩溃：`as_is` 没有「这个指针是不是类实例」的判定 —— `src/runtime.ts:1178`

```c
static bool as_is(void* obj, void* target_vt) {
    if (obj == NULL) return false;
    // A NULL target can never match, and answering it requires reading obj's first
    // word as a vtable -- which is a data pointer or a mark callback for an Array/
    // Vector/Dictionary, so the read itself would be the crash.      <-- 你们已经知道
    if (target_vt == NULL) return false;                             <-- 但只挡了这一种
    void* vt = ((as_object_header*)obj)->vtable;                     <-- target_vt 非空时照读
    ...
}
```

注释写着「读第一个字本身就是崩溃」，而**能触发它的条件当时被当成只剩 `target_vt == NULL`**；`is <用户类>`（`target_vt` 非空）是第二条路径。

**可用的现成料**：你们在 `:2038` 已经用 `gc_in_heap(v.ptr)` 把「Class 值 vs 真实例」区分开了；GC header 本身带 `GCT_ARRAY`/`GCT_OBJECT`/… 类型标记。数组/Vector/Dictionary/ByteArray 的第一个字不是 vtable，这件事是可判定的。

### 3.3 `*` 槽也崩：`as_v_is_inst` 对 tag 6 放行 —— `src/runtime.ts:2026`

```c
if (v.tag != 4 && v.tag != 6) return false;   // Array(tag 6) 放行给 as_is
if (!as_is(as_v_obj_val(v), target_vt)) return false;
```

`*` 槽的 `is Array` 是**对的**（走 `as_v_is_array`），但 `is <用户类>` 同样段错误。

### 3.4 那条「不装箱」的决定在哪 —— `src/runtime.ts:3432`

```c
static void* as_value_to_obj(as_value v) {
    switch (v.tag) {
        case 1: return (void*)as_number_new(v.num);      // Number -> 包装体
        case 2: return (void*)as_boolean_new(...);       // Boolean -> 包装体
        case 3: return (void*)as_string_new(...);        // String  -> 包装体
        case 4: case 6: return v.ptr;                    // Object / Array -> 裸指针  <-- 这里
```

即 `Object*` 与 `as_array*` 在 C 层**同型**。⇒ 两条修法路线，任选：

- **(A) 让解箱/类型判定认得「裸容器指针」**（改 3.2/3.3 的判定；3.1 顺势修好）。改动集中在运行时，不动物化表示。
- **(B) 让 Array 也装箱**（在 3.4 给 tag 6 造包装体）。会牵动 `as_array*` 与 `Object*` 之间所有既存隐式转换，面更大。

**我们不作建议**（不了解你们的性能/表示约束），只报事实：`is Number/String/Boolean` 在 `Object` 槽上**今天是对的**（实测），修法不要把它弄坏。

## 4 我们这边的门会怎么反应（设计如此，不是抱怨）

修好后：

- `node asaotui/probes/g14-minimal/run.cjs` → **exit 1**（`NOT reproduced`）并列出要更新的三处登记；
- `node asaotui/probes/obj-array-identity/run.cjs` → **exit 1 `GAP-CHANGED`**（`knownAotDeviations` 里的条目会「消失」）；
- `node asaotui/tools/gates.cjs` 里那两道相关门会变红，直到我们更新登记。

这是我们**故意**的反向绊线：偏离集必须**恰好等于**登记集，新增/消失/少跑都红。届时我们会更新 `compiler-gaps.md` G14、`probes/obj-array-identity/expect.json`、`ui-demo/CheckUi.as` §8，再跑全量门确认 18/18。**不需要你们替我们改这些文件。**

## 5 我们这边不依赖你们修

`asaotui/` 已经绕开：style 层在**调用点**用 `is Array` 分流（在 `*` 动态读上做，那里是可靠的），`Fill.fromAny` 里那句假守卫已删（它被折成 `if (false)`），并配了双面钉子：

- `ui-demo/CheckUi.as` §8（4 条断言：数组背景**不崩**且无填充、标量背景仍是实色、兄弟字段不被吞）；
- 变异 `ui-demo/mutation-checkui-array-bg.cjs` **2/2** —— 把那一行改回原样 ⇒ `exit 3221225477`（**崩溃可复现**）；把 `Fill.fromAny` 改成恒 null ⇒ 标量断言当场报错。

所以这是一个**纯编译器侧欠账**（AIR 能做对而我们不能），不影响本库交付。

## 6 非目标 / 请别顺手做

- 不要只把 `is Array` 的 `false` 改成 `true` —— `Object` 槽里可能是任何值。
- 不要把 `x is Array` 改成走 vtable：`CORE_CLASS_VT` 里 `int`/`uint`/`Array` 的 vt 是 **`'NULL'`**（`src/emit.ts:275`），走 vtable 那条路对这三个类型没有意义，这也是 `as_is` 开头那个 `target_vt == NULL` 守卫的由来。
- 三个症状（静默假 / 段错误 / `.length` undefined）看起来是同一个根因，但**别假定修一个就全好**：`as Array`（`tag 6` 走 `as_v_obj_val`）与 `as_dyn_get` 走的是另外两条路。
