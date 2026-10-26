# 新增一个 `asaot.ui` 控件（贡献者契约）

> 给 AI worker 与人类作者。**照抄 `chip` 三件套**即可；本文件说明为什么。
> 参考实现（已实测 19/19 全绿、经两次变异证明检查器有牙）：
>
> ```
> kit/asaot/ui/ChipNode.as          描述节点（类）
> kit/asaot/ui/chip.as              工厂函数（小写文件名！）
> kit/asaot/ui/kind/ChipWidget.as   行为实现（Widget 接口）
> probes/widgets/chip/Main.as       自带探针
> probes/widgets/chip/expect.json   手算期望值
> ```

---

## 0 硬性禁令

| 禁止 | 原因 |
|---|---|
| 改 `as3compiler/` 任何文件 | 项目级承诺（占阶段号 + 全量回归）。工作全在 `asaotui/` |
| 改 `UiNode.as` / `UiApp.as` / `Reconciler.as` / `Widget.as` / `Widgets.as` / `PaintKit.as` / `Node.as` / `Element.as` / `Control.as` | 由协调者独占；并行改会互相覆盖。**缺扩展点就报回来，不要自己动** |
| 改 `style/Style.as` / `style/StyleRefinement.as` | 另一路 worker 正在改 |
| 改 `ui-demo/kit-list.cjs` | 已改为**自动发现**，你新增的 `.as` 不需要登记 |
| 用 `|| echo` 之类吞掉失败 | 假绿陷阱。要判绿必须看退出码 |
| 一次删多个证据文件 | 先看清再删 |

**你只能新建/修改**：`kit/asaot/ui/<X>Node.as`、`kit/asaot/ui/<x>.as`、`kit/asaot/ui/kind/<X>Widget.as`、`probes/widgets/<x>/**`。

---

## 1 三件套配方

### 1.1 描述节点 `kit/asaot/ui/ProgressNode.as`

```as
package asaot.ui
{
    import asaot.ui.kind.ProgressWidget;

    public class ProgressNode extends Control
    {
        public var label:String;
        public var value:Number;          // 0..1

        private static var registered:Boolean = false;

        public function ProgressNode(l:String):void
        {
            super("progress");            // ← kind 字符串，全库唯一
            if (!registered) { registered = true; Widgets.register("progress", new ProgressWidget()); }
            this.role = "progressbar";    // ← 必须非 null，Reconciler 会抛
            this.tabEnabled = false;
            this.label = l;
            this.value = 0;
        }
    }
}
```

### 1.2 工厂 `kit/asaot/ui/progress.as`（**文件名必须小写**）

```as
package asaot.ui
{
    public function progress(label:String, opts:Object = null):Node
    {
        var n:ProgressNode = new ProgressNode(label);
        OptionSupport.applyOpts(n, opts);
        if (opts != null && opts.value != null) n.value = Number(opts.value);
        if (n.ariaName == null) n.ariaName = label;
        return n;
    }
}
```

### 1.3 行为 `kit/asaot/ui/kind/ProgressWidget.as`

实现 `Widget` 的 **7 个方法**（见 §2）。参考 `kind/ChipWidget.as`。

---

## 2 `Widget` 接口契约（逐条都要遵守）

| 方法 | 何时调用 | 规则 |
|---|---|---|
| `build(n)` | **仅**结构期一次 | 往 `n.backing` 加显示对象，**低的先加**。可设 `n.shapeA`/`n.shapeB`/`n.tf`（UiNode 预留槽位）。结构期可分配 |
| `payload(n, desc)` | **每帧** reconcile 时 | 把本 kind 的字段镜像到节点上。**变了要 re-measure 就 `return true`**；只是装饰变化就 `n.dirty \|= Dirty.M_PAINT` 并 `return false`。用 `n.extra["…"]` 记上次值，**绝不每帧无条件返回 true**（那会每帧重排） |
| `wantsPress()` | 结构期一次 | 要不要 MOUSE_DOWN/UP 的按下态（纯视觉，永不重排） |
| `measure(n)` | pass 1，可多次 | 只写"内在尺寸"：用 `PaintKit.measureField(n, n.tf, text, s)` 量文字，`PaintKit.autoW/H(s)` 判断是否自适应，然后 `PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, v)` |
| `arrange(n)` | pass 2 | `n.absX/absY/absW/absH` 已是解算结果。放内部显示对象；用 `PaintKit.insetX/insetY/contentW/contentH(n)` |
| `paint(n)` | pass 3 | 画。**稳态零分配**（见 §5）。背景/边框走 `PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n))` 。若要「下一帧接着画」（动画自走），结尾调 `n.app.markPaint(n)`——驱动是**先清位后画**，所以这样抬的请求会活到下一帧；但**不得**同时抬布局位（那会让整棵树每帧重解，`probes/widgets/feedback` 两句断言钉着） |
| `click(n)` | 点击时 | **返回 true = 我消费了这次点击**，`onClick` 不会再触发（复选框就是这么做的）。否则返回 false |

