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
| `paint(n)` | pass 3 | 画。**稳态零分配**（见 §5）。背景/边框走 `PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n))` |
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

> 另有一路 worker 正在补 `justifyContent/alignItems/alignSelf/margin/inset/position`。
> **你的控件代码不要用它们**（否则会编译失败），但你写的**探针**可以在它们落地后用。

---

## 4 会咬人的编译器/平台事实（都实测过）

1. **G7 一个文件只能有一个与文件名同名的外部可见定义**（mxmlc 硬报错）。且本机文件系统**不区分大小写**：`progress.as` 与 `Progress.as` 是**同一个文件**。所以类叫 `ProgressNode`、工厂文件叫 `progress.as`。
2. **mxmlc 的文件名匹配区分大小写**（Windows 上也区分）。`p/lower.as` 里放 `lower()` 能编过；`p/Mixed.as` 里放 `mixed()` → **硬错**。
3. **`Array` 进 `Object` 槽会丢身份，而且会崩**（G14，2026-10-23 实测）：`Number/String/Boolean` 进 `Object` 槽会被**装箱**，`Array` **不会**（裸指针 cast）。后果：`is Array` 常量折成 `false`、`as Array` 得 `null`、`.length` 得 `undefined`，而 **`o is <用户类>` 直接把数组头当 vtable 读 ⇒ `0xC0000005`**（同一条在 `*` 槽也崩）。⇒ 数组一律**显式 `as Array`** 传给 `Array` 形参（`Size.fromArray` / `Edges.fromArray` 就是这么设计的）；**别把「`if (o is Array) return null;`」当作防线**——它会生成 `if (false)`，是死代码（`Fill.fromAny` 里就有这么一句，已登记）。
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

## 6 交互与键盘的现状（别踩空）

- 悬停/按下/点击**可用**（`setHover/setPressed/click`）。
- **键盘完全没接**：`UiApp` 里 `KeyboardEvent/KEY_DOWN/TEXT_INPUT/focus` 各 0 处；`Control.tabEnabled/tabIndex` 目前**没有消费者**。所以**不要**假设 Tab 序或按键事件会来；键盘相关能力请登记进 `asaotui/STATUS.md §3.1`，不要在控件里自己造。
- 控件"能点"靠 `n.backing` 的鼠标事件；`wantsPress()` 只影响按下态。

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
