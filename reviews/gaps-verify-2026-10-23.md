# 缺口清单复核（2026-10-23，Windows 本机实测）

> 对 [`../compiler-gaps.md`](../compiler-gaps.md) 的 G1–G8 逐条复核。
> **口径**：只写这次真正跑出来的东西；跑不出来的明确写「未实测 / 本机无法测」。
> 环境：Windows 10.0.26200，LLVM **23.1.3**，`temp/ccbin/cc.exe` shim，wasi 侧
> `build-tools/wasi/wasi-sysroot-34.0` + `build-tools/wasi/resource-dir`。
> **本机没有 AIR SDK / `adl.exe`**（全盘搜 `adl.exe` 零命中）⇒ 需要 AIR 行为口径的
> 条目（G3、G5）只能按 Adobe 参考文档实现，**不能 adl 实测**。

---

## 逐条结论

| 条目 | 复核结果 | 判定是否仍成立 | 能否做 |
|---|---|---|---|
| **G1** `System.exit` | **仍缺**。`System.exit(0)` → `Codegen error at 5:7: undefined variable 'System' in class G1` | ✅ 成立（**文案确实是误导**：`System` 认得，缺的是成员） | 可做（小） |
| **G2** `flash.accessibility.*` | **仍整包缺失**。6 个源文件（emit/symbols/runtime/checks/build/index）grep `accessibility` 只有 `emit.ts:26725` 一句无关注释 | ✅ 成立 | 可做（中），但**只能做数据壳**，见下 |
| **G3** Tab 序 | **仍成立且比登记更差**：`as_tab_scan` 只读 `tabEnabled`；`tabIndex` 字段有（`emit.ts:10602` 初始化 -1）**但全代码从不读**；`tabChildren` 同样只声明不读；上限 **64** 是 `emit.ts:10940` 的字面量栈数组 | ✅ 成立，**新增两条子缺口**（tabIndex / tabChildren 未实现） | 可做（中） |
| **G4** 旗标透传 | **仍成立**。`-w` → `unknown argument: -w (see \`as-aot --help\` for the full list)`；`index.ts:191-236` 的 29 个 case 里没有任何透传口 | ✅ 成立 | 可做（小） |
| **G5** 触摸事件 | **仍成立**。`vendor/window_glue.cc` 只处理 `SDL_WINDOWEVENT / MOUSEMOTION / MOUSEBUTTON* / KEY* / TEXTEDITING / TEXTINPUT / MOUSEWHEEL`，无 `SDL_FINGER*`、无 `WM_TOUCH`；`emit.ts` 里 `TouchEvent` 类完整但 **零** `as_touch_*` 派发助手；`Multitouch` 只有 `maxTouchPoints`，**没有 `supportsTouchEvents`** | ✅ 成立（比登记的更缺一层：连派发机制也没有） | **可做但无法验证**（本机无触屏、无 adl） |
| **G6** `--target wasm` + C++ | **仍 throw**（`build.ts:1327`）。**但工具链已经齐了**：实测 `t.cc`（`std::string` / `std::vector`）→ `clang++ --target=wasm32-wasip1 --sysroot=…/wasi-sysroot-34.0 -resource-dir=…/resource-dir -O2` 编译干净 → 链接出 **183,695 B** 的 `t.wasm` → `node:wasi` 跑出 `wasi-cxx-ok 11 3`、`WASI_EXIT=0` | ⚠️ 登记为「构建层限制」仍准确，但**前提已变**：不是「做不到」，是「没接线」 | 可做（中），前提已实测满足 |
| **G7** 单文件单 public 定义 | **仍完全不检查**。`symbols.ts` 里搜 `filename`/`file name` 零命中；`fileId` 只在 `reach.ts:689-701`（`--air-app` 路径）被打上，普通多文件编译**没有任何 per-file 溯源**；`FuncDecl` 连字段都没有；`parse(source)` 也不收文件名 | ✅ 成立 | 可做（小~中） |
| **G8** 保留名 / C 宏 | **两类都今天复现了**：① `bind` → `error: conflicting types for 'bind'`（对 `winsock.h:744`）+ `too few arguments… expected 3, have 2`；② `stat` → 已改写成 `_stat`，但 MSVC 的 `_stat` → `_stat64i32` **宏**仍炸 `conflicting types for '_stat64i32'`。另核实 `C_RESERVED` **不含** `bind/select/listen/socket/connect/send`（只有 `stat`） | ✅ 成立 | 可做（① 小，② 中） |

---

## 复核过程中发现的、登记里没写的三条

1. **G3 实际有三处缺**，不是「上限 + 全扫」两处：`tabIndex` 与 `tabChildren` 都是**声明了但从不使用**。
   `tabIndex` 是 AIR 的公开排序语义（`InteractiveObject.tabIndex`，默认 -1），我们完全忽略；
   `tabChildren` 同理（容器级 `tabChildren=false` 应让整棵子树退出 Tab 序）。
2. **G6 的「做不到」理由不成立**。原来的登记等于「wasi 侧没有 C++ 标准库」，但本机
   `wasi-sysroot-34.0` 带 `libc++` / `libc++abi`（`lib/wasm32-wasip1/{eh,noeh}/libc++.a`）、
   头文件在 `include/wasm32-wasip1/{eh,noeh}/c++/v1`（188 个）、`resource-dir/lib/wasm32-unknown-wasip1/
   libclang_rt.builtins.a` 也在。**编译 + 链接 + 运行三段都实测通了**，剩下的只是 build 层接线。
3. **G1 的诊断文案比登记的更糟**：错误位置是**语句行**（`5:7`），而 `System.exit(0)` 在
   `emitSystemConst` 那条路径上其实**会**抛出 `unknown System constant 'exit'`——只是**方法调用**走的是
   另一条分支（`emit.ts:29857` 起的 `isSystemClass` 链），没命中就掉到通用标识符路径。
   所以修文案的正确位置是**调用路径**，不是常量路径。

---

## 各条的可做性分级（给选择用）

| 级别 | 条目 | 理由 |
|---|---|---|
| **现在就能做完并全量验证** | G1、G4、G8①、G7、G3（去上限 + tabIndex + tabChildren）、G2（数据壳） | 全部落在编译器自己的代码里，`node test.ts` 能兜底 |
| **能做但要接环境** | G6 | 本机工具链已实测可用；要处理「C 编译步骤走 cc、C++ 步骤走 clang++、wasm 链接点加 `-lc++ -lc++abi`」 |
| **能做但本机验证不了** | G5 | 无触屏、无 adl ⇒ 只能验证「编译过 + 合成事件能派发」，无法验证真实触控 |
| **做了也只能算「诚实的半实现」** | G2 | 真正接屏幕阅读器（Windows UIA / MSAA）是另一个量级；可行的是「类与属性都在、`active` 恒 false、`updateProperties()` 只上报一次不支持」 |

---

## 探针留档

- `temp/gapprobe/g1.as`（G1）、`temp/gapprobe/g8bind.as` + `p/Bind2.as`（G8①）、
  `asaotui/probes/name-collision/{NamesMain.as,p/Names.as}`（G8②，原探针今天重跑仍是 4 个 error）、
  `temp/gapprobe/t.cc` + `runwasi.cjs`（G6 工具链三段实测）。