**`n.desc`** = 本帧的描述节点，可 `ProgressNode(n.desc).value` 读本 kind 字段。
**`n.extra`** = 每节点私有 scratch，**结构期分配一次**，稳态零分配。

**顺序铁律：`resolveStyle()` 先跑，`payload()` 后跑。** 于是：

1. 读 `n.resolved.*` 拿到的是**本帧**已解算的值（不是上一帧）；
2. 若 `payload` 改的是**喂给 resolve 的东西**（`BoxNode.direction` → `n.directionOverride` 就是如此），
   必须在 `return true` 之前**显式重解一次**——style 指针在后续帧不变，**之后不会有任何东西再来 resolve 它**，
   于是该字段永远停在第一帧的值（多页 demo 的 `body` 槽位曾因此沿用**上一页的方向**布局）。
   `UiNode.applyPayload` 已替 `directionOverride` 做了这件事：`resolveStyle(true)`——
   `true` = 保留 `previous`（它是动画的「起点」，重定基准会静默吃掉同帧的 tween）。
   **新控件若也往 resolve 里喂料，照这个模式加。**

### 2b 可选销毁钩子 `WidgetTeardown`（**只要你在 `build()` 里挂了节点外的东西，就必须实现**）

```as3
public interface WidgetTeardown { function teardown(n:UiNode):void; }
```

`Widget` 是已发布契约，不因销毁再多一个方法；需要清理的 kind 写
`class FooWidget implements Widget, WidgetTeardown`。
`UiNode.destroySubtree()` 会在 **null 掉 `n.extra`/`n.backing` 之前**调用它（顺序：`Anim.clear` →
`teardown` → 递归子件 → 置空），`Reconciler.destroyRoot()` 对整棵根子树同样如此。

| 你在 `build()` 里做了什么 | 必须在 `teardown()` 里做什么 |
|---|---|
| `stage.addEventListener(...)`（弹层的「点外面关闭」） | `Stage(st).removeEventListener(...)`。**不拆的后果不是泄漏，是崩溃**：下一击回调读已 null 的 `n.extra` → `#1009`，整个 App 死掉（阶段：浮层六件已踩，
`ui-demo/mutation-gallery-teardown.cjs` M1 可复现） |
| `setTimeout` / `setInterval`（吐司自动关） | `clearTimeout` / `clearInterval` |
| 全局注册表（`Widgets.register` 除外） | 注销。稳态不得增长 |
| 只往 `n.backing` 加子件 | 不需要实现这个接口（节点自己拆） |

**探针测不出来这一类缺陷**（探针只建不拆）⇒ 钉子必须放在**多页 tour**里（`stage.numChildren` 回基线 +
`findByKey(已关闭的弹层) == null`）。

---

### 2c 可选键盘/焦点钩子 `WidgetKeys` / `WidgetFocus`（**想参与 Tab 环就必须读**）

```as3
public interface WidgetKeys  { function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean; } // true = 我消费了
public interface WidgetFocus { function focusTarget(n:UiNode):DisplayObject; }                  // 缺省 = n.backing
```

`UiApp` 的管线（在 stage 的 `KEY_DOWN` 上）：

1. **Tab / Shift+Tab**：`focusNext(dir)` 遍历**保留树**（不是运行时的 `as_tab_scan`），
   收集条件只有一条：`n.tabEnabled && !n.inert()`。焦点已在 `overlayRoot` 子树里时**不逃出去**（焦点陷阱）。
2. **其它键**：先给**焦点节点自己**的 `WidgetKeys.onKey`（它自己再沿 widget 接口找），
   **没人消费才**把 `Enter(13)`/`Space(32)` 当成一次点击——**`TextField` 例外**（那是打字）。
3. 焦点一换：旧节点 `setFocused(false)`、新节点 `setFocused(true)`（`M_PAINT`），
   `applyStageFocus()` 把 stage 焦点真的设过去（`focusTarget()` 可返回内部的 `TextField`）。

**你要做什么**：

| 你的控件是 | 要做的事 |
|---|---|
| 可点击的按钮类 | **什么都不用做**（13/32 自动当点击，焦点环由 `PaintKit.drawBoxFor` 画） |
| 有内部选中态（菜单/下拉/标签页） | 实现 `WidgetKeys`，处理上下/左右/Esc（参考 `kind/MenuWidget.as`、`kind/SelectWidget.as`） |
| 内部有真 `TextField` | 实现 `WidgetFocus.focusTarget` 返回那个 `TextField`（参考 `kind/InputWidget.as`） |
| 想在 `build()` 之外接管 Esc（浮层壳） | 实现 `WidgetKeys` 并**只在 `closeOnScrim` 时**吃 Esc（参考 `kind/PanelShellWidget.as`） |

**不要**自己在控件里 `stage.addEventListener(KeyboardEvent.KEY_DOWN, …)`：那会绕过焦点环、
在销毁时又漏拆监听（§2b）。库里已有 `WidgetKeys` 的地方一律走它。

