# air-check —— 「这个库能不能在 AIR 上跑」

回答一个问题：**`asaotui` 的 UI 库（含布局）能不能用 `mxmlc` 编、用 `adl` 跑。**
结论：**能，而且是逐值一致地能。**

接缝之所以画在 **AS3 interface 层**（`../seam/README.md`），就是为了这个：整库是纯 AS3、不调任何宿主 C 函数，
所以 AIR 工具链可以完整编译并运行它。这个目录把这句话变成了实测。

## 用法

```bash
export AIRSDK_HOME=/d/Adobe/Flex_Sdk/AIRSDK_51.4.1        # 本机装的 AIR SDK 51.4.1

cd asaotui/air-check
"$AIRSDK_HOME/bin/mxmlc.bat" -output=aircheck.swf -source-path=../seam AirMain.as
node run-adl.cjs app-air.xml 90000        # 带超时地跑；结果落在 air-out.txt
```

`Hello.as` / `app.xml` 是最小冒烟（只证工具链通），`AirMain.as` / `app-air.xml` 才是跑库的那个。

## 结果（本机实测）

```
AIR-CHECK air=51.4.1.1 (mxmlc -> adl)
---- 105 checks, 0 failures ----
RESULT: PASS
```

105 行 `GOT` 与 [`../diff-check/`](../diff-check/) 的另外两条臂**逐字符相同**：

| 臂 | 工具链 | 引擎 |
|---|---|---|
| Yoga | clang → native | Yoga（C） |
| AOT | 我们自己的 AOT → C → native | `As3LayoutEngine`（纯 AS3） |
| **AIR** | **mxmlc → adl** | **`As3LayoutEngine`（纯 AS3）** |

⇒ 三方 105 行 `GOT` 逐字符一致。**同一份 `.as` 源码，两条工具链同一份数值。**

## mxmlc 比我们更严的一条（实测发现，已写进代码）

加上 P1~P8 后 `mxmlc` 报了 `重复的 variable 定义: remaining`——AS3 的 `var` 是**函数级作用域**，
同一函数内不得重复声明。同名的 `remaining` 在 `layoutFlow` 里既用于交叉轴行间距、又用于主轴分布，
**我们的 AOT 没报错编过去了**，AIR 臂当场拦下。已将两者改名为 `remainingCross` / `remainingMain`。
⇒ 这是「AS3 语义差异」而非「AIR 特有行为」，但正是三臂并行才能让它暴露；
以后写引擎代码时，同一函数内不要重复 `var` 同名变量（AOT 不拦）。

## 三个 AIR 专属的坑（都实测过，写下来省下一次重复踩）

1. **`adl` 不会自己退出。** AIR 应用默认常驻事件循环，不调
   `NativeApplication.nativeApplication.exit()` 就永远不返回 —— 实测挂到 **900 秒被杀**。
   `run-adl.cjs` 用 `child_process` 的 `timeout` 兜底（本机没有 `timeout` 命令）。
2. **`trace()` 的输出进不了 Windows 上 `adl.exe` 的 stdout**（无控制台附加）。
   ⇒ 结果**必须由程序自己写文件**（`File.applicationDirectory` + `FileStream`，`FileMode.WRITE`）。
   `adl.log` / stdout 一直是空的，别以为「没输出=没执行」。
3. **`adl` 的 cwd 是 `app.xml` 所在目录**，不是启动它的 shell 的 cwd。写相对路径时要按这个算。

## dogfooding 发现

### 1. `System.exit()` —— AIR **有**（签名 `exit(code:uint):void`），我们**没有**

> **前提先排除掉（用户 2026-10-22 纠正）**：AS3/AIR 里**惯用的退出调用不是 `System.exit`**，而是
> ```as3
> import flash.desktop.NativeApplication;
> NativeApplication.nativeApplication.exit();
> ```
> **这条我们完全支持，已实测跑通**（AOT 编出来跑 → `EXIT=0`；headless 下按设计是 no-op）。
> 本项目 AIR 侧驱动本来就用它（[`AirMain.as`](AirMain.as):61、[`Hello.as`](Hello.as):28）。
> ⇒ 下面这条 `System.exit` 只是「**API 面少一个成员**」，**不影响程序能不能正常退出**。
> 完整取证： [`../reviews/probe-exit-paths-2026-10-22.md`](../reviews/probe-exit-paths-2026-10-22.md)

