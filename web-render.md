# Web 渲染参照：gpui web 端 vs asaotui web 后端

**规则**（与 [`cui-borrow-map.md`](cui-borrow-map.md)、[`gpui-borrow-map.md`](gpui-borrow-map.md) 同一口径）：
本工作区任何「借鉴 gpui web 端渲染」的说法，都必须落到下表某一行，并给出 gpui 源码里的
**具体文件 + 行号**。没有出处的不写；写出处却对不上的，删掉。

> 上游源码：gpui-fast 的 `crates/gpui_web`（22 文件）+ `crates/gpui_wgpu`（26 文件）。
> 本机 checkout 是 sparse-checkout（只检出了 `gpui`/`gpui_platform`/`gpui_windows`/`docs`），
> web 两个 crate 已用 `git archive HEAD crates/gpui_web crates/gpui_wgpu` 从 git 对象库导出到
> [`gpui-fast-src/gpui-web-src/`](gpui-fast-src/gpui-web-src/)（45 个 `.rs` + 4 个 `.wgsl`）。
> 行号以该导出为准。对照侧是 asaotui 自己的 web 后端：
> [`as3compiler/docs/zh-cn/html5-web.md`](../as3compiler/docs/zh-cn/html5-web.md)、
> `vendor/skia_glue.cc`、`vendor/web_glue.cc`、`vendor/stage3d_webgl.cc`。
>
> **结论先说**：gpui web 端没有「web 独有魔法」——它把 native 的 wgpu 场景图渲染器原样编译进
> wasm，用 WebGPU/WebGL2 画到 `<canvas>`（不是 DOM）。它的加速点与 native 完全同源
> （glyph atlas、实例化 batching、retained mode 依赖跟踪、tile cache）。asaotui 走的是另一条
> 栈（Skia Ganesh + WebGL2），两者**共享的借鉴面是机制，不是引擎**；最关键的落差——「WebGPU
> 探测失败回退 WebGL2，再失败才报错」——在 asaotui 当前 Skia 栈下**不能低成本照搬**，原因见 §4.1。

---

## 0. 渲染栈坐标系对齐

| 维度 | gpui web（出处） | asaotui web（落点） |
|---|---|---|
| 图形 API 抽象 | wgpu（Rust 跨后端层）：同一渲染器，底层 WebGPU / WebGL2 由 `WebBackendPreference` 切 | Skia：CPU 光栅用 `SkSurfaces::Raster`，GPU 光栅用 **Ganesh `GrDirectContext` + WebGL2**（`html5-web.md` §2 表） |
| 渲染进 wasm 的方式 | `gpui_wgpu` 整个编译进 wasm，画到 `<canvas>` | `vendor/skia_glue.cc` + wasm 版 `libskia.a` 编译进 wasm，画到 `<canvas>` |
| 后端选择 | **三级回退**：WebGPU → WebGL2 → 报错（`platform.rs:230-284`） | **固定 WebGL2**，`-s MAX_WEBGL_VERSION=2`；不支持 WebGL2 直接报错，不降级（`html5-web.md` §6.9/§6.12） |
| 文本整形 | 双轨：cosmic-text（wasm）+ Canvas fallback（emoji/缺字形，`text_system.rs:20`） | SkParagraph + HarfBuzz（wasm）；字体 `SkFontMgr_New_Custom_Data`，**无逐字符回退**（G40） |
| 字形光栅化 | GPU glyph atlas（`wgpu_atlas.rs:23`） | Skia 内部 glyph cache（Ganesh / SkParagraph） |
| draw call 合并 | 实例化 batching：`pass.draw(0..4, range)`（`wgpu_renderer.rs:1762,1782`） | Ganesh 内部 batching（不直接暴露） |
| 帧驱动 | `requestAnimationFrame`（`window.rs:485`）+ `ResizeObserver`（`:281`） | `emscripten_set_main_loop` + rAF（`html5-web.md` §3.2）+ `data-asc-fill`/`sk_web_canvas_size_changed`（§3.7） |
| 增量重画 | retained mode（依赖跟踪，纯 CPU，跨平台）+ scroll layer tile cache（`tile_cache.rs`） | 子树级 measure（`cui-borrow-map.md` §3.8）+ cacheAsBitmap 增量 re-bake（G30） |
| 线程 | `wasm_thread`（Web Worker + SharedArrayBuffer） | 单线程（emscripten 默认） |

