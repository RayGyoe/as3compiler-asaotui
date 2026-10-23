# U1 前置测量 · 严格 `wasm32-wasip1` 体积报告（CI 阻塞项 ①）

> 对应 `u1-yoga-precheck.md` §6.2 的 **CI 阻塞项 ①**：在 `WASI_SDK_HOME` 就绪的环境上，
> `clang --target=wasm32-wasip1` 能编 + 链 Yoga，且 wasm 增量 **≤ 192 KiB**。
> 原判定「本机不可测 / 待 CI」，本报告把它改成 **本机已测**。
>
> 全部数字是**本机 Windows x86_64 实测**（clang 23.1.3 + wasi-sdk 34 sysroot），
> 脚本与原始日志见 `wasi-probe/attrib/`。未测项集中登记在 §5。

---

## 0. 一句话结论

- **能力检疫：通过。** 30 个 seam 函数 + 17 项验收测在严格 `--target=wasm32-wasip1`
  下**编、链、运行全部通过**（`17 checks, 0 failures`，`RESULT: PASS`），两次独立配置
  （`-O2 -DNDEBUG` 与 `-Oz -DNDEBUG -flto`）都跑通且结果一致（`17/17`）。
- **预算检疫：通过（但必须按项目自己的默认形态测）。** 关键发现是：
  之前 `wasip1-size.log` 里「343.6 KiB」这个数**测的不是项目产物**——它把 wasi-sdk 34
  预编译 `libc.a`/`libc++.a` 里自带的 **DWARF（约 205 KiB）** 一并算进去了。项目的
  `src/build.ts` 默认就带 `-Wl,--strip-debug`（`wasmStripFlags()`），emcc `-O2` 也默认剥离，
  所以 emscripten 形状的 120.3 KiB 本来就是**剥离后**的数。按同一口径重测：

  | 口径 | `yoga_min` | `seam_test`（30 函数 + 验收测） | 门 B（≤192 KiB） |
  |---|---|---|---|
  | 裸链接（含 DWARF，= 旧日志口径） | 321.3 KiB | 343.6 KiB | ❌ 假失败 |
  | **`-Wl,--strip-debug`（项目默认）** | **116.1 KiB** | **136.7 KiB** | ✅ |
  | 同上 + `-Oz -flto` | 81.5 KiB | 90.0 KiB | ✅✅ |

  **结论：192 KiB 门在 wasip1 上过。** 旧「超预算」100% 是**测量口径错误（没带项目默认的
  `--strip-debug`）**，不是能力缺陷，也不是接缝设计问题。**不需要按形状分档**。

---

## 1. 工具链怎么装起来的（含 5 个坑）

本机 `clang` 是 23.1.3（`x86_64-pc-windows-msvc`），**不是** wasi-sdk 自带的 clang。因此需要
手动把两样东西拼进一个可用的 wasm 交叉工具链。全部落在 `build-tools/wasi/`（与
`build-tools/skia-src`、`build-tools/emsdk` 同级，**不进 `as3compiler/`**）。

```bash
export PATH="/d/Program Files/Git/usr/bin:$PATH"
cd <repo-root>/build-tools
mkdir -p wasi && cd wasi

# (a) wasi-libc + libc++ 的 sysroot（wasi-sdk-34.0 的官方 release asset）
curl -L -o wasi-sysroot-34.0.tar.gz \
  https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-34.0/wasi-sysroot-34.0.tar.gz
tar xzf wasi-sysroot-34.0.tar.gz

# (b) wasm32-unknown-wasip1 的 compiler-rt builtins（多 triple 打包）
curl -L -o libclang_rt-34.0.tar.gz \
  https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-34.0/libclang_rt-34.0.tar.gz
tar xzf libclang_rt-34.0.tar.gz

# (c) 组装私有 resource-dir：clang 内建头 + wasm builtins
mkdir -p resource-dir/lib
cp -r "$(clang -print-resource-dir)/include" resource-dir/include          # 261 个头文件
cp -r libclang_rt-34.0/wasm32-unknown-wasip1 resource-dir/lib/
```

装配完成后的目录形状（实测 `VERSION` 内容：`wasi-libc: 2e6fb9d8…` / `llvm-version: 23.1.0`）：

```
build-tools/wasi/
├── wasi-sysroot-34.0/                 # include/ (wasi-libc 头) + lib/wasm32-wasip1/{,eh/,noeh/}
├── resource-dir/
│   ├── include/                       # 261 个 clang 内建头（stdarg.h / stddef.h / …）
│   └── lib/wasm32-unknown-wasip1/libclang_rt.builtins.a
├── wasi-sysroot-34.0.tar.gz
└── libclang_rt-34.0.tar.gz
```