### 2d 回调契约：参数个数是**运行时语义**，不是代码风格

AVM2 上**实参比形参少就是 `#1063 Argument count mismatch`**（不像 JS 那样补 `undefined`）。
它不会 `throw` 到你的 `try` 里，而是被**帧守卫**接住：控制台一行流、这一帧回滚、
**回调根本没跑**——屏幕保持上一棵树，看上去像「点了没反应」。

这条库里已经踩过：四个开关类控件的 `n.onChange()` 少传了参数，而每个调用方都声明
`function (v:Number)` ⇒ 所有开关与滑块的回调**全是死的**（`STATUS.md` §3.10）。

**三条契约，写新控件时当硬约束（`UiNode.as` 顶部同名注释）**：

| 回调 | 参数 | 例 |
|---|---|---|
| `n.onClick` | **0 个** | `onClick: function ():void { … }` |
| `n.onRightClick(x, y)` | **恰好 2 个**：**本帧事件坐标**（不是节点局部坐标） | `onRightClick: function (x:Number, y:Number):void { m.atX = x; }` |
| `n.onDoubleClick()` | **0 个** | `onDoubleClick: function ():void { … }` |
| `n.onChange(v)` | **恰好 1 个**：新值（`Boolean` / `0..1` 的 `Number` / 文本 / 索引） | `onChange: function (v:Number):void { slVal = v; }` |
| `n.onCommit(v)` | **恰好 1 个**：提交值（失焦/Enter 时） | `onCommit: function (v:String):void { … }` |

**`Control.action` / `Control.tabIndex` 是作者的，不是控件的**：一旦 `action` 有值，`Enter`/`Space`
走 `ActionRegistry.dispatch(action)` 而**不再**走 `onClick`（一次按键一个效果）；`tabIndex` `-1` = **没有显式序**
（不是「不可 Tab」，后者归 `tabEnabled`/`disabled`）。控件**不得**自己绕过这两条去接 `KEY_DOWN`。

**两道门钉着它**（都得过）：`tools/callback-arity.cjs` 扫**源码两边**（kit 的调用点恰好 1 实参、
`ui-demo` 与 `probes` 的声明恰好 1 形参，`onClick` 两边 0），变异 6/6；行为面是
`probes/widgets/callback`（只点**未绑定**控件 —— 走 `Binding` 的控件**压根不经过 `onChange`**，
所以 `probes/widgets/form` 比它先诞生却一直没发现这个缺陷）。

**写拖拽类控件时顺带记住**：没有 pointer capture ⇒ 拖动期间在 **stage** 上临时挂
`MOUSE_MOVE`/`MOUSE_UP`，闭包存 `n.extra` 里以便**按引用摘除**，`endDrag` 要**幂等**
（松手、下一次按下、`teardown` 三条路都会走到），并且松手后要**清拖动标志**
（即使监听已摘，标志是第二道防线——见 `kind/SliderWidget.as`）。

---

## 3 值类型与 unset 哨兵

| 类型 | 未设哨兵 | 构造 |
|---|---|---|
| `Number` | `NaN` | 直接给 |
| `String` / 对象 | `null` | 直接给 |
| `Length` | `null` | `Length.px(8)` / `Length.pct(0.5)` / `Length.AUTO` |
| `Edges`（padding/border） | 各边 `NaN` | `Edges.all(8)` / `Edges.hv(h,v)` / `Edges.of(t,r,b,l)` |
| `Size` | 分量为 `null` | `Size.of(w,h)` |
| `Corners` | 各角 `NaN` | `Corners.all(8)` / `Corners.of(tl,tr,br,bl)` |
| `Fill` | `null` | `Fill.solid(0xRRGGBB)` / `Fill.fromArgb(a,r,g,b)` |
| `TextStyle` | 分量哨兵 | `TextStyle.fromAny({...})` |

`pct(0.5)` 的作者侧是 **0..1**，不是 0..50。

**样式面当前可用字段**（写样式只能用这些，别碰还没接线的）：
`flexDirection, size, minSize, maxSize, flexGrow, flexShrink, flexBasis, padding,
borderWidths, gap, gapX, gapY, boxSizing, background, border, borderColor,
cornerRadii, opacity, visibility, text`

> **样式面 31 字段已全部落地**（`style/Style.as`；`justifyContent/alignItems/alignSelf/alignContent/flexWrap/margin/inset/position/aspectRatio/display/overflow` 都已接线）。
> 仍刻意缺席：`grid`、`boxShadow`、`cursor`（引擎不实现，`applyEngineStyle` 会抛错）。完整清单见 [`STATUS.md`](STATUS.md) §3.2。

---

## 4 会咬人的编译器/平台事实（都实测过）