⇒ 两套栈在「GPU 光栅 + wasm + canvas」这条大路上同向，但**抽象层不同**：gpui 的 wgpu 让它
能在同一个渲染器上换 WebGPU/WebGL2 后端，asaotui 的 Ganesh 只有 GL 一个 web 后端。

---

## 1. 三级回退：WebGPU → WebGL2 → 报错（核心落差）

### gpui 的实现（`platform.rs:230-284`）

```rust
async fn initialize_graphics(...) -> Result<...> {
    match preference {
        WebBackendPreference::Auto => {
            // 1) 先探测 WebGPU
            if wgpu::util::is_browser_webgpu_supported().await {
                if let Ok(prepared) = WgpuContext::new_web(&canvas, WebBackendPreference::WebGpu).await {
                    return Ok(prepared);
                }
                // WebGPU 失败 → 删掉 webgpu canvas，换 WebGL2
            }
            // 2) 回退 WebGL2
            if let Ok(prepared) = WgpuContext::new_web(&canvas, WebBackendPreference::WebGl).await {
                return Ok(prepared);
            }
            // 3) 再失败 → 报错
            Err(anyhow!("No browser graphics backend could be initialized. Tried WebGPU, then WebGL2. ..."))
        }
        // 显式 WebGpu / WebGl → 只试那一个，失败报错
    }
}
```

### asaotui 的现状（`html5-web.md` §6.9、§6.12）

- `vendor/skia_glue.cc:506` 硬编码 `attrs.majorVersion = 2`（WebGL2），`-s MAX_WEBGL_VERSION=2`。
- §6.9：「不支持 WebGL2 的浏览器上 `getContext('webgl2')` 失败 → 上下文创建报错，而不是静默降级」。
- §6.12：「web 渲染后端固定为 WebGL2，未使用 WebGPU」——wasm 版 Skia `skia_use_webgpu=false`、
  `skia_enable_graphite=false`、`skia_use_dawn=false`、`skia_use_webgl=true`，`libskia.a` 里 Dawn 符号为 0。

### 为什么不能低成本照搬（这是本节唯一要点）

gpui 的三级回退**便宜**，是因为它用 **wgpu**：`WgpuContext::new_web` 只是把一个 `preference`
参数切到 WebGPU 或 WebGL2 后端，**渲染器代码（scene → draw call）完全同一份**。

asaotui 的 GPU 后端是 **Skia Ganesh**，而 **Ganesh 没有 WebGPU 后端**（只有 Metal/D3D/Vulkan/GL）。
Skia 的 WebGPU 支持在 **Graphite + Dawn** 里，那是**另一套渲染引擎**，不是「加个探测」。所以
「WebGPU 失败回退 WebGL2」对 asaotui 意味着：

| 要动的 | 代价 |
|---|---|
| Skia 引擎 Ganesh → Graphite + Dawn | 渲染器重写（`html5-web.md` §6.12 明确「Ganesh 无 WebGPU 后端 ⇒ 迁 Graphite + Dawn」） |
| wasm32 拉 Dawn 重编 | 新工具链依赖，Dawn wasm 支持需确认 |
| Emscripten 3.1.44 是否够 | §6.12 明确「升级 Emscripten」 |
| Stage3D 后端 | 现有 `stage3d_webgl.cc`（WebGL2 + GLSL ES）要再加 **WGSL** 第三后端 |
| 字体/atlas | 全部适配 Graphite 的纹理接口 |

### 借鉴决策

- **「探测 → 降级 → 报错」的状态机骨架：可借**（成本极低）。这是纯逻辑：先试首选后端，失败
  时清理失败产物、换次选、再失败给出「试了 A、又试了 B」的诚实报错——不静默白屏。
- **「WebGPU」这一级：暂不借，登记缺口**。在 Skia Ganesh 下它就是换引擎，且
  `html5-web.md` §6.12 已量化「换 WebGPU 换不到 fps」（GPU 路径单帧仅占帧预算 1.35%，瓶颈是
  rAF/面板刷新率）。重启触发条件见 `TODO.md` 阶段八十九·二十九。
