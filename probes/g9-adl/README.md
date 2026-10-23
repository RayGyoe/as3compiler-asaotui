# g9-adl —— 用**真 AIR**判定 G9：`Boolean(x)` 在 `Object` 槽位上是不是我们的缺陷

G9 原来登记为「遗留欠账」，但那条判定是**推断**（AIR 有、我们无），本机当时缺 AIR SDK，
没做过 A/B。本目录把它变成实测。

## 关键前提：AIR SDK 就在本机

```
D:/Adobe/Flex_Sdk/AIRSDK_51.4.1/bin/adl.exe        （runtimeVersion 51.4.1.1）
D:/Adobe/Flex_Sdk/AIRSDK_51.4.1/bin/mxmlc.bat
```

之前记的「本机无 AIR SDK、全盘零命中」**不成立**（当时只搜了 C:，SDK 在 D:）。
`AIRSDK_HOME` 未设时 `../../air-check/verify-air.cjs` 也默认指这个目录。

## 同一份用例，两条工具链

`G9Cases.as` 是**唯一**的用例源（26 条），两个驱动只是输出通道不同：

| 臂 | 驱动 | 输出通道 |
|---|---|---|
| AIR | `G9Air.as`（document class，`mxmlc` → `adl`） | 写文件 `g9-air.txt`（Windows 上 `adl.exe` 没有控制台） |
| AOT | `G9Aot.as`（顶层语句，我们的编译器 → native） | stdout |

## 复现

```bash
cd asaotui/probes/g9-adl

# AIR 臂
cmd /c "D:/Adobe/Flex_Sdk/AIRSDK_51.4.1/bin/mxmlc.bat" -output=g9air.swf -source-path=. G9Air.as
AIRSDK_HOME=D:/Adobe/Flex_Sdk/AIRSDK_51.4.1 node ../../air-check/run-adl.cjs app.xml 60000

# AOT 臂（带 temp/ccbin 才有 cc）
PATH="/c/Users/rayle/Desktop/as3compiler-aot/temp/ccbin:$PATH" \
  node ../../../as3compiler/src/index.ts G9Cases.as G9Aot.as -o ../../../temp/g9adl/g9aot -w
../../../temp/g9adl/g9aot.exe
```

## 结果

**修复前**（阶段二百四十七，`721e12f`）：

```
AIR: ---- 26 checks, 0 failures ----
AOT: ---- 26 checks, 7 failures ----
```

七条全错在同一个地方 —— **`Boolean(...)` 作用在静态声明为 `Object` 的量上**：

| 用例 | AIR | AOT |
|---|---|---|
| `var o:Object = getFalse(); Boolean(o)` | `false` | `true` ✗ |
| `var z:Object = 0; Boolean(z)` | `false` | `true` ✗ |
| `var s:Object = ""; Boolean(s)` | `false` | `true` ✗ |
| `var n:Object = NaN; Boolean(n)` | `false` | `true` ✗ |
| `var bb:Boolean = false; var ob:Object = bb; Boolean(ob)` | `false` | `true` ✗ |
| `var p:Object = holder.flag /* false */; Boolean(p)` | `false` | `true` ✗ |
| `Boolean(new Boolean(false))` | `false` | `true` ✗ |

同一个值的**其余六种读法两边逐字相同**：`typeof`＝`boolean`、`String()`＝`false`、
`is Boolean`＝`true`、`== false` / `=== false`＝`true`、`Number()`＝`0`、`== null`＝`false`，
连 `if (o)` 都**正确地不进分支**。⇒ 缺陷只在 `Boolean()` 这一个降级入口，不是「箱信息丢了」。

**修复后**（阶段二百四十八，`src/emit.ts` 的 `Boolean` 分支：`Object` 根先
`as_obj_to_value` 解箱再 `as_v_truthy`，与 `condExpr` 同一条规则）—— 同一份用例、
同一条命令，AOT 臂变成 **`26 checks, 0 failures`**（原始输出
[`aot-got-fixed.txt`](aot-got-fixed.txt)，修复前是 [`aot-got.txt`](aot-got.txt)）。
两臂自此逐字符一致。

## 附带量到的 AS3 事实（不是缺陷，是参考值）

`new Boolean(false)`：AIR 的 `typeof` 是 **`"boolean"`**（不是 ES3/JS 的 `"object"`），
`Boolean(wrapper)` 也是 **`false`**（不是 ES3 的 `true`）。AVM2 对 Boolean 包装器是**透明**的。
我们这两格与 AIR 一致。

## 文件

| 文件 | 作用 |
|---|---|
| `G9Cases.as` | 26 条用例（`WANT` 列 = AIR 实测值） |
| `G9Air.as` / `app.xml` | AIR 驱动 + 描述符 |
| `G9Aot.as` | AOT 驱动 |
| `air-got.txt` / `aot-got.txt` | 两臂原始输出（修复前） |
| `aot-got-fixed.txt` | AOT 臂修复后输出（26/0） |