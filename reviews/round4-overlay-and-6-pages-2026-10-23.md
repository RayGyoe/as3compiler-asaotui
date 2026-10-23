# 第四轮：浮层系统（第二棵保留树）+ 六页画廊

日期：2026-10-23 · 对应 `kit/` **138 个 .as** · 一次性复核：`node tools/gates.cjs` → **25/25 PASS**
（落盘 `reviews/gates-all-13.txt`）

## 1 交付了什么（都是跑过的，不是意图）

| # | 交付 | 规模/证据 |
|---|---|---|
| 1 | **六种浮层控件** `dialog` / `drawer` / `popover` / `menu` / `toast` / `select` | 6 个 Node + 6 个 factory + 7 个 kind 类 + 2 个宿主（`overlay` / `toastHost`）；`probes/widgets/overlay` **65 checks, 0 failures** |
| 2 | **第二棵保留树** | `View.renderOverlay()` + `UiApp.overlayRoot/getOverlayRoot()/overlayDisplay()`；主树先 describe/reconcile，浮层树随后；**主树先 solve、浮层树后 solve**（锚定弹层要读锚点本帧矩形）；绘制主树在前、浮层最后 ⇒ 天然置顶 |
| 3 | **共用几何与调色板** | `OverlayChrome`（HOST/SCRIM/LAYER_*/PANEL/TITLE/FOOTER/TOAST_*）与 `OverlayList`（菜单与下拉共用的行高/行几何/`labelOf`/`valueOf`/`localYIn`） |
| 4 | **销毁契约** | 新可选接口 `WidgetTeardown`（`Widget` 保持 5 方法不变）；`UiNode.destroySubtree` 在置空 scratch 之前调它；`Reconciler.destroyRoot` 显式把根 backing 从 stage 容器摘除 |
| 5 | **画廊第 6 页 Overlay** | `ui-demo/demo/GalleryView.as::renderOverlay` + `overlayPage()`；tour 循环 6 页、6 张 PNG；新增两条判据：`stage.numChildren` 回基线、`findByKey(离开页的弹层) == null` |
| 6 | **两道新门** | `probes/widgets/overlay`（探针）与 `probes/array-coerce`（`Array(x)` 两臂一致）；门的清单与每道门的变异配方写在 `tools/gates.cjs` 头部 |

控件规模：**31 kind / 37 factory**（第三批 +6/+8）。画廊：**6 页**。

## 2 这一轮修掉的 7 个新缺陷（累计 12，全表见 `STATUS.md` §3.3）

按发现的顺序：

1. **浮层树只在窗口出现前解算一次**（560×460 兜底），之后再不重解 ⇒ 弹层整体偏左、宽度少 200px。
   根因：百分比根在 `reflow` 里没有「窗口尺寸变了就重解」这条路径，而 style 指针不变 ⇒ 协调器跳过 resolve。
2. **面板矩形正确、屏幕空白**：`PaintKit.paintBox` / `OverlayList.band` 对 `n.shapeA == null` 是静默 return，
   而三个面板 kind 的 `build()` 忘了建它。
3. **对话框缩成 300 宽**：控件自己的选项名 `width` 被 `StyleRefinement.from(opts)` 读成 layer 显式尺寸，
   而 flex 里显式 size 赢过 inset。
4. **点菜单任何一行都选第 0 行**：`MouseEvent.localY` 是 TARGET-relative（AIR 也如此），点击目标是「行」。
   新增 `OverlayList.localYIn`。
5. **可见性翻转不上屏**：`visible` 由 arrange 写给 `backing`，只改 visible 的 payload 不抬位。
6. **销毁的弹层仍监听 stage** ⇒ 下一次点击读已置空的 `n.extra` ⇒ `#1009` ⇒ 画廊 tour 死在切页（TIMEOUT）。
7. **浮层宿主被永久留在 stage 上**（根节点没有父 NODE，`destroySubtree` 的摘除步骤对根永不执行）。

第 6、7 两条**只有「建了再拆」的程序能看见**——探针从不拆树。它们现在的钉子是多页 tour 的两条判据，
变异 `ui-demo/mutation-gallery-teardown.cjs` **2/2**（+3 个还原钉子）。

## 3 最后挖出来的那个缺陷（值得单独写）

