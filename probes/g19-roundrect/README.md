# probes/g19-roundrect — `Graphics.drawRoundRect` must draw a ROUND rect (G19)

Two programs, one copy of each source, both runtimes:

| 源 | 测什么 |
|---|---|
| `Round.as` | **几何**：7 个 40×40 圆角矩形，逐行报「首个/末个 alpha>128 的像素」，外加 5 实参的默认调用 |
| `RoundArgs.as` | **参数契约**：NaN / 省略 / 负 / 无穷椭圆，以及负/零宽高，报「抛了什么错」或「墨迹包围盒」（整体经 +10,+10 位移画，免得负半径的溢出不落在位图里），负半径另附逐行 dump |

AOT 臂给每份源**追加一行** `var _d:X = new X();`：我们的编译器跑顶层代码，AIR 由运行时实例化
document class，所以这一行是两边唯一的差别，被测类体逐字节不变。

## 为什么不能只比「AIR 与 AOT 一致」

两端都错也会一致。所以 AOT 臂还要自证与**解析计算的理想圆角椭圆**相符：一个正确的光栅器每一行都
应在数学值 1 px 之内。这样差异能归因：

- **byte-identical**：逐字节相同；
- **within AA tolerance**（±1 px / ±2 count）：两端都贴着数学值，只是舍入；
- **AIR drift**：AOT 在椭圆 1.01 px 内、AIR 超出 —— 那是 AIR 自己的 kappa 三次曲线拟合偏心椭圆的误差
  （实测 `ew=100/eh=4` 把 AIR 顶到理想四分之一椭圆内 2 px）；
- **known**：负半径（AIR 的 cubic 自交，墨迹溢出盒子 1~2 px；我们夹到 0 = 直角），只判 verdict 一致。

## 跑法

```
node probes/g19-roundrect/run.cjs            # 双臂对照 + 解析自检
AIR_ONLY=1 node probes/g19-roundrect/run.cjs # 只刷 AIR 侧（改了源之后）
```

退出码：`0` 全行都在椭圆 1 px 内且无分歧；`1` 有分歧；`2` 构建/adl 出错。

## 状态

**已修（阶段二百六十七，v0.4.231）**。修前的生成体是 `{ (void)ew; (void)eh; Graphics_drawRect(...); }`
——两个半径被就地吞掉。当前结果：`292 行逐字节相同 / 27 行在 AA 容差内 / 0 行分歧 / 40 行已登记`，
`RESULT: PASS`。

登记处：`compiler-gaps.md` G19。回归：`as3compiler/examples/roundrect.as`（23 条像素断言）、
`unit: graphics/roundrect`（16 条源级钉）。