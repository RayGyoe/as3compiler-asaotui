# 死节点上的监听器：`#1009`，以及一个没有指针的 UI 门（第十二轮）

用户第四次贴截图，一句话：**「多点了几次报错」**。控制台里是

```
TypeError: Error #1009: Cannot access a property or method of a null object reference.
    at asaot.ui::UiNode/setHover()
    at Function/UiNode.as$1::anonymous()
```

`UiNode.as$1::anonymous` 是**节点自己挂在自己 backing 上的那个闭包**。上一轮的 `#2006` 是「显示位算错」，
这一轮是「**对象已经死了，事件还在往它身上投**」——两个完全不同的话题，但失败方式一模一样：**只有 AIR 会
报，我们自己的 AOT 一声不响**。

---

## 1 根因：两层时序，缺一不可

### 1.1 库侧：`destroySubtree()` 摘得掉显示对象，摘不掉监听器

节点销毁时把 backing 从父容器摘掉、把字段置空：

```as3
this.backing.parent.removeChild(this.backing);   // 显示列表里没有了
this.app = null;                                 // 字段清空
this.extra = null;
this.backing = null;
```

但**监听器是挂在 backing 这个 EventDispatcher 上的**，`removeChild` 不会替你摘。于是那个闭包仍然活着，
它的捕获变量里是**已经置空的字段**。

### 1.2 AIR 侧：`mouseOut` 晚一拍才投递

AIR 的重算顺序是：先结束这一帧（此时节点已经被销毁），**然后**才重新计算「指针下面是谁」，并把
`mouseOut` 投给**上一帧的那个对象**。所以只要「指针停在某个控件上，而某一帧把那个控件拆了」，就会得到一次
迟到的 roll-out，落在尸体上。

**实测（`adl` 51.4.1，本机）**：`ui-demo/air-gallery/air-trace.txt` 里，`ERROR` 只出现在**点击会拆树的
那几页**——`accordion` 1 次、`dialog` 4 次、`drawer` 3 次、`menu` 3 次。其余 37 页 0 次：它们点了以后
树不动。

> 顺手实测到的第二条 AIR 契约：**按下期间指针「属于」按下目标**，按住按钮把指针移出去**不会**投递
> leave。写拖拽/滑块时这条会影响「按下后移出是否取消 hover」，`ScrollViewWidget.endDrag` 的栈式摘除
> 就是按这个假设写的。

---

## 2 为什么整个 AOT 套件都是绿的

`src/emit.ts` 里 `mouseOver` 这个字符串出现 **0 次**（`rollOver` 只出现在注释里）：
**AOT 的鼠标派发只发 `mouseDown` / `mouseUp` / `click` / `wheel` 与 Stage 的 `mouseLeave`，逐对象的
roll-over/roll-out 那一对从未发出**（`_mouse_in` 只喂 MovieClip 的按钮态，见 `emit.ts:17702-17713` 的
实测注释与 `TODO.md` 的 rollOver/rollOut 残留项）。

⇒ 在我们的 AOT 上那个监听器**永不执行**，「执行到尸体上」也就不可能发生。这不是「运气好」，
是**结构性盲区**：19 个探针、41 页截图、CheckUi、tour 全都跑在这条「不发 hover 事件」的运行时上。

已登记为缺口 **G25**（[`../compiler-gaps.md`](../compiler-gaps.md)）——它有两副面孔：

- 对**使用者**：AOT 编出来的应用，`addEventListener(MOUSE_OVER / MOUSE_OUT / ROLL_OVER / ROLL_OUT, …)`
  永不触发，**hover 反馈是死的**；
- 对**我们**：所有「监听器生命周期」类缺陷在 AOT 上不可观测。

---

## 3 修法（库侧，结构性）

`kit/asaot/ui/UiNode.as`：

```as3
public var wired:Array;                                  // (target, type, fn) 三元组

public function listen(target:EventDispatcher, type:String, fn:Function):void
{
    if (target == null) return;
    target.addEventListener(type, fn);
    if (this.wired == null) this.wired = [];
    this.wired.push(target, type, fn);                   // 记住，才能摘
}

private function releaseListeners():void { … removeEventListener 三元组 … }
```

`destroySubtree()` **第一句**就 `releaseListeners()`，然后才摘显示对象、才置空字段——顺序是契约：
先断线，再断电。

全库 **24 处**监听器、**16 个 widget 文件**从裸 `addEventListener` 改成 `n.listen(...)`。**STAGE 监听器
刻意不在此列**：它们属于某一次手势（拖拽/长按），保留 widget 自己 teardown 里的显式 add/remove 对，
否则「手势结束但节点还活着」时会被误摘。