1. **G7 一个文件只能有一个与文件名同名的外部可见定义**（mxmlc 硬报错）。且本机文件系统**不区分大小写**：`progress.as` 与 `Progress.as` 是**同一个文件**。所以类叫 `ProgressNode`、工厂文件叫 `progress.as`。
2. **mxmlc 的文件名匹配区分大小写**（Windows 上也区分）。`p/lower.as` 里放 `lower()` 能编过；`p/Mixed.as` 里放 `mixed()` → **硬错**。
3. **`Array` 进 `Object` 槽的身份问题：曾经会崩，已随 G14 修好**（2026-10-23 实测；编译器 **阶段二百五十三**）。**修前**：`Number/String/Boolean` 进 `Object` 槽会**装箱**，`Array` **不会**（裸指针 cast）⇒ `is Array` 折成 `false`、`as Array` 得 `null`、`.length` 得 `undefined`，`o is <用户类>` 把数组头当 vtable 读 ⇒ `0xC0000005`（`*` 槽同样崩）。当时 style 层**因此**把每个入口按形参类型拆成「标量 `fromAny(o:Object)` / 数组 `fromArray(a:Array)`」。
   **现状**：该拆分**已回退**——`Size / Edges / Corners / LengthEdges / Fill.fromAny` 自己 `if (o is Array)` 分派，`fromArray` 保留为**显式**入口（渐变那条路要它）。⇒ **写法照旧**：数组**可以**直接传给 `Object`（或 `*`）形参，`is Array` 也照常回答。两 runtime 逐字对照：`node probes/style-fromany/run.cjs`（19 格，AOT 与真 AIR 51.4.1 全一致，变异 4/4）。
   ⚠️ **别**把「防御性的 `if (o is Array) return null;`」当成好习惯：它曾经**编译成 `if (false)`**（死代码——`Fill.fromAny` 里那句就是这么被发现的）。**要留就留真的**，且必须有探针证明它真会被执行到。
4. **`with` 是保留字**：不能做方法名（`withPatch` 是为此改的名）。
5. **符号名逐字进生成的 C**（G8）：别用 `bind`（撞 socket `bind(2)`）、`stat`（被 MSVC `stat→_stat64i32` 宏吃掉）等 libc 保留名做函数/方法名。**注（2026-10-23）：上游阶段二四七已把保留名表改成机器生成、文件作用域用 `__` 后缀，G8 已修**（`probes/name-collision/` 4→0 errors）。公开 API 仍叫 `bindTo`：**这是主动选择，不再是被逼的**——① 不依赖编译器的 C 名剪辑，机制一回归就又是 `conflicting types for 'bind'`（而错误文案会把人引向 socket）；② `bindTo` 读起来就是“bind to X”。⇒ **别为“消除绕行”而改回 `bind`**（参见 `compiler-gaps.md` G8 行）。
6. **AOT 拒绝裸 clang 旗标**（`-g` → `unknown argument`），`--opt` 只接受**单个**旗标。
7. **窗口持有 .exe** ⇒ 重编会 `permission denied`，先 `taskkill /F /IM <exe>`。
8. **本机 bash 无 coreutils**（无 `grep/head/ls/cat/rm/sleep`）⇒ 用 `node -e` 或 `tools/*.cjs`。
9. **`bd.draw(未挂载的对象)` 全零** ⇒ 像素探针必须 `app.mount(stage); app.attachRoot(); stage.showWindow(...)` 之后再 `bd.draw(stage)`。
10. **`stage.showWindow()` 不返回** —— 它把主线程交给帧/消息循环，直到窗口关闭。所以**所有 setup 与所有 `setTimeout(...)` 必须写在它之前**。写在之后的定时器**完全不会触发**，症状看起来像「我的定时器坏了」（本工作区一个探针就是这样空着日志的）。
11. **读你没写过的代码报 C 错时，先看编译器树，不要「重跑一次」**（G11，2026-10-23 结案为非缺口）：`no member named '_time' in 'struct Date'` / `___restrict` / `socket` 这类错（出现在 `struct` 与**手写内建体**之间）从来不是「生成器随机」，而是**编译器源码正被另一个进程改到一半**时测量的后果。本机确实会并发改编译器（我这次测量期间亲见它从 clean 变 4 个 `M`）。⇒ 处置：`git -C ../as3compiler status --porcelain`，有**已跟踪文件被修改**就是这个条件；等它提交或换干净树再测。两个 runner 已把重试循环换成**树状态报告**（重试会把真缺陷伪装成偶发）。一条命令给结论：`node probes/g11-nondeterminism/run.cjs`。**注意判据是「测量期间编译器源码有没有动」，不是「树脏不脏」**：稳定但脏的树照样可测（PASS 会点名 `src/` 内容哈希——我 2026-10-23 那次 PASS 认证的 `d7d7f962fa2eb80b` 就是后来被上游提交成 `1ac26b4` 的那份内容）；**测量期间真在动**才不可测，那道门报 `[SKIP]`（exit 3）而不是假红或假绿（`reviews/gates-skip-path.txt`）。
12. **先大分配、后堆分配会挂起**（G12）：`ByteArray.length=` / `BitmapData.draw` + `getPixels` 之后，**创建或增长任何 GC 对象**（`push` 首个元素、字符串拼接、`new` 类实例）可能让进程**保留存活外观但停步**（不是崩溃）。读图/读文件之后建 UI 节点就是命中形状 ⇒ 日志写成**文件**并每步追加，才能看出卡在哪一句。
13. **AOT `--run` 时，程序的 cwd = 你传给 AOT 的那个 cwd**（不是 exe 所在目录）。本仓曾因此把 `bind-truthy.txt` / `clock.txt` 两个证据文件写进了 `as3compiler/` 源码树。⇒ 要么证据写**绝对路径**，要么像 `tools/probe.cjs` 那样：构建用编译器目录当 cwd，**启动 exe 时用探针目录当 cwd**。**注意**：构建本身也会把产物（`.exe`、`icudtl.dat` 这类数据文件）放到那个 cwd ⇒ 拿编译器仓库当 cwd 跑构建，就会在**源码树里**留下未跟踪产物（本仓已发生过一次：`icudtl.dat`；2026-10-23 上游会话已把它删掉，但机制不变）。复核工具：`node tools/compiler-fingerprint.cjs`（工作树一脏就报，包括**新出现的** `??` 文件；它的 porcelain 解析自身有钉子 `tools/fingerprint-parse-check.cjs`——那处曾因 `.trim()` 静默漏报首个脏文件）。
14. **控件自绘的标签不占布局位**：`progress`/`slider` 的标签画在节点**顶部**、轨道在 `height-12`（⇒ 高度 < ~28 会自己压自己）；`card({title:...})` 的标题画在内容盒左上、**不占子节点位置**（⇒ 压住第一个子节点）。两者都不是 bug，是「标签自绘 + 尺寸由作者给」的约定：**给够高度，或把标签写成真正的子节点**。

