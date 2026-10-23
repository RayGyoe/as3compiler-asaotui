# probe: G13 —— `--air-app` 闭包**不展开**强制文件发现的类（2026-10-23，**已修**）

> **本文是「修前」的完整登记（2026-10-23 上午）。当天稍后，编译器侧在同一工作树里
> 修掉了它（阶段二百四十九），本工作区已独立复核：**
>
> | 测量 | 修前 | 修后 |
> |---|---|---|
> | `tools/reach-dump.cjs probes/reach-freefn/src p.Main` | kept 3/5，edges 1 | kept **5/5**，edges 3 |
> | 探针默认臂（`--air-app`，不带 `--all-sources`） | 红：`unknown superclass 'Base' of 'p_Leaf'` | 绿：建→链→跑 `EXIT 0` |
> | gallery demo（默认面） | 红：`unknown superclass 'Control' of 'asaot_ui_AvatarNode'`（76/96） | 绿：**94/97**，`RESULT: PASS` |
> | login demo（默认面） | 红：同一个错 | 绿：`RESULT: PASS` |
>
> ⇒ 下文所有「当前处置：附加 `--all-sources`」**均已被取代**（两个 runner 已移除该开关）；
> `probes/reach-freefn/run.cjs` 的断言已**反转成回归钉**（kept 5/5 + 默认面能建能跑），
> `mutation.cjs` 改为**在编译器侧撤回修法的两半**（M1 mark-vs-enqueue、M2 顺序）来证明有牙。
> 复核所用 `src/reach.ts` 为**未提交**状态：`HEAD 6121b30` + `M src/reach.ts`，
> 哈希 `sha256[:16] = 4e855c84951f9ecb`。

> 命题（**修前**）：`as-aot --air-app <descriptor>` 的**类引用闭包**会把「首次由**强制文件**
> （含自由函数/模块语句的文件）发现的类」标为可达却**从不展开**，于是它的父类与被
> 引用类被裁掉，构建在 codegen 阶段报 `unknown superclass`。
>
> 仪器：编译器 `HEAD 721e12f`；本机 `clang`；探针 [`../probes/reach-freefn/`](../probes/reach-freefn/)；
> 闭包转储 [`../tools/reach-dump.cjs`](../tools/reach-dump.cjs)（直接 `import` 真实
> `src/reach.ts` 的 `prepareReachFiles`/`computeReachable`，**不是重写一遍闭包逻辑**）。

---

## 1 起因：demo 改用 `--air-app` 后构建停住

用户指示 demo 一律用 `--air-app` 编译，好让 **AIR 描述符**当窗口属性的唯一真相源
（`<requestedDisplayResolution>high</requestedDisplayResolution>` ⇒ 高分辨率）。
`ui-demo` 的多页画廊按此改造（`run-gallery.cjs` + `air-gallery/app.xml` +
`demo/GalleryMain.as`，见 `ui-demo/README.md`）后，构建报：

```
[1/4] read        .../air-gallery/app.xml (main demo.GalleryMain, 76/96 sources reachable from demo.GalleryMain)
[3/4] codegen     emit C source
Codegen error at 11:5: unknown superclass 'Control' of 'asaot_ui_AvatarNode'
```

「76/96」与「`Control` 不存在」是两条互相印证的线索：**`Control.as` 明明在
`src/` 里**，却像不存在。第一反应会怀疑「staged 目录没拷进去」或「包名没解析」，
两者都错——实测两者的否定证据如下。

| 假设 | 证否方式 | 结果 |
|---|---|---|
| kit 没被 stage 进 `src/` | `stage-air.cjs` 每次打印拷贝清单与内容哈希（`4 seam + 87 kit + 5 demo = 96 .as units`），且 `Control.as` 在清单内 | **否定** |
| 包名/短名解析不了 `Control` | 闭包转储直接打印**解析后的 AST** 声明：`DECL asaot/ui/Control.as name=Control pkg=asaot.ui extends=Element fileId=asaot_ui_Control` —— 声明在、包名对 | **否定** |
| 闭包把它裁了 | 转储 kept/dropped 两张表 | **成立**（`Control.as` 在 DROPPED） |

于是问题从「我 staging 错了」变成「**闭包本身不健全**」，改为直接对闭包取证。

---

## 2 闭包层的取证：3/5，漏的恰好是父类与被引用类

最小复现（[`../probes/reach-freefn/`](../probes/reach-freefn/)）刻意做成**只有 5 个文件**、
且 `Main.as` **不出现任何类型名**（连 `var l:Leaf;` 都不写——一写 `Leaf` 就走主循环，
缺陷当场消失，这正是 `mutation.cjs` 用的变异）：

```
src/p/Main.as    document class；只调 make()，不提任何类型
src/p/Fac.as     自由函数 make():Leaf —— 唯一特殊之处：它让这个文件成为「强制文件」
src/p/Leaf.as    class Leaf extends Base，构造器里 new Helper()
src/p/Base.as    Leaf 的父类          -> 被裁
src/p/Helper.as  只被 Leaf 构造器引用  -> 被裁
```

`node tools/reach-dump.cjs probes/reach-freefn/src p.Main`：

```
main=p.Main  kept 3/5  edges 1
roots: p.Main
KEPT (3):
  p/Fac.as
  p/Leaf.as
  p/Main.as
DROPPED (2):
  p/Base.as
  p/Helper.as
```

**`edges 1` 是关键数字**：整条闭包只走出了 **一条**边（`Fac.as` 的自由函数 → `Leaf`）。
`Leaf extends Base` 与 `new Helper()` **一条都没走**。⇒ `Leaf` 被标记可达、被发射，
但它的引用**从未被收集**。

