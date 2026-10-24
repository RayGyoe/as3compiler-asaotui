# probes/g20-settextformat — `setTextFormat` 替换区间，不叠加 run（G20）

**问题**：AIR 的契约是「设置该范围内的格式」（同一区间施加两次 == 一次；全区间格式覆盖已有子区间格式）。
我们此前每次都往 `TextField._runs` 追一条 `(begin, end, TextFormat)`，而排版侧
`sk_textlayout_new_runs` 是「按 run 顺序把 `text[start..end)` 各拷一遍」——同一段字符被排 N 遍，
**宽度随重绘次数线性增长**，应用侧看到的就是「输入过的字被复制了一遍」。

## 为什么全是关系式

AIR 与我们的文本引擎不同，**绝对宽度本来就不同**（同一格式施加一次：AIR 52 px，我们 46.66 px）。
所以 12 个用例全部是「同一个进程里两个字段互比」，从不比绝对值：

| 组 | 断言 |
|---|---|
| A | 施加 1/2/3 次后 `textWidth` 三者相等；墨迹宽度也相等；文本与长度不变 |
| B | 子范围施加 3 次 == 1 次 |
| C | 全范围格式**覆盖**已有子范围格式 == 干净字段 |
| D | 两个不相交范围与施加顺序无关 |
| E | run 真的**生效**（24px run 必须比 20px 默认字宽宽）—— 否则「一个 run 都没装上」也能让上面全绿 |
| F | 窄范围落在一条 run 内部时把它**切开**（尾部 / 中间）== 三段独立格式 |
| G | 反复 `BitmapData.draw` 后宽度不变（用户实际踩到的形状） |

## 跑法

```
node probes/g20-settextformat/run.cjs            # 两臂并排
ASC_SKIP_AIR=1 node probes/g20-settextformat/run.cjs
node probes/g20-settextformat/mutation.cjs       # 证明 run.cjs 会红（5/5）
```

退出码：`0` 两臂与手推规则一致；`1` 有不一致；`2` 构建/adl 出错。

## 已登记偏差（不修、持续测量）

`TextField.getTextFormat()` 在我们这里恒返回 `defaultTextFormat`、不读 run 表（AIR 返回该区间**生效的**
格式）。用例 10/11 把它记在 `expect.json` 的 `known` 里：AIR 必须答 `true`、我们**当前**必须答 `false`
—— 哪天修好了，脚本会因为「登记的偏差消失了」而**变红**，提醒把它删掉。登记处 `compiler-gaps.md` G21。

## 状态

**已修（阶段二百六十八，v0.4.232）**。修前 7/12 格红（46.66 → 91.53 → 136.41 px 线性增长）。
回归：`as3compiler/examples/settextformat-runs.as`（12 条断言）、`unit: text/settextformat`（15 条源级钉）。