# G22 —— 闭包里的静态字段读取丢掉 `_cinit()` 守卫（探针）

**已修：阶段二百六十九，v0.4.233。** 缺口判定、根因与影响面见 [`compiler-gaps.md`](../../compiler-gaps.md) G22。

## 测什么

一个类的静态字段**只被闭包读**时，闭包体走的是与普通方法不同的发射路径。修前的差别很直白：

```c
/* 普通方法里 */  double v = (Bag_cinit(), Bag_SEED);        /* 先跑惰性初始化，再读 */
/* 闭包体里   */  double v = Bag_SEED;                        /* 裸读 —— _cinit() 从未被调用 */
```

于是 `static const NAMES:Array = ["alpha","beta",…]` 在运行时仍是 `NULL`，`NAMES[0]` 抛
`TypeError #1009`。这类写法的自然产物就是「页面即闭包」的 UI：常量表写成类字段，读点全在工厂闭包里。

10 格用例全部**只从闭包内**读静态字段（`ClosureCases.as`），覆盖三种形态：

1. 字面量标量常量（`Bag.SEED`）—— 修前也是对的（字面量不依赖初始化函数），留作对照；
2. 需要运行时初始化的标量（`Sealed.make()` 里算出来的 `LIMIT`）；
3. **静态数组/对象**（`Bag.NAMES[0]`、`Bag.TABLE["k"]`）—— 修前在这里崩，是主判据。

`Bag.as` 的数组字段是 `public static const`，`Sealed.as` 的常量由私有 `seed()` 算出（AS3 没有
`static {}` 块，`mxmlc` 直接拒绝那种写法）。

## 判据

`node probes/g22-closure-statics/run.cjs` 要求同时满足三件事：

1. **两端逐字相同**：同一份 `expect.json` 手推答案，`adl` 与 AOT 各自写出的 10 行必须一字不差；
2. **生成的 C 自证**：每个**运行时**静态读（排除字面量/常量折叠处）都必须带 `(Owner_cinit(), …)`；
3. **前向声明先于首次调用**：`run()` 里补的那轮 `static void <Cls>_cinit(void);` 必须出现在闭包体定义之前
   —— 只有守卫没有声明，C 会以「隐式声明」直接拒绝这份程序（`mutation.cjs` 的 M2 就是这条的见证：
   它得到的不是「答案错」，而是构建失败 exit 2）。

第 2、3 条不是「顺手多看一眼」：修法的两半缺一不可，而它们**都能生成能跑但语义错的 C**（第 2 条）
或**根本编译不过**（第 3 条），只比较运行结果会漏掉一半。

## 命令

```sh
node probes/g22-closure-statics/run.cjs            # 双 arm + 生成 C 审计
ASC_SKIP_AIR=1 node probes/g22-closure-statics/run.cjs
node probes/g22-closure-statics/mutation.cjs       # 证明 run.cjs 会红（4/4）
```

退出码：`0` 通过；`1` 有分歧；`2` 构建/adl 出错。

## 变异（`mutation.cjs`，4/4 命中）

| # | 变异 | 期望 | 实际 |
|---|---|---|---|
| M1 | 删掉提前的 `collectCinitClasses()` | run.cjs 红 | `RESULT: FAIL` |
| M2 | 删掉提前的前向声明 | 构建失败 | `AOT BUILD FAILED`（exit 2） |
| M3 | 改 `expect.json` 一个答案 | 与参照不一致 | `the REFERENCE disagrees` |
| M4 | 改 `ClosureCases.as` 的读点 | 与参照不一致 | `the REFERENCE disagrees` |

每个变异都会在结束时**逐字节还原**（sha256 校验）。

## 状态

**已修（阶段二百六十九，v0.4.233）**：10/10 两端逐字相同，M1–M4 全部被抓。
回归：`as3compiler/examples/closure-statics.as`（11 断言）、`unit: closure/statics`（9 条源级钉）。

工作区的绕行脚手架（`ui-demo/demo` 里 7 个常量类的 `warmUp()` 与 `DocsMain` 的调用）已随修复删除
—— 留一份「手动热身」就等于把这个缺陷永远盖住。