# probes/g31-space —— `A` 后面那个空格比别的空格窄（compiler-gaps.md G31）

一条命令、两条 runtime、同一个问题：

```bash
node probes/g31-space/run.cjs                 # ASC_SKIP_AIR=1 只跑我们这一臂
```

产出（本机实测）：

```
  text              AIR (51.5.1)                  ours (AOT)
  A |               span=12 gaps=[ 4 ]            span=11 gaps=[ 2 ]
  b |               span=11 gaps=[ 4 ]            span=11 gaps=[ 5 ]
  X |               span=12 gaps=[ 4 ]            span=12 gaps=[ 3 ]
  T |               span=12 gaps=[ 4 ]            span=12 gaps=[ 4 ]
  V |               span=12 gaps=[ 4 ]            span=12 gaps=[ 3 ]
  Q |               span=14 gaps=[ 4 ]            span=14 gaps=[ 4 ]
  1 |               span=11 gaps=[ 6 ]            span=11 gaps=[ 6 ]
  A box             span=29 gaps=[ 4 1 1 ]        span=29 gaps=[ 2 1 1 ]
  Abox              span=26 gaps=[ 1 1 1 ]        span=27 gaps=[ 1 1 ]
  A  box            span=32 gaps=[ 7 1 1 ]        span=32 gaps=[ 5 1 1 ]
  A card is a box   span=79 gaps=[ 4 1 1 4 1 5 4 1 1 ]  span=79 gaps=[ 2 1 2 1 5 2 5 5 1 1 ]
```

退出码：**0 = 缺陷复现**（这个包就是为它存在的）；**1 = 已修**（有人修好了字宽取整，
那就回来更新 `compiler-gaps.md` G31）；**2 = 工具链问题**（构建失败、SDK 缺失）。

## 怎么量的

`Arial 12pt`、`wordWrap=false`、`multiline=false`，把 `TextField` 画进一张白底 `BitmapData`，
**逐列数墨迹**（luma < 200），输出"每段空白有多宽"。之所以不用 `textWidth`：它需要一个参照物，
而且两条 runtime 可以在与本题无关的地方对它意见不同；**墨迹列宽是读者真正看到的东西**。

`<字母> |` 这种同尾串是关键设计：`|` 是不变的尾巴，所以两行之间的差异**只可能来自那个字母与空格**。

## 结论（三条，全部实测）

1. **空格没有被删。** `A  box`（两个空格）的间隙是 `A box` 的两倍多（5 vs 2）⇒ 空格一直在，
   早先"`A  box` 只剩一个空格 / 空格被吃掉"的说法是把放大截图当量具的误读。
2. **窄是（A, 空格）这一对特有的。** AIR 对**每个**字母都给 4px：`A |` = `b |` = `X |` = `T |` = `V |` = `Q |` = 4。
   我们给 `A` 2px、`X`/`V` 3px、`T`/`Q` 4px、`b` 5px —— 随字母漂。
3. **总宽和 AIR 完全一致**（`A box` 29=29、`A card is a box` 79=79，`span` 一栏逐项相等）。
   ⇒ **不是字被丢了、也不是行宽算错**，而是**各个字形的 advance 被按整数取整**：`A` 的 advance
   向下取整变宽一点、空格的 advance 向上取整变窄一点，差额互相抵消，总宽看着没错，
   但**空格落在 2px**——12pt 正文里 2px 的间隙读起来就是连字（`Acard`）。

## 为什么这值得立项

- 我们**总是**在 12pt 用比例字体时把词间距画窄 1–3px，而 12pt 正是文档正文与大量 UI 文本的字号。
- 与换行、字体族别名、富文本 run、粗体都无关：非换行与 `wrap=408/200` 三种模式首行间隙**逐项相同**；
  等宽面（Consolas）无此现象；12pt 最差（11/13/14pt 的空格贡献都是 3px）。
- 上游的修法是**一个开关级**的改动（不要 hint/取整 advance，走亚像素定位），
  修完重跑本探针应当看到 `A |` = 4px，其余行不变、总宽不变。

## 三条会让人白跑一趟的坑（都踩过）

1. **`new Stage()` + 手写 manifest 量不出任何墨迹。** 没有窗口就没有渲染上下文，`bd.draw` 全白，
   每个用例都报 `NO INK`；必须走 `--air-app`（真实窗口）——和 gallery 同一条路。
2. **`Stage.showWindow()` 阻塞在事件循环上**，`ENTER_FRAME` 在它之前不会派发，所以测量不能写在它后面。
   `ADDED_TO_STAGE` 才是能跑到的那一帧（gallery 的 tour 就在那里跑）。
3. **`adl` 下 `File.applicationDirectory` 只读**（`SecurityError: fileWriteResource`），
   AIR 臂改写 `File.userDirectory`；而且 `mxmlc` 在 Windows 是 `.bat`，必须经 `cmd /c`
   （`tools/mxmlc-run.cjs` 就是为这两条存在的）。

## 文件

| 文件 | 作用 |
|---|---|
| `src/Main.as` | AOT 臂，`package g31`，`--air-app` 驱动；写 `g31-aot.txt` |
| `AirMain.as` | AIR 臂，`mxmlc` → `adl`；写 `~/g31-air.txt` |
| `app.xml` | AOT 臂的描述符（120×40，`--air-app` 用它生成窗口） |
| `app-air.xml` | AIR 臂的描述符（`visible=false`，只用来拿一个渲染上下文） |
| `run.cjs` | 一条命令跑两臂、并排打印、给结论与退出码 |