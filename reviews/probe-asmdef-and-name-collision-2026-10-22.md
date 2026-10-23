# 探针：AS3 定义规则（AIR 强制 / 我们不强制）+ 用户符号名与 C 符号冲突

**日期**：2026-10-22  **探针源码**：[`../probes/asmdef-rule/`](../probes/asmdef-rule/)、[`../probes/name-collision/`](../probes/name-collision/)
**新登记的缺口**：**G7**（定义规则不强制）、**G8**（符号名冲突表不全 + 前缀改写挡不住 C 宏）

两条都是从**写 `asaot.ui` 工具链**这个真实任务里撞出来的，不是构造出来的。方法都一样：
**同一份输入同时喂 AIR 的参考编译器与我们自己的 AOT，把「谁说不行」判清楚，再落到文档**。

---

## 1 缘起：想证明「工具链是纯 AS3、能在 AIR 上跑」

「纯 AS3」如果只是自己声明，就不是证据。唯一能证实它的是**拿真 AIR 编一遍**。
于是有了 [`tools/mxmlc-check.cjs`](../tools/mxmlc-check.cjs)（通用封装：把一棵源码树交给 `mxmlc`）
和 [`air-check/AirKitProbe.as`](../air-check/AirKitProbe.as)（点名引用工具链**每一个**公开类型与工厂函数）。

第一次跑就红了——而且红的方式很信息量：

```
警告: 找不到定义 asaot.ui.box。            （×8，工厂函数）
错误: 找不到类型或类型不是编译时常量: Binding。
错误: 找不到类型或类型不是编译时常量: Corners。
错误: 找不到类型或类型不是编译时常量: Edges。
错误: 找不到类型或类型不是编译时常量: Length。
错误: 找不到类型或类型不是编译时常量: TextStyle。
```

「类找不到」很反常：那些文件明明在、`public class` 也在。

---

## 2 G7：一个文件只能有一个「与文件名同名的 public 顶层定义」——AIR **硬报错**，我们**不报**

### 最小判定（`probes/asmdef-rule/`）

把一个**公开包级函数** `hello()` 与一个类 `Lib` 一起放进 `p/Lib.as`：

```as3
package p {
    public function hello():String { return "hello-from-package-scope"; }
    public class Lib { public function Lib():void { } }
}
```

| 工具链 | 结果 |
|---|---|
| **AIR `mxmlc`** | **`MRC_EXIT 2`**，硬错误：`错误: 意外发现一个具有名称"p.hello"的外部可见定义。`，并且该文件**本该提供的类** `Lib` 也连带报 `找不到类型: Lib` |
| **我们的 AOT** | **`Build successful`**，程序跑出 `asmdef-rule: p.Lib constructed`，**`EXIT 0`** |

### 合法形态的对照（同目录 `p/hello.as`）

```
$ node tools/mxmlc-check.cjs --root air-check/pkgfn-probe/UsePkgFn.as --src air-check/pkgfn-probe
MRC_EXIT 0
OK: compiled by AIR -- 480 bytes
```

⇒ 规则不是「包级函数不能用」，而是 **「public 顶层定义必须住在与它同名的文件里，且一个文件只能有一个」**
（这与 AS3「一个文件只能有一个 public 类」是同一条规则）。AIR 严格执行；**我们的 AOT 完全不检查**。

### 为什么这是**缺口**而不是「我们更宽松也挺好」

因为它制造**静默的可移植性陷阱**：在我们这里编过的代码，到 AIR 上编不过，而我们**从不提示**。
这正好违反 `AGENTS.md` §1.5 的判据——「同一输入 `adl` 能跑而我们跑不出」是遗留缺陷；这里是反向的
一半：**同一输入 AIR 拒绝而我们接受**，于是 AIR 上的失败被推迟到用户手里才暴露。

### 工具链里**真实受影响**的文件（7 个，AIR 侧全部不可编译）

| 文件 | 与规则冲突的公开顶层定义 |
|---|---|
| `kit/asaot/ui/Factories.as` | `box` `row` `column` `text` `label` `button` `textField` `checkbox`（8 个；文件里没有类，mxmlc 连文件都到不了） |
| `kit/asaot/ui/Binding.as` | `bindTo`（另有类 `Binding`） |
| `kit/asaot/ui/style/Length.as` | `px` `rem` `pct` `auto` `rems`（另有类 `Length`） |
| `kit/asaot/ui/style/Fill.as` | `fill`（另有类 `Fill`） |
| `kit/asaot/ui/style/Edges.as` | `edges`（另有类 `Edges`） |
| `kit/asaot/ui/style/Corners.as` | `corners`（另有类 `Corners`） |
| `kit/asaot/ui/style/TextStyle.as` | `textStyle`（另有类 `TextStyle`） |