编译/链接的**固定形状**（下称 `$CXX`）：

```bash
CXX="clang++ --target=wasm32-wasip1 \
     --sysroot=build-tools/wasi/wasi-sysroot-34.0 \
     -resource-dir=build-tools/wasi/resource-dir \
     -L build-tools/wasi/wasi-sysroot-34.0/lib/wasm32-wasip1/noeh"
```

### 五个坑（都是实测踩过的，报错原文附上）

| # | 坑 | 报错原文 | 解法 |
|---|---|---|---|
| 1 | **本机 clang 没有 wasm builtins**。它只带 `x86_64-pc-windows-msvc` 的 `libclang_rt`。 | `wasm-ld: error: cannot open C:\Program Files\LLVM\lib\clang\23\lib\wasm32-unknown-wasip1\libclang_rt.builtins.a: no such file or directory` | 用 `-resource-dir=` 指向自组 resource-dir（放 (b) 的 builtins）。 |
| 1b | **`-resource-dir` 会连内建头一起换掉**。只放 `lib/` 不放 `include/`，`<stdarg.h>` 就没了。 | `<stdin>:1:10: fatal error: 'stdarg.h' file not found` | 必须把 clang 自己的 `include/` 也拷进 `resource-dir/include/`。 |
| 2 | **`eh` vs `noeh`**。wasi-sdk 把 libc++/libc++abi 分装在 `lib/wasm32-wasip1/eh/` 与 `noeh/`；**wasi-sdk 的 clang 驱动会自动选，本机 stock clang 不会**。选错子目录就撞异常运行时符号。 | 指向 `eh/`：`wasm-ld: error: …/eh\libc++abi.a(cxa_handlers.cpp.o): undefined symbol: __cpp_exception` 与 `undefined symbol: _Unwind_RaiseException` | 本项目统一 `-fno-exceptions -D_LIBCPP_HAS_NO_EXCEPTIONS` + `-L …/noeh`（与原生 precheck 的 `o2-fs-noexc` 同一档）。 |
| 3 | **`-x c` 会粘住后面的文件**。`clang -x c main.c libyoga.a` 会把 `.a` 当 C 源码解析。 | `libyoga-o2.a:1:1: error: expected identifier or '('` + `1 | !<arch>` | 归档前插 `-x none`：`-x c main.c -x none libyoga.a`。 |
| 4 | **`node:wasi` 的 `start` 用法**。`new WASI({})` 缺 `version`；命令型模块要 `start()` 而不是 `initialize()`；import 键必须是 `wasi_snapshot_preview1`。 | `Error: The "options.version" property must be of type string. Received undefined` | 见 `wasi-probe/run-wasi.mjs`：`new WASI({version:'preview1', args:[file], env:{}, returnOnExit:true})` → `WebAssembly.Instance(m,{wasi_snapshot_preview1:wasi.wasiImport})` → `wasi.start(instance)`。 |
| 5 | **MSYS/bash 与 node 的路径转换不一致**（写脚本时才会撞）。bash 调原生 exe 会自动把 `/c/...` 转成 `C:/...`，node 的 `execFileSync` **不会**。 | `llvm-nm.exe: error: /c/Users/.../libyoga.a: no such file or directory` | 交给原生 exe 的路径在 JS 侧自己转：`p.replace(/^\/([a-zA-Z])\//, (_,d)=>d.toUpperCase()+':/')`（见 `attribute.mjs`）。 |

另外两条把 `node:wasi` 跑起来必须知道的：
- `run-wasi.mjs` 里 **`args[0]` 必须给**（wasm 文件名），否则某些 `argv` 访问会取到空。
- 本机**没有** wasmtime/wasmer/wasm3，`node --no-warnings …run-wasi.mjs <wasm>` 是唯一运行入口。

> `src/build.ts:1406+` 对 `WASI_SDK_HOME` 的要求（`crt1.o` / `libc` / `libsetjmp.a`）在这一套里
> 都能满足；只是我们用的是自组 `--sysroot`（`wasi-sysroot-34.0`）而不是完整 wasi-sdk 安装。
> 若将来接 `WASI_SDK_HOME`，把 `WASI_SDK_HOME` 指到 `build-tools/wasi`、sysroot 指到
> `wasi-sysroot-34.0`、resource-dir 指到 `resource-dir` 即可等价。

---

## 2. 归因：`257.0 KiB` 到底是什么

