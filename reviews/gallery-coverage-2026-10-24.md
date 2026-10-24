# 画廊覆盖率审计：七个控件发出去了，但没人能看见

日期：2026-10-24 · 触发问题：「所有组件都放到 `ui-demo/air-gallery` 中展示了吗？」

## 结论先说

**不是。** 审计前画廊 **6 页 / 31 个工厂**在展示，注册表里有 **39 个**。
漏的七个：`select` / `combobox` / `datePicker` / `virtualList` / `scrollView` / `drawer` / `popover`。
（`tree` 也在漏的名单里，但审计脚本第一版**读错了**——见 §3。）

`STATUS.md` 当时写着「`scrollView` 是唯一没进画廊的 kind」——**错 6 个**，而且这句话本身没人核过。

## 1. 修法：不是补一张清单，是补一道门

手工清单不可能长期对（这句话就是被它自己证伪的）。新增 `tools/kind-coverage.cjs`：
kind → 注册它的节点类（`Widgets.register("<kind>", …)` 所在文件的 `public class`）→
**构造该类的工厂函数**（`new <Class>(` 的文件里的 `public function`）→ 问**画廊有没有调用**其中之一。
扫的是 `ui-demo/demo/`，**不是** `ui-demo/air-gallery/src/`：后者由 `stage-air.cjs` 每次构建重新生成，
扫它只会认证「上一次构建」——第一次改的那个目录就被构建原地覆盖了（本轮真踩到）。

它成为第 **20** 道门（`tools/gates.cjs`，`6b2`）。

## 2. 新增第 7 页「Advanced」

652×374 的内容区放两列（440 + 12 + 200）：左列「Pickers」（`select` / `combobox` / `datePicker` / 两个按钮）
+「Scrolling」（`scrollView` 四条色带 / `virtualList` 500 行只挂 9 个）；右列「Tree」（两开分支、一行选中）。
`drawer` 是**底部抽屉、到达即开**（`side:"bottom"`, `size:90`, `scrim:false`），`popover` 由 tour 点开后再采样像素。

**布局途中撞出两处真缺陷**（都是「能跑但看不见」这一类）：

| 症状 | 真因 | 处置 |
|---|---|---|
| 第 7、8 个 tab 不可见、tour 切不过去 | 右缘抽屉（`side:"right"`, 200 宽）盖住 tab 条 | 改**底部抽屉**，页面内容止于 y = 470（560 − 90） |
| 浮层压住虚拟列表的网格 | 弹层向下展开，锚点是行内**最后**一格时面板落在下一张卡上 | 锚点留在最后的按钮，面板宽度收到 120 ⇒ 右缘只擦到树卡的左边框（476），树行全部可读 |

## 3. 扫描器自己的两处假绿（第一版）

| 假绿 | 真因 | 处置 |
|---|---|---|
| `tree` 判为「已展示」 | 画廊散文里有 `the second tree (the page below …` ⇒ `\btree\s*\(` 命中**注释** | 扫描前 `strip()` 掉注释与字符串 |
| `box`/`button`/`checkbox`/… 判为「无工厂」 | `BoxNode.as` 里 `// the class gained …` 被读成 `class gained` ⇒ 类名错 | 只认 `public class <Name>` |

这两个都不是「少算」，是**把散文当代码**。一道扫描门只要会读错输入，它认证的东西就没有意义。

## 4. 变异（`tools/mutation-kind-coverage.cjs` 3/3）

- **M1** 把画廊里的 `tree(` 改名 ⇒ 红，点名 `tree`。（日常回归：页面重写，控件悄悄消失。）
- **M2** 新加一个 kind + 它的工厂，画廊一个字都不提 ⇒ 红，点名 `shadow`。**这是真发生过两次的那个回归**，也是唯一能证明「kind → 类 → 工厂」解析链有效的变异。
- **M3** 把 `tree(` 藏进 `//` 注释 ⇒ 红。（钉住 §3 的假绿。）

每例 `finally` 还原并比 sha256，且还原后必须回到绿——否则中断一次就会留下一个坏 demo。

## 5. 落盘证据

- `node tools/gates.cjs` ⇒ **31/31 PASS**，`reviews/gates-all-16.txt`。
- `node tools/compiler-fingerprint.cjs` ⇒ `0 files` / byte-for-byte（编译器树未触碰，HEAD `480b81c`）。
- `cd ui-demo && node run-gallery.cjs` ⇒ `RESULT: PASS`，7 张 1050×840 PNG；
  第 7 页手算矩形全对：`advCol 24,132,440,374`、`advTreeCard 476,132,200,338`、`advDrawer:panel 0,470,700,90`、
  `advTree:tsrc/a.as 491,201,170,26`、`page6 popover: body rect=367,274,100,50 pixel=#dbeafe`。
- `cd ui-demo && node mutation-gallery-teardown.cjs` ⇒ **2/2 + 3 pins**，7 张截图逐字节还原。

## 6. 顺带修掉的陈旧计数

文档一直写「34 个 kind」，注册表实际 **35**（`scrollView` 加进来后从没计过数）——
现在这个数字由门看着，改错会红。