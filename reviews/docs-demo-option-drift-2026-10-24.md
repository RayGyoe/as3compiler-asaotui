# 文档站的示范与工厂不同步（2026-10-24，第八轮补）

> 用户报告：在画廊 `toastHost` 页点 **“Show two toasts”**，控制台开始**每帧**刷
> `Uncaught exception: asaot.ui.toast: unknown tone 'info' (accepted: default | success | danger)`，
> 而页面本身看着正常（矩形都对，其余 40 页都正常）。

## 1 根因：不是编译器，也不是 `toast`

`toast()` 在未知 `tone` 上**抛错**是契约（AGENTS.md §2.5 不静默回落；同 `Style` 的非法值、
`scrollView.barMode()` 的非法值）。真正错的是**文档页示范了一个不存在的取值**：它把 chip 的
语气词 `neutral/info/danger` 用到了 toast 上，而 toast 的词汇表是 `default/success/danger`。

为什么一直没人发现，有两层：

1. **41 页的扫描只渲染、不点击**。这一页的两条 toast 只有模型里 `tsh.open` 翻转之后才存在，
   所以“每页都渲染过”对它是无效证据。
2. **抛在 `build`（describe/reconcile）里，被帧守卫接住**（`Stage_dispatchFrame` 的
   setjmp/longjmp）：程序不崩、继续跑下一帧、下一帧再描述同一棵坏树、再抛一次
   ⇒ 症状是**控制台刷屏**，屏幕上停在**上一棵成功构建的树**（按钮右边还写着 `open: false`）。

## 2 顺着这个形状扫了一遍，又抓到两页

`tools/demo-options.cjs`（新门）：把每个工厂**真的读**的键与文档站每个调用点传入的顶层键求差。
“真的读”= `opts.x` ∪ `OptionSupport.opt(opts,"x")` ∪ `applyOpts` 的共享键 ∪
**`StyleRefinement.from` 的样式简写**（没有 `style` 时它才是样式来源，所以 `box({gap})` 合法 ——
第一版没算这一条，误报了 57 处）。

| 页面 | 示范的写法 | 工厂实际行为 | 修法 |
|---|---|---|---|
| `toastHost` | `toast({ tone: "info" })` | **抛错**，且每帧再抛（见 §1） | 改 `tone: "default"`；`toast` 页补一句「`tone` 是**名字**不是颜色」 |
| `tooltip` | `tooltip("…", { arrow: "bottom", tone: "info" })` | `arrow` 只认 `up/down/left/right/none` ⇒ `"bottom"` **不画箭头**却白占 6px 宽度；`tone` 是**填充色**（Number），`Number("info")` = **NaN** ⇒ `prev != NaN` 恒真 ⇒ **每帧重绘**，且填充色成了 0 | 改 `arrow: "down"` + `tone: 0x2563EB`（info 蓝）；文案补上 `arrow` 的取值表与「`tone` 是填充色」 |
| `progress` | `progress("Indexing", { tone: "danger" })` | `progress()` **没有 `tone`**（只读 `value`）⇒ 传了等于没传，那条“红色进度条”从没红过 | 去掉 `tone`（两根条靠 `value` 区分） |

三页都已改；页面上的代码块（`DocsOverlay`/`DocsFeedback` 里打印的字符串）与真实调用**同改**，
否则读者复制的仍然是错的。

## 3 钉子（两道，都做过变异）

### 3.1 行为面：tour 的 `6d toastHost` 阶段

`ui-demo/demo/DocsMain.as`：选中该页 → **按 stage 坐标真点按钮**（`click()` 先 down/up 再单独派发
`"click"`，因为运行时不会从 down+up 合成 CLICK）→ 断言两条 toast 的**角栈矩形**：

- `x = winW - 16 - 220 = 764`（`OverlayChrome.TOAST_LAYER` 的 16 内边距 + `toast` 默认 220 宽）
- 下游条的下沿 `= winH - 16 = 684`
- 两条之间 `gap = 8`

再把 `tsh.open` 翻回 `false`，断言两条都卸载、`stage.numChildren` 回基线。

**为什么必须 `try/catch`**：帧守卫会吞掉这个异常继续跑 ⇒ 不包的话 tour 永远写不出 `gallery.done`，
门只会给一个不透明的 TIMEOUT。包起来后失败长这样（实测）：

```
FAIL opening the toastHost demo threw: asaot.ui.toast: unknown tone 'info' (accepted: default | success | danger);
     clicking 'Show two toasts' mounted no first toast and no second one;
```

变异 3/3（`tools/mutation-docs-tour.cjs`，逐个还原并用 sha256 逐字节核对）：

| 变异 | 结果 |
|---|---|
| `DocsView.as` 的 `tone: "default"` 改回 `"info"`（**用户遇到的那个**） | CAUGHT，报出上面的两条 |
| `OverlayChrome` 的 `TOAST_LAYER` `gap 8 → 0`（纯几何，不抛错） | CAUGHT，`the toast gap is not 8 (652 -> 652)` |
| `ScrollViewWidget.build` 去掉 `n.aboveContent = n.shapeB`（见 §5） | CAUGHT，`the 'docScroll' bars sit at display index 1 of 3` |

### 3.2 静态面：`tools/demo-options.cjs`（第 38 道门）

源级扫描，不建不跑（瞬间）。它扫**字符串代码块**也扫真实调用：那串字符**就是**读者复制的东西。
变异 3/3（`tools/mutation-demo-options.cjs`）：