### 2.1 先纠口径：其中约 205 KiB 是 DWARF，不是代码

`wasip1-size.log` 的产物是**裸链接**（没带 `-Wl,--strip-debug`）。用 `llvm-objdump -h` 拆节：

| 产物 | 总字节 | `CODE` | `DATA` | **`.debug_*`** | `name` | 其它 |
|---|---|---|---|---|---|---|
| `floor_c` | 65,828 | 3,616 | 159 | **60,376** | 854 | 823 |
| `floor_printf` | 122,243 | 15,476 | 2,678 | **102,183** | 1,049 | 857 |
| `yoga_one` | 244,457 | 27,541 | 2,870 | **210,774** | 2,328 | 944 |
| `yoga_min` | 329,018 | 99,298 | 3,878 | **210,060** | 14,456 | 1,326 |
| `seam_test` | 351,879 | 115,400 | 4,870 | **211,775** | 18,387 | 1,447 |

- `.debug_*` 在 Yoga 系列里**恒在 210 KiB 上下**——它与 Yoga 代码量几乎无关，来自
  **wasi-sdk 预编译归档自带的 DWARF**（`crt1.o`、`libc.a`、`libc++.a` 成员都用 `-g` 编过；
  实测 `crt1.o` 自带 `.debug_loc/.debug_abbrev/.debug_info/.debug_str/.debug_line`）。
  我们自己编的 Yoga `.o` 没有 `-g`，一条 DWARF 都不产生。
- `src/build.ts` 对此**早有处置**（`debugInfo` 默认 `false` → `wasmStripFlags()` 返回
  `-Wl,--strip-debug`），原注释写着「wasi-sdk 34 的 libc.a 带 DWARF，wasm-ld 默认保留，
  fib.wasm 421 KB → 133 KB」。本报告只是把这条**用在 Yoga 上**并量化。

所以下面所有归因都按**剥离后**（`-Wl,--strip-debug`）做。

### 2.2 剥离后的基线表

```bash
$ bash wasi-probe/attrib/matrix.sh        # §3 的矩阵脚本，[A] 段
```

| 程序 | 裸链接 | `--strip-debug` | 剥离后 KiB |
|---|---|---|---|
| `floor_c`（C 驱动，`printf`） | 65,828 | 5,358 | 5.2 |
| `floor_cpp`（C++ 驱动，同源） | 65,830 | 5,360 | 5.2 |
| `floor_printf`（`%.3f` 浮点） | 122,243 | 19,966 | 19.5 |
| `yoga_one`（只 new/free） | 244,457 | 33,590 | 32.8 |
| `yoga_min`（真 flex + grow） | 329,018 | 118,865 | 116.1 |
| `seam_test`（30 函数 + 17 用例） | 351,879 | 140,008 | 136.7 |

派生：
- **`libc++ floor = 2 B`**（`floor_cpp − floor_c`）→ **libc++ 在这条链上几乎零成本**。
- `yoga_min − floor_cpp`：裸 257.0 KiB → **剥离后 110.8 KiB**。
- `seam_test − floor_cpp`：裸 279.3 KiB → **剥离后 131.5 KiB**。

### 2.3 `--why-extract`：链进来的归档成员

```bash
$ clang++ --target=wasm32-wasip1 --sysroot=… -resource-dir=… -O2 -fno-exceptions \
    -I yoga-src -x c tmp/yoga_min.c -x none libyoga.a \
    -Wl,--why-extract=why_min.txt -Wl,-Map=map_min.map -o yoga_min_raw.wasm
$ tail -n +2 why_min.txt | cut -f2 | sed -E 's/.*[\\/]//' | sort -u | …
```

被链接器**抽取**的归档成员（`yoga_min`）：`libyoga.a` **16** 个 TU、`libc.a` **43** 个、
`libc++abi.a` **7** 个、`libc++.a` **1** 个。触发链很清楚：

```
yoga/config/Config.cpp.o     -> getDefaultLogger()            (libyoga Log.cpp.o)
libyoga Log.cpp.o            -> vfprintf / vprintf            (libc.a vfprintf.c.obj)
yoga/debug/AssertFatal.cpp.o -> std::terminate()              (libc++abi cxa_handlers.cpp.o)
yoga/config/Config.cpp.o     -> std::__libcpp_verbose_abort   (libc++.a verbose_abort.cpp.o)
yoga/YGConfig.cpp.o          -> operator new                  (libc++abi stdlib_new_delete.cpp.o)
libc++abi stdlib_new_delete  -> malloc                        (libc.a dlmalloc.c.obj)
yoga/algorithm/PixelGrid.cpp.o -> round                       (libc.a round.c.obj)
```

