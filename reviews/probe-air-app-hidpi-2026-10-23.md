# probe: demo 改走 `as-aot --air-app`，并实测 HiDPI 成因（2026-10-23）

> 用户指示：`asaotui/ui-demo` 的 demo **最好用 `--air-app` 来编译**，以启用**高分辨率
> （HiDPI）等信息**。
>
> 本文记录：改造了什么、**高分辨率被实测证明**（不是声称）、撞出的编译器缺口 **G13**、
> 以及在过程中被**变异测试抓出的两个「我自己仪器」的缺陷。
>
> 仪器：编译器 `HEAD 721e12f`；本机 `clang`；一次跑完的门：`node tools/gates.cjs`（**14/14**，
> 落盘 `reviews/gates-all-5.txt`）。

---

## 1 为什么 `--air-app` 才是「高分辨率」的正路

`--air-app <descriptor>` 把 **AIR 应用描述符**当成窗口属性的**唯一真相源**：

| 描述符里的字段 | 到构建/运行时的后果（逐条实测） |
|---|---|
| `<requestedDisplayResolution>high</requestedDisplayResolution>` | 构建 define **`ASC_DISPLAY_HIGH=1`**（在生成的 `*.build.json` 的 `defines` 里可读到）⇒ 窗口向 SDL 要**原生分辨率** drawable、渲染面按**物理像素**分配 |
| `<renderMode>cpu` | 软件光栅 + blit（`auto` 是 AIR 文档默认，回落 CPU；`direct/gpu` 走 Ganesh） |
| `<width>/<height>/<title>/<resizable>` | 初期窗口本身。**应用代码不再自己调 `Stage.showWindow`** —— `--air-app` 生成的 bootstrap 在 `new <Main>()` + `stage.addChild(app)` 之后替它调 |

**实测的硬数字**：同一个 App、两个只差上面那一行的描述符 ⇒ PNG **1050×840** vs **700×560**。
`check-dpi.cjs` 一条命令两臂都跑并断言这个 A/B（见 §4）。

改造范围（两个 demo 都走同一条路）：

| 之前 | 现在 |
|---|---|
| `ui-demo/UiDemo.as`（**顶层脚本** + `stage.showWindow`）+ `--manifest examples/window.build.example.json` | `ui-demo/demo/UiDemoMain.as`（**`Sprite` 文档类**）+ `ui-demo/air-uidemo/app.xml` |
| `ui-demo/GalleryApp.as`（顶层脚本） | `ui-demo/demo/GalleryMain.as`（`Sprite` 文档类）+ `ui-demo/air-gallery/app.xml` |
| 手写 manifest（无 HiDPI 概念） | 描述符 + `--air-app` + `--main-class` |

**为什么必须换成文档类**：`--air-app` 的 bootstrap 要 `new` 一个类，顶层脚本没有构造器；
而 mxmlc 也只认 `Sprite` 文档类。所以换完之后，**AOT 侧与 AIR 侧是同一个形状**——
登录 demo 的两份证据（`uidemo.txt` / `ui-demo-air.txt`）因此可以**逐行对读**。

窗口本身仍能看图：`ASC_NO_OPEN=1` 才是「读完判定就关窗」，默认把窗口留给人点。

---

## 2 撞出的编译器缺口：G13（闭包**不展开**强制文件发现的类）—— 当天已修

第一次用 `--air-app` 编 gallery 就死在 codegen：

```
[1/4] read  .../air-gallery/app.xml (main demo.GalleryMain, 76/96 sources reachable from demo.GalleryMain)
[3/4] codegen  emit C source
Codegen error at 11:5: unknown superclass 'Control' of 'asaot_ui_AvatarNode'
```

`Control.as` 明明在 `src/` 里（`stage-air.cjs` 还逐字节校验过拷贝）。根因**不是我的 staging**，
而是 `src/reach.ts` 的闭包**不健全**：排空循环结束后的两趟「强制文件」处理**只把类标成可达、
从不展开它**。本 kit 的**每个控件都靠小写工厂自由函数进入**（`chip.as` → `ChipNode`）⇒
**所有 `*Node` 类都在那一趟被发现** ⇒ 它们的共同父类 `Control.as`、构造器里
`Widgets.register(...)` 注册的 `kind/*Widget.as`（16 个）连 `PaintKit.as` 一起被裁。

