# G21 —— `TextField.getTextFormat()` 读回该区间**生效的**格式（探针）

**已修：阶段二百七十，v0.4.234。** 缺口判定、结构前提与影响面见 [`compiler-gaps.md`](../../compiler-gaps.md) G21。

## 测什么

修前 `TextField_getTextFormat` 是一行 `return tf->defaultTextFormat;`（注释自述「one format per
field」，写于 run 表存在之前）。用 `setTextFormat(fmt(30, 0x0000FF))` 给整段上色定字号之后，
`getTextFormat().color` 仍是 `0`、`size` 仍是 `20`。

`expect.json` 里 30 格覆盖 AIR（adl 51.4.1）实测的全部分支，按读回结果归成六类：

| 类 | 输入 | AIR 的回答 |
|---|---|---|
| ① | 从未调过 `setTextFormat`，非空区间 | `defaultTextFormat` |
| ② | 整段落在**一条** run 内 | 该 run 的格式（**副本**，改它不影响字段） |
| ③ | 跨两条 run 的边界 / 反序（`begin > end`）/ 文本内部空区间（如 `(3,3)`） | **全 `null` 的空 `TextFormat`**（不抛错） |
| ④ | 相邻两条 run **数值相同** | 仍回答该格式 —— 比的是**值**，不是 run 身份 |
| ⑤ | `(0,0)` / 空文本 / `begin >= length` / `end > length` | 抛 `RangeError #2006` |
| ⑥ | 任一端点为 `-1` | 「未提供」：不做越界检查，按另一端截取（`(-1,-1)` 在空文本上答空格式，`(0,0)` 才抛） |

③ 与 ⑥ 是这条缺口最容易被写错的两处：直觉会想「跨边界就报错」，而 AIR 是**安静地给一个空格式**；
端点 `-1` 也不是 `0`，它表示「这一侧没给」，因此不参与越界判定。

## 判据

`node probes/g21-gettextformat/run.cjs` 三重检查：

1. **30 格双 runtime 逐字相同**（`adl` 与 AOT 各自写 30 行，与 `expect.json` 手推答案比对）；
2. **生成的 C 读 run 表**：`TextField_getTextFormat` 的定义体里必须出现 `tf->_runs`；
3. **三个 helper 真的在用**：`as_tf_fmt_eq(`（严格 `as_v_eq` 逐段比对）、`as_tf_fmt_empty()`（空格式）、
   `as_tf_fmt_clone(`（返回副本），以及越界路径上的 `2006`。

第 2、3 条的查找都用 `lastIndexOf` 定位**定义**：原型声明与 vtable 表项出现在前面，`indexOf` 会落在
错误的位置上（这曾在本探针的第一版里制造 5 个假失败）。

## 命令

```sh
node probes/g21-gettextformat/run.cjs            # 双 arm + 生成 C 审计
ASC_SKIP_AIR=1 node probes/g21-gettextformat/run.cjs
node probes/g21-gettextformat/mutation.cjs       # 证明 run.cjs 会红（5/5）
```

退出码：`0` 通过；`1` 有分歧；`2` 构建/adl 出错。

## 变异（`mutation.cjs`，5/5 命中）

| # | 变异（改哪里） | 期望 | 实际 |
|---|---|---|---|
| M1 | `b >= e` 返回 `clone(default)` 而不是空格式 | run.cjs 红 | caught |
| M2 | 禁掉 `#2006` 分支 | run.cjs 红 | caught |
| M3 | 跳过逐段 `as_tf_fmt_eq` 比对（永远回答第一段） | run.cjs 红 | caught |
| M4 | 改 `expect.json` 的 case 27（相邻同值 run） | 与 AIR 不一致 | caught |
| M5 | 改 `GetFmtCases.as` 的 case 28 run 字号 30→31 | 与 AIR 不一致 | caught |

M1–M3 改 `src/emit.ts`（语义），M4–M5 改**真值来源** —— 后者证明 `expect.json` 里每一格都是被
`adl` 检验过的，而不是照着我们自己的输出抄的。每个变异结束后逐字节还原。

## 状态

**已修（阶段二百七十，v0.4.234）**：30/30 两端逐字相同，M1–M5 全部被抓。

连带影响：同目录外的 [`probes/g20-settextformat/`](../g20-settextformat/) 的 case 10/11 曾把这条缺口
登记成 `known` 豁免（AIR `true` / 我们 `false`），修好后 `known` 已整键删除、两格转为正式断言，12/12 全绿
—— 这正是当初「哪天修好了脚本会变红」那条提醒生效的结果。

回归：`as3compiler/examples/gettextformat.as`（11 组断言）、`unit: text/getTextFormat`（31 条源级钉）。