### 2.4 逐符号归因（`attrib/attribute.mjs`）

把最终 wasm 的每个已定义符号（`llvm-nm --print-size`）按定义它的归档分类求和。
注意 wasm `name` 段里是**已 demangle 的名字**，而归档成员是 mangled，脚本用 `llvm-cxxfilt`
对齐（详见脚本头注释）。

`yoga_min`（`-O2 -DNDEBUG`，剥离后 118,865 B；符号和 = 103,190 B）：

| 归档 | 字节 | KiB | 占比 |
|---|---|---|---|
| **`libyoga.a`（Yoga 自己的代码）** | **75,235** | **73.5** | **72.9%** |
| `libc.a`（wasi-libc） | 23,356 | 22.8 | 22.6% |
| `libc++abi.a` | 275 | 0.3 | 0.3% |
| `libc++.a` | 56 | 0.1 | 0.1% |
| 未匹配（`crt1`/`.rodata`/wasm 胶水） | 4,268 | 4.2 | 4.1% |

最大的几个成员：

| 成员 | 字节 | KiB |
|---|---|---|
| `libyoga.a/yoga_algorithm_CalculateLayout.cpp.o` | 42,260 | 41.3 |
| `libyoga.a/yoga_algorithm_AbsoluteLayout.cpp.o` | 12,376 | 12.1 |
| **`libc.a/vfprintf.c.obj`** | **9,945** | **9.7** |
| **`libc.a/dlmalloc.c.obj`** | **8,159** | **8.0** |
| `libyoga.a/yoga_node_Node.cpp.o` | 7,878 | 7.7 |
| `libyoga.a/yoga_YGNode.cpp.o` | 3,086 | 3.0 |
| `libyoga.a/yoga_YGNodeStyle.cpp.o` | 2,706 | 2.6 |
| `libyoga.a/yoga_algorithm_PixelGrid.cpp.o` | 2,412 | 2.4 |

对照 `yoga_one`（只 new/free，剥离后 33,590 B）：
`libyoga.a` 只有 **3,812 B**，`libc.a` 已 **23,304 B**（其中 `vfprintf` 9,945、`dlmalloc` 8,159）。
**即：一个「什么都不做」的 Yoga 程序已经把 vfprintf + dlmalloc 全拖进来了**（日志默认
logger + `operator new`），Yoga 自己的 Node/Config 代码才 3.7 KiB。

### 2.5 用「受控地板」把 110.8 KiB 拆开

除了按归档归类，再用**受控对照**钉死「哪些是 Yoga 不可回避的 libc 依赖」：

| 地板（剥离后） | 字节 | KiB | 说明 |
|---|---|---|---|
| `floor_cpp` | 5,360 | 5.2 | C++ hello（`printf("hi")` 被折成 `puts`） |
| `floor_abort` | 9,720 | 9.5 | `abort()` |
| `floor_new` | 19,179 | 18.7 | `operator new/delete`（→ dlmalloc） |
| `floor_vfprintf` | 19,219 | 18.8 | 走 `vfprintf(va_list)` |
| `floor_printf` | 19,966 | 19.5 | 浮点 `snprintf("%.3f")` |
| `floor_terminate` | 28,876 | 28.2 | `std::terminate()` |
| **`floor_yoga_deps`** | **29,363** | **28.7** | new/delete + vfprintf(va_list) + terminate + 格式化 printf ≈「一个 Yoga 程序不可避免的库地板」 |

于是 `yoga_min`（116.1 KiB）可以这样分：

| 组成 | 字节 | KiB |
|---|---|---|
| `floor_cpp`（C++ 程序本就有的） | 5,360 | 5.2 |
| ＋ Yoga 不可回避的 libc/libc++ 依赖（dlmalloc + vfprintf + terminate…） | 24,003 | 23.4 |
| ＝ `floor_yoga_deps` | 29,363 | 28.7 |
| ＋ **Yoga 自己的代码**（`libyoga.a` 符号） | 75,235 | 73.5 |
| ＋ Yoga 额外拉进的 libc（`round`/`frexp`/`scalbn`/`memchr`/`exit`/stdio 等）＋ `.rodata`/name 段/结构开销 | 14,267 | 13.9 |
| ＝ **`yoga_min`** | **118,865** | **116.1** |

### 2.6 「引擎真身」= `yoga_min − yoga_one`？