- **可落地的低配版**：把「WebGL2 创建失败 → 报错」升级为「WebGL2 创建失败 → 探测是否可用
  CPU 光栅（`SkSurfaces::Raster` + `putImageData`）→ 再报错」。即回退的第二级不是 WebGPU，
  而是 asaotui 已有的 CPU 路径——这跟 gpui 的「WebGPU 优先、WebGL2 兜底」**形态同构**，但
  用的是 asaotui 已有的两条后端，无需换引擎。**（待用户定：默认 opt-in，因 CPU 路径对
  `adl` 逐像素校准，语义无漂移，但性能大幅退化，须显式声明而不是静默切。）**

---

## 2. 文本双轨制 + Canvas fallback（对照 G40）

### gpui（`text_system.rs` + `canvas_text.rs` + `glyph_cache.rs`）

`WebTextSystem`（`text_system.rs:20`）持有两条轨道：

| 轨道 | 实现 | 用途 |
|---|---|---|
| 主轨 | `native: CosmicTextSystem`（`text_system.rs:62`，cosmic-text 编译进 wasm） | 正常文本整形 + 光栅化到 GPU atlas |
| 副轨 | Canvas2D（`canvas_text.rs`） | 缺字形（cosmic 没这个码点）或彩色 emoji 表示 |

`layout_line`（`text_system.rs:288-306`）先走 cosmic-text 排版，再 `apply_fallback`：扫描缺失
glyph 或「需要彩色却拿不到彩色」的 run，逐字符交给 Canvas 量宽 + 光栅化，替换进 `LineLayout`。
「浏览器 ink extent 只影响光栅 bounds，不影响周围行的 line metrics」（`text_system.rs:187` 注释）
——即 Canvas 回退不污染 cosmic 的排版基线。

Canvas 副轨的三件加速（这就是「web 端文本不卡」的机制）：

1. **`willReadFrequently: true`**（`canvas_text.rs:36`）：`getContext("2d", {willReadFrequently:true})`
   告诉浏览器走 CPU 回读优化路径，避免每个字形光栅化后 GPU→CPU 读回的昂贵开销。
2. **三级缓存**（`text_system.rs` State）：
   - glyph 去重 `GlyphCache`（`glyph_cache.rs:15-18`）：`(FontId, color) → HashMap<text, GlyphId>`；
   - measurement 缓存 `HashMap<(FontId, GlyphId, Pixels), CanvasTextMetrics>`，**上限 4096 条、满了 clear**（`text_system.rs:17,161`）；
   - font-id 映射 `canvas_font_ids`（`text_system.rs:34`）。
3. **`thread_local` 单例 OffscreenCanvas**（`canvas_text.rs:14-20,65-82`）：整线程复用一个
   `TextCanvas`，不每字形新建 canvas/context。

### asaotui 现状（G40）

`vendor/skia_glue.cc` web 分支用 `SkFontMgr_New_Custom_Data` 注入字体，**不提供
`matchFamilyStyleCharacter` 的逐字符回退** ⇒ 混合脚本页面装一个「覆盖全脚本」的面，否则缺字形
画 `.notdef`（空心方框）。库侧已用单字体子集（`ui-demo/fonts/MiSans-DemoSubset.ttf`，
`tools/web-font.cjs` 切出源码全部字符）绕开，代价是 web 端英文改用 MiSans（`compiler-gaps.md` **G40**）。

### 借鉴决策

- **「文本缺字形/emoji 走第二轨道兜底」这一形态：可借，但技术栈不同**。gpui 的副轨是
  Canvas2D；asaotui 没有「浏览器 Canvas 量宽」这条路（文本全走 SkParagraph）。asaotui 的等价
  正解是 G40 已登记的：给 `SkFontMgr_New_Custom_Data` 包一层 `onMatchFamilyStyleCharacter`
  （或换带 cascade 的 data fontmgr），让同 family 缺码点落到已注册的其它面——**这是后端能力
  缺口，不是照搬 gpui 的 Canvas 副轨**。
- **「颜色不进测量键、emoji 与文本分开」这一口径：已借**。正是子树级 measure 落地的
  `Style.diffFlags` 拆分（`cui-borrow-map.md` §3.8）；gpui 的 `GlyphCache` 用 `color: bool` 区分
  彩色 emoji 与普通字形（`glyph_cache.rs:11`），与 asaotui `measureField` 的「Colour is
  deliberately NOT in the key」同一条原则。
