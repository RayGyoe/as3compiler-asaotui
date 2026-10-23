# 探针记录：AIR 的两条退出路径（`NativeApplication.exit` vs `System.exit`）

> 日期：2026-10-22 · 触发：用户指出「退出是这样调用的：
> `import flash.desktop.NativeApplication; NativeApplication.nativeApplication.exit();`」
>
> 本记录回答两个不同的问题，**不要混为一谈**：
>
> 1. **惯用退出路径**（`NativeApplication.nativeApplication.exit()`）我们的编译器支不支持？
>    ⇒ **支持，且已实测跑通**。
> 2. **`flash.system.System.exit(code:uint)`** AIR 有没有、我们有没有？
>    ⇒ AIR **有**、我们**没有** ⇒ 这才是 [`compiler-gaps.md`](../compiler-gaps.md) G1。

---

## 1 「我们支持惯用退出路径」——两次实测

### 1.1 AOT 臂（我们的编译器 → C → native）

探针 `as3compiler/temp/exitprobe/Main.as`：

```as3
import flash.desktop.NativeApplication;

trace("before exit");
trace("nativeApplication != null: " + (NativeApplication.nativeApplication != null));
NativeApplication.nativeApplication.exit();
trace("after exit (headless: no event loop to end)");
```

```
node src/index.ts temp/exitprobe/Main.as --manifest temp/exitprobe/probe.build.json --run -o temp/exitprobe/out
```

实际输出（`EXIT=0`）：

```
before exit
nativeApplication != null: true
after exit (headless: no event loop to end)
```

⇒ 静态 getter `NativeApplication.nativeApplication` 返回**非 null 单例**，`exit()` 可调用。
**headless 构建里 `exit()` 是 no-op**（`src/runtime.ts:9756` 注释明说「No event loop to end」），
所以 `after exit` 那行仍会打印。这是**设计行为**，不是失败。

### 1.2 静态事实（为什么它一定能编）

| 环节 | 位置 |
|---|---|
| `exit` 方法签名注册 | `src/symbols.ts:1233` —— `exit` → `returnType: void`、`params: []`、实例方法 |
| 静态 getter `nativeApplication` | `src/symbols.ts:1276` —— `isStatic: true, isGetter: true` |
| `nativeApplication` 的发射 | `src/emit.ts:10345`（懒建单例）、`:3589` |
| `exit()` 的发射 | `src/emit.ts:10380` —— `void NativeApplication_exit(void* _this) { (void)_this; as_window_request_exit(); }` |

### 1.3 AIR 臂（也是本项目自己的 dogfooding 惯例）

`asaotui` 的 AIR 侧驱动**本来就用这条惯用路径**，不是这次才发现的：

- `air-check/AirMain.as:61` —— `NativeApplication.nativeApplication.exit();`
- `air-check/Hello.as:28` —— 同样的调用，注释还写明「`NativeApplication.exit()` is also what
  our own AOT registers, so the same driver form stays compilable by both toolchains.」

即：**同一份 `.as` 源码（含这句退出）两边工具链都能编**——这正是接缝改到 AS3 接口层换来的收益。

### 1.4 回归地位

`examples/native-window.as:207` 也调用 `NativeApplication.nativeApplication.exit()`，且该示例的
**编译+链接**被 `test/examples.ts:475` 长期钉住（它开真窗口，只在 `exit()` 处返回，故不进 run 套件）。
⇒ 这条路径有**既有回归覆盖**，不是无人看守的角落。

---

## 2 `System.exit` —— AIR 有、我们没有（G1）

### 2.1 AIR 侧：用真 `mxmlc` 判（AIR 51.4.1）

探针 `as3compiler/temp/exitprobe-air/`。**必须有负对照**，否则「编译通过」分不清「有」与
「被静默忽略」。

| 探针 | `mxmlc` 结果 | 说明 |
|---|---|---|
| `System.exit(0)` （`SysExitProbe.as`） | **RC=0，零报错** | 该成员**存在** |
| 负对照 `System.noSuchMemberXyz(0)`（`SysBogusProbe.as`） | **RC=2**：`通过静态类型为 System 的引用调用的方法 noSuchMemberXyz 可能未定义` | 证明报错真能区分「有/没有」 |

（更细的参数形态实测——`System.exit()` 报「需要 1 个」、`System.exit(true)` 报「Boolean 无法隐式转 uint」、
`var f:Function = System.exit` 可编译——见 [`air-check/SystemExitProbe.as`](../air-check/SystemExitProbe.as) 头部注释。）

⇒ AIR 的签名是 **`flash.system.System.exit(code:uint):void`**；属**遗留欠账**（AIR 有、我们无）。

### 2.2 我们这边：报错，但**文案误导**

```
$ node src/index.ts temp/exitprobe/SysExit.as -o temp/exitprobe/sysexit
Codegen error at 3:1: undefined variable 'System' at top level
```

对照 `System.gc()`（`temp/exitprobe/SysGc.as`）：codegen **通过**，一路走到 `[4/4] compile`。
⇒ **`System` 这个名字本身我们是认得的**（`src/emit.ts` 里的手写伪类，认
`gc`/`output`/`pauseForGCIfCollectionImminent`/`setClipboard`/`disposeXML`/`useCodePage` 与内存常量）。

所以真实情况是「**`System` 这个伪类没有 `exit` 成员**」，而报错说成
「`undefined variable 'System'`」——读者会以为整个 `System` 不可见。这违反 AGENTS.md §2.5
「报错要能定位 + 能理解」，是**独立的诊断缺陷**，与「补不补 `exit`」可以分开修。

---

## 3 结论

| 问题 | 答案 | 依据 |
|---|---|---|
| 我们的编译器支持惯用退出路径吗？ | **支持**（且 headless 下按设计 no-op） | §1.1 实测 `EXIT=0`；§1.4 既有回归 |
| `System.exit` 是我们的缺陷吗？ | **是**，但影响**极低**——因为惯用路径已通 | §2；G1 |
| 报错文案「`undefined variable 'System'`」对吗？ | **不对**，是误导 | §2.2 对照 `System.gc()` |