已按工作区纪律完整登记并建钉子：

- 登记：`compiler-gaps.md` **G13**（含机制、最小复现、影响半径、逃生通道、根治方向）；
- 最小复现 `probes/reach-freefn/`（5 个文件）：闭包 **3/5**、`p/Base.as` 与 `p/Helper.as` 被裁；
- 两臂 A/B 一条命令 `node probes/reach-freefn/run.cjs`：**默认臂必红**（`unknown superclass 'Base' of 'p_Leaf'`）
  + **`--all-sources` 臂必绿**（build→link→run `EXIT 0`）；
- **变异证明有牙** `node probes/reach-freefn/mutation.cjs`：给 `Main.as` 加一行 `var leftover:Leaf;`
  把 `Leaf` 挪回主循环 ⇒ 两条闭包断言**双双变红**，还原按哈希核对逐字节一致；
- 成为 **第 11 道门**（`tools/gates.cjs`：`G13 air-app reach`）。

**处置**：当时（不改编译器源码）两个 demo 的 runner 都加了 `--all-sources` 并就地注明
「这是绕 G13 的必需项……上游修好后请重测并删掉」。

### 2.1 当天稍后：G13 被修（阶段二百四十九），复核后开关已删

编译器侧在同一工作树里修掉了根因（两趟强制文件处理**上提到排空循环之前**，且非类顶层
代码那趟由 `reachable.add(n)` 改为 `enqueue(n)`），**未提交**（`HEAD 6121b30` +
`M src/reach.ts` + `M test/unit/reach.ts`，`src/reach.ts` 哈希 `sha256[:16] = 4e855c84951f9ecb`）。

我能独立复核的（只读测量、**未改编译器**）：

| 测量 | 修前 | 修后（本次实测） |
|---|---|---|
| `node tools/reach-dump.cjs probes/reach-freefn/src p.Main` | kept **3/5**，edges 1 | kept **5/5**，edges 3 |
| `ASC_NO_OPEN=1 node ui-demo/run-gallery.cjs`（默认面，**不带** `--all-sources`） | `unknown superclass 'Control' of 'asaot_ui_AvatarNode'`，76/96 | **94/97 reachable** → 建→链→跑 → `RESULT: PASS`，4 张 1050×840 PNG |
| `ASC_NO_OPEN=1 node ui-demo/build-and-run.cjs`（默认面） | 同一个错 | `AOT-CHECK: PASS` 8/8 → `RESULT: PASS`，750×563 PNG |

⇒ 两个 runner 的 `--all-sources` **已删**（`REMOVED（阶段二百四十九）`），并写明「若这个
`unknown superclass` 再出现，那是闭包回归——去修闭包，**不要**重新加上这个开关（它会把
整包编进去，把这类回归永久遮住）」。探针语义**反转成回归钉**（`probes/reach-freefn/run.cjs`
现在断言 kept 5/5 + 默认面能建能跑），`mutation.cjs` 改为**在编译器侧撤回修法的两半**
（M1 mark-vs-enqueue、M2 顺序）来证明钉子有牙。

**一条教训**：G13 从登记到修好不到几小时，而我的文档在**同一分钟内**就陈旧了——
`ui-demo/README.md` 写成于 21:25:54，runner 的开关移除落于 21:26:36。⇒ 共享工作树里，
**文档里的「当前处置」必须紧跟最后一次实测**，不能拿几分钟前的结论当现况。
本次已把 `ui-demo/README.md`、`CONTRIBUTING-widget.md` §4.18、`STATUS.md`、`compiler-gaps.md` G13、
本文件与探针 README 全部对齐到**实测**的那一版。
⇒ 一行 `unknown superclass 'X' of 'Y'` 而 `X.as` 就在 `src/` 里、且可达数明显偏小，
**优先想 G13**（已写进 `CONTRIBUTING-widget.md` §4 第 18 条）。

