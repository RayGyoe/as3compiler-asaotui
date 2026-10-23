# 第三轮：组件目录页 + 一条 auto 文本的布局缺陷（+ 把 tour 的诊断变成判据）

> 2026-10-23 · 交付 [`ui-demo/demo/GalleryView.as`](../ui-demo/demo/GalleryView.as) ·
> 缺陷钉子 [`probes/widgets/data/`](../probes/widgets/data/) ·
> 变异 [`ui-demo/mutation-gallery-zerorect.cjs`](../ui-demo/mutation-gallery-zerorect.cjs)
> 一次性验收 `node tools/gates.cjs`（**23/23 PASS**，定稿记录 [`reviews/gates-all-12.txt`](gates-all-12.txt)，
> 编译器 HEAD `9cb054e`／阶段254）
>
> 用户这一轮要的是三件事：**① G14 修好后 UI 库能做什么改进**（已另文结案，见
> [`revisit-g14-unlocks-2026-10-23.md`](revisit-g14-unlocks-2026-10-23.md)）**② 把还没实现的控件补完**
> **③ air-gallery 补齐（「例如 `list`、`image` 等还没有」）**。本文是 ②③ 的收尾记录。

---

## 0 结论先行

| 做了什么 | 结论 | 证据 |
|---|---|---|
| **控件集补完** | 第二批九件全部落地：`image` / `scrollView` / `spinner` / `skeleton` / `tooltip` + `table` / `accordion` / `breadcrumb` / `pagination` ⇒ **25 kind / 29 工厂** | `node tools/probe.cjs probes/widgets/{media,feedback,data}` ⇒ **43 / 43 / 77 checks, 0 failures** |
| **air-gallery 补齐** | 第 5 页 **Catalog**：media/feedback/data 九件同屏；tour 现在遍历 **5 页**、落 **5 张** PNG，页脚 off-by-one 修掉（`segs = (652 - 8*(n-1))/n`，n 从标签数组算，不再写死） | `cd ui-demo && node run-gallery.cjs` ⇒ `RESULT: PASS`；`air-gallery/gallery.txt` 里有 page 4 的手算矩形；`gallery-page4.png` |
| **发现并修掉一条真框架缺陷** | **auto 宽度的文本节点发布的是「纯字形宽」，而引擎 `boxSizing` 默认 border-box（点尺寸 = 整盒）** ⇒ 有内边距的 auto 文本，盒比内容小，字形溢出到邻居身上（面包屑分隔符 `/` 贴在下一个 crumb 上） | 钉子：`probes/widgets/data` 程序内断言 `sep.absW == sep.tf.textWidth + 8`；变异 M5 复现 ⇒ 红并点名 `must include its insets` |
| **把「静态诊断」升级成判据** | 画廊 tour 一直在**数**三类静默失败（无 engine 节点 / 零矩形 / backing 未挂）但只写进日志；现在它们进 `problems` ⇒ 新控件的「悄悄没上屏」不再能被 PASS 掩盖 | 变异 `ui-demo/mutation-gallery-zerorect.cjs`（**4 行全绿**）：`M1 actually rewrote the screenshots`（先证明变异**真的**改到了像素）→ `M1 ... -> named red`（tour 红并点名 `page 4 has N node(s) with a zero rect`）→ `M1 screenshots restored byte-identical`（5 张 PNG 逐字节还原）；baseline 绿、源码还原逐字节一致 |
| **文档计数纠偏** | `16 kind / 20 工厂`、`53 文件`、`18 道门`、`4 页`、`16 widget kinds registered.`（demo 里**渲染出来的**那句话）全部按实测改成 **25 / 29 / 114 个 .as / 23 道门 / 5 页 / 25** | `git diff STATUS.md README.md ui-demo/README.md` |

---

## 1 页面：第 5 页「Catalog」

`ui-demo/demo/GalleryView.as` 加了一页，两列都是 320px 的 flex 列（与第 1 页同几何，故矩形推导共用）：

