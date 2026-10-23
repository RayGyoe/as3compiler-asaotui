# diff-check —— 布局差分测试（同一份输入，两台引擎）

[`../seam/README.md`](../seam/README.md) §3.2 把「两套实现必须一致」定为**硬要求**。这个目录是那条要求的落地：
**同一份冻结的输入规格**，同时喂给 **Yoga（C）** 与 **纯 AS3 引擎**，逐行比对输出。

## 为什么必须「同一份输入」，而不是「两份 harness 各断言同样的数」

两份手写 harness 各自断言同一组期望值，**可能两组数字都对、却在引擎上分歧** —— 这正是
默认 `flex-direction` 那个 bug 活下来的方式：a~e 全部**显式**设了方向，所以默认方向写错照样全绿。
只有**共用一份输入 + 比对输出**才能抓到这一类。

## 规格：`spec/cases.txt`

冻结格式（`#` 注释、空白分隔、**id 全局唯一**）：
`engine` / `node` / `root` / `dir` / `size` / `minmax` / `pad` / `border` / `gap` / `flex` / `boxsizing` / `check`，
**增量扩充**（旧行原样可用）为：
`justify` / `align` / `alignself` / `aligncontent` / `wrap` / `margin` / `pos` / `inset` / `overflow`，
`dir` 多接受 `row-reverse` / `column-reverse`，`root` 多一个**可选**尾随 `ltr|rtl`（缺省 ltr），
`pad` / `border` / `gap` / `margin` / `inset` 多一个**可选**尾随单位 token（缺省 `point`）。
唯一语法变更是这两个**可选尾随 token**，其余都是新增指令。完整表头（含每条指令的取值域）在文件顶部。

**输入与期望值在同一个文件里** —— 于是「改了输入却没改期望」是**文件内可见**的，不会在别处悄悄绕过。
`dir` **可以省略**，那一块专门用来钉 config 的默认方向；`aligncontent` **也可以省略**，那一块（`k2`）钉
config 的默认 **align-content = stretch**。

两条硬规矩：`dir` 未给时**绝不许**调 `setFlexDirection`；`root` 行触发 `calculate`，`check` 行读完后统一求值
（id 全局唯一正是为此：否则后一个 block 的 `calculate` 会覆盖前一个 block 的节点）。

## 三条臂

| 臂 | 工具链 | 引擎 | 入口 |
|---|---|---|---|
| Yoga | clang → native | Yoga（C） | `yoga-driver/yoga_driver.c` |
| AOT | 我们的 AOT → C → native | `As3LayoutEngine` | `as3-driver/DiffMain.as` |
| AIR | mxmlc → adl | `As3LayoutEngine` | [`../air-check/AirMain.as`](../air-check/AirMain.as) |

Yoga 与 AOT 两臂**读同一份 `cases.txt`**（运行时读文件：C 侧 `fopen`，AS3 侧 `flash.filesystem.File`）。
AIR 臂的用例是**内联**的（但名字/顺序/数值与 spec 完全一致）—— 见 `../air-check/README.md` 说明的取舍。

## 命令

```bash
## 臂 1：Yoga（C）
cd asaotui/diff-check/yoga-driver
export PATH="/c/Program Files/LLVM/bin:$PATH"          # 本机 clang 在这里
U1="$WORKSPACE_DIR/asaotui/u1-prototype"
clang   -O2 -D_CRT_SECURE_NO_WARNINGS -I "$U1" -c yoga_driver.c -o build/yoga_driver.o
clang++ -O2 build/yoga_driver.o "$U1/build/native/yoga_glue.o" "$U1/build/native/libyoga.a" \
        -Wl,/OPT:REF -Wl,/OPT:ICF -o build/yoga_driver.exe
./build/yoga_driver.exe ../spec/cases.txt > ../yoga.out

## 臂 2：AOT（AS3 → C → native）
cd as3compiler
node src/index.ts ../asaotui/diff-check/as3-driver/DiffMain.as \
  ../asaotui/seam/asaot/ui/LayoutConstants.as ../asaotui/seam/asaot/ui/LayoutEngine.as \
  ../asaotui/seam/asaot/ui/as3/As3LayoutNode.as ../asaotui/seam/asaot/ui/as3/As3LayoutEngine.as \
  --run --cc clang -I ./vendor/curl/include -L ./vendor/curl/lib/windows-x64 -l zlib > ../asaotui/diff-check/as3.out

## 臂 3：AIR（mxmlc → adl）—— 见 ../air-check/README.md
```

## 当前结果（本机实测）

**三条臂的 105 行 `GOT` 逐字符相同**（Yoga/C == 我们的 AOT == AIR/adl），
每条臂的自测也都是 `---- 105 checks, 0 failures ----`：

| 臂 | 结果 |
|---|---|
| Yoga | `EXIT=0`，105 checks 0 failures |
| AOT | `EXIT=0`，105 checks 0 failures，`GOT` 与 Yoga 逐字符相同 |
| AIR | `ADL_EXIT 0`，105 checks 0 failures，`GOT` 与上面逐字符相同 |

前 16 行是原有的 a~g（基线，本阶段未动）；第 17~105 行是本阶段新加的命令/语义。

## 防假绿：做过的变异测试

| 变异 | 结果 |
|---|---|
| 把纯 AS3 引擎的 `createNode` 默认方向**钉死为 column**（只改一侧） | 差分**当场抓到**：`f.child1` yoga `50.0000 0.0000` vs as3 `0.0000 40.0000 50.0000 40.0000`，AS3 臂 exit 1 |
| 在 `spec/cases.txt` 把 `h6.justifySpaceEvenly2` 的期望 `137.5` 改成 `137` | 两臂**自测各报 1 FAIL**（`got(137.5000…) want(137.0000…)`），Yoga 臂 exit 1、AOT 臂 exit 1；期望值**不是从输出抄的** |
| 在 `As3LayoutEngine.as` 把 `space-evenly` 的主轴 lead 篡改成 `0.5 * remaining / n`（即 `space-around` 的 lead 公式，只改引擎） | AOT 臂**自测 4 FAIL**：`h6.justifySpaceEvenly got(25.0…) want(32.5…)`、`h6.justifySpaceEvenly2 got(115.0…) want(137.5…)`、`i3.justifyGapEvenly got(23.3333…) want(30.0…)`、`i3.justifyGapEvenly2 got(120.0…) want(140.0…)`；这 4 行的 `GOT` 与 Yoga 分叉，**exit 1**。证明 harness 对**引擎 bug** 也有牙，不只是对「写错的期望值」 |

这三条同时证明三件事：两臂**真的**在读规格（Yoga 那行 `50,0` 只可能来自 web defaults 真的生效）、
C 侧与 AS3 侧**确实走了不同的代码路径**（不是同一份逻辑的两个壳）、这个 harness **有牙**。
三处变异均已还原，还原后复跑回全绿。

## 环境注意（踩过的坑）

- **`yoga-driver/build.sh` 在本机跑不通**：脚本内 `export PATH="/usr/bin:$PATH"` 会把 clang 挤掉
  （本机 clang 在 `/c/Program Files/LLVM/bin`，且脚本似乎跑在另一个 bash 里，`pwd` 显示 `/mnt/c/...`）。
  用上面 README 里的直编命令。
- Yoga 库复用**只读**的 `../u1-prototype/build/native/{yoga_glue.o,libyoga.a}`；本目录**不**重编 Yoga。
- 本机 bash 缺 coreutils，文本处理一律走 Node。
