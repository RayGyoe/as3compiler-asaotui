# Yoga 静态库 / 目标文件体积清单

> 全部为本机实测（clang 23.1.3 x86_64-pc-windows-msvc；emcc 3.1.44 见下方 wasm 段）。
> 生成日期见文件 mtime；复现：`bash build-yoga.sh <name> <flags>`。

## 1. 归档与对象总和（native）

| config | opt | `.o` 总和 (B) | `libyoga.a` (B) | 对象数 |
|---|---|---|---|---|
| `o2-nofs` | -O2 | 409551 | 461086 | 19 |
| `o2-fs` | -O2 | 458226 | 509762 | 19 |
| `os-fs` | -Os | 444964 | 511876 | 19 |
| `oz-fs` | -Oz | 562303 | 667802 | 19 |
| `o2-fs-noexc` | -O2 | 367224 | 415064 | 19 |
| `oz-fs-noexc` | -Oz | 499063 | 603596 | 19 |
| `oz-fs-noexc-noeh` | -Oz | 489752 | 593828 | 19 |
| `o2-fs-noexc-noeh` | -O2 | 364910 | 412294 | 19 |

## 2. 单个 .o 明细（最优 native 配置 `oz-fs-noexc`：-Oz + fs + fno-exceptions）

| 对象 | 字节 |
|---|---|
| `yoga_YGNodeStyle.cpp.o` | 105085 |
| `yoga_algorithm_CalculateLayout.cpp.o` | 94806 |
| `yoga_node_Node.cpp.o` | 65272 |
| `yoga_algorithm_AbsoluteLayout.cpp.o` | 56597 |
| `yoga_YGNode.cpp.o` | 49064 |
| `yoga_algorithm_FlexLine.cpp.o` | 44267 |
| `yoga_algorithm_Baseline.cpp.o` | 21216 |
| `yoga_YGEnums.cpp.o` | 16364 |
| `yoga_config_Config.cpp.o` | 7900 |
| `yoga_event_event.cpp.o` | 7322 |
| `yoga_YGConfig.cpp.o` | 5602 |
| `yoga_algorithm_PixelGrid.cpp.o` | 4758 |
| `yoga_debug_Log.cpp.o` | 4728 |
| `yoga_YGNodeLayout.cpp.o` | 3900 |
| `yoga_algorithm_Cache.cpp.o` | 3430 |
| `yoga_node_LayoutResults.cpp.o` | 3231 |
| `yoga_debug_AssertFatal.cpp.o` | 2948 |
| `yoga_YGValue.cpp.o` | 1384 |
| `yoga_YGPixelGrid.cpp.o` | 1189 |

## 3. wasm 对象（em++ 3.1.44, -O2 -DNDEBUG -DYG_NDEBUG -ffunction-sections -fdata-sections）

- `.o` 总和：**211228 B**（19 个）
- `libyoga.a`：**234470 B**

| 对象 | 字节 |
|---|---|
| `yoga_algorithm_CalculateLayout.cpp.o` | 62375 |
| `yoga_YGNodeStyle.cpp.o` | 47526 |
| `yoga_node_Node.cpp.o` | 22235 |
| `yoga_algorithm_AbsoluteLayout.cpp.o` | 20695 |
| `yoga_YGNode.cpp.o` | 16733 |
| `yoga_algorithm_FlexLine.cpp.o` | 10301 |
| `yoga_YGEnums.cpp.o` | 7305 |
| `yoga_algorithm_Baseline.cpp.o` | 3938 |
| `yoga_config_Config.cpp.o` | 3238 |
| `yoga_algorithm_PixelGrid.cpp.o` | 2999 |
| `yoga_node_LayoutResults.cpp.o` | 2784 |
| `yoga_event_event.cpp.o` | 2487 |
| `yoga_YGConfig.cpp.o` | 2213 |
| `yoga_YGNodeLayout.cpp.o` | 1446 |
| `yoga_algorithm_Cache.cpp.o` | 1392 |
| `yoga_debug_Log.cpp.o` | 1321 |
| `yoga_debug_AssertFatal.cpp.o` | 1307 |
| `yoga_YGValue.cpp.o` | 513 |
| `yoga_YGPixelGrid.cpp.o` | 420 |

## 4. 最终可执行 / wasm 产物体积

| 产物 | 字节 | 说明 |
|---|---|---|
| `c_floor.exe` | 120832 | C 驱动，printf 空程序（地板） |
| `c_floor_cpp.exe` | 120832 | C++ 驱动，同上（证明 C++ 驱动本身 0 增量） |
| `yoga_min_oz-fs-noexc.exe` | 215040 | 布局程序 + Yoga（最优 native） |
| `yoga_min_projflags.exe` | 214528 | 同上 + 项目旗标 \`-fms-runtime-lib=static\` |
| `wasm_floor.wasm` | 2072 | emcc 地板 |
| `wasm_yoga_min.wasm` | 125252 | 布局程序 + Yoga（standalone / WASI-shaped） |
| `yoga_web.wasm` | 125404 | emscripten JS-glue 路径 |
| `yoga_web.js` | 50149 | 同上 JS glue |
