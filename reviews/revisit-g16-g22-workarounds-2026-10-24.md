# G16/G19/G20/G21/G22 修好之后：库内临时应对审计（2026-10-24）

编译器的这五条缺口现在都已修好（`dccab94` = G16/G19/G20，阶段 266–268；
`07ed035` = G21/G22，阶段 269–270；本工作区的复核树 HEAD `d82d199`）。
当时为了绕开它们，UI 库里写过一些**非自然写法**与**失去意义的注释**。本文逐处复核：
**哪些能撤、哪些不该撤、哪些根本不是绕行**，以及一条容易忽略的副作用 ——
**某道变异钉子是靠缺陷取牙的，缺陷修好后它自己变成了绿跑**。

结论先行：

| 缺口 | 库内当时的应对 | 现在怎么办 | 为什么 |
|---|---|---|---|
| **G16** `cond ? null : X` 条件为假时塌成结果类型零值 | 7 个文件里改成 `if/else`；注释写「绝不能用三元」 | **4 处换回三元**；3 处 `if (opts.x != null)` **保留并改写注释** | 前者是语法绕行，没有理由留下；后者不是绕行，是「作者给了值才覆盖默认」的最短写法 |
| **G19** `drawRoundRect` 忽略半径 | **无代码绕行**（库一直把半径传给引擎，只是画出来是直角）；探针把直角像素钉成期望值 | 无需回退；探针期望像素与一句陈旧注释已改 | 库从没绕开它 ⇒ 修好后圆角自动出现，正是当初钉这个像素的目的 |
| **G20** `setTextFormat` 追加 run 而非替换范围 | `InputWidget.paint` **不调** `setTextFormat`；`PaintKit.measureField` 照调（依赖替换语义） | 注释改写：从「禁令」变「设计选择」；`measureField` 加注指回本条 | 单格式字段本来就只有一套格式，不调是合理的；禁令的前提消失后，文字必须跟上 |
| **G21** `getTextFormat()` 忽略 run 表 | **无绕行**：全库 0 个调用点 | 无 | 没人用过，就没有绕法 |
| **G22** 闭包内静态读丢 `_cinit()` 守卫 | 7 个常量类的 `warmUp()` + 首帧前调一次 | **已随修复删除**（本轮全仓复核 0 命中） | 纯脚手架，修复后只会污染作者模型 |

---

## 1. G16：4 处换回三元，3 处守卫保留

`cond ? null : X` 的毛病是 **null 字面量在 THEN 槽**时，条件为假不返回 `X`，
而是塌成结果类型的零值（`object`→null、`Number`→0、`Boolean`→false，
`String` 免疫）。当时的对策是「凡这类形状，一律写成 if/else」。

修复后（阶段 266，`unifyType` 补了 null 家族规则）这个形状是正确的，
而 `probes/g16-ternary-null` 的 **AOT 偏离集已清空**——门要求偏离集**恰好等于**
已登记集，所以空集意味着「任何一格重新变坏都会当场变红」。这就是可以放心把
语法绕行撤掉的依据。

**换回三元的 4 处**（都是「条件成立就给个默认值，否则在对方基础上打补丁」）：

| 文件 | 现在 |
|---|---|
| `kit/asaot/ui/kind/ImageWidget.as` | `bitmapOf`：`return o == null ? null : Bitmap(o);` |
| `kit/asaot/ui/table.as` | 单元格取值 `rowValue == null ? null : rowValue[key]`（**这一行就是当初发现问题的地方**） |
| `kit/asaot/ui/breadcrumb.as` | `n.style = n.style == null ? dirRef : n.style.withPatch(dirRef);` |
| `kit/asaot/ui/pagination.as` | 同上（stepper 方向的默认样式） |

**保留的 3 处**：`combo` / `datePicker` / `virtualList` 的
`if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);`。
这**不是**绕行——它表达的是「选项缺省时不覆盖节点自身默认值」，比
`n.onSelect = opts.onSelect == null ? n.onSelect : (opts.onSelect as Function);`
短得多也直白得多。它们原来的注释写的是「G16 规则：绝不能用三元」，在修复后是
**错误信息**（会让人以为编译器还有这个坑），已逐处改写成
「这个形状曾中招、已修、钉在哪」。

顺带一个反证：同类形状在本库里一直有**未改写**的活样本
（`PanelShellWidget.as:128`、`UiApp.as:458/557` 的 `cond ? null : value`），
它们从没出过问题——因为**所有中招的格子都是 null 字面量在 THEN 槽**。
这次没有动它们，正说明「缺口与 null 在哪一侧强相关」这条登记判断是对的。

## 2. G19：没有代码可撤，只有一句话在自相矛盾

