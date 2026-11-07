# G31 / G32 上游立项说明（待项目负责人点头）

> 提出日期：2026-11-07 · 提出者：`asaotui` 侧（dogfooding 撞到）
> 现居 `asaotui/`，**未改动 `as3compiler/` 一行**。按 `compiler-gaps.md` §5：立项 = 占阶段号 + 升版本 +
> 全量回归，属项目级承诺，须先取得同意。**本文件就是拿来点头的那份东西。**

---

## 1 一句话

12pt 正文里 `A` 后面的空格比 AIR 窄 **2px**，整行总宽却与 AIR **逐项相等** ⇒ 不是丢字、不是行宽错，
是**逐字形的 advance 被整数取整**，差额从空格挪给了相邻字母。文档站每段以 `A …` 起句的正文都受影响
（`Acard`、`Abutton`），且 12pt 正是正文与大量 UI 文本的字号。

## 2 判据（AGENTS.md §1.5）

| 缺口 | 归类 | 依据 |
|---|---|---|
| G31 空格被画窄 | **遗留欠账** | AIR **有**正确行为（同串实测 4px），我们是 2px；`adl` 能跑对而我们跑不对 |
| G32 `TextFormat.letterSpacing` 无效 | **遗留欠账**（`TextFormat` 是 AIR 文档字段） | 我们接受该属性但排版从不读它；当前 `asaotui` 未使用，故**无当前可视缺陷**，优先级低于 G31 |

两者都不属于「AIR 本来就不支持」的增强，也不是平台边界。

## 3 证据（可复现，一条命令）

```bash
node asaotui/probes/g31-space/run.cjs      # 0 = 复现, 1 = 已修, 2 = 工具链问题
```

| 串（12pt Arial） | AIR 51.5.1 | 我们（AOT） |
|---|---|---|
| `A \|` | span 12，gap **4** | span 11，gap **2** |
| `b \|` | span 11，gap 4 | span 11，gap **5** |
| `X \|` / `V \|` | span 12，gap 4 | span 12，gap **3** |
| `T \|` / `Q \|` / `1 \|` | 4 / 4 / 6 | 4 / 4 / 6（一致） |
| `A box` | span **29**，gaps `[4 1 1]` | span **29**，gaps `[2 1 1]` |
| `A  box` | span **32** | span **32** |
| `A card is a box` | span **79**，gaps `[4 1 1 4 1 5 4 1 1]` | span **79**，gaps `[2 1 2 1 5 2 5 5 1 1]` |

读法：**总宽相等、间隙分布不等** ⇒ 字没少，是各自的 advance 被取整。AIR 对每个字母都恰好 4px（说明它
既没 kern 也没取整），我们随字母在 2–5px 之间漂。

代码侧事实（读，未改）：

- `vendor/skia_text_glue.cc`：`sk_textlayout_new` / `mkStyle` 只设 `size/color/weight/slant/families/height`；
  `sk_text_run` 结构里**没有** `kerning`，也**没有** `letterSpacing` ⇒ 默认的字形定位（hinted、advance 取整）。
- `src/emit.ts`：`TextFormat.letterSpacing` 只被**存 / 比较 / 复制**（24485、24514、24537、25824、25837、25848），
  `as_tf_paragraph` 读格式时只取 `size/bold/italic/leading/color/font` ⇒ 从未到达排版。
- 段落缓存键（`as_tf_paragraph` 的 `_para_*`）里既没有 kerning 也没有 letterSpacing。

已排除的替代解释（都有实测，见探针 README）：换行路径、字体族别名、富文本 run、粗体、抗锯齿阈值、
库侧度量缓存（上述量全部来自**裸 `TextField`**，不经过 `asaot.ui`）。

## 4 建议改动（最小面，按先后）

1. **G31 主体**：段落排版走**亚像素字形定位**——不让 advance 被 hint/round 到整像素（SkFont 线性度量）。
   目标：`3.33px` 的空格真的落成 `3.33px`。**不要**顺手把 kerning 关掉当修法：AIR 给 `A`/`b` 同样的 4px，
   说明它本来就没 kern；关 kern 只会改别的字对。
2. **G31 连带的接口完整性**（可同阶段做，也可另开）：把 `TextFormat.kerning` 真正接进 `sk_textlayout_new` /
   `sk_text_run`（AIR 默认 `false`），并进段落缓存键。**做完必须有 adl A/B**：AIR 关闭/开启 kerning 各量一遍，
   确认我们与之一致，而不是"看起来更紧凑"。
3. **G32**：`sk_text_run` 加 `letterSpacing` → `TextStyle::setLetterSpacing`，同样进缓存键。
   零值必须**逐字节不改变**现有产物（可用现有 `probes/widgets/textfx` 与 `probes/widgets/typing` 做回归钉）。

## 5 验收标准（建议）

| 检查 | 通过条件 |
|---|---|
| `probes/g31-space/run.cjs` | 由「0 = 复现」变「**1 = 已修**」；`A \|` = 4px，其余行与 `span` 与 AIR 逐项相等 |
| 现有文本类探针 | `probes/widgets/{typing,textfx,choice,data}` 全绿（文字度量一动就会波及这三个） |
| 文档站 | `node asaotui/ui-demo/run-gallery.cjs` 仍 `pages=60 nodes=13907 badPages=0`；目视 `gallery-page1.png` 首行不再出现 `Acard` |
| G32（若同做） | 新增一条探针：`letterSpacing=0` 与未设时产物逐字节相同；`=2` 时 `textWidth` 增加 `2*(n-1)`，两臂一致 |
| 全量 | `node test.ts` 全绿（阶段收尾三件事之一） |

## 6 明确不做

- 不在库侧绕（不换词、不插 NBSP、不把正文改成 13pt）——一绕，这个缺陷就再也不会暴露。
- 不把 `sk_textlayout_new` 的签名改成"传一堆可选参数"了事；缓存键必须同步，否则会拿旧段落顶新设置。
- 不在同一阶段顺手改 `letterSpacing` 的**样式表**路径（那是另一条线，见 `emit.ts:25718` 的注释）。

## 7 需要拍板的三件事

1. **是否立项**：G31 单独一个阶段（推荐，改动集中、验收清晰），还是与 G32 合并。
2. **占用哪个阶段号**与版本号（按 AGENTS.md §2.7：一个阶段一个 patch 版本）。
3. 是否允许改 `vendor/skia_text_glue.cc`（shim）**同时**改 `src/emit.ts` 的段落缓存键——只改前者会出现
   "设置变了但缓存命中"的隐性错误，两条必须同一处提交。