```
左（colM）                   右（colD）
catImg   320x72  @24,132     catTable 320x78  @356,132   （表头 26 + 2 行 26）
catSpin  320x56  @24,216     catAcc   320x120 @356,222   （h0 33 / catP0 32 / h1 33）
catSk    320x26  @24,284     catCrumb 320x20  @356,354   （c0 44 / s0 12 / c1 30 / s1 12 / c2 29）
catTip    56x29  @24,322     catPage  320x28  @356,386
```

四个刻意的选择（都写进了源码注释）：

1. **`table` 的高 = `rowHeight * 3`**（26×3 = 78）：表是显式高，多给就会在最后一行下面留一条死白。
2. **`tooltip` 不给尺寸**（`StyleRefinement.from({})`）：`TooltipWidget.measure` 自己算「文字 + 2×内边距」，
   `paint` 里把标签居中 ⇒ 写死一个 320 宽的盒只会得到一个「宽气泡 + 左对齐的短字」。
3. **`image` 的源是 `BitmapData`**，且是**静态常量**（`SRC8`）：每帧 `new BitmapData` 会被 `image` 读成
   「像素变了」而永远重新量，静态同一指针才是稳定态。
4. **`breadcrumb` / `pagination` 的水平方向在 factory 里补的**（`StyleRefinement.from({flexDirection:"row"})`
   作为 patch），因为 resolver 的默认方向是 column —— 作者不用知道这件事，见 `u1` 的一条设计决定。

tour 侧（`GalleryMain.as`）：`pageKeys(4)` / `otherKeys(4)` 补齐，**tabs 点击坐标重算**——
分段是等分的：`segW = (652 - 8*(5-1))/5 = 124`，第 2 段中心 `= 132*2 + 62 = 326`（原来 4 段时是 408）。

---

## 2 那条缺陷：auto 文本节点没有把内边距算进自己的尺寸

**症状**（先看图，再看数）：`gallery-page4.png` 里面包屑读起来是 `Library /Data /Raw`——`/` 贴着右边的 crumb。

**根因**（三处并排就能看出来）：

- 引擎 `As3LayoutNode.boxSizing` 默认 **`BOX_SIZING_BORDER_BOX`**（`seam/asaot/ui/as3/As3LayoutNode.as:110`），
  即 `setPointSize` 给的是**整盒**尺寸，`padding` 在里面；
- `PaintKit.measureField` 写的是**纯字形宽**（`n.state.measuredW = field.textWidth`）；
- `kind/TextWidget.measure` 把 `measuredW` **不加内边距**地发布出去 —— 而同一仓库里
  `BadgeWidget:67` / `ButtonWidget:58` / `CardWidget:66` / `ChipWidget:71` **全都加了**
  （`measuredW + padH + borderH`）。⇒ `TextWidget` 是唯一的例外，不是设计，是漏。

数值上：分隔符 `/` 的字形宽 **4**，`sepRef` 的内边距是 `[4, 0]`（`padH = 8`）。
发布 4 而盒按 border-box 解 ⇒ 引擎把它夹到 padding 的 8；`arrange` 又把 `tf` 放在
`insetX = 4` ⇒ **4px 字形被画在 8px 盒的右半边**，正好溢出到下一个 crumb 的起点。

**修法**：`kind/TextWidget.as` 的 auto 分支改成
`measuredW + PaintKit.padH(s.padding) + PaintKit.borderH(s.borderWidths)`（高度同理）。

**钉子（不用抄字体度量）**：`probes/widgets/data/Main.as` 断言
`sep.absW == sep.tf.textWidth + 8`——右边是**控件自己测量出来的**字形宽，左边是布局结果，
两边同源；`±1` 只用来吸收布局取整。修前实测会打印
`separator box 8 is not its text 4 + padding 8`。

**变异（证明钉子有牙）**：`probes/widgets/data/mutation.cjs` **M5** 把内边距去掉一字 ⇒
`MUTATION data: 5/5 caught`（另 4 条：M1 选中色、M2 槽位窗口、M3 面板全挂、**M4 是探针首跑抓到的层叠 bug 复现**），
每次 `finally` 还原并 **sha256 逐字节核对**。