| 变异 | 结果 |
|---|---|
| 给一个真实调用加 `bogusOption` | CAUGHT（`no factory reads it at all`） |
| 让 `progress()` 不再读 `value`（= 工厂从对的文档下面搬走） | CAUGHT（4 个调用点，标注 `a DIFFERENT factory reads it`） |
| 从 `StyleRefinement.from` 删掉 `flexGrow` 一条简写 | CAUGHT（2 处 `box({flexGrow})`）—— 证明“样式简写放行”是**从源码推导**的，不是万能豁免 |

> 第三条变异的第一版是 `if (false && o.flexGrow != null)`：**扫描照绿**，因为工具读的是
> “源码里有没有 `o.flexGrow !=`”这条**文本**事实。把锚点改成整行删除后才有牙 —— 这正好说明
> 一个静态扫描的牙长在**它能看见的那一层**上。

## 4 这道门看不见什么（如实登记）

- 它只比**键名**，不看**取值**：`tone: "info"` 的键是存在的。这一类只能靠**行为**（真点击）发现，
  也就是 §3.1 的那道阶段。
- 它读的是“源码里出现过的键”，所以工厂里**被注释掉的**读取也会被当成“读过了”。目前没有这种情况；
  真要根治得让编译器吐 `opts` 的键集合，那是另一件事。
- 容器形态 `row({…}, [children])` 与单参形态 `toast({…})` 都覆盖（扫**每个**顶层对象字面量参数）。

## 5 顺带的第二个发现：证据文件自己报了案

修完三页之后，`gallery-page0.png`（被追踪的截图）**变了**。不能把解释不了的证据改动提交上去，
所以把它拿 HEAD 的版本做逐像素对比：差异**只在两条竖带**里（x≈223..233 与 ≈958..968），
而且形状很怪——thumb 只在**没被东西盖住的缝隙**里露出一条，代码块（`0f172a`）、demo 卡片的底色
（`fbfdff`）、选中的导航行（`eff6ff`）都压在条上。

**根因不是条画错了，是排序基点错了**：`Reconciler.fixDisplayOrder` 从 `internalCount` 开始给内容
子件排显示索引，而 `internalCount` = `build()` 之后 `backing` 的子件数 —— 对「背景」这是对的，
对「chrome」是错的。于是内容一律在条之上，条只能靠 `paintBars` 里那句 `setChildIndex` 补救，
而补救能不能发生**取决于这一帧有没有重绘这个滚动节点**：切页是「描述但不重绘」
（`Dirty.ALL == 15` 不含 `M_PAINT`）⇒ 条埋下去就上不来。这也解释了为什么同一个二进制
两次跑出来不一样：**它本来就是个「碰巧对」的状态**。

修法：`UiNode.aboveContent` —— kind 在 `build()` 里声明「我这一个对象在内容之上」，
`internalCount` 于是不数它，内容排到它前面，**每次 describe 都自动把它推到最后**，不依赖重绘。
`paintBars` 那句保留，它现在是给 `applyLift`（子件回到末尾）那条路的。

钉子：tour 的 6d 阶段加 `chromeOnTop("docScroll"/"nav")`，**在切页那一帧**（只有 describe、没有
paint）断言条是 backing 的最后一个子件 —— 正是「没别的东西会把它放回去」的那一帧，所以确定性。
变异见上表第三条。

> 这一条值得单独记一笔：**像素证据的价值不在「能看图」，而在「图变了就得给个说法」**。
> 当时完全可以把新截图当成「反正更好看了」提交，那个从第七轮就存在的缺陷就会一直埋着。

## 6 变更清单

- `ui-demo/demo/DocsView.as`：`demoToast1` 的 `tone` 由 `"info"` → `"default"`，并写明“toast 的词汇表
  不是 chip 的”（这行注释就是这个缺口的绊线说明）。
- `ui-demo/demo/DocsOverlay.as`：`toastHost` 代码块 `tone: "info"` → `"default"`；`toast` 页文案补
  「`tone` 是名字不是颜色」。
- `ui-demo/demo/DocsFeedback.as`：`tooltip` 的 `arrow: "bottom"` → `"down"`、`tone: "info"` →
  `tone: 0x2563EB`，文案补取值表；`progress` 去掉不存在的 `tone`（代码块与调用同改）。
- `ui-demo/demo/DocsMain.as`：新增 `6d toastHost` 阶段 + `chromeOnTop()` 断言。
- `kit/asaot/ui/UiNode.as`：新增 `aboveContent`（并在 `internalCount` 里排除它）。
- `kit/asaot/ui/kind/ScrollViewWidget.as`：`build()` 里设置 `n.aboveContent = n.shapeB`。
- `tools/demo-options.cjs`、`tools/mutation-demo-options.cjs`：新工具 + 变异机。
- `tools/mutation-docs-tour.cjs`：tour 的变异机（3/3，含用户遇到的那个）。
- `tools/gates.cjs`：接第 38 道门，并更新 6b（tour）的说明。
- `STATUS.md` §3.9 + 门数 37→38；`README.md` 同步；证据 `reviews/gates-all-22.txt`（38/38 PASS）。

## 7 一条更值得记的经验

**“每页都渲染过”不是“每页都能用”**：文档站的 41 页扫描覆盖的是**渲染路径**，而这三次缺陷全都
只在**点击路径**上。同理，`kind-coverage` 覆盖的是“有没有出现”，不是“用得对不对”。
所以这一轮补的两道钉子刚好一人一半：**静态**那半边保证页面不教不存在的键，**行为**那半边
（真点击 + 那个只有切页才暴露的排序断言）保证页面教的东西真的跑得通。