- **「`willReadFrequently` 回读优化」：不直接适用**。asaotui 的 CPU 上屏路径用
  `putImageData`（`web_glue.cc`），GPU 路径是 `GrDirectContext::flush`，都没有「逐字形 canvas
  回读」这个场景；但**若将来做 Canvas fallback**（见上），这一条是必抄的。

---

## 3. GPU glyph atlas（对照 asaotui 的 Skia glyph cache）

### gpui（`wgpu_atlas.rs`）

- `WgpuAtlas`（`:23`）是线程安全的 atlas 状态：字形/图片光栅化后上传进一张（或多张）GPU 纹理，
  渲染时 GPU 采样，避免每帧重光栅化。`allocate`（`:162`）在 atlas 里找空位放 tile。
- fork 的 web 特化 bug fix（`fast/atlas.rs`）：tile 大于 `max_texture_dimension_2d`（WebGL2 通常
  8192/16384，比 native 严）时**先判 `fits` 再分配**，不再为放不下的 tile 无限 new 一张 1 GiB
  纹理直到 OOM（`fast/atlas.rs:13-18` 注释）。

### asaotui 现状

Skia 自带 glyph cache（Ganesh 的 `GrTextBlob` / SkParagraph 的 run cache）。asaotui 不直接管
atlas，而是 Skia 内部处理。G41（HarfBuzz 快路径）已经绕开 SkParagraph 做短纯 ASCII 单行字段
的轻量 shape（`compiler-gaps.md` G41/G42）。

### 借鉴决策

- **atlas 层：不借**。asaotui 的 atlas 是 Skia 内部的，无需（也无法）照搬 wgpu 的 `WgpuAtlas`。
- **`fits` 预检这一条：不直接适用**。它是 WebGL `MAX_TEXTURE_SIZE` 上限的 bug fix，asaotui 若
  引入「超大 surface 缓存」再抄；当前 Skia 内部已处理。

---

## 4. 实例化 batching（对照 asaotui 的 Ganesh）

### gpui（`wgpu_renderer.rs`）

`draw`（`:1154`）→ `draw_instances`（`:1762`）/ `draw_sprites`（`:1782`）：同类 primitive 合并成
**一次实例化 draw**——`pass.set_pipeline` + `set_bind_group` + `pass.draw(0..4, instance_range)`。
每个 primitive 是一个 4 顶点 quad（instance），一批 instance 共享 pipeline + bind_group。
这是 WebGL 上省 draw call 的关键：WebGL 每个 draw call 有 JS↔wasm↔驱动 的桥接开销，实例化
batching 把「N 个 primitive」从 N 次调用压成 1 次。

### asaotui 现状

Ganesh 内部自己做 batching（`GrOpsTask` 按 pipeline 分组）。asaotui 生成的 C 不直接发 draw call，
而是喂 Skia canvas（`sk_canvas_*`），所以「draw call 合并」这一层是 Skia 的职责，不是 asaotui 的。

### 借鉴决策

- **不借**。这是 wgpu 渲染器的职责，asaotui 的对应层是 Ganesh，Skia 已经处理。asaotui 能影响的
  是**喂给 Skia 的命令量**（这正是子树级 measure / cacheAsBitmap 在做的事），不是 draw call 层。

---

## 5. device_lost / GPU 错误处理（asaotui 当前空白，可借）

### gpui（`wgpu_renderer.rs:1155-1197`）

`draw` 开头有 **wasm 特化的 `device_lost()` 分支**（`:1155-1165`）：

```rust
#[cfg(target_family = "wasm")]
if self.device_lost() {
    log::error!("Browser graphics context was lost; rendering has stopped. Reload the page to recover.");
    self.unconfigure_surface();
    return false;
}
```

另有 GPU error 计数（`:1173-1197`）：连续失败 >5 次 → `invalidate_intermediate_textures` +
`atlas.clear()` + `TileCache::clear()` + `needs_redraw=true`（清缓存重画），>10 次 → panic。

### asaotui 现状