修百分比根的「窗口 resize 要重解」之后，**`probes/widgets/feedback` 红了**：
`spinning repainted only 1 time(s) in 10 frames`。

追下去是三层叠在一起：

- **表层**：`paintDirty`/`paintAll` 画完才清 `M_PAINT`，于是 `paint` 里 `markPaint(n)` 抬的「下一帧再画」
  当场被抹掉；`reflow` 末尾的 `_needsPaint = false` 抹第二遍。
- **为什么以前没暴露**：`_solvedW` 只在主树 solve 时写 ⇒ `ENTER_FRAME` 的窗口尺寸检查**每帧都误判变化**、
  每帧重描述并顺带全量重画。**一个缺陷（每帧误判）遮住了另一个缺陷（自抬的 paint 被吃掉）。**
  把前一个修对，后一个立刻露出来。⇒ 这不是回归，是既有缺陷被揭开。
- **修法**：把「消费」提到「画之前」——
  `reflow` 开头 `var wantsPaint = _needsPaint; _needsPaint = false;`（闸门改用 `wantsPaint`），
  `paintAll`/`paintDirty` 先清位再 `paintSelf()`。语义随之明确：**本帧服务的请求是本帧开始时那些，
  绘制过程中抬的请求属于下一帧**。

钉子就是那两句断言（既不许冻住、也不许改布局），变异 `tools/mutation-widget-probes.cjs` **M5/M6**
（6/6，含逐字节还原核对）：

| 变异 | 做法 | 结果 |
|---|---|---|
| M5 | 回到「画完才清位」 | `FAIL spinning repainted only 2 time(s) in 10 frames` |
| M6 | 让自抬的帧抬**布局**位 | `FAIL spinning re-solved layout 9 time(s)` |

## 4 必须披露：编译器工作树上有两个**本地补丁**

长期口径是「`asaotui` 不动 `as3compiler/` 一行」。本轮破了例，因为这两个缺陷让**本机无法构建任何窗口程序**
（不是风格问题）：

| # | 文件 | 症状 | 改法 |
|---|---|---|---|
| P1 | `src/runtime.ts` | TS 模板字符串里的 `'\\'` 交给 C 时只剩 `'\'` ⇒ **生成的 C 不是合法 C**（Windows 的 `FindFirstFile` 分支） | 3 处转义加倍 |
| P2 | `vendor/window_glue.cc` | `#else`（非 Cocoa）分支缺 `sk_menu_flush`/`sk_menu_ensure`，而帧循环与事件循环**无条件调用** ⇒ 链接失败 | 两个显式空桩 |

登记为 `compiler-gaps.md` **G17/G18**。代价：`node tools/compiler-fingerprint.cjs` 现在如实报
`NEW dirty file: src/runtime.ts` / `vendor/window_glue.cc`（HEAD 已由并发会话推到 `5949cb7`）。
上游修好并提交后应**删除这两个补丁**，指纹回 CLEAN。

## 5 没做 / 做不到（登记，不修）

| 项 | 现状 |
|---|---|
| 键盘 / 焦点陷阱 | 全库 0 处（`STATUS.md` §3.1）。⇒ 对话框开着时**焦点仍在后面那棵树**，Tab 序无从谈起 |
| 浮层越界 | 不做翻转/夹紧：`placement` 写什么就是什么，锚点靠边会出窗 |
| 子菜单 / `z-index` | 菜单是扁平行；堆叠**只由子序列**决定（引擎刻意没有 z-index） |
| 开合动画 | 无过渡（卡在「布局动画」那道缺口，§3.4） |
| 虚拟滚动 | `list`/`table` 仍对每个 item 建真实节点 |
| `LICENSE` | 仍缺 |

## 6 怎么复核（一条命令）

```sh
cd asaotui && node tools/gates.cjs          # 25/25 PASS 才叫绿
```

单独跑：

```sh
node tools/probe.cjs probes/widgets/overlay # 65 checks
node probes/widgets/overlay/mutation.cjs    # 7/7
node ui-demo/run-gallery.cjs                # 6 页 tour + 6 张 PNG
node ui-demo/mutation-gallery-teardown.cjs  # 2/2 + 3 pins
node probes/array-coerce/run.cjs            # 8 格 AGREE
node tools/mutation-widget-probes.cjs       # feedback+media 6/6
```