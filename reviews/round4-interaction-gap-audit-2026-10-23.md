# 第四轮缺口审计：交互层（hover / focus / keyboard / text input）

日期：2026-10-23 · 对应 HEAD `caefc98` · 只读扫描，**未改任何源码**

本文件回答一个问题：**控件集已经 31 个 kind 了，但「用起来」还差什么？**

结论：差的不是控件数量，而是**一条交互管线**。库里有状态字段、有事件监听、
有编译器侧的键盘/焦点运行时，但三者在中间**没有接上**——状态写得进去、读不出来。

---

## 0 扫描口径

所有结论来自对源码的字面扫描，不是凭文档：

| 项 | 数值 | 命令 |
|---|---|---|
| `kit/` 下 `.as` | 138 | `node .scratch/scan-gaps.cjs` |
| `kit/asaot/ui/` 顶层 `.as` | 88 | 同上 |
| `kit/asaot/ui/kind/*.as` | 32 | `node .scratch/scan-gaps3.cjs` |
| 调 `PaintKit.paintBox` 的 kind | 18 | 同上 |
| `Style` 字段 | 31，**无一个随状态变化** | 同上 |

---

## 1 交互状态：写进去了，没人读（最便宜的一处）

**事实链**：

1. `ElementState.as:15-18` 声明 `hover / pressed / focused / disabled` 四个字段。
2. `UiNode.as:170-171` 真的挂了 `MOUSE_OVER` / `MOUSE_OUT`，`UiNode.as:180-195` 的
   `setHover/setPressed` 会改字段并 `markPaint`。
3. **但 `PaintKit.as` 全文 0 处读 `state.hover` / `state.pressed`**；32 个 kind 里
   读这两个字段的也是 0 个（扫描：`state.hover` 命中文件数 = 1，就是 `UiNode.as` 自己）。
4. `Style` 的 31 个字段里没有任何 `hover*` / `pressed*`，所以即便想画也无处取值。

⇒ **鼠标悬停、按下，在屏幕上没有任何视觉反馈**。这不是某个控件的疏漏，是整层缺失。

**`disabled` 更彻底**：`Node.as` / `Element.as` / `Control.as` 三个声明层**连字段都没有**
（扫描结果均为 `no`），只有 `ElementState.disabled` 这个无人写入也无人读取的变量。
⇒ 现在**无法禁用任何控件**，也没有「禁用态不响应点击」的闸门。

**修改成本**：`PaintKit.paintBox` 一处派生（pressed 压暗、hover 微提亮、disabled 降不透明），
18 个 kind 自动受益，不动 `Style` 公共面；`disabled` 需要 `Node` + 工厂选项 + `handleClick` 闸门。
**风险**：所有像素基线会变 ⇒ 6 张画廊截图 + 相关探针要重出，变异门要补。

---

## 2 键盘 / 焦点：缺口在库，**不在编译器**（重要纠正）

此前 `STATUS.md` 记「键盘/焦点 0 处」，容易被读成「AOT 不支持」。实测编译器源码：

| 能力 | 编译器侧证据 |
|---|---|
| `KeyboardEvent` 构造与分发 | `as3compiler/src/emit.ts:12469` |
| Tab / Shift+Tab 焦点环 | `emit.ts:11734`（`as_tab_scan`）、`:11755`（`as_focus_tab`）、`:12491`（keyCode 9 触发） |
| `TextEvent.TEXT_INPUT` | `emit.ts:12509`、`runtime.ts:9315` |
| `FOCUS_IN` / `FOCUS_OUT`（含 AIR 顺序：FOCUS_IN 先于 mouseDown） | `emit.ts:11645-11649`、`:17802` |

而 `UiApp.as` **对 `Keyboard` / `KEY_` / `focus` / `Focus` 的命中数全部为 0**。

⇒ 运行时齐了，`UiApp` 一个监听都没挂。这意味着 `dialog`(Esc/Tab 陷阱)、`menu`(方向键)、
`select`(键盘选择)、`list`(上下键) **现在就能做**，不必等编译器。
已知运行时限制只有 **G3**（Tab 环上限 64 个、扁平静态扫描）。

---

## 3 文本输入：`textField` 是「只读镜像」

`kind/InputWidget.as` 自述（第 6-10 行注释）：

