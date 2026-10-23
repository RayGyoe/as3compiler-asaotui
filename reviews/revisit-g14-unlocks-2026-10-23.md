# G14 修好之后：UI 库能拿回什么（逐项复核 + 回退实测）

> 2026-10-23 · 探针 [`probes/style-fromany/`](../probes/style-fromany/) · 登记 [`compiler-gaps.md`](../compiler-gaps.md) **G14**
> · 门 `tools/gates.cjs` 第 11 道 · 编译器 **阶段二百五十三**（`54bda6d`, v0.4.217）
>
> 一句话：**G14 一死，style 层为它做的那套「标量形参 / 数组形参」拆分就失去了全部理由，已回退；
> 但那 10 处 `*` 绑定读取不该跟着回退**（它们的理由是装箱成本，与 G14 无关）。
> 每一处改动都用**同一份用例 × 两个 runtime** 重新量过，没有一处靠「应该没事」。

---

## 1 先确认 G14 真的没了

不是读提交信息，是跑反向绊线：

```sh
cd asaotui && node probes/g14-minimal/run.cjs     # exit 1 = 已修（exit 0 = 复现）
cd asaotui && node probes/obj-array-identity/run.cjs
```

实测：最小复现包 `exit 1`；26 格矩阵 **`AOT deviations from AIR: none`**
（修前是 `1, 3, 12, 15, 16, 19, 21, 26`，其中 5 条 `0xC0000005`）。AIR 臂 26/26 仍符合手写 AS3 规则
⇒ 参考臂没漂。

**这决定了一件事**：`Array` 落进 `Object`（或 `*`）槽后，`is Array` / `as Array` / `.length` /
下标 / `join` / `String()` 全都可用。⇒ 凡是「把数组塞进 `Object` 形参」的写法，从「会崩」变成「正常」。

---

## 2 逐项复核：哪些是 G14 的债，哪些不是