### 4a 浮层 / 工厂类的新增实测（第三批六件吞出来的，都会重复发生）

> **A1** **`Array(x)` 恒 wrap，不是复制**：`Array([1,2])` 是**长度 1** 的数组（`[0]` 就是那个数组）、`Array(3)` 是长度 3 的空位数组。拿它做「单值/列表归一」会在 `for (i<len)` 里拿到一个 Array 当元素——若接着 `is <某节点类>` 就抛 `#1034`。 **必用 `OptionSupport.list(v)`**（`kit/asaot/ui/OptionSupport.as`）。两臂实测：`node probes/array-coerce/run.cjs`（门 §7b）。
> **A2** **工厂签名不统一，多看一行再写调用**：`column/row/overlay` 有**第二参 `children`**；`dialog/drawer/popover` 也收；而 `button/checkbox/divider/image/menu/select/skeleton/spinner/textField/toast` **只接 `opts:Object=null`**。⇒ `button("OK", {...})` 是**编译错**（`too many arguments (expected 1, got 2)`），要写 `button({ label: "OK", ... })`。
> **A3** **控件自己的选项名会变成样式简写**：`OptionSupport.applyOpts` 会调 `StyleRefinement.from(opts)`，所以 `{width: 300}` / `{size: [300, 200]}` 不只被你的控件读到，**也被当成 layer 的显式尺寸**。flex 里显式 size **赢过 inset** ⇒ 居中/拉满的弹层会缩成 300 宽。⇒ 浮层类工厂 patch 完 layer style 后**必须** `n.style.size = null;`。
> **A4** **面板类 kind 必须自建 `shapeA`（child 0）**：`PaintKit.paintBox` 与 `OverlayList.band` 对 `n.shapeA == null` 是**静默 return**（为了兼容不画的控件）⇒ 矩形全对、屏幕全白。
> **A5** **`MouseEvent.localX/localY` 是 TARGET-relative**（冒泡时保持不变，与 AIR 一致）：点击目标是「行」时，你拿到的 y 永远在 `0..rowHeight`，**跟你点在哪行无关**。容器内坐标走 `OverlayList.localYIn(n, e)`（沿 parent 累加 `t.y`，chain 断了返回 `NaN`）。
> **A6** **只改 `visible` 的 payload 也要抬 arrange**：`visible` 是 `arrangeSelf` 写给 `backing` 的，不抬位就“树上是 true、屏上是旧值”。模式：`if (vis != n.visible) { n.dirty |= Dirty.M_ARRANGE | Dirty.M_PAINT; n.markLayoutDirty(); }`。
> **A7** **`Function(opts.fn)` 是 AOT 解析错**（写成 `(opts.fn as Function)`）；**`tabEnabled` 只在 `Control`**（`Element` 子类写了会报未定义属性）；**`Edges.fromArray` 的二元形式是 `[水平, 垂直]`（h,v）**，**不是** CSS 的 v,h。
> **A8** **`node -e` 里别写 `\n`**：经 bash 传递后变成**字面换行**，生成的 `.as` 里字符串字面量变成真换行 ⇒ `Lex error: unterminated string literal`（本轮踩中两次）。长脚本写 `.cjs` 文件；实在要在字符串里换行就写 `String.fromCharCode(10)`。
> **A9** **`box()` 的 `direction` 字段覆盖样式里的 `flexDirection`，且默认 `"column"`**：给 `box({style:{flexDirection:"row"}})` 也不行，它仍按 column 排（子项按 `alignItems` 居中，症状是「行内部的标签跑到 x=142」）。⇒ **行布局一律用 `row({...})`**（`row`/`column` 都会显式写 `n.direction`）。**第五轮 tree 探针就因为这一点把标签排到了 x=142**。
> **A10** **`OverlayList.atPoint` 回答的是「最深」节点，不是「命中控件」**：点日历上的「15」命中的是 `dp:d15:t`（日格的文本子件），点「<」命中的是 `dp:prev:t`。⇒ 点击路由必须**沿 `parent` 上溯**逐级试 key（`DatePickerWidget.onClickAt` 的 walk-up），否则只有点到单元格空白边缘才生效。同理：**任何「命中子件但归属父件」的控件都适用**。
> **A11** **钉死行高要同时钉 `minSize.height`，只写 `height` 会被 flexbox 压**：`virtualList` 的窗口是 `fit+1` 行（九行 20px 溢出 150px 视口）⇒ 九行被均分成 16.67px；而 `flexShrink:0` 会被编码成「flex:1 zero basis」反而夹成 **0**。**真正钉住的是 min**（solve 后生效，溢出行整体落在 clip 外）。
> **A12** **退场动画必须自己「按住」`visible`**：作者的 `open=false` 是**立即**的，下一次 reconcile 就把 `visible:false` 写到 `backing`，动画当场被抹掉。⇒ `UiNode.visibleHold`（退场开始置 1、落地帧置 0，**只有拥有退场的 shell 写**）。探针必须包含「**退场中强制重渲染**」相位（描述符全程 `visible:false`，中间态仍要有 `alpha>0`）。
> **A13** **探针的初值不要等于它要验的结果**：`datePicker` 探针的初值曾是 `2026-10-15`，而「点 15 号」的断言是 `value == "2026-10-15"` ⇒ **点击完全没生效也照样绿**（变异 M8 掘出来的假绿）。⇒ 初值必须与目标值**可区分**（改成 `2026-10-02`），或者断言「**变化**」而非「等于某值」。
> **A14** **探针里凡是「按窗口行数取 `children[i]`」之前，必须先守行数**：窗口行数不对时 `children[i]` 读越界会让 AS3 侧**直接无 verdict**（既不 PASS 也不 FAIL），变异机把它归为 `BUILD FAILED` ⇒ 一个真变异被当成“编译不过”而漏计。守一句 `if (rows.length != want) { fail("..."); return; }` 就能保住判定。
> **A15** **新增 kind 必须同时进画廊 `ui-demo/demo/GalleryView.as`，否则门会红**：`tools/kind-coverage.cjs` 把每个 `register("<kind>", …)` 解到节点类、再解到 factory 函数，然后问**画廊有没有调用**其中之一（扫描 `ui-demo/demo/`，不是被 `stage-air.cjs` 重新生成的 `air-gallery/src/`）。这条门是被现实逼出来的：`virtualList`/`tree`/`combobox`/`datePicker`/`select`/`drawer`/`popover` **七个控件发出去了却没人能看见**，而 `STATUS.md` 当时还写着「只有 `scrollView` 没进画廊」。⇒ 写 kind 的最后一个动作是「让它上第七页 Advanced」，并把它加进 `GalleryMain.pageKeys(6)`（切页后仍在/已不在都要断言）。**扫描器必须剥掉注释**：把 `//` 当成代码会得到「`tree` 已展示」的假绿（注释里有 `the second tree (the …`）。