---

## 3 途中被变异测试抓出的三个「仪器」缺陷（都是真的）

G13 的探针与 DPI 的 A/B 都做了变异测试，各自抓出**我自己写错的东西**——记下来，因为这两类
错误正是「看着绿、其实没在测」的典型。

### 3.1 闭包探针的弱断言：只看「出现过」，不看「在哪一段」

初版断言是「输出里出现了 `p/Base.as`」。变异（把 `Leaf` 挪回主循环）后这两行只是从
**DROPPED 段搬到了 KEPT 段**，断言**照旧绿**。⇒ 已改成**只在 `DROPPED (` 之后的那一段里找**，
变异下 2/2 全红。

### 3.2 描述符里的**注释**骗过「首个匹配」正则（两处）

描述符是**自述文件**，注释里引用了标签原文（`…除了一行 -- requestedDisplayResolution…`）。

- **runner 侧**：`descriptorWindow()` 用首个正则匹配 ⇒ 会把**注释里的**值当成真值。
  在本仓当前文本下恰好同值，所以**从来没暴露**；一旦有人只改真标签，runner 就会读错。
- **变异机侧**：`mutation-dpi.cjs` 的 `replace()` 命中的**就是注释**——注释翻成 `high`、
  真标签还是 `standard`。于是探针为**另一个原因**变红（「描述符说 high 但 manifest 没有
  define」），**不是**在验证「两臂相同」。**一个没打在它声称的地方的变异，比没有变异更糟：
  它认证了错的东西。**

⇒ 统一修法：`air-run.cjs::blankComments()` 在匹配前把注释**抹成等长空格**（保住字节偏移，
于是调用者仍能取到 span 并**原样拼回**文件）；`initialWindowBlock()` 用它取块，
变异机用它的偏移做**定点拼接**，并额外断言「变异后的块确实说 high、原块确实说 standard，
否则拒绝跑」。

### 3.3 顺带：`--air-app` 的 HiDPI 断言原本会**误杀分数缩放**

`sx !== sy` 这种「两轴严格相等」的写法，在 500×375 @150% 上必然翻车（375×1.5 = 562.5 ⇒ 563）。
⇒ 改为**共享实现** `air-run.cjs::checkShot()`：两轴允许相差 ≤ 1 物理像素、每轴必须是
「逻辑 × 设备缩放」**四舍五入到整像素**（这正是窗口系统的行为），且 **1× 只在描述符说
`high` 时才算问题**（否则 `standard` 臂会被自己的控制组判红）。

### 3.4 顺带记一条：G13 的变异从「改输入」搬到了「改编译器」

修前，缺陷可以用**输入**制造（给 `Main.as` 加一行 `var leftover:Leaf;` 就把 `Leaf` 挪回
主循环那趟）——那是**无损**的变异。修后输入侧再也造不出这个形状了，于是 `mutation.cjs`
改为**写 `as3compiler/src/reach.ts`**（两个变异各自撤回修法的一半），`finally` 还原 + 哈希核对。
⇒ 这条变异**碰了编译器仓库**，在**共享工作树**里是有真实风险的：若另一个会话正在编辑
`src/reach.ts`，还原步骤会把它的在飞改动覆盖掉。已在探针 README 写明了这个危险与
「只能在静止的树上跑」。

---

## 4 HiDPI 的成因证明（不是相关，是因果）

单臂测出「1050×840」只说明**这一次**是高分辨率；要证明**是那一行描述符导致的**，
必须做**单侧变异**。`ui-demo/check-dpi.cjs` 一条命令跑两臂（同一份 AS3、同一个 700×560 逻辑舞台）：

| 臂 | 描述符 | PNG | 设备缩放 | tour |
|---|---|---|---|---|
| HIGH | `air-gallery/app.xml`（`high`） | **1050×840** | 1.5 | exit 0 |
| STANDARD | `air-gallery-standard/app.xml`（`standard`） | **700×560** | 1 | exit 0 |