> 顺带一条方法论：这条缺陷**任何单控件探针都测不出来**（探针不关心「字形有没有溢出自己的盒」），
> 是「把控件摆进一页真页面并**看图**」才暴露的——与 `STATUS.md` §5 那条「探针要配一个真实应用」同源。

---

## 3 tour 的诊断从「日志」变成「判据」

`GalleryMain.treeDiag` 从第一版起就在数三类静默失败：

```
nodes=45 engineNodeNull=0 zeroRect=0 detachedBacking=0
```

但只有「三页里这页多了/少了节点」这类**键存在性**断言会进 `problems`，这三个数永远只是日志 ⇒
新控件「建了节点却没上屏」会是一个带 0 的 PASS。本轮把它们接进 `problems`，并配
`ui-demo/mutation-gallery-zerorect.cjs`（现在 **4 行判据**）：

```
MUTATION PASS  baseline (unmutated) gallery tour                    [exit=0 + RESULT: PASS]
MUTATION PASS  M1 actually rewrote the screenshots                  [the mutated build really does overwrite the five tracked PNGs]
MUTATION PASS  M1 catalog image sized 0x0 -> named red              [exit=1 + the zero-rect verdict named the page]
MUTATION PASS  M1 screenshots restored byte-identical               [5 PNG(s), same bytes as before the mutation]
restore: GalleryView.as byte-identical; screenshots byte-identical
MUTATION gallery-zero-rect: PASS (1/1 + 2 pins)
```

第 2 行是**成本为零的牙齿证明**：如果哪天变异不再改到像素（例如 `fit` 的退化分支被改掉），
第 4 行的「还原成功」会退化成一句空话——这一行专门拦住它。

> **这条 pin 是踩出来的，不是想出来的。** 第一次跑这个变异时我**掐掉**了长跑（以为它挂了），
> 结果磁盘上留下的 `gallery-page4.png` 是**变异版**——目录页那张图里面的 `image` 被从居中画到了左边。
> 这正是「变异把**被追踪的证据文件**改成了假图」这一类事故。⇒ 变异机现在把 5 张 PNG 也在
> `finally` 里按字节还原，并用**读回磁盘的哈希**自证（不是「我写过」而是「现在读到的就是原来那串」）。
> 顺带把「渲染是否确定」也当场量了：**现在跑一次完整 `run-gallery.cjs`，5 张 PNG 与提交里那 5 张逐字节相同**
> （`sha256` 对比 ⇒ 渲染是确定的，截图可以当证据）。

---

## 4 如实登记的边界（本轮**不**做）

0. **跑画廊时要带 `ASC_NO_OPEN=1`**：不带它直接 `node run-gallery.cjs` 会挂在「开窗」那一步
   （我这次就挂了一次、600s 超时后被迫掐掉——截图其实已经落盘了）。变异机与门都自带这个环境变量，
   手动跑时请照抄。
1. **页脚原来是 `page p of 3`（4 页时报 3）**，tour 不管这句话 ⇒ 已改成从标签数组的长度算，
   但**没有任何断言盯着它**（它只出现在 PNG 里）。若要钉，需要一个读 PNG 文字的手段（现在没有 OCR，
   也不该为这句话引一个）。
2. **`pagination` 的 chip 高 33 > 容器 28**（`pg3 428,412,24,33`）：chip 的尺寸由字体度量定，
   容器是作者给的 28 ⇒ 竖向溢出 5px。它在 `probes/widgets/data` 里是被**手算钉住**的现状
   （不是 bug，是「容器高度该给够」的约定，同 `progress`/`slider` 的标签约定）。
3. **目录页的矩形只在报告里打印**，不参与断言（与另外四页同规格）。页面的**组成**靠
   `probes/widgets/{media,feedback,data}` 的 163 项断言托底，页面本身靠
   「键齐 + 无零矩形 + settled 不重解」托底。
4. **`G16` 未修**：目录页与 `table.as` / `breadcrumb.as` / `pagination.as` 里凡是
   `cond ? null : X` 形状的地方都改写成 `if/else`（登记见 `compiler-gaps.md` G16、门 §9b）。
   本轮**没有新增**对 G16 的依赖。