我们编译器对 `System.exit(0)` 报的是
`undefined variable 'System' at top level`（`System` 是 `src/emit.ts` 里的手写伪类，认
`gc`/`output`/`pauseForGCIfCollectionImminent`/`setClipboard`/`disposeXML`/`useCodePage` 与内存常量，
**不含 `exit`**），落到通用路径后文案**误导**——读者会以为是 `System` 这个名字不可见，而不是「System 无 exit 成员」。
（对照：`System.gc()` 的 codegen **通过**，一路走到 `[4/4] compile` ⇒ 这个名字我们是认得的。）

**用 `mxmlc` 做真参考**（AIR 51.4.1）逐项实测，结论不是靠印象：

| 探针 | mxmlc 结果 | 说明 |
|---|---|---|
| `System.exit()` | **错**：`参数个数不正确。需要 1 个` | 该成员**存在**，但**无默认值** |
| `System.exit(0)` / `System.exit(3)` | **过** | 参数是 `uint` |
| `System.exit(true)` / `(false)` | **错**：`Boolean 值无法隐式转换为 uint` | 参数**不是** `Boolean`（与 `NativeProcess.exit(force:Boolean)` 不同名不同型） |
| `var f:Function = System.exit;` | **过** | 确实是个存在的函数成员 |
| 负对照 `System.definitelyNotAMemberXYZ()` | **错**：`方法 … 尚未定义` | 证明「编译通过」真能区分「有」与「没有」 |

⇒ **AIR 的签名是 `flash.system.System.exit(code:uint):void`**（1 个必填 `uint`，无默认值）。
故这是**遗留欠账**（AIR 有我们无），不是「AIR 也没有」——与「凭直觉猜它有个 Boolean 参数」差得很远，
这也正是 AGENTS.md §1.5 禁止凭直觉入表的原因。

**已登记在 [`../compiler-gaps.md`](../compiler-gaps.md) G1**（该文件是本工作区所有编译器缺口的唯一登记处）；
按用户 2026-10-22 指示，**不直接改编译器代码、不改 `as3compiler/TODO.md`**；若要立项才进 `遗留待开发` 表。

（`SystemExitProbe.as` 就是上表第一行的那个探针：它**故意**用 0 参数，好让「需要 1 个参数」这条证据留在仓库里。）

### 2. mxmlc 能干净地编译我们整个接缝库

`-source-path=../seam` 指过去，`LayoutEngine.as` / `LayoutConstants.as` / `As3LayoutEngine.as` /
`As3LayoutNode.as` **零报错**编出 12,008 字节的 SWF（`aircheck.swf`，P1~P8 扩展后的体积；
扩展前为 6,288 字节）。
AIR 的严格类型检查没有挑出任何问题。

### 3. AIR 与我们的 AOT 在 AS3 语义上**没有**可观测差异（本用例范围内）

同 `As3LayoutEngine.as` 源码、同用例，两条工具链输出 105/105 一致。
（注意这**只**说明本用例覆盖到的语言子集没差异，不等于全语言面。）

### 4. 差点误判成「AIR 与 AOT 行为不一致」

第一次跑 AIR 臂时 **5 项 FAIL**，全是「row 容器 + 子件交叉轴 = 0」。**根因是我的 harness 写错了**，
不是语言差异：`AirMain.as` 当时对 c/e1/e2 的子件调了 `child(..., 0, 0)`，即**显式 0 尺寸**；
而 `CheckMain.as` 对应用例**根本不调 `setSize`**（auto，交叉轴才会 stretch）。
显式 `0` 与「未设」在接缝上是两回事。已改为 `childAuto()` 并复跑 105/105。

> 教训：跨工具链的差异**必须先排除自己的 harness**再怀疑语言/引擎。那次如果不是去读 `CheckMain.as`
> 对照，很容易写出一条「实测发现 AIR 与 AOT 语义不同」的**假结论**。