| 口径 | 差值 | KiB |
|---|---|---|
| 裸链接 | 84,561 | 82.6 |
| 剥离后 | 85,275 | 83.3 |
| `-Oz -flto` | 51,286 | 50.1 |

**明确写出来**：`yoga_min − yoga_one ≈ 82.6–83.3 KiB`（LTO 后 50.1 KiB）确实是**布局引擎
（flex/grid 计算核心）的边际增量**，因为两个程序共享同一套 libc 依赖（`yoga_one` 已付过
vfprintf+dlmalloc）。但从「Yoga 一共贡献多少」看，**真正的 Yoga 代码是 73.5 KiB**
（`libyoga.a` 符号和，LTO 后压到 27.9 KiB），另外 ~23.4 KiB 是**任何 Yoga 程序都要付的
libc 地板**（主要是 `vfprintf` 9.7 + `dlmalloc` 8.0）。

**一句话归因**：`257.0 KiB` 的旧数字里，**~205 KiB 是 DWARF（口径错误）**、**73.5 KiB 是
Yoga 自己的代码**、**22.8 KiB 是 wasi libc**（vfprintf + dlmalloc 占 17.7）、
**0.3 KiB 是 libc++/libc++abi**、其余是 wasm 结构与数据。**DCE 在动**：同一 `libyoga.a` 下
`yoga_one` 只抽出 16 个 TU 中真正可达的代码，布局核心（`CalculateLayout.cpp` 42 KiB）只在
`yoga_min` 出现——`wasm-ld` 的 `--gc-sections` 默认开启且有效（负向对照见 §3）。

---

## 3. 缓解实验矩阵（每个都实测）

统一口径：`--target=wasm32-wasip1`、`-fno-exceptions -D_LIBCPP_HAS_NO_EXCEPTIONS`、
`-L …/noeh`、`-Wl,--strip-debug`；被测量者为 `yoga_min`（`tmp/yoga_min.c`），地板 `floor_cpp = 5,360 B`。

| # | 配置 | `yoga_min` 字节 | KiB | Δ vs floor_cpp | 结论 |
|---|---|---|---|---|---|
| 0 | **裸链接（旧口径）** | 329,018 | 321.3 | 257.0（对裸 `floor_cpp` 65,830） | ❌ 含 205 KiB DWARF，口径错 |
| 1 | `-O2 -DNDEBUG` + **`-Wl,--strip-debug`** | **118,865** | **116.1** | **110.8** | ✅ 项目默认，**决定性**（−205.2 KiB） |
| 2 | `-Oz -DNDEBUG` | 115,237 | 112.5 | 107.3 | −3.6 KiB（-Oz 略优） |
| 3 | `-O2 -DNDEBUG -fno-rtti` | 118,871 | 116.1 | 110.9 | ±0（Yoga 基本不用 RTTI） |
| 4 | `-Oz -DNDEBUG -fno-rtti` | 115,243 | 112.5 | 107.3 | ±0 |
| 5 | `-O2`（**去掉 `-DNDEBUG`**） | 116,024 | 113.3 | 108.1 | 反而更小 2.8 KiB（见下） |
| 6 | `-Oz`（去掉 `-DNDEBUG`） | 116,262 | 113.5 | 108.3 | 同上 |
| 7 | `-O2 -DNDEBUG -flto` | 112,506 | 109.9 | 104.6 | −6.4 KiB |
| 8 | **`-Oz -DNDEBUG -flto`** | **83,464** | **81.5** | **76.3** | **−35.4 KiB，代码侧最强** |
| 9 | `-Oz -DNDEBUG` **不加 `-ffunction-sections`** | 115,242 | 112.5 | 107.3 | ±0（wasm 的 GC 按函数走，与 `-ffunction-sections` 无关） |
| 10 | seam 侧替换 `Log.cpp`+`AssertFatal.cpp`（`-O2`） | 117,716 | 115.0 | 109.7 | −1.1 KiB |
| 11 | seam 侧替换同上（`-Oz -flto`） | 81,922 | 80.0 | 74.8 | −1.5 KiB |

**逐条说明（含负面/无效的如实登记）：**

- **`-Wl,--strip-debug` = 唯一决定性手段**：329,018 → 118,865 B（**−210,153 B = −205.2 KiB**）。
  且这正是项目默认（`wasmStripFlags()`）；emcc `-O2` 也默认剥离，**所以它才是与 precheck
  的 120.3 KiB 可比的口径**。