并且：**两次 tour 的文本逐字节相同**（3033 B，`sha256[:16] = 18dc0f9adeca927a`）。
⇒ 那一行只改**像素密度**，**一个逻辑坐标都没动**——这正是「应用代码永远用逻辑坐标、
高分辨率由后端负责」的含义，也是这两张图能当证据的原因。

**前置校验**：`check-dpi.cjs` 先比对两个描述符的 `<initialWindow>` 块（把 resolution 值
归一化掉）**必须逐字节相同**，否则**拒绝跑**——「一变因」是实验有效性的前提。
（这个前置校验**当场抓到** control 臂原本还多差一个 `<title>` ⇒ 已改成完全相同。）

**变异证据**（`node ui-demo/mutation-dpi.cjs`，把 control 臂也改成 `high`）：

```
  HIGH      high      stage 700x560  ->  PNG 1050x840   scale 1.5   tour exit 0
  STANDARD  high      stage 700x560  ->  PNG 1050x840   scale 1.5   tour exit 0
  tour text: IDENTICAL (3033 B, to the byte)
RESULT: FAIL
  STANDARD arm rendered at 1.5x; <requestedDisplayResolution>standard must be 1x
  HIGH and STANDARD produced the same PNG size (1050x840): the descriptor line changed nothing, so it is not the cause
==== MUTATION: PASS -- the mutant makes check-dpi go red (check-dpi has teeth) ====
mutator: air-gallery-standard/app.xml restored  3c68d5b42fdf94aa  (identical)
```

两臂在 **1× 的显示器上会同为 1×** ⇒ 那时 `check-dpi.cjs` 报 **`RESULT: INCONCLUSIVE`**
（并解释原因、仍以 0 退出），而不是谎报通过。

---

## 5 收尾对照（命令 → 期望）

| 命令 | 期望 | 本次实测 |
|---|---|---|
| `node tools/gates.cjs` | **15/15 PASS** | 15/15，[`gates-all-7.txt`](gates-all-7.txt)（第 15 道门是本次新增的 fingerprint porcelain 解析钉子） |
| `cd ui-demo && ASC_NO_OPEN=1 node run-gallery.cjs` | gallery tour PASS + 4 张 1050×840 PNG | PASS（写在 `air-gallery/`；日志 [`gallery-post-g13-2026-10-23.txt`](gallery-post-g13-2026-10-23.txt)） |
| `cd ui-demo && node check-dpi.cjs` | standard 1× vs high 1.5×，tour 文本逐字节相同 | PASS（日志 [`dpi-ab-2026-10-23.txt`](dpi-ab-2026-10-23.txt)） |
| `cd ui-demo && ASC_NO_OPEN=1 node build-and-run.cjs` | 8 项断言 + 750×563 PNG | PASS（日志 [`uidemo-post-g13-2026-10-23.txt`](uidemo-post-g13-2026-10-23.txt)） |
| `node probes/reach-freefn/run.cjs` | 默认面绿（kept 5/5）+ `--all-sources` 臂仍绿 | PASS |
| `node tools/fingerprint-parse-check.cjs` | 20 项全绿（含两条前导空格回归断言） | PASS；变异 [`mutation-fingerprint-parse-2026-10-23.txt`](mutation-fingerprint-parse-2026-10-23.txt) |
| `node tools/compiler-fingerprint.cjs` | 报「上游并发工作」而非我方改动 | 见 §6 |

## 6 与编译器仓库的边界
本次**没有改动 `asaotui/../as3compiler/` 的任何源文件**（用户指令：不动编译器）。指纹复核
`node tools/compiler-fingerprint.cjs` 报的是**上游并发工作**，不是我的：