grep `vendor/skia_glue.cc`/`web_glue.cc` 无 `webglcontextlost` / `is_context_lost` 命中——**没有
context lost 处理**。浏览器 GPU 上下文丢失（GPU 进程崩溃、驱动重置、WebGL 出错）时，Skia Ganesh
会怎样是**未定义**的：可能白屏、可能 `GrDirectContext` 内部报错但无上层处置。

### 借鉴决策

- **可借，成本低**：在 web 后端的帧循环入口加一个 `webglcontextlost` 事件监听（或
  `gl.isContextLost()` 探测），发现丢失时**停止渲染 + 明确报错 + 提示 reload**，而不是静默白屏
  或继续用坏 context 画。这与 gpui 的 `device_lost()` 分支同构。
- 落点：`vendor/web_glue.cc`（帧循环入口）+ `vendor/skia_glue.cc`（`sk_gr_reset_context` 已有，
  见 `html5-web.md` §3.3 第 7 条，可复用）。**登记缺口（见 §8 G45）。**

---

## 6. scroll layer tile cache（对照 asaotui 的 cacheAsBitmap）

### gpui（`tile_cache.rs`）

fork 的 scroll layer tile cache（`fast/layers/tile_cache.rs`）：

- `TileCache`（`:30`）+ `Tile`（`:56`）+ `TileTexture`（`:72`）；
- 缓存键 `(LayerKey, TileCoord)`——layer 是 scroll layer 身份，coord 是 tile 坐标；
- **换代机制**：`begin_frame`（`:145`）标记本帧 seen，前一代没被碰的 tile 保留（`:8` 注释）；
- `drop_unseen_layers`（`:230`）删掉整帧没被看到的 layer；
- `evict_to_budget`（`:262`）按预算 LRU 淘汰（`last_used` 排序）。

⚠️ 但 `README.md:7` 明确 scroll layers 只宣称「on macOS, Linux and Windows」——**web 不在列**。
代码在 wasm 也编译（`fast/mod.rs` 的 `layers` 模块无 cfg 排除），但 fork 未对 web 宣称/验证。

### asaotui 现状

cacheAsBitmap 增量 re-bake（`compiler-gaps.md` G30），`ASC_PASS_TRACE` 显示 `live=444 cached=23723`。
子树级 measure 后续 dissect（G41）结论：live 场景的 paint 瓶颈是文本整形，**不是光栅化/tile**。

### 借鉴决策

- **不借（当前阶段）**。理由两条：① gpui 自己都没在 web 上宣称 tile cache 可用；② asaotui 实测
  （G41 dissect）已经证明 live 场景的瓶颈是文本整形（89%），tile/光栅化层没有可省的浪费——
  `live=444 cached=23723` 说明 cacheAsBitmap 已经在增量 re-bake，没有「没变却重画」。

---

## 7. 窗口循环 / composition / 线程（对照结论）

### 7.1 窗口循环（rAF + ResizeObserver + visibility）

gpui `window.rs`：
- `request_animation_frame`（`:485`）驱动渲染；
- `ResizeObserver`（`:281`）监听 canvas CSS box 变化，resize 时**同步渲染**（`:382-389`，
  `require_presentation: true`）避免「新 CSS box 被旧 backing image 拉伸」呈现一帧；
- visibility 处理（`:199` `document_visibility`），隐藏页跳过渲染（`:325` 注释「zero-size canvas
  (e.g. display:none)」）。

asaotui 等价物已具备：rAF（`html5-web.md` §3.2）、`data-asc-fill` + `sk_web_canvas_size_changed`
（§3.7，四条约定的其中一条就是「未变化 box 直接丢」）。**这一块无需借，asaotui 已经对齐。**

### 7.2 window composition 在 wasm 被排除

`gpui_wgpu/src/fast/mod.rs`：`#[cfg(not(target_family = "wasm"))] pub(crate) mod composition;`
——代码级确认「浏览器页面没有窗口合成」。fork 因此加了 `WebPlatform::wgpu_context()`
（`fast/wgpu_context.rs`），让 wgpu 渲染的内容作为 `WgpuDynamicTexture` 纹理被 GPUI 采样。
**asaotui 无对应需求**（没有「在 web 页面里嵌原生内容」的场景），不借。

### 7.3 wasm_thread（多线程）

