# G11 的一次假红：端点哈希对看不见「改完又还原」的窗口

- 日期：2026-10-23
- 触发：删掉 `kit/asaot/ui/UiNode.as.pre-widget` 后跑全量门（`node tools/gates.cjs`），G11 变红
- 结论：**不是生成器不确定**，是本门自己的仪器有洞 —— 端点哈希对看不见窗口内的「写入→还原」
- 处置：`run.cjs` 改为**逐次构建**采样 `src/` 内容哈希，并把归因本身做成变异目标（M6b）
- 现状：`mutation.cjs` **10/10**、全量门 **18/18 PASS**

---

## 1 症状

```
[FAIL] G11 determinism: 5 builds -> 1 C, spellings agree, artifacts decay (2/5 hashes)  (exit 1)
FAIL: the 5 builds produced 2 distinct C files
   -> THE GENERATOR IS NONDETERMINISTIC
```

证据（`probes/g11-nondeterminism/run-2026-10-23.txt`）：

```
B. 5 builds of probes/array-scope/Main.as, same command, same tree
   run 1: 3704980 B  sha256/16 ae3fabbe9fc30ad8  (6.9s)
   run 2: 3704980 B  sha256/16 ae3fabbe9fc30ad8  (6.9s)
   run 3: 3704980 B  sha256/16 ae3fabbe9fc30ad8  (8.1s)
   run 4: 3704898 B  sha256/16 3c6a8202239da3f1  (8.1s)     <-- 少 82 B
   run 5: 3704980 B  sha256/16 ae3fabbe9fc30ad8  (6.9s)
   input hash after the runs: 9a8aee7b944c9911 (unchanged)
   src/ content hash after the runs: 7a11a34a62dd099b (unchanged -> the generator revision was stable)
```

门自己的两个前提都说「没变」：**输入没变、`src/` 内容哈希首尾相同**。而 5 次里有 1 次不同。
这正是「生成器不确定」该有的样子 —— 所以门这么报了。**但结论是错的。**

## 2 真因

同一时刻磁盘上的事实（`mtime` 皆为 +0800）：

| 时刻 | 事件 |
|---|---|
| 08:44:42 | 本次 G11 测量开始，`srcHashBefore = 7a11a34a62dd099b` |
| 08:44:52 | 并发会话写出 `as3compiler/temp/g14/mutate.cjs` |
| ~08:45:06 | **run 4 启动** |
| 08:45:07 | `src/runtime.ts` 最后一次写入 |
| 08:45:12 | `src/emit.ts` 最后一次写入 |
| ~08:45:17 | 测量结束，`srcHashAfter = 7a11a34a62dd099b`（**与 before 相同**） |

而 `mutate.cjs` 的做法是（原文）：

```js
for (const m of MUTATIONS) {
  const original = fs.readFileSync(m.file);
  const before = sha(original);
  ...
  fs.writeFileSync(m.file, toCrlf(parts.join(m.to)));   // 写入变异体
  try { res = runGroup(); }                             // 跑单元组
  finally { fs.writeFileSync(m.file, original); }        // ← 还原成「原字节」
  const after = sha(fs.readFileSync(m.file));
  if (before !== after) { /* 报未还原 */ }
}
```

**它保证「还原后与原字节逐字节相同」** —— 也就是说，窗口内存在过变异体、但窗口两端的内容完全一致。
`mtime` 08:45:07/08:45:12 就是那两次 `finally` 还原。

于是：run 4 编译到了**变异体**（`M1` 之类，仍能生成合法 C，只是内容少 82 B），而门在首尾各采的那一次
哈希都落在「非变异」状态上。**端点对采样对这种形状是结构性盲的**，而且盲的恰好是并发会话 mutation
harness 的**默认行为**——它会一直这么干。

复核：事后连跑 12 次，**12/12 同一哈希**（`ae3fabbe9fc30ad8`）⇒ 不是不确定。

## 3 修法

`run.cjs`：把 `src/` 内容哈希从「首尾各一次」改成**每一次构建的紧邻前后各一次**，并把差异**归因给「源码动过」**：

```js
const srcSamples = [];   // 每一次构建前后各采一次
for (...) {
  const before = process.env.ASC_G11_FORCE_ITER === String(i) ? srcHashBefore + '-moved' : srcTreeHash();
  const r = spawnSync(...);                    // 构建
  const after = srcTreeHash();
  srcSamples.push({ i, before, after });
  ...
}
const movedBuilds = srcSamples.filter((s) => s.before !== srcSamples[0].before || s.after !== s.before);
const v = distinctVerdict(uniq.size, hashes.length, movedBuilds.length);
```

`distinctVerdict()` 是**纯函数**，把「N 份不同输出」这一个判定抽出来，于是变异机可以直接驱它：

| 输入 | 结论 |
|---|---|
| `uniq = 1` | `ONE output for one input` |
| `uniq = 2`，**0 条被污染** | `THE GENERATOR IS NONDETERMINISTIC` + **计入 failures**（缺陷） |
| `uniq = 2`，**≥1 条被污染** | `the generator MOVED mid-run … NOT evidence of nondeterminism`，**不计入 failures** |

被污染的构建 ⇒ 进 `blockers` ⇒ **exit 3（`[SKIP]`）**，`gates.cjs` 已把它算作单独一类并**大声**打印
（「a green would certify an unknown tree, and a red would blame this workspace for someone else's uncommitted edit」）。

每次构建的行上还带 8 位 `src` 戳：`run 4: 3704898 B sha256/16 … [src 7a11a34a -> b3c1d0e2 MOVED]`。

## 4 牙（`mutation.cjs` 10/10）

新增 **M6**：

- **M6a**（端到端）`ASC_G11_FORCE_ITER=1` ⇒ 必须 exit 3 且指名「during build 1」，且**不得**出现 `PASS:`。
- **M6b**（判定本身）直接驱 `distinctVerdict`：0 条污染必须仍读作缺陷并计 failure；1 条污染必须改口且不计。
  **没有这一半，`uniq != 1 就 SKIP` 这种实现也能过 M6a** —— 那等于悄悄废掉本仓唯一能发现真不确定生成器的测量。

全部文件 `finally` 还原并哈希核对（本轮 `run.cjs eea3e1bbdda5a994`）；三份历史产物 + 两个 mutant 无残留。

## 5 这一类坑的教训

1. **「没变」的两个端点 ≠ 「没变过」。** 凡是靠「测量前后采样同一量」来证明「期间没人动过」的仪器，
   都对「动过又还原」结构性失明。多采几次、并且**在真正要用的那一刻**采。
2. **变异 harness 的「还原」保证会主动制造这种形状**：它越严格（逐字节还原），越像「什么都没发生」。
   本仓的互测环境里，这类假红不是小概率。
3. **把归因做成可测的函数**：`distinctVerdict` 抽成纯函数后，「不归因」的错实现会被 M6b 抓住；
   否则它只会被一个需要真实不确定生成器的场景抓住 —— 那个场景永远不会来。
4. 与 §G11 结案时那条同源：**先看树，再下结论**。这次树的两个端点都是干净的，所以要往窗口里看。

## 6 未做

- 未改 `gates.cjs` 对 exit 3 的处置（已正确：单独计数、loud `[SKIP]`）。
- 未给 `run.cjs` 加「重试」——那正是 G11 结案时撤掉的东西。
- 未处理 `.gitignore` 里 `probes/g11-nondeterminism/run-*.txt` 的**追加**增长（与 `anim` 日志同类），
  当前仍入库：它是**不可再生的证据**（历次红/绿的记录），与「每跑一次就变的计时日志」不同类。