---

## 3 构建层：同一条命令，报错文案与图纸一致

```
$ node src/index.ts --air-app probes/reach-freefn/app.xml --main-class p.Main --cc clang
[1/4] read        ... (main p.Main, 3/5 sources reachable from p.Main)
[3/4] codegen     emit C source
Codegen error at 8:5: unknown superclass 'Base' of 'p_Leaf'
```

报错**不是静默吞错**（AGENTS.md §2.5 的底线守住了），也**不是**在 C 编译器里才炸——
它在 codegen 就定位了。但报错**指向一个我们没写过的类型**（`p_Leaf` 的父类），
这正是「闭包漏集」的典型指纹：使用者的源代码与报错文案对不上。

---

## 4 逃生通道的 A/B：同源、同描述符，只差一个开关

```
arm A: --air-app app.xml --main-class p.Main              -> exit 1, unknown superclass 'Base'
arm B: --air-app app.xml --main-class p.Main --all-sources -> exit 0, builds + links
                                                              RUN: exit 0, "ReachFreeFn rendered"
```

`--all-sources` 是**文档化的**逃生通道（恢复阶段一百二十四之前的「整包编译」面）。
⇒ 缺陷在**剪枝**，不在源码；也顺手证明了「**该源码本身是合法的**」。
两臂由 [`../probes/reach-freefn/run.cjs`](../probes/reach-freefn/run.cjs) 一条命令
同时断言（默认臂**必须红**、`--all-sources` 臂**必须绿**），此处结论可一键复跑。

---

## 5 为什么判成「遗留欠账」而不是「平台边界」

`src/reach.ts` 自己在文件头承诺：闭包**必须是 `mxmlc` 闭包的超集**（宁可过度近似也不漏）。
而 `mxmlc` 并**没有**这道剪枝——它编整个包。这里得到的闭包是**漏集**（漏掉父类与被引用类），
即**违背了模块自己写下的健全性承诺**。按 AGENTS.md §1.5：
`adl`/`mxmlc` 能跑对、我们跑不出 ⇒ **遗留欠账**。⇒ 登记 G13，不降级、不静默。

**影响半径**（比探针更大）：任何「**用自由函数当工厂/入口**」的 AIR 应用都会踩。
本项目 kit 把**每一个控件**都做成小写工厂自由函数（`chip.as` → `ChipNode`），
于是**所有 `*Node` 类都只在那一趟被发现**：`Control`（共同父类）与
`kind/*Widget.as` ×16（构造器里 `Widgets.register(...)` 注册的）连同 `PaintKit.as`
一起被裁。整棵 demo 树 **76/96**。

---

## 6 变异测试：这套断言有牙

`node probes/reach-freefn/mutation.cjs` —— 只改**输入**（给 `Main.as` 加一行
`var leftover:Leaf;`），让 `Leaf` 从「强制文件那趟」挪回「主循环那趟」，
缺陷理应消失、断言理应变红：

```
mutator: Main.as  ca52fdedf4ca2210 -> 307606db80b69d2b
     main=p.Main  kept 5/5  edges 3
  FAIL closure keeps 3/5 files (expect 3: Main, Fac, Leaf)
  FAIL closure DROPS p/Base.as and p/Helper.as (the defect)
==== MUTATION: PASS -- the mutant makes the probe go red (probe has teeth) ====
mutator: Main.as restored  ca52fdedf4ca2210  (identical)
```

变异机**还把一条弱断言揪了出来**（这正是变异测试的价值）：初版检查「输出里出现
`p/Base.as`」，变异后这两行只是从 DROPPED 段**搬到了 KEPT 段**，断言**照旧绿**。
已改成**只在 `DROPPED (` 之后的那一段里找**，于是变异下 2/2 全红。
变异机以 `finally` 还原并**用哈希核对还原是否逐字节一致**——留变体的变异机会污染后续每一次运行。

---

## 7 结论与处置

| 项 | 结论 |
|---|---|
| 定性 | **遗留欠账**（闭包漏集，违背模块自述的「⊇ mxmlc 闭包」承诺）；不是平台边界，不是我的 staging 错 |
| 症状指纹 | **`unknown superclass 'X' of 'Y'`，而 `X.as` 明明在 `src/` 里**；`N/96 sources reachable` 里 N 明显偏小；报错点名使用者没写过的类型 |
| 当前处置（**已过期，见顶部横幅**） | 修前：**不改编译器源码**（用户指令），两个 runner 一律 `--air-app + --all-sources`。⇒ **现在：已修（阶段二百四十九），开关已删——默认面才是测试面** |
| 持续看住 | `tools/gates.cjs` 的 **G13 air-app reach** 门（跑 `node probes/reach-freefn/run.cjs`，一条命令三测量）；修后它是**回归钉**（默认面必须能建能跑），不再是「默认臂必红」 |
| 根治方向（已按此修好） | 把那两趟强制文件处理**挪到排空循环之前**，并在非类顶层代码那趟把 `reachable.add(n)` 换成 `enqueue(n)`。需要的不变式是一句话：**任何可达的类，其引用都必须被收集**，无论它由哪一趟发现 |
| 证据 | 本文 + [`../probes/reach-freefn/README.md`](../probes/reach-freefn/README.md) + `run-2026-10-23.txt` + `mutation-2026-10-23.txt` + [`../tools/reach-dump.cjs`](../tools/reach-dump.cjs) |