> there is no TEXT_INPUT listener writing edits back, so a repaint reverts typed text
> and `onCommit` is never called.

`paint()` 每次把模型写进 `n.tf`（`if (n.tf.text != shown) n.tf.text = ...`），
而**没有任何反向写回**。⇒ 用户输入一次重绘就被擦掉，`onCommit` 永不触发。
此文件里 `TEXT_INPUT` 的唯一命中就是这段注释本身，**不是代码**。

这是本库当前**唯一「看起来能用、实际不能用」**的控件。

---

## 4 建议顺序（按「解锁下游多少」排，不按「哪个控件缺」排）

| 序 | 事项 | 解锁 | 规模 | 代价 |
|---|---|---|---|---|
| 1 | `disabled` 字段 + `PaintKit` 状态派生 | 全库 18 个绘制型控件的 hover/pressed/disabled 观感；禁用闸门 | 小（1 处派生 + 3 处声明 + 工厂选项） | 像素基线全变，需重出 6 张截图 |
| 2 | `textField` 输入回写 | 修好唯一「假能用」控件；`onCommit` 生效 | 中（TEXT_INPUT + 焦点 + Enter/blur 提交 + 聚焦期间不覆盖） | 需新探针（输入不可脚本模拟 → 探针走直发 `TextEvent`） |
| 3 | `UiApp` 键盘/焦点管线 | 一次性解锁 dialog/menu/select/list 的键盘操作 + Tab 序 | 大（`UiApp` 路由 + 焦点栈 + 各 widget `onKey`） | 契约面扩张（`Widget` 是否加 `onKey`，类比 `WidgetTeardown` 的取舍） |
| 4 | 浮层越界翻转 / 子菜单 / 开合动画 | 浮层观感 | 中 | 只在 overlay 内 |

**不建议**现在继续加控件（`steps` / `carousel` / `calendar` 等）：在 §1 修好之前，
新控件同样没有 hover/pressed/disabled，只是把缺口复制一遍。

---

## 5 未做（审计当时）

- 审计当时未修 §1/§2/§3 任何一条，未产生像素或探针变更；
- `as3compiler/` 当时带两个**本地补丁**（`runtime.ts` 转义、`window_glue.cc` 菜单空桩），
  已登记 G17/G18，指纹如实报脏。

---

## 6 结案（2026-10-24）：四条全部关闭

| 审计项 | 状态 | 证据 |
|---|---|---|
| §1 hover/pressed/focused/**disabled** | ✅ 关 | `PaintKit.drawBoxFor`/`stateColor` 派生四态（只对可交互节点）；`Element.disabled` + `UiNode.inert()`；探针 `probes/widgets/interact` **25 项**、变异 **8/8** |
| §2 键盘/焦点管线 | ✅ 关 | `UiApp` 接 `KEY_DOWN`/`FOCUS_IN`/`FOCUS_OUT`：Tab/Shift+Tab 环（保留树遍历 + 浮层焦点陷阱）、Esc、方向键、Enter/Space；契约用**可选接口** `WidgetKeys`/`WidgetFocus`（`Widget` 不加方法，与 `WidgetTeardown` 同一取舍） |
| §3 `textField` 回写 | ✅ 关 | `Event.CHANGE` → `n.value`/`Binding`/`onChange`；Enter/失焦 → `onCommit`；Esc 回滚；占位符独立层；重绘不重赋 `tf.text`（保 caret）。审计时担心「输入不可脚本模拟」，实测**直接改 `tf.text` 再派发 `Event.CHANGE`** 就够（探针就是这么做的） |
| §4 浮层翻转/子菜单/开合动画 | ✅ 关 | 四向翻转 + 夹回窗口（`probes/widgets/flip` 54 项 / 变异 5/5）；子菜单 = 普通 `menu` + `anchorKey`（overlay 探针 M8/M9）；入场动画 `OverlayMotion` |

**审计的两条判断被实测证实是对的**：①「不建议继续加控件」——本轮确实一个控件没加，
而是把已有 31 kind 点亮；②「键盘缺口在库不在编译器」——`UiApp` 挂上监听后立刻可用，
编译器侧只需要 G3（Tab 环上限 64）这一条已知限制，**零改动**。