- **`--gc-sections` 已默认开启**：负向对照 `-Wl,--no-gc-sections` → **204,342 B**（比默认大
  85 KiB），证明 GC 默认生效且必要。显式加 `-Wl,--gc-sections` 与默认**大小逐字节相同**
  （118,860 B）；`cmp` 会报 3 字节不同，但这来自 **wasm-ld 本机输出不确定**
  （同一条命令跑两次也差同样 3 字节，实测），不是 flag 的效果。
- **`-Oz` 略胜 `-O2`**（115,237 vs 118,865，−3.6 KiB）；注意 `libyoga.a` 归档本身 `-Oz` 反而
  **更大**（309,350 vs 216,154 B，因为 `-Oz` 少内联），但**最终链接产物更小**——比的是最终
  `.wasm`，不是 `.a`。
- **`-fno-rtti` 无效**（±6 B）：Yoga 的 `type_info` 引用只有 `event.cpp` 的 `typeinfo for void`
  那点，早已被 GC。**不必加。**
- **`-DNDEBUG` 在 wasip1 上不是减重项**：去掉它 `yoga_min` 反而**小 2.8 KiB**（116,024 vs
  118,865）。这是真实的编译非单调性（`assert` 去留改变内联决策；`libyoga.a` 归档仍是无
  `-DNDEBUG` 更大 3.7 KiB，但最终链更小）。原生 precheck 里 `-DNDEBUG` 值 26.5 KiB 的结论
  **不能平移到 wasm**。→ 建议保留 `-DNDEBUG`（语义上关断言是对的），但**不要把它当体积杠杆**。
- **`-flto` 是代码侧最强**，但**必须配 `-Oz`**：`-Oz -flto` −35.4 KiB，而 `-O2 -flto` 只 −6.4 KiB。
  LTO 把 `libyoga.a` 的 73.5 KiB 压到 **27.9 KiB**（跨 TU 内联 + 跨 TU DCE），libc 那 23.7 KiB
  不动。**LTO 产物已实测能跑对**（`yoga_min` 输出 `116.7 183.3`；`seam_test` 17/17 PASS）。
- **`-ffunction-sections -fdata-sections`：wasm 上无差别**（115,242 vs 115,237，±5 B）。
  wasm 对象本身就是「一函数一段」，GC 粒度天然到位。**保留无害，但别指望它省字节。**
- **`std::terminate` / `__libcpp_verbose_abort` / `vfprintf` 能不能断？**
  - **Yoga 源码里没有任何日志/断言开关**：`grep -rn "YG_ENABLE_LOGGING\|YG_ENABLE_EVENTS\|NDEBUG\|YG_NDEBUG" yoga/`
    **零命中**。`Log.cpp` 的默认 logger **无条件**调 `vfprintf`/`vprintf`；
    `AssertFatal.cpp` 在 `-fno-exceptions` 下**无条件**调 `std::terminate()`。
  - 唯一（不 patch 上游的）办法是**在 seam 侧把同名符号定义掉**、并把 `Log.cpp`/`AssertFatal.cpp`
    从归档里剔除，让链接器**不抽取**这两个 TU。实测（`controls/nolog_stub.cc`）：
    **只省 1.1–1.5 KiB**。原因很直接：**只要程序自己用格式化 `printf`（任何真程序都会），
    `vfprintf` 照样在**，被替掉的只是 `Log.cpp`/`AssertFatal.cpp` 薄壳 + `std::terminate` +
    `typeinfo` 那一丁点。
  - **`_LIBCPP_HAS_NO_VERBOSE_ABORT` 不存在**：grep sysroot 的 libc++ 头（`…/c++/v1/`）**零命中**。真正可覆盖的钩子是
    **`_LIBCPP_VERBOSE_ABORT(...)` 这个可变参宏**（`__verbose_abort` 里明确写「用户可自备」），可
    `-D_LIBCPP_VERBOSE_ABORT(...)=__builtin_abort()` 绕过 `__libcpp_verbose_abort`；但它对应的
    `libc++.a/verbose_abort.cpp.o` 在本链里**只有 56 B**，且它转调的还是 `abort()`/`fprintf`（早已在链里），
    **省不了什么，不建议动。**

---

## 4. 结论与预算建议

### 4.1 192 KiB 门：过

| 判据 | 值 | 门 B | 判定 |
|---|---|---|---|
| `yoga_min` 增量（剥离，`-O2`） | 110.8 KiB | ≤ 192 | ✅ |
| `yoga_min` 增量（剥离，`-Oz -flto`） | 76.3 KiB | ≤ 192 | ✅✅ |
| `seam_test` 增量（剥离，`-O2`） | 131.5 KiB | ≤ 192 | ✅ |
| `seam_test` 增量（剥离，`-Oz -flto`） | 84.8 KiB | ≤ 192 | ✅✅ |