- `HEAD` 已从 `721e12f` 前移到 **`6121b30`**（`fix(codegen): Boolean() 在 Object 槽上补解箱（阶段二百四十八 · G9）`）；
- 工作树另有**未提交**的 `M src/reach.ts` + `M test/unit/reach.ts`——那正是**阶段二百四十九的 G13 修复**（含它自己的单元测试），由编译器侧完成，我只做了**只读复核**。指纹已在 21:42 重新基线化到这 3 条（`treeFingerprint 40048261434941b7f6b4`，当场再跑一次报 `UNCHANGED`）；**几分钟后它又报红**：`content changed: test/unit/reach.ts`——对方还在改他们的单测。这正是工具该做的事。关键是**我复核所钉的那一版未变**：`src/reach.ts` 仍是 `sha256[:16] = 4e855c84951f9ecb`（mtime 21:25:29）⇒ 本文所有测量对**该修订**成立。
- ⇒ 要判定「我有没有碰过编译器」，看的是 `git status` 里那几项的**内容与归属**，不是哈希差异本身。**同时记住：这个工作树有并发会话**（编译器侧同时在改 `as3compiler/`，也顺手校正了本文件的阶段号）⇒ 「零改动」「当前处置」这类断言必须**当场重测**，不能拿几分钟前的结论当现况（§2.1 末尾那条教训就是同一件事）。

### 6.1 顺着这件事抓出并修好了**我自己的一个仪器缺陷**（很典型，所以写下来）

指纹工具第一次报的是「**2** files」——而 `git status` 明明有 **3** 条，少的正是 `src/reach.ts`
（整件事的主角）。根因：工具用了

```js
const git = (...a) => execFileSync('git', ['-C', REPO, ...a], {encoding:'utf8'}).trim();
//                                                                        ^^^^^^^ 元凶
for (const line of status.split(/\r?\n/)) { code = line.slice(0,2); f = line.slice(3); ... }
```

`.trim()` 抹的是**整个缓冲区**的首尾空白，而“仅工作区修改”的那一行**开头就是一个空格**
（`" M src/reach.ts"`）⇒ 首行每个字段左移一位，路径被切成 `rc/reach.ts`、`existsSync`
为假，于是**不声不响地丢掉**。**仪器少报比没仪器更糟**：它认证了一个并不在盘上的状态。

已修：改用 `git status --porcelain -z`（NUL 分隔，路径不被引号/转义，可定点切割），
并把无法解析的记录**大声报错**（exit 2）而不是静默跳过。
钉子：`tools/fingerprint-parse-check.cjs`（20 项：工作区修改/已暂存/`MM`/删除/带空格的路径/
空输出/重命名/以及两条**“前导空格不得丢”**的回归断言）；变异：`tools/mutation-parse.cjs`
把解析器改回「逐条 trim」⇒ 4 项变红（含输出里真的出现 `"f":"rc/reach.ts"`），还原哈希一致。
落盘 [`reviews/mutation-fingerprint-parse-2026-10-23.txt`](mutation-fingerprint-parse-2026-10-23.txt)。

我的产出全在 `asaotui/`：两个 demo 的描述符/文档类/runner、`stage-air.cjs`（把 `seam` + `kit` + `demo`
实体拷进 `<appDir>/src`，逐字节校验）、`air-run.cjs`（共享管道）、`check-dpi.cjs` + `mutation-dpi.cjs`、
G13 探针与登记。G13 的**根因修复不是我做的**（用户指令：不动编译器），我只把它登记成 G13、
建了最小复现与回归钉；修好之后我复核并把所有「必须加 `--all-sources`」的文档改回实测的那一版。

**遗留偏差**：编译器仓库根留下两个未跟踪产物——`ReachFreeFn.exe`（探针同名输出，来自某次
以编译器目录为 cwd 的构建）与 `icudtl.dat`（10 MB，构建就近拷的数据文件，mtime 10-09）。
前者**已删**（5.8 MB，名字可证明是本探针的输出）；后者无法证明属于本次工作，**保留并报明**
（它仍在基线里）。`icudtl.dat` 在**探针目录**里也有一份拷贝 ⇒ 构建会把数据文件拷到 cwd，
即 `CONTRIBUTING-widget.md` §4.13 那类「cwd 相对路径写进源码树」的陷阱。