### 4b `--air-app` 专用（demo 一律走这条路，见 `ui-demo/README.md`）

15. **`--air-app` 只编 `<appDir>/src/**/*.as`，而且它的 walker 不认 junction/符号链接**（`isDirectory()` 对 junction 为假）⇒ 共享的 `kit/`、`seam/` 必须**实体拷进去**。用 `ui-demo/stage-air.cjs`（它逐字节校验拷贝、打印内容哈希、缺 `app.xml` 就拒绝跑）。
16. **`--main-class` 必须显式给**：推断规则是「文件名**以 `Main.as` 结尾**」⇒ `GalleryMain.as` 会让它猜 `demo.Main`（不存在），死法是在闭包里报一个你没写过的类。描述符**不携带**文档类，是**编译命令行**告诉它的。
17. **`--air-app` 每次构建都重写 `<filename>.build.json`** ⇒ 手改 manifest 不会存活，要改就改描述符。检查定义有没有真走到：描述符说 high 时，manifest 的 `defines` 里必须有 `ASC_DISPLAY_HIGH=1`（两条 runner 都就地断言了这点）。
18. **`--air-app` 的闭包曾是坑，现已是回归钉（G13，已修）**：默认面是「从文档类算类引用闭包」，**曾经**不展开「先被自由函数文件发现的类」——我们的控件**全部**靠小写工厂自由函数进入（`chip.as` → `ChipNode`），于是共同父类 `Control.as` 与构造器注册的 `kind/*Widget.as` 被裁，报 `unknown superclass 'Control' of 'asaot_ui_AvatarNode'`。**阶段二百四十九已修**：默认闭包现在 94/97 且两个 demo 原样可建。
    ⇒ 实战规则：看到 `unknown superclass '(\w+)' of ...` 而那个 `.as` 明明在 `src/` 里、可达数又明显偏小，**那就是闭包回归**——去修闭包，**不要**用 `--all-sources` 盖过去（它会把整包都编进去，把这类回归永久遮住）。钉子在 `probes/reach-freefn/run.cjs`（5 文件、与 UI 库无关）+ `probes/widgets/*`（端到端半边）。