**不需要按形状分档。** 192 KiB 对 emscripten（实测 120.3 KiB）与 wasip1（实测
110.8–131.5 KiB）**都成立**，且 wasip1 并不比 emscripten 差——`yoga_min` 上 wasip1
（110.8）甚至**略小于** emcc（120.3）。

### 4.2 建议（给门 B 的措辞补一条口径，不改数值）

> **门 B 必须注明 debug-info 口径**：预算以**默认 `--debug-info=false`（即 wasm 带
> `-Wl,--strip-debug`）** 为口径；`--debug-info=true` 的产物会额外带 ~205 KiB DWARF，
> 属**刻意请求**的诊断构建，不应计入预算门。原生（`cc -O2`）与 emcc（`-O2` 自带剥离）
> 本来就满足该口径，只有 wasi 后端需要显式反旗——项目已实现（`build.ts` §debugInfo）。

即：**门 B 保持 `wasm ≤ 192 KiB`，但把「剥离 DWARF」写进口径**，而不是调数值、更不是放宽。

### 4.3 这两条形状差异是「接缝设计问题」还是「wasi libc 固有成本」？

**都不是主因——主因是我们自己的测量口径。** 分层回答（AGENTS.md §1.5 口径）：

1. **~205 KiB 的「超预算」= 测量口径错误**（没带项目默认的 `--strip-debug`）。这是**我们的
   脚本**（`wasip1-size.sh`）的问题，不是接缝、不是 wasi-libc、更不是 Yoga。已在本报告纠正。
2. **剥离后剩余的 ~10–20 KiB 形状差**（wasip1 110.8 vs emcc 120.3，或 seam 131.5）是
   **wasi-libc 的固有成本 + 我们自己的 seam/驱动代码**：
   - wasi-libc 的 `vfprintf` 9.7 KiB + `dlmalloc` 8.0 KiB 是**任何**「要格式化输出 + 要
     `operator new`」的 wasm 程序都付的（受控地板 `floor_new`/`floor_vfprintf` 各 18.7/18.8 KiB
     证实）。**这是 wasi libc 固有成本，按 §1.5 如实报明，不算降级。**
   - `seam_test − yoga_min ≈ 21 KiB` 是**我们自己的** 30 个 seam 函数 + 验收驱动
     （`test_layout.c`）；生产里验收驱动不进构建、seam 也会按真实用到的子集裁剪。
3. **接缝设计本身没有把东西变重**：`seam_test` 相对 `yoga_min` 只多 ~21 KiB，且这 21 KiB
   里明确含验收测试驱动；seam 函数全是薄封装（`libc++ floor = 2 B` 说明 C⇄C++ 边界几乎零开销）。

**结论：不是接缝设计问题；剩下的形状差是 wasi-libc 固有成本（vfprintf + dlmalloc）加上
验收驱动，属如实报明的平台成本，不是需要「绕行」的缺陷。**

### 4.4 可选的进一步减重（不是过门所需，供 U1 实施择优）

- **`-Oz -flto`**：`seam_test` 140,008 → 92,209 B（−47.8 KiB），是代码侧唯一值得拿的大块。
  代价是构建更慢、需在编译与链接两侧都加 `-flto`（`build.ts` 已有 `lto` 配置项）。
- `-Oz`：再省 3.6 KiB，几乎免费（仅与 LTO 叠加时注意）。
- 不值得做：`-fno-rtti`（±0）、`-ffunction-sections`（wasm 上 ±0）、seam 侧 stub 掉日志断言（1.1–1.5 KiB）。

---

## 5. 未测项（如实登记）

