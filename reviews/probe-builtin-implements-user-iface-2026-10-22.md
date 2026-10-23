# 探针：内建类 `implements` 用户 `.as` 接口（2026-10-22）

> 结论：**P 成立**。这是 `asaot.ui` 布局接缝方案（纯 AS3 接口 + 内建类实现）的**前置闸门**，
> 通过 ⇒ **架构无需回退**。证据保留在 `as3compiler/temp/ifaceprobe2/`（正例）与 `temp/ifaceprobe3/`（反证）。

## 1. 命题

`P`：**编译器注册的内建类，可以 `implements` 一个由用户 `.as` 源码声明的接口，并在运行时
通过接口类型调用其成员（普通方法与 accessor）。**

为什么必须验：`asaot.ui.LayoutEngine` 要是**纯 `.as` 接口**（这样整库能在 `mxmlc→adl` 上跑），
而 native 实现 `NativeLayoutEngine` **必须是内建类**（AS3 无 FFI，纯 `.as` 调不到 C）。于是
native 路径完全压在这条**此前无先例**的模式上（既有内建只 `implements` 内建接口，如
`symbols.ts:726` 的 `IGraphicsData`）。

## 2. 机制侧的静态证据（先读码确认「应该能通」）

| 环节 | 覆盖内建类 | 位置 |
|---|---|---|
| 用户接口注册**先于**内建类 | ✅ | pass 0 `symbols.ts:580-616` → pass 0.5 `symbols.ts:617` |
| 接口一致性检查遍历整个 `classMap` | ✅ | `symbols.ts:7383`；报错点 `:7403` |
| 接口 vtable 发射遍历 `symbols.classes` | ✅ | `emit.ts:3962` `emitInterfaceVtables()` |
| 内建字段凭 `FieldInfo.isAccessor` 满足接口 accessor | ✅ 有先例 | `symbols.ts:7390-7402`（先例 `temp/accprobe*`） |
| 用户接口的 classMap key 拼法 | ✅ | `probe.ISizable` → **`probe_ISizable`**（包名点换下划线 + 名） |

## 3. 实测（本机 Windows，clang 23）

### 3.1 正例

改动：`src/symbols.ts` 的 `DisplayObject` 注册处 `implements: ['IBitmapDrawable']`
→ `['IBitmapDrawable', 'probe_ISizable']`（**一行**）。

探针源（`temp/ifaceprobe2/`）：

- `ISizable.as`：用户接口 `probe.ISizable`，含 accessor 对 `x`（内建里是普通存储型）、
  accessor 对 `width`（内建里是计算型）、普通方法 `hitTestPoint` ⇒ 一次压满 vtable 三种槽位。
- `Main.as`：**对照组**用户类 `UserSizable implements ISizable`；**主组** `var s:ISizable = new Sprite()`。

```
node src/index.ts temp/ifaceprobe2/Main.as temp/ifaceprobe2/ISizable.as --run --cc clang \
  -I <repo>/vendor/curl/include -L <repo>/vendor/curl/lib/windows-x64 -l zlib
--- output ---
user x=50 hit=false
x=120
w=0
hit=false
s is ISizable=true
```

生成的 C 里接线正确（`temp/ifaceprobe2/Main.c`）：

```c
static probe_ISizable_vtable DisplayObject_probe_ISizable_vt = { "probe_ISizable", NULL, NULL, NULL, NULL,
  DisplayObject_hitTestPoint, DisplayObject_get_x, DisplayObject_get_width, DisplayObject_set_x, DisplayObject_set_width };
```

并沿继承链传播到 `InteractiveObject`/`DisplayObjectContainer`/`Stage`/`Sprite`/`MovieClip`
（对应 `symbols.ts:7696` 的 `implements` 集合并）。

### 3.2 反证（**关键** —— 证明「编过」不是因为检查没覆盖）

接口里加一个 `DisplayObject` 确实没有的成员 `function bogus():void;`（`temp/ifaceprobe3/`），
编译 **`EXIT=1`**：

```
class 'DisplayObject' does not implement method 'bogus' of interface 'probe_ISizable'
```

⇒ 一致性检查**确实在管内建类**，不是静默放过。

### 3.3 还原

`git checkout -- src/`，`git status --short` 为空；编译器仓库零残留（探针源留在 `temp/` 供复核）。

## 4. 结论与架构含义

- `P` **成立**（普通方法 ✅ / accessor ✅ / `is` 判定 ✅）。`NativeLayoutEngine`
  声明 `implements: ['asaot_ui_LayoutEngine']` **在编译器侧可行**。
- 原设计里的**回退方案（内建静态方法 + AOT-only 适配器）不再需要**，仅作备查。
- 其余两条 CI 阻塞项（严格 `wasm32-wasip1` 已验证通过；macOS `-Wl,-dead_strip` 待 CI）**不受影响**。

## 5. 本次**未**验证的点（不得当成已验）

1. 只测了 `DisplayObject`（所有显示类的基类）。**未测**不继承 `DisplayObject` 的内建类
   （如 `EventDispatcher`/`ByteArray`）——预计同法可通，但**未实测**。
2. **未测**子类自带同名 accessor 覆盖基类时的 vtable 选择（`NativeLayoutEngine` 是新类、无此情形，风险低）。
3. **未测** `any` → 用户接口的运行时 `as` cast、`describeType` 对该接口的报告。
4. `width=0` 是空 `Sprite` 的**计算型**语义（bounds 为空），非缺陷；但若要「经接口存取可写数值」，
   应选普通存储型属性（`x`/`y`/`alpha`），`NativeLayoutEngine` 的字段需照此设计。