19. **描述符注释里引用标签会骗过「首个匹配」的正则**：本仓的描述符会自述 `requestedDisplayResolution` 等设置，读它的代码若直接 `exec` 首个匹配，就会把**注释里的**值当成真值。⇒ 匹配前先把注释抹掉（`ui-demo/air-run.cjs::blankComments`，抹相同长度的空格以保住字节偏移）。这条是 `mutation-dpi.cjs` 抓出来的：变异「打在注释上」，探针为了错误的原因变红。
20. **HiDPI 要自证成因**：同一个 App、两个只差 `requestedDisplayResolution` 一行的描述符 ⇒ PNG **1050×840（1.5×）** vs **700×560（1×）**，而两次 tour 的文本**逐字节相同**（逻辑坐标与分辨率无关）。一条命令：`node ui-demo/check-dpi.cjs`（两臂各自 build+run）；它自己先校验两个描述符的 `<initialWindow>` 除那一行外**逐字节相同**，否则拒绝跑（「一变因」是实验有效性的前提）。

### 4c 集合选型：`Vector.<T>` vs `Array`（实测，两 runtime 对照）

> 一条命令：`node probes/vec-vs-arr/run.cjs`。**同一份 `BenchCore.as`**（同 N、同循环、同 `getTimer`）编两次：一次我们的 AOT、一次 `mxmlc`→`adl`。⇒ 差值是**运行时差值**，不是 harness 差值。变异 `mutation.cjs` **2/2**（其中一条是「让 Vector 那一行真的跑在 Array 上」，比值当场塔向 1）。

`N = 1,000,000`，best of 5，ms（两次独立运行一致到 ±1~3ms）：

| 基准 | 我们的 AOT | AIR 51.4.1 (`adl`) |
|---|---|---|
| `Array` fill+sum（`push` + 下标读） | 11 | 36 |
| `Vector.<int>` fill+sum（`push` + 下标读） | **2** | 33 |
| `Vector.<Number>` fill+sum | **2** | 41 |
| `Array` prealloc（`a.length=N` + 下标写） | 5 | 20 |
| `Vector.<int>` prealloc（`new Vector.<int>(N)` + 下标写） | **1** | **3** |

比值：**AOT `Vector.<int>`/`Array` = 0.18x，`Vector.<Number>`/`Array` = 0.18x**；**AIR 同两项 = 0.92x / 1.14x**。

**为什么我们的 AOT 快 5~6 倍**（**读生成的 C 得到**，不是推测）：

```c
// Vector.<int> —— 单态化：元素是裸 int，push/get 就是一次存/取
typedef struct { void (*mark)(void*); int* data; int length; int capacity; bool fixed; } as_vector_int;
v = as_vector_int_new();
while (i < N) { as_vector_int_push(v, i); i++; }                 // 无装箱
s = s + ((double)as_vector_int_get(v, k));                       // 返回 int，无 tag 分派

// Array —— 一格一个装箱 as_value
v = as_array_new();
while (i < N) { as_array_push(v, as_v_num((double)i)); i++; }    // 每格一次 as_value
s = s + as_v_to_number(as_array_get(v, k));                      // 每格一次解箱
```

⇒ 快的**不是「Vector 是魔法」，是「不装箱」**：`as_vector_int` 是 `int*` 连续存储，`as_array` 是 `as_value`（16 字节带 tag）连续存储 + 每次读写都要造/拆 tag。`Vector.<Number>` 同理落成 `double*`。

**AIR 为什么几乎没差**：AVM2 的 JIT 已经为 `Array` 做了内联缓存/整数特化，两边都便宜到同一量级（33~41ms）。但**prealloc 那一行才是有意思的**：AIR 的 `Vector.<int>` 在**预分配 + 下标写**时是 **3ms**（vs 它自己的 `Array` 20ms，**6.7x**），而 `new Vector.<int>()` + `push` 高达 33ms。⇒ **AIR 上 Vector 的收益全在「避开 push/增长」**，而我们这边两条路径都快（增长已摊销）。

**实用结论（我们库内）**：

