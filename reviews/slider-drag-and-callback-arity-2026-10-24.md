# 拖一下滑块就报错、滑块也不动 —— 回调参数个数 + 滑块没有拖动（2026-10-24，第九轮补）

> 用户报告（第二张截图，原文「**这个拖动后报错**」）：在组件文档站的 `slider` 页按住滑块拖动，
> 控制台抛一行 `#1063: Argument count mismatch`，滑块**不跟手**、松手也不动。
> 与上一轮的 toast 报错（[`docs-demo-option-drift-2026-10-24.md`](docs-demo-option-drift-2026-10-24.md)）
> 形态相同：**屏幕上只有一个报错，页面其它部分都正常**。

## 1 结论先行

**不是编译器缺陷，是两个库侧缺陷叠在同一个控件上**（`kit/asaot/ui/kind/SliderWidget.as`）：

1. **调用传 0 个实参，声明要 1 个形参 ⇒ `#1063`。** `n.onChange()` 被调用时不给参数，而
   文档站每一页写的是 `function (v:Number):void`。AVM2 上**实参少于形参即抛**
   （不像 JS 补 `undefined`）；帧守卫（`emit.ts` 的 `as_throw` → `longjmp`）接住它 ⇒
   处理函数**从未运行**、模型从未变、屏幕停在上一棵树，唯一痕迹是控制台。
   同一个形状还在 `CheckboxWidget` / `SwitchWidget` / `RadioWidget` 里（`RadioWidget` 是
   `onChange()` 少了那个恒为 `true` 的常量）。
2. **滑块本身没有拖动机制。** 旧实现只有「按下就地设值」：`MOUSE_DOWN` 里算一次
   `valueAt(localX)` 就结束，之后移动鼠标什么都不发生 —— 一个「看起来能拖」的控件。

## 2 为什么 40 道门都没抓住

| 现有守卫 | 为什么看不见 |
|---|---|
| `probes/widgets/form`（41 项，最早覆盖滑块的探针） | 它的滑块用例**只点绑定了 `binding` 的控件**：走 `Binding` 分支，`onChange` 那条路径**从未被执行**。（这一次已把它改成真实按下，但它的主题仍是绑定控件，未绑定那条新开了探针） |
| 41 页画廊截图扫描 | **只渲染、不点击**。`#1063` 抛在**事件回调**里，截图时根本没有回调 |
| `tools/demo-options.cjs`（上一轮新增） | 只扫**选项键名**，与回调签名无关 |
| 帧守卫本身 | 它让「抛错」变成**可见性问题**而不是崩溃：页面继续渲染，所以只翻截图永远发现不了 |

上一轮得出的结论在这里第二次成立：**错误只在「真点击」的路径上暴露**。

## 3 修法

- 四个调用点补参数：`onChange(next)` / `onChange(next)` / `onChange(true)`（radio 的选择是常量）。
- `SliderWidget` 按 `ScrollViewWidget` 的同一套写法重写：
  - `implements Widget, WidgetTeardown`；
  - 按下：`endDrag` 一次（幂等）→ 记起本地几何 → `commit(valueAt(localX))` → 在 **stage** 上挂
    `MOUSE_MOVE`/`MOUSE_UP` 临时监听（闭包存 `n.extra["dragmv"]/["dragup"]`，**按引用**摘除）；
  - 拖动：`valueAt` 用 `localX / absW`（1:1 跟手，不做「减滑块长」的换算）并夹在 `0..1`；
  - 松手 / 下一次按下 / `teardown`：都走同一个 `endDrag` —— 摘监听 + 清拖动标志；
  - **单一写入点** `commit(v)`：状态 → `Binding` → `onChange(v)` → `markPaint(n)` →
    `invalidate(Dirty.VALUE)`；**值没变不报**（一次手势只写一次模型）。
- `UiNode.as` 顶部登记三条契约（`onClick()` 零参 / `onChange(v)` / `onCommit(v)` 各一个），
  `CONTRIBUTING-widget.md` §2d 同步成硬约束。

**为什么「控件欠屏幕自己的重绘」要单独说**：`invalidate(Dirty.VALUE)` 只会重跑描述/协调；
滑块的标签是**常量**，没有任何布局/描述变化 ⇒ 若不 `markPaint`，拖动时旋钮根本不动
（而值、模型、`onChange` 全对）。这一条被新探针钉在**拖动中间那一帧**。

## 4 新增的两层钉子

### 4.1 行为面：`probes/widgets/callback`（门，24 项，变异 8/8）

写这个探针时踩了三个坑，每个都值得记住（探针注释里逐条写明）：

1. **手势必须包 `try/catch`**：未捕获的 `#1063` 会**掀掉整次派发**，探针的 `setTimeout` 链就此断掉、
   `<name>.done` 永远不写 ⇒ 工具报的是**不透明的 TIMEOUT**，而不是「回调没跑」。
   包住之后才拿到「具名失败」。（这一点也是 `probes/widgets/callback/mutation.cjs` 能出结果的前提：
   首版 M1–M6 全是 `TIMEOUT -- an opaque failure is not a named one`。）