| # | 库内现状 | 它是谁的债 | 判定 | 理由 |
|---|---|---|---|---|
| 1 | `Size/Edges/Corners/LengthEdges/Fill` 各有 `fromAny(o:Object)` + `fromArray(a:Array)` 两个入口，`StyleRefinement.from` 在每个调用点做 `is Array ? ... : ...` 三元分流（6 处） | **G14** | ✅ **已回退**：`fromAny` 自己分派数组，6 处三元全部收成一行的 `fromX.fromAny(...)` | `fromAny` 的第一句就是 `o is Length` / `o is Fill`（**用户类**）——这正是修前必崩的形式。前提没了，拆分就只是噪音；留着它，每个新字段都要记得写两遍 |
| 2 | `Fill.fromAny` 里一句 `if (o is Array) return null;`，2026-10-23 上午被**删掉**（它被折成 `if (false)`，是死代码） | **G14** | ✅ **重新插入，并且现在是活代码** | 不是「加回保护」，是这句话第一次**真的会执行**。探针 case 12/18 钉住它（`Fill.fromAny([11,22])` → `null`，两个 runtime 都如此） |
| 3 | `Fill.fromArray(a:Array):Fill` 恒返回 `null` | **G14**（它是拆分的产物） | ✅ **保留**，注释重写 | 数组 = 渐变停机列表，渐变仍 defer（返回 `null` 是对齐 AIR，不是发明）。保留它的真正理由不是 G14：**形参写成 `Array`，将来渐变落地时 `a.length` 天生安全** |
| 4 | 10 处绑定读取声明成 `*`（6 处 `Boolean` 型 + 4 处 `Number` 型） | **G9**（+ 撞上 G14） | ❌ **不回退成 `Object`** | ① `var x:Object = binding.get()` 会把标量经 `as_value_to_obj` **装箱**，每次读一次 GC 分配；`*` 不装。② 这 10 处不是躲缺陷，是**正确的默认类型**。G14 修好后②这条理由消失，①还在 ⇒ 结论不变，**只是理由少了一条**（注释已相应改写，不再说「因为 G14」） |
| 5 | 公开 API 叫 `bindTo` 而不是 `bind` | **G8**（已修阶段二四七） | ❌ **不改回 `bind`** | 与 G14 无关。撤了等于把公开 API 名重新押在编译器的 C 名剪辑上，而回归症状会把人引向 socket（`conflicting types for 'bind'`）。见 [`revisit-g8-g9-workarounds-2026-10-23.md`](revisit-g8-g9-workarounds-2026-10-23.md) |
| 6 | `CONTRIBUTING-widget.md` §4 第 3 条整条在讲「数组一律显式 `as Array` 传给 `Array` 形参」 | **G14** | ✅ **重写** | 那条现在是**反的**：数组可以直接进 `Object` 形参。保留下来会让后来者写出没必要的拆分 |
| 7 | `ui-demo/CheckUi.as` §8 的注释说「这里曾经在**调用点**分流」 | **G14** | ✅ **重写 + 加一条断言** | 调用点不再分流，注释描述的形状已经不存在。新增 `Fill.fromAny([255,0,0]) == null`（**直接**问 `fromAny`，不问 `StyleRefinement`），否则「别处忘写分流」这一类回归会从这条钉子底下走过去 |
| 8 | `ui-demo/mutation-checkui-array-bg.cjs` 的 `M1`：把调用点改回无分流 ⇒ **期待 `exit 3221225477` 崩溃** | **G14** | ⚠️ **这条变异已经变成假钉子，已重写** | 调用点那个 anchor 不存在了；**更关键的是崩溃不可能再发生**。⇒ 若不动它，这道变异要么抛「anchor not found」，要么改成「退出码非 0」而实际上因为别的原因红。新判据：把 `Fill.fromAny` 的数组分支改成返回 `solid(0x000000)`，要求两条数组断言**按名字**报红 |
| 9 | 门 7（style scan，原 G9 扫描）的注释把「`*` 是正确的默认」归因于 (a) 装箱成本 + (b) G14 | **G9/G14** | ✅ **改注释** | (b) 已经不是正确性理由了。门本身不动（它仍然是对的，只是理由从两条变一条） |
| 10 | `compiler-gaps.md` G14 行「对 UI 库的影响 ①：拆分**不能合并**」 | **G14** | ✅ **改写成「登记时的判定」+ 新增回退行** | 那句在当时是对的，现在不成立。**不删历史**，标明它在什么条件下成立 |
| 11 | `compiler-gaps.md` G14 行「与 G9 的关系」里写着「G14 **未修**」 | —— | ✅ **改** | 事实错误，最该先改的一处 |
| 12 | `STATUS.md` 的门 9 行写「AOT 偏离 **8** 条」、结论写「G14 新登记、未修」 | —— | ✅ **改** | 同上 |

**没有动的**（复核过，确认与 G14 无关）：`bindTo` 命名、`*` 的那 10 处、`Vector.<T>` 的用法
（规模不匹配：现有集合都很小，改 `Vector` 只增加类型噪音）、`Fill.fromArray` 的 `null` 语义。

---

## 3 回退怎么做（不是「删掉三元」那么简单）

`StyleRefinement.from` 的 6 处三元是这样收的（以 `size` 为例）：

```as3
// 修前（G14 期间）
r.size = o.size is Array ? Size.fromArray(o.size as Array) : Size.fromAny(o.size);
// 修后
r.size = Size.fromAny(o.size);
```

收三元本身是机械的，**承重的是另一边**：`Size.fromAny` 必须先学会分派数组。五个类各加一段，
顺序有讲究 —— **数组检查必须在 `is <用户类>` 之前**：

```as3
public static function fromAny(o:Object):Size
{
    if (o == null) return null;
    if (o is Array) return fromArray(o as Array);   // <- 必须先问数组
    return of(lenOf(o), lenOf(o));                   //    再问 Length / Number
}
```

`Fill.fromAny` 同理，且注释里写清了为什么这个顺序是**语义**而不是风格：`is Fill` 对数组永远为假，
所以顺序本身不再影响正确性；但**先问数组**让「数组 = 渐变」这条规则一眼可见，且将来若有人把
`fromArray` 的返回值从 `null` 改成真渐变，这行不需要跟着动。

---

## 4 为什么这次「敢」合并：19 格 × 2 runtime + 4 条变异

一条命令，两个 runtime，同一份用例表：

```sh
cd asaotui && node probes/style-fromany/run.cjs
```