> 这条修法不依赖 AIR 的时序细节：**只要监听器活得比对象久，任何迟到事件都是潜在崩溃**。所以它是对的，
> 而不是「碰巧躲开了 AIR 的某一拍」。

---

## 4 四道新门（两道静态、一道 AOT、一道 AIR）

| 门 | 测什么 | 结果 |
|---|---|---|
| `probes/lifecycle/` | 10 种 kind × 5 种指针事件版本：**节点销毁后**再派发 `MOUSE_OVER/OUT/DOWN/UP/CLICK` 不抛、`state.hover` 保持 0、没有游离的 `onClick`；同时证明**活节点上这道闸不改变行为**、真点击仍然有效 | **9 checks, 0 failures** |
| `tools/listener-wiring.cjs` | 源码扫描：`kit/` 里禁止裸 `x.backing.addEventListener(` / `x.tf.addEventListener(`，且 `destroySubtree` 里必须有 `releaseListeners()`；**扫到 0 处也算失败**（扫不到东西的钉子等于没钉） | **29 wired, 0 raw** |
| `tools/air-sweep.cjs`（**指针钻**，本轮给上一轮的门加的） | 每页离开前**悬停该页每一个叶子**，切页后**下一拍**投递 `mouseOut`；`ROLL` 行报告悬停数与「真的已销毁」数 | **3107 hovered / 348 destroyed / 0 errors** |
| 变异 | `probes/lifecycle/mutation.cjs` **4/4**；`tools/mutation-listener-wiring.cjs` **3/3**；`tools/mutation-air-sweep.cjs` 由 3/3 扩到 **5/5**（新增：去掉 `releaseListeners()` ⇒ 立刻 145 个 `#1009`；只悬停不投递 ⇒ 指针钻报 `0/41`） | 全部 CAUGHT |

**「AIR 不能脚本点击」不是理由。** 门需要的从来不是 OS 指针，而是**事件**——而事件是可以自己 dispatch 的。
上一轮的 `air-sweep` 自称「真跑参考运行时」，却**一个指针事件都没发过**，于是这一类缺陷整整齐齐地从它
旁边走过去。这是本轮最该记住的教训：

> **一个没有指针的 UI 门，等于没测指针类缺陷。**

指针钻因此也必须**可度量**：`ROLL` 行里的 `destroyed` 就是「这次钻到底咬到了没有」——
3107 个悬停对象里 348 个真的被切页销毁，说明钻头是热的。把投递那一步删掉，门会报 `0/41`（变异 M5），
而不是安静地绿着。

---

## 5 回归

`node tools/gates.cjs`（`AIRSDK_HOME` 指向 51.4.1）→ **44/44 PASS**
（日志 [`gates-all-26.txt`](gates-all-26.txt)；门数从 42 增到 44，新增 `probe lifecycle` 与
`kit listeners are all releasable`）。

六个 widget 探针复跑全绿：callback 24、form 41、scrollbar 44、typing 18、motion 23、data 77，0 failures。

> 本轮还顺手清掉一个**开工前就在工作树里的改动**：`ui-demo/air-gallery/app.xml` 的
> `<renderMode>` 被改成 `gpu`（提交里是 `cpu`）。它让 DPI A/B 门变红——那道门要求两份描述符
> **只差 `requestedDisplayResolution` 一行**，多一个变量就不再是 A/B。已 `git checkout` 还原。

---

## 6 披露

- 库侧 ✅ 已修；编译器侧 ❌ 未动（本工作区不动 `as3compiler/`），登记 **G25**：建议补逐对象的
  `mouseOver/mouseOut/rollOver/rollOut`，并带上 AIR 那两条时序契约（①移除对象的**下一帧**仍投递
  roll-out；②按下期间不投递 leave）。补上之后，这类缺陷会被任何 AOT 探针**当场具名抓到**。
- `probes/lifecycle` 只能在 AOT 上跑（它用**显式 `dispatchEvent`** 模拟指针，两个运行时都走同一条路），
  所以它证明的是「库里的闸在」，不是「AIR 上不再迟到」。AIR 那一半由 `air-sweep` 的指针钻负责——
  这两者是**互补的两半**，不是重复。
- 悬停 3107 个叶子里只有 348 个真的被销毁：其余是 reconciler 复用掉的节点（同 key、同结构）。这是
  实测事实，不是漏测；门把 `destroyed` 的下限定在 100（实测 348 的三分之一），掉下去就报「钻头不咬了」。