`asaot.ui` 从不绕开 `drawRoundRect`：`PaintKit.drawBox/drawBoxFor` 一直把
`r * 2` 传给引擎，只是在旧编译器上画出来是直角。所以修复后**圆角自动出现**，
库代码零改动。

当初的「应对」只有探针：`probes/widgets/motion` 把 `(20,20)` 钉成直角颜色
`#3366cc`，并注明「若此像素变白说明 G19 已修」。修复提交里已把期望值改成
`#ffffff`（半径 12 的圆角把角落切掉了，露出根背景）。

本轮发现的是**残留的文字矛盾**：同一个 `Main.as` 里，上方注释还写着
「G19: drawRoundRect ignores it, so there is no pixel to read」，而文件末尾
断言的恰恰就是这个像素。修好之后这句话不只是过时，而是**把人往反方向带**
（会让人以为末尾那条断言是废的）。已改写为「修好后它也成了像素，就是下面这条断言读的」。

`compiler-gaps.md` 的 G19 条目新增一行，写明「库侧无绕行 ⇒ 无需回退；唯一改动的是
探针期望值与这句注释」，免得以后有人去找并不存在的回退点。

## 3. G20/G21：一条「禁令」降级为「设计选择」，以及一颗变哑的钉子

### 3.1 禁令 → 选择

旧运行时的 `TextField.setTextFormat` 是**追加 run**（不是替换范围），排版器又对
每条 run 都 `addText` 一遍字符串 ⇒ `InputWidget.paint` 每帧调一次，
文本就被画 N 遍（用户看到的「失焦再聚焦，字复制了一遍」）。

当时的库里写了「单格式字段**一律不调** `setTextFormat`」。修复后（阶段 268，
setter 改为重建 run 表）这句话作为**禁令**已经不成立：再调也只是每帧多做一次
无用的 run 表重建。但作为**设计选择**它仍然成立——单格式字段由
`defaultTextFormat` + `textColor` 就描述完了，run 表只在富文本（`htmlText` /
逐段格式）时才需要。

所以处置是**改注释、不改代码**：

- `kind/InputWidget.as` 文件头「defect b」与 `paint()` 里的注释改成
  「G20 已修（阶段 268）；这里不调是设计选择，如今调它只是每帧多余的工作量」；
- `PaintKit.measureField`（唯一的调用点，**测量路径**，不在 paint 路径上）
  补一条注释：它依赖**替换**语义，G20 的修复保证重复测量不会累积 run。

### 3.2 真正的发现：`typing` 的 M3 修好之后自己变绿了

`probes/widgets/typing/mutation.cjs` 的 M3 原本是：

```
find:     n.tf.textColor = uint(color);
replace:  n.tf.textColor = uint(color);\n            n.tf.setTextFormat(f);
expect:   "(runs accumulated)"
```

它的**取牙原理就是 G20**：让 widget 重新调 `setTextFormat`，靠运行时的追加
行为把文本撑宽。G20 修好后，这条变异**不再制造任何缺陷**，于是：

```
M3  MISSED (THIS IS BAD)  ...
     verdict: RESULT: FAIL  MISSING the expected failure line "(runs accumulated)"
```

（程序其实仍然红了，但红的是别的断言——它已经不在测自己想测的东西。）
这正是「钉子的前提会随修复蒸发」的典型：**修好一个缺陷，可能让某道门悄悄失去牙**，
而门本身不会报错。

处置：**重指**（re-point）而不是删除。M3 现在把字符串**写两遍**：

```
find:     if (n.tf.text != shown) n.tf.text = shown;
replace:  if (n.tf.text != shown) n.tf.text = shown + shown;
expect:   "the final frame shows"
```

实测 `FAIL the final frame shows '1111911119' not '11119'` ⇒ **4/4 CAUGHT**，
restore 仍逐字节一致。理由写在 `why` 里：这条钉子守护的契约是「字段里永远只有一份
模型文本」，而当初只是**借 G20 的缺陷**来制造两份；契约没变，制造手段换掉即可。
这与上一轮 G16 变异的重指是同一手法（`reviews/revisit-g8-g9-workarounds-2026-10-23.md`）。

同时把探针里那句诊断文案 `(runs accumulated)` 改成
`(more than one copy of the string)`：旧文案把**结论**写死了（现在不一定是 run 累积）。

### 3.3 G21：零调用点

全库 `getTextFormat()` 调用点 **0 个**（`kit/`、`ui-demo/` 均无）⇒ 没有绕行可撤，
也没有「读回来 = 我设的值」的旧假设需要复查。修复的价值在于作者以后可以这么写，
`probes/g21-gettextformat`（30 格）与 `probes/g20-settextformat`（12 格）已经把
AIR 口径钉成断言。