| 项 | 为什么没测 | 谁来测 / 何时 |
|---|---|---|
| wasip1 上**真实 GUI 构建**（Yoga + Skia + 生成的 `.c`）的总体积 | 本前置测量只测 Yoga 单独增量，不接 Skia/窗口后端 | U1 实施阶段 |
| **wasi-sdk 自带 clang**（`$WASI_SDK_HOME/bin/clang`）与本机 clang 23.1.3 的产物字节差 | 本机只用 stock clang 23.1.3 + wasi-sdk 34 sysroot；wasi-sdk 的 clang 是 23.1.0-wasi-sdk | CI（装完整 wasi-sdk） |
| `-flto` 在 **wasm + 预编译非 LTO 归档**混合下的 TLS/线程变体 | 只用单线程 preview1；`-threads` 变体未测 | 需要时 |
| `-Wl,--lto-O` / `--lto-partitions` 调参 | LTO 默认已过门，未细调 | 若追极致体积 |
| `--strip-all`（`-s`）而非 `--strip-debug` | 项目刻意保留 `name` 段（trap 出栈名）；`-s` 会丢名。实测 `-s` 再省 ~14 KiB（`yoga_min` 104,070），但**不建议** | — |
| **运行期**（wasmtime/wasmer/browser）行为 | 本机无这些运行时，只用 `node:wasi`；`node:wasi` 与 wasmtime 的行为差未测 | CI / U1 |
| AS3 `throw/try/catch`（`setjmp/longjmp` → `-mllvm -wasm-enable-sjlj` + `-lsetjmp`）在 wasip1 的链接 | 本 seam 的 C 验收测不抛异常，未触发该路径 | U1 实施阶段（`build.ts` 已实现该旗标） |
| macOS arm64 上的等价测量 | 本机 Windows | CI（arm64 macOS） |

---

## 6. 复现命令

全部脚本在 `asaotui/measurements/wasi-probe/attrib/`（本节命令均以 `asaotui/measurements` 为 cwd，
且**每条 bash 命令前先** `export PATH="/d/Program Files/Git/usr/bin:$PATH"`）。

```bash
# 0) 工具链见 §1（一次性）；下面假设 build-tools/wasi/ 已就绪

# 1) 基线与逐符号归因（stripped + 无 strip 对照）
bash wasi-probe/attrib/matrix.sh            # → wasi-probe/attrib/matrix.log
node wasi-probe/attrib/attribute.mjs \
  wasi-probe/attrib/matrix/yoga_min_o2.wasm \
  wasi-probe/attrib/matrix/libyoga-o2.a:libyoga.a \
  ../../build-tools/wasi/wasi-sysroot-34.0/lib/wasm32-wasip1/libc.a:libc.a \
  ../../build-tools/wasi/wasi-sysroot-34.0/lib/wasm32-wasip1/noeh/libc++.a:libc++.a \
  ../../build-tools/wasi/wasi-sysroot-34.0/lib/wasm32-wasip1/noeh/libc++abi.a:libc++abi.a

# 2) --why-extract（谁抽取了哪个归档成员、为什么）
cd wasi-probe/attrib
clang++ --target=wasm32-wasip1 --sysroot=…/wasi-sysroot-34.0 -resource-dir=…/resource-dir \
  -O2 -fno-exceptions -D_LIBCPP_HAS_NO_EXCEPTIONS -L …/noeh \
  -I ../../yoga-src -x c ../../tmp/yoga_min.c -x none matrix/libyoga-o2.a \
  -Wl,--why-extract=why_min.txt -Wl,-Map=map_min.map -o yoga_min_raw.wasm
tail -n +2 why_min.txt | cut -f2 | sed -E 's/.*[\\/]//' | sort -u

# 3) 接缝验收（stripped + LTO 两档，都跑）
bash wasi-probe/attrib/run-u1-wasip1.sh     # → wasi-probe/attrib/run-u1.log
#   o2      seam_test = 140008 B (136.7 KiB)  → 17 checks, 0 failures, RESULT: PASS
#   oz_lto  seam_test =  92209 B ( 90.0 KiB)  → 17 checks, 0 failures, RESULT: PASS

# 4) 单独跑任意 wasm
node wasi-probe/run-wasi.mjs wasi-probe/attrib/u1-wasip1/o2/test_layout.wasm
```

产物 / 日志清单（均在 `wasi-probe/attrib/`）：

| 文件 | 内容 |
|---|---|
| `matrix.sh` / `matrix.log` | 地板 + 缓解矩阵（本报告 §2.2/§3 的主脚本） |
| `run-u1-wasip1.sh` / `run-u1.log` | 30 函数 + 17 用例的接缝验收（两档，含实跑） |
| `attribute.mjs` / `attr_*.txt` | 逐符号归因脚本与输出 |
| `final-numbers.log` | §2/§3 全部数字的汇总 |
| `why_min.txt` / `map_min.map` | `wasm-ld --why-extract` / `-Map` 原始输出 |
| `matrix/` | 各配置的 `libyoga-*.a`、`*.wasm`、地板控制 |
| `controls/` | `floor_*.c/.cc` 受控地板、`nolog_stub.cc` |

> 说明：`wasi-probe/wasip1-size.sh` 与 `wasip1-size.log` 是**旧口径**（无 `--strip-debug`），
> 保留为历史记录；本报告的 `matrix.sh` 是它的修正超集。