gpui 用 `wasm_thread`（Web Worker + SharedArrayBuffer，`Cargo.toml:48`）在 web 上保留多线程
dispatcher，后台整形/布局在 worker。asaotui 是 emscripten 默认单线程（`html5-web.md` 无 pthread
描述）。**不借**：emscripten 的 pthread + SharedArrayBuffer 需要 COOP/COEP 头，跨源部署约束大，
且 asaotui 当前瓶颈（文本整形、rAF）不在「缺线程并行」上。

---

## 8. 借鉴决策汇总 + 缺口登记

### 汇总表

| # | 机制 | gpui 出处 | 决策 | 理由 / 落点 |
|---|---|---|---|---|
| W1 | WebGPU→WebGL2→报错 三级回退 | `platform.rs:230-284` | **骨架借、WebGPU 级不借** | wgpu 换后端便宜；Skia Ganesh 无 WebGPU，需换 Graphite+Dawn（§4.1） |
| W2 | 文本双轨 + Canvas fallback | `text_system.rs:20`、`canvas_text.rs` | **形态借、技术栈不搬** | 对应 G40 正解是给 `SkFontMgr_New_Custom_Data` 补 cascade，不是抄 Canvas 副轨 |
| W3 | `willReadFrequently` 回读优化 | `canvas_text.rs:36` | 暂不适用 | 仅当将来做 Canvas fallback 时必抄 |
| W4 | glyph 去重 + 测量缓存（4096 上限） | `glyph_cache.rs`、`text_system.rs:17,161` | 已借（原则） | 即子树级 measure 的「颜色不进测量键」 |
| W5 | GPU glyph atlas | `wgpu_atlas.rs:23` | 不借 | Skia 内部已管 |
| W6 | 实例化 batching | `wgpu_renderer.rs:1762,1782` | 不借 | Ganesh 内部已做 |
| W7 | device_lost / GPU error 处理 | `wgpu_renderer.rs:1155-1197` | **可借，成本低** | asaotui 当前空白，登记 G45 |
| W8 | scroll layer tile cache | `tile_cache.rs` | 不借（当前） | gpui 自己未宣称 web；G41 实测瓶颈在整形非 tile |
| W9 | rAF + ResizeObserver + visibility | `window.rs:281,485` | 已对齐 | asaotui §3.2/§3.7 已具备 |
| W10 | window composition | `fast/mod.rs` | 不借 | web 无窗口合成，asaotui 无此场景 |
| W11 | wasm_thread 多线程 | `Cargo.toml:48` | 不借 | COOP/COEP 约束大，瓶颈不在线程 |

### 缺口登记（进 `compiler-gaps.md`）

- **G45（新增）—— web 后端缺 `webglcontextlost` 处置**：浏览器 GPU 上下文丢失时无上层处置，
  可能静默白屏或继续用坏 context。参照 gpui `wgpu_renderer.rs:1155-1165` 的 `device_lost()` 分支，
  在 `vendor/web_glue.cc` 帧循环入口加 `webglcontextlost` 监听 / `gl.isContextLost()` 探测，
  丢失时停止渲染 + 明确报错 + 提示 reload。
- **WebGPU 探测回退（不新增条目，挂 TODO.md 阶段八十九·二十九）**：`html5-web.md` §6.12 已定性
  「换 WebGPU = 换引擎，换不到 fps」，重启条件已有。本文 §4.1 补一条**低配可落地**路径
  （WebGL2 失败回退 CPU 光栅）供未来决策，不单独立缺口。

---

## 9. 自检

```bash
# 本工作区里所有提到 gpui web 渲染机制的地方（应全部落在上表）
grep -rn "gpui_web\|gpui_wgpu\|WebBackendPreference\|wgpu_context\|tile_cache\|device_lost" asaotui --include=*.md
```

> 本机 bash 无 coreutils（无 `grep`），实际用内置 grep 工具执行。
> 每次改动本表后跑一遍，确认没有**无出处**的借鉴声明。
>
> 与 `cui-borrow-map.md` / `gpui-borrow-map.md` 的关系：本表是**web 渲染后端**的专用切片，
> 三者正交不合并。同一件事出现在多表时（例如「颜色不进测量键」），以最早落地的
> `cui-borrow-map.md` §3.8 为准。