## 4. G22：`warmUp()` 脚手架确认清零

旧绕行是每个只用闭包读静态常量的类加一个 `public static function warmUp(): void`
（读一遍静态字段，逼出 `_cinit()`），再由 `DocsMain` 在首帧前统一调用一次。
修复提交（阶段 269）已连同调用一起删除。

本轮用脚本全仓扫描 `warmUp`（`*.as` / `*.md` / `*.cjs`，排除 `node_modules`/`.git`/`.scratch`）：
**命中 2 处，都是历史叙述**（`compiler-gaps.md` 的 G22 条目、`probes/g22-closure-statics/README.md`
的「已随修复删除」）。代码里 0 处 ⇒ 确认清理完毕，无需动作。

## 5. 明确**不撤**的相邻事项

审计时最容易误伤的，是那些「看起来像绕行、其实不是」的写法。逐条钉住，免得下一轮再翻：

| 写法 | 为什么留 |
|---|---|
| `if (opts.x != null) n.x = ...`（全库工厂） | 见 §1：这是选项守卫的惯用最短写法，与 G16 无关 |
| `OptionSupport` / `OverlayList` 的**类静态**辅助函数 | mxmlc 解析不了包级自由函数（AS3 语义，不是缺口） |
| `settled` 代替 `final`、`(x as Function)` 代替 `Function(x)` | AS3 保留字 / 强制转换语义（不是缺口） |
| `InputWidget.paint` 不调 `setTextFormat` | 见 §3.1：现在是设计选择 |
| 10 处 `*` 绑定读、`bindTo` | 上一轮已复核：`*` 是省一次装箱的性能默认（G9 修好后仍成立） |
| G3（Tab 环上限 64） | **仍是活缺口**，库内仍在文档里如实报明，不假装可绕 |

另外扫了 `staging/`（30 个文件的另一个移植副本，只有 avatar/badge/card/divider/progress/
radio/slider/toggle/list/tabs 这十个简单控件）：`G16`~`G22` / `setTextFormat` / `warmUp`
均 **0 命中**，无需同步。

## 6. 重跑证据（本轮，全部在本机实测）

| 项 | 命令 | 结果 |
|---|---|---|
| G16 两臂 | `node probes/g16-ternary-null/run.cjs` | **20/20 一致，AOT 偏离集为空**，变异 4/4 |
| G19 圆角 | `node probes/g19-roundrect/run.cjs` | **292 行逐字节相同 / 27 行在 AA 容差内 / 0 行分歧 / 40 行已登记** |
| G20 run 替换 | `node probes/g20-settextformat/run.cjs` | **12 格关系式两臂全绿** |
| G21 读回 | `node probes/g21-gettextformat/run.cjs` | **30 格两臂逐字相同（0 分歧）** |
| G22 闭包静态 | `node probes/g22-closure-statics/run.cjs` | **10 格一致** + 生成 C 审计通过 |
| 打字探针（含重指的 M3） | `node probes/widgets/typing/mutation.cjs` | baseline PASS，**4/4 CAUGHT**，restore 逐字节一致 |
| 受影响控件探针 | `node tools/probe.cjs probes/widgets/data` / `media` / `motion` / `scrollbar` | **77 / 43 / 23 / 44 checks，0 failures** |
| 真实文档站 | `cd ui-demo && node run-gallery.cjs` | **41 页 / 5541 节点 / badPages=0 / overflowingBlocks=0 / PASS**（4 处三元回退跑的就是这份代码） |
| 全量门 | `node tools/gates.cjs` | **37/37 PASS**（`reviews/gates-all-21.txt`）——本轮把 **G21/G22 正式接进门**（此前只有探针、没有绊线，修复不会被全量门守到） |

## 7. 这一轮学到的

1. **缺陷修好后要反向审计「测试的牙」。** 门变红会叫人，门**变哑**不会。凡变异是
   「重新引入某个已修缺陷」的，修复那天必须重跑变异并确认它仍然 CAUGHT；
   若变绿，就重指到**契约**而不是缺陷。
2. **注释也会过期，而且过期的注释比没有更糟。** 「绝不能用三元」「drawRoundRect
   ignores it」在修复后都是把人往反方向带的信息，属于必须清掉的资产。
3. **`if (x != null)` 与 `cond ? null : x` 不是同一件事。** 前者是惯用法，
   后者才是有问题的形状；一刀切地「禁三元」会把惯用法也一起冤枉掉。
4. **能撤的语法绕行一定要撤。** 留着写 `if/else` 的代码，下一位读者会以为
   编译器还有这个坑，然后把新代码也写成旧形状——缺口会以注释的形式永生。