这不是「写法风格」问题，是**能不能在 AIR 上跑**的问题。两条出路（择一，属工具链侧决策）：
① 每个 public 顶层定义单独一个**同名文件**（保住 `box({...}, [...])` 这个作者语法，
代价是十几个小文件）；② 都收成**类的 static 方法**（文件少，但改掉设计文档里的作者语法）。
无论选哪条，都不该把「只有自家 AOT 能编」当成默认。

---

## 3 G8：用户符号名会**逐字**进 C —— 冲突表不全，且前缀改写挡不住宏

### 3.1 现象 A：`bind` 缺在保留名表里（`probes/name-collision/p/Bind.as`）

```as3
package p { public function bind(owner:int, field:int):int { return owner + field; } }
```

我们的 AOT：`Build` → **`error: conflicting types for 'bind'`**、
`error: too few arguments to function call, expected 3, have 2`（撞上 socket `bind(2)`），**`EXIT 1`**。

### 3.2 现象 B：有保留名表，但**前缀改写挡不住 C 宏**（`probes/name-collision/p/Names.as`）

一次放 8 个名字，只有 `stat` 炸：

```
error: conflicting types for '_stat64i32'
error: too few arguments to function call, expected 2, have 1
```

生成 C 里我们**确实**在改写：

```c
char* _once0 = as_str_concat("sum=", as_str_from_int((((((((_div(6, 2) + _free(1))
    + _stat(1)) + _time(1)) + _open(1, 1)) + _close(1)) + _read(1)) + __exit(0))));
```

`div/free/time/open/close/read/exit` 被改写成 `_div/_free/…/__exit` 都**编过了**；
而 `_stat` 仍被 MSVC 的 `stat → _stat64i32` **宏**展开成真声明 ⇒ 前缀改写对付不了宏。

⇒ 结论：**「加下划线前缀」这条现有机制对 `#define` 类冲突是无效的**；
而「哪些名字在表里」看起来是**手工列举**的，`bind` 就漏在外面。

### 3.3 对工具链的影响

`asaot.ui.Binding` 的设计文档语法是 `bind(owner, field)`，实测不可用 ⇒ 工具链已退到
`bindTo(...)`（见 `kit/asaot/ui/Binding.as` 顶部的 NAME NOTE）。这是**被 G8 逼出来的改名**，
应当记录在案，避免以后有人「顺手改回更漂亮的名字」再炸一次。

---

## 4 复现（两条都一条命令）

```bash
# G7：同一份非法输入，两个编译器给出不同判决
cd asaotui
AIRSDK_HOME=<AIR SDK root> node tools/mxmlc-check.cjs \
  --root probes/asmdef-rule/UseLib.as --src probes/asmdef-rule --out probes/asmdef-rule/.air.swf
#   -> MRC_EXIT 2

cd ../as3compiler
node src/index.ts ../asaotui/probes/asmdef-rule/Main.as ../asaotui/probes/asmdef-rule/p/Lib.as \
  --run --cc clang -I ./vendor/curl/include -L ./vendor/curl/lib/windows-x64 -l zlib
#   -> Build successful ... asmdef-rule: p.Lib constructed   (EXIT 0)

# G8：符号名冲突
node src/index.ts ../asaotui/probes/name-collision/Main.as \
  ../asaotui/probes/name-collision/p/Bind.as \
  --run --cc clang -I ./vendor/curl/include -L ./vendor/curl/lib/windows-x64 -l zlib
#   -> error: conflicting types for 'bind'   (EXIT 1)
```

> 本机 bash 无 coreutils；`tools/ls.cjs`、`tools/as3-index.cjs`、`tools/mxmlc-check.cjs`
> 是为这台机器写的替代品。`tools/as3-index.cjs` 就是**静态查出 G7 受害文件**的那个工具——
> 它按「AIR 会把 `import a.b.C` 解析到文件 `a/b/C.as`」这条规则，给每个文件标出
> `PKG-LEVEL-FNS(not mxmlc-importable)`。

---

## 5 与编译器仓库的边界（重申）

按用户 2026-10-22 指示：**不动 `as3compiler/` 代码、不改 `TODO.md`、不占阶段号、不升版本**。
G7/G8 只登记在本工作区的 [`compiler-gaps.md`](../compiler-gaps.md)（唯一登记处），
探针源码留在 `asaotui/probes/`（**不放编译器仓库的 `temp/`**）。