2. **文件作用域的初始化按源码顺序发**：`var threw:String = ""` 写在 `stage.showWindow(...)`
   **之后** ⇒ 那条赋值落在主循环之后，**永不执行**，变量一直是 `NULL`，于是
   `threw != ""` 恒真 ⇒ 一次「什么都没抛」的运行反而报 `a gesture threw: null`。
   它现在与其他顶层状态放在一起，注释写明原因。
3. **像素断言必须取在「单独一次 move」之后的那一帧**：按下（`setPressed` 抬重绘）或松手
   （翻转 pressed）都会自己抬一次重绘，把「控件没自抬重绘」这个缺陷**盖住**。
   实测：第一版把按下+移动放在同一个回调里 ⇒ 变异 M5（去掉 `markPaint`）**MISSED**；
   拆成「press 一帧 / move 一帧 / 采样」之后 M5 变红并点名
   `the fill after a drag to 0.75 (the knob must follow the drag) is #ffffff not #2563eb at (60,144)`。
   同一帧里灰色轨道是被 pressed 染色过的 `#CACBCF`（不是 `#E5E7EB`），所以裸轨道的采样放在松手之后。

覆盖：checkbox/toggle/radio 的未绑定点击（含「已选中的 radio 再点一次不再上报」）、
滑块的 按下→拖到 0.75→越界夹到 1→拖回 0→松手→松手后再移动必须无效→纯点击设 0.5，
以及两个像素帧（拖动中 / 松手后）。

变异 8/8（`probes/widgets/callback/mutation.cjs`，每次 `finally` 还原并 sha256 逐字节核对）：

| # | 变异 | 结果 |
|---|---|---|
| M1 | 滑块重新用 `onChange()`（**用户报告的那个缺陷**） | 红 |
| M2 | checkbox 用 `onChange()` | 红 |
| M3 | switch 用 `onChange()` | 红 |
| M4 | radio 丢掉常量 `true` | 红 |
| M5 | 去掉 `markPaint`（只 `invalidate`） | 红（**取样帧改对之后**，见上） |
| M6 | 松手什么都不结束（监听与标志都留着） | 红 |
| M7 | 拖动时忽略鼠标移动 | 红 |
| M8 | 去掉「值没变不报」的闸门 | 红 |

> M6 的第一版只删 `removeEventListener` 两行 ⇒ **MISSED**，原因不是夹具坏了，而是实现有**两道防线**
> （摘监听 + 清标志）：任一单独存在都使「松手后的移动」无效。变异的语义因此改成
> 「松手什么都不结束」，一条概念一次改动。这条也如实登记：**单删摘监听那一行是行为上不可见的**
> （只是每个被销毁的滑块多留一个空转闭包），目前无人钉 —— 与 `ScrollViewWidget` 的现状相同。

### 4.2 静态面：`tools/callback-arity.cjs`（门，变异 6/6）

双向源码扫描（能感知注释与字符串边界）：

- **方向一**（kit）：每个值回调**调用点**恰好 1 个实参，`onClick` 恰好 0 个；
- **方向二**（`ui-demo/demo` + `probes/`）：每个 `onChange`/`onCommit` **声明**恰好 1 个形参，
  `onClick` 0 个。

首版两处误报并已修：`PanelShellWidget.onClick(n,e)` 是**静态方法**（跳过首字母大写的接收者）、
`static function onClick(n,e)` 是**方法声明**而非调用（要求点号）。

现状 **15 个调用 / 81 个声明 / 0 违规**。**它看不见什么**（如实登记）：按引用传的回调
（`onChange: this.tabChanged`）解析不到 —— 那一半只能靠行为门。

## 5 验证

```sh
cd asaotui
node tools/callback-arity.cjs                                                # 0 violations
AIRSDK_HOME=… ASC_CC=clang node tools/probe.cjs probes/widgets/callback      # 24 checks, 0 failures
AIRSDK_HOME=… ASC_CC=clang node probes/widgets/callback/mutation.cjs         # 8/8 caught
node tools/mutation-callback-arity.cjs                                       # 6/6 caught
AIRSDK_HOME=… ASC_CC=clang node tools/probe.cjs probes/widgets/form           # 41 checks, 0 failures
AIRSDK_HOME=… ASC_CC=clang ASC_NO_OPEN=1 node run-gallery.cjs                # 41 页 / badPages=0
node tools/gates.cjs                                                         # 40 道门（reviews/gates-all-23.txt）
```

## 6 未做

- 滑块**无 pointer capture**（后端没有），所以拖动期间监听挂在 stage 上；出了窗口再回来仍跟手，
  但**没有**「拖出窗口自动取消」的语义（AIR 也没有）。
- 拖动**不做吸附/步进**（`step` 选项不存在）：需要整数取值的作者自己在 `onChange` 里取整。