1. 持久容器**优先 `Vector.<T>`**，元素类型选得越窄越好（`Vector.<int>` ≥ `Vector.<Number>`）。
2. **长度已知就预分配**（`new Vector.<int>(n)`，我们 AOT 支持，落成 `as_vector_int_new_sized`），两端都是最优；既避开装箱又避开增长。
3. `Array` 只在「装异质值 / 长度动态 / 稀疏 / 需要 `sort`/`splice`/`concat` 等 Array 独有 API」时用。
4. **与 §5 零分配不矛盾**：§5 禁的是 `paint/measure/arrange` **每帧新建**容器（“别每帧分配”）；这里是「**要分配时选什么**」。每帧热路径两者都不能建，但**持久字段**用 `Vector.<T>`。
5. **不要为了这条去重写现有 `Array` 用法**：布局/样式/事件层规模是几十项，boxing 开销不可观测（一次 `extractChildren` 级几十格，那 5x 是 100 万格才显形）。新增**有量级**的结构（几何缓存/顶点缓冲/大数组）按上面选型。
6. **读数注意**：`getTimer` 分辨率是 **1ms**，≤3ms 的格子已到分辨率槛，比值只取**数量级**意义（“快 5~6 倍”），别当精确值。门只钉 **≤0.5x**（“至少 2 倍”）也是为此。

---

## 5 稳态零分配（AGENTS.md 内存红线）

`paint` / `arrange` / `measure` 在**每帧**被调用。这些方法里：

- **不要** `new` 数组、对象、闭包、字符串拼接；
- **不要** `Vector.<X>` 或 `[]` 字面量（这里是「**别每帧建**」；持久字段该不该用 `Vector.<T>` 见 §4c）；
- 需要临时容器就用**调用者提供的缓冲**或节点的持久字段；
- `paint` 里读 `n.extra["tone"]` 是**属性读**，不分配，OK；`n.extra["k"] = v` 只在值变化时写。

## 6 交互与键盘的现状

- 悬停/按下/点击**可用**（`setHover/setPressed/click`）；`PaintKit` 从这四种状态
  （`hover`/`pressed`/`focused`/`disabled`）**派生绘制**，见 §2c 上面的「你要做什么」。
- **派生只对「可交互节点」生效**：`n.tabEnabled || n.onClick != null` 且 `!n.state.disabled`。
  这条闸门在 `drawBoxFor` 与 `stateColor` 里**各写一遍**（宁可重复也不让两者漂移）——
  去掉它，每个布局容器都会变成 CSS `:hover`，页面根节点在鼠标划过时整体提亮 8%。
- `n.state.disabled` 由 `Element.disabled`（+ 沿 parent 链的 `n.inert()`）驱动：
  `handleClick` 早退、Tab 环跳过、`backing.alpha = 0.45`。
- **仍然没有**：按键重复（长按不会连发）、应用级快捷键表、输入法合成事件、右键/双击语义。
  要加这些请先改 `UiApp` 的管线，**不要**在单个控件里自己装 stage 监听。

---

## 7 怎么验证（唯一认可的方式）

```sh
cd asaotui
node tools/probe.cjs probes/widgets/<x>
```

这个命令会：清掉旧证据 → 用我们的 AOT 编译（含整个 kit）→ 启动窗口（detached）→ 等程序写 `<x>.done` → 杀进程 → 把程序写的 `<x>.rects.txt` / `<x>.bmp` 与**你手写的** `expect.json` 逐项比对 → 打印 `PROBE <x>: n checks, m failures`，退出码 0/1。

### 探针协议（必须照做）

- 目录名 == 输出前缀（`probes/widgets/chip` ⇒ 程序写 `chip.*`）。
- `setTimeout(finish, 900)` 后再 `bd.draw(stage)`（窗口要先稳定）。
- 写三个文件：`<x>.rects.txt`（每行 `key x,y,w,h`）、`<x>.bmp`、`<x>.done`（内容 `PASS` 或 `FAIL <原因>`）。
- BMP 写入函数**照抄** `probes/widgets/chip/Main.as` 的 `writeBmp`。

### `expect.json` 铁律

- **期望值一律手算**，并在 `_derivation` 里写清算法。**绝不**跑一遍抄输出当期望。
- 至少要有：每组控件的 **rects**，以及每个视觉状态**一个精确整数颜色**的采样点。
- 采样点要**避开文字**（标签居中，取靠左 4px 处）。

### 交付前必做

1. `node tools/probe.cjs probes/widgets/<x>` → **exit 0**；
2. **变异测试**：至少把实现里一个数值（颜色/尺寸/间距）改 1 个单位，证明探针**变红且退出码 1**，然后还原；把两次输出贴进报告；
3. 若某个控件确实无法在探针里断言（例如需要真实交互），**明说**，不要编造通过。

---

## 8 报告格式（照这个写）

```
## 交付
<控件名>: 文件清单（3 件套 + 探针 + expect.json）

## 验证
$ node tools/probe.cjs probes/widgets/<x>
...

## 变异证据
$ (mutation) ... -> PROBE_EXIT=1，FAIL 行原文
$ (restore)  ... -> PROBE_EXIT=0

## 未做 / 做不到
<诚实列出，别藏>
```

**报告写完必须自己再跑一遍再交**——报告被截断或与实测不符视为未交付。