19 格覆盖 **机制本身**（数组进 `Object` 形参后 `is Array`）+ 五个类的**每一种文档化形状** +
`StyleRefinement.from` 的**动态读**路径。期望值**手算**写在 `expect.json`（连同逐条推导），
**两个臂都拿它当裁判** —— 所以「AIR 是参考」这句话本身是被测的。

实测：

```
RESULT: PASS (19 cases; both arms agree with the hand-derived answers)
AOT exit: 0
```

**最该看的一格**是 15：

```
15  isArrayInObjectSlot([1])   true
```

这就是回退的全部前提。若它不成立，其余 18 格**照样会绿**（数组只是走到 `null`），
所以探针的变异里专门有一条 `M3` 把它硬编码成 `false` —— 必须被抓。

变异（`node probes/style-fromany/mutation.cjs`）：

```
M1  CAUGHT  failed cases: 1, 3, 16        (删掉 Size.fromAny 的数组分支)
M2  CAUGHT  failed cases: 5               (Edges.fromArray 的 [h,v] 交换)
M3  CAUGHT  failed cases: 15              (机制本身硬编码 false)
M4  CAUGHT  failed cases: 10              (LengthEdges.fromArray 的 [h,v] 交换)
MUTATION style-fromany: 4/4 caught, 0 problem(s)
```

每次都在 `finally` 里还原并 **sha256 逐字节核对**。

库内那半边（端到端 + 一条按名报红的变异）：

```sh
cd asaotui/ui-demo && node run-check.cjs                       # CHECKUI: 33 checks, 0 failures
cd asaotui && node ui-demo/mutation-checkui-array-bg.cjs       # MUTATION: PASS (2/2)
```

---

## 5 顺带确认：G14 修完**没有**解锁的事

| 想法 | 为什么不做 |
|---|---|
| 把 `Size/Edges/...` 的 `fromArray` 整个删掉 | 保留它是有成本的收益：**渐变落地时**那个 `Array` 形参让 `a.length` 天生安全，而且 `Fill.fromArray` 已经是公开入口。删了将来还得加回来 |
| 把 10 处 `*` 改回 `Object`（「缺陷都修了，绕行该清了」） | 净退化：每次读多一次装箱。`*` 从一开始就是更便宜的**正确**写法，不是绕行 |
| 用 `is Array` 替换掉 `@:meta` 之类的手写类型标记 | 库内没有这类标记，无对象可换 |
| 现在就把 `Dictionary` 进 `Object` 槽的行为也「顺便」验一遍 | **G15 还开着**：`getQualifiedClassName(new Dictionary())` 我们回 `"Object"`，AIR 回 `"flash.utils::Dictionary"`。它不影响 style 层（style 层的 `fromAny` 不问 qcn），但凡是按 qcn 分流的诊断/序列化代码都会错 ⇒ 单独登记，不夹带 |

---

## 6 落点清单

| 文件 | 改动 |
|---|---|
| `kit/asaot/ui/style/{Size,Edges,Corners,LengthEdges,Fill}.as` | `fromAny` 分派数组（数组检查在前）；注释改写为「为什么现在是全能入口」 |
| `kit/asaot/ui/style/StyleRefinement.as` | 6 处调用点三元 → `fromX.fromAny(...)` |
| `kit/asaot/ui/{checkbox,radio,toggle,list,tabs,slider}.as` + `kind/{Checkbox,Radio,Switch,List,Tabs}Widget.as` | 10 处 `*` 的**理由**注释重写（G9/G14 均已修；`*` 仍是最便宜的正确答案） |
| `probes/style-fromany/` | **新探针**：19 格 × 两臂 + 4 条变异 + README |
| `ui-demo/CheckUi.as` §8 | 注释重写 + 新增 `Fill.fromAny(Array)` 直接断言（27→33 格中本段 4→5 条） |
| `ui-demo/mutation-checkui-array-bg.cjs` | `M1` 重写：判据从**退出码/崩溃**升级为**断言名**（旧钉子在 G14 修好后必然假绿） |
| `CONTRIBUTING-widget.md` §4.3 | 重写（原文是反的） |
| `compiler-gaps.md` | G14 三条行改写 + §3 正面结论加一行；**未改任何历史结论** |
| `tools/gates.cjs` | 新增第 11 道门；门 7 的注释理由收窄为一条 |

> 编译器侧仍**零改动**：`node tools/compiler-fingerprint.cjs` 复核。
