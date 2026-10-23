# 校验记录：`ui-toolkit-feasibility*.md` 对一手源码的逐条核实

> **日期**：2026-10-22　**范围**：`asaotui/ui-toolkit-feasibility.md`（中文）与
> `asaotui/ui-toolkit-feasibility-en.md`（英文镜像）的**全部 `文件:行号` 引用与关键论断**。
> **方法**：一切行号均在本次会话里用 `grep -n` / `sed -n` / `awk` 从一手源码现读得到，未沿用文档自述。
> **修的对象**：只改上面两份文档；`as3compiler/`（含 `TODO.md`）**只读、未改**。
>
> **取证环境**（全部命令前需 `export PATH="/d/Program Files/Git/usr/bin:$PATH"`）：
> - GPUI 检出：`asaotui/gpui-src/`，`main`@`544780422affd11699fb531c49af5cc6e82a3fd7`（git describe = `nightly`，2026-10-21）。
>   注意：本检出**只含** `crates/{gpui,gpui_macros,refineable,util}`，平台渲染后端（blade/macos/windows）不在其中。
> - 编译器：`as3compiler/`，`main`@`e798ef72b40489277b7b896989c244f16dc2c750`（2026-10-22 05:58 +0800）。
> - `asaotui/` 本身不是 git 仓库；`gpui-src/` 是嵌进来的独立检出。

---

## 0. 结论速览

- ✅ 属实：GPUI 的四趟管线、`Style`/Taffy、`TabStopMap`、`Scene` 图元表、AccessKit、`notify()` 数据流、
  `hybrid immediate and retained` 自述；编译器侧的自动布局/actions/无障碍/控件集缺失、焦点与 Tab
  的四个形态限制、`TouchEvent` 有类无输入、IME 通道、`NativeWindow` 43 成员、219 示例。
- ⚠️ 行号修正：**18 处**（逐条见 §A/§B/§C）。最常见的漂移是同期几次提交后代码下移，以及把「注释块/前后文」
  当成了「定义行」。
- ❌ 不实：**10 处**（逐条见 §A/§B/§C），其中最重要的四类：
  1. **`Style` 不是「~50 项」**，实测 **38 项**（`style.rs:180-322`）。
  2. **`key_dispatch.rs`/`keymap.rs` 不是「GPUI 第二大的模块」**（按行数仅排第十左右）。
  3. **`scene.rs` 的 `Primitive` 成员表把 `StartLayer` 混了进去**——`StartLayer` 属 `PaintOperation`，不在 `Primitive`。
  4. **无障碍的证据话术错**：`grep -rn "accessibility" src/*.ts`（大小写敏感）其实**零命中**，
     并不存在「`Sound`/`Keyboard.isAccessible` 这类无关命中」（那两者拼写里没有 `accessibility`）。
  其余：`ElementTree` 不是具名类型（实为 `Drawable`/`ElementDrawPhase`）；「轴对齐特化在 `emit.ts:~21740`」实为 `as_do_extents:21464`；
  `examples/` 子目录「8 个」实为 **12 个**；`rust-text-backend.md` 的 15 函数接缝在 §1.1（非 §3）、② 刀在 §0 摘要（非 §1）；
  「`TODO.md` 有比阶段二百三十一更高的编号在途」不成立（232+ 零命中）。
- 🟡 另有若干「引用能对上但指向的文件/节错位」：`rust-text-backend.md` 的 15 函数接缝在 **§1.1**（非 §3）、
  两刀的 ② 在 **§0 摘要**（非 §1）；`ElementTree` 不是具名类型；`StartLayer` 归属；`8 个目录` 实为 **12 个**。

---

## A. §2「GPUI 实际长什么样」——逐条

### A1. §2.1 生命周期与「整棵树被丢弃」

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `crates/gpui/src/element.rs:8-14` 引文 | **⚠️ 行号修正为 `10-14`**（第 8 行是 `# Element Basics` 标题；引文段落从 `:10` 起） | `awk 'NR>=8&&NR<=17{printf "%d: %s\n",NR,$0}' element.rs` → `:10` = "Elements are constructed by calling …"、`:13` 末接 `:14` = "tree and any callbacks … dropped and the process repeats." |
| 「在下一帧开始之前，整棵元素树和回调都被丢弃」 | ✅ 英文原文逐字属实 | `element.rs:13-14`：「…Before the start of the next frame, the entire element **tree and any callbacks they have registered with GPUI are dropped and the process repeats.**」 |
| `Element::PrepaintState`(`element.rs:17`) | **⚠️ `:17` 只是模块说明；关联类型定义在 `:59`** | `grep -n PrepaintState element.rs` → `:17`（doc）、`:59`（`type PrepaintState: 'static;`） |
| 「hybrid immediate and retained」自称 | ✅ 属实 | `grep -rni "hybrid immediate" crates/gpui/README.md` → `README.md:3` |
| `ElementTree` 作为 GPUI 的类型名 | **❌ 不实**（本检出无此具名类型；是 `Drawable`/`ElementDrawPhase` 状态机） | `grep -rn "pub struct ElementTree" src/` 零命中；`element.rs:315-348` 是 `Drawable` + `enum ElementDrawPhase` |

### A2. §2.2 四趟管线

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `Element`(`element.rs:52-96`) 只有四件事 | **⚠️ `52-105`**（`pub trait Element` 在 `:52`，`paint` 从 `:96` 起、到 `:105` 收尾） | `grep -n "pub trait Element\|fn request_layout\|fn prepaint\|fn paint" element.rs` → `:52`/`:74`/`:84`/`:96` |
| `paint` 对应我们 `as_render_object`(`src/emit.ts:22235`)/`_content`(`:22477`) | ✅ 两处定义行都对 | `grep -n "static void as_render_object" src/emit.ts` → `:22235`、`:22477` |

### A3. §2.3 `Style` 与 Taffy

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `Style`(`style.rs:180` 起) 是「**~50 项**扁平值表」 | **❌ 不实：实测 38 个 `pub` 字段**（`Style` 结构体 `:180-322`） | `awk 'NR>=180&&NR<=322{if($0~/^    pub /)print NR": "$0}' style.rs` 得 38 行；`awk` 求 `^}` 得结构体止于 `:322` |
| 字段清单（`display`…`mouse_cursor`） | **⚠️ 漏了 6 项**：`opacity`/`grid_cols`/`grid_rows`/`grid_location`/`debug`/`debug_below`（`style.rs:302/306/310/313/317/321`） | 同上 |
| 标 `#[refineable]` 的字段驱动继承 refine | ✅ 属实（本检出 **11 个**字段带该属性） | `awk` 数 `#[refineable]` → 11；分别落在 `overflow`/`inset`/`size`/`min_size`/`max_size`/`margin`/`padding`/`border_widths`/`gap`/`corner_radii`/`text` |
| `taffy.rs:31` `TaffyLayoutEngine`、`:62` `request_layout`、`:187` `compute_layout`、`:345` `layout_bounds` | ✅ 四行全对 | `grep -n "TaffyLayoutEngine\|pub fn request_layout\|pub fn compute_layout\|pub fn layout_bounds" taffy.rs` → `:31`/`:62`/`:187`/`:345` |
| `Style → taffy::style::Style` 转换在 `taffy.rs:439` 起；`rem_size`/`scale_factor` 在 `:436` | ✅ 属实 | `grep -n "impl ToTaffy<taffy::style::Style> for Style"` → `:439`；`:436` = `fn to_taffy(&self, rem_size: Pixels, scale_factor: f32) -> Output;` |

### A4. §2.4 数据流

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `_ownership_and_data_flow.rs` 开篇即「每个 model/view 由顶层 `App` 拥有」 | ✅ 属实（`:1`） | `sed -n '1p' _ownership_and_data_flow.rs` |
| `notify()` / `observe()` / `subscribe()` / `emit()` | ✅ 属实；补上位置 | `grep -n "pub fn notify\|pub fn observe\|pub fn subscribe\|pub fn emit" app/context.rs` → `:221`/`:64`/`:94`/`:780`；`app.rs:3164` 是 `App::notify` |

### A5. §2.5 输入 / keymap / Tab 序

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `key_dispatch.rs` **82 KB**、`keymap.rs` **43 KB** | **⚠️ 字节数≈对（KiB），改为行数**：`key_dispatch.rs` **2216 行 / 84782 B**、`keymap.rs` **1135 行 / 44406 B**（+ `keymap/context.rs` 891 行、`keymap/binding.rs` 143 行 ＝ 模块 2169 行） | `wc -l key_dispatch.rs keymap.rs keymap/*.rs`；`ls -la` |
| 「是它**第二大**的模块」 | **❌ 不实**：按行数 `key_dispatch.rs`(2216) 约排**第十**，前面有 `window.rs` 9979、`elements/div.rs` 5789、`geometry.rs` 4020、`platform.rs` 3907、`app.rs` 3888、`elements/list.rs` 3638、`profiler/journal.rs` 3540、`gestures.rs` 2331、`profiler.rs` 2225 | `find . -name '*.rs' \| xargs wc -l \| sort -rn \| head -16` |
| `TabStopMap`(`tab_stop.rs:1-20`)、`insertion_history`、`Insert`/`Group`/`GroupEnd` + `SumTree` | **⚠️ 行号修正为 `:11-23`**（`:1` 只是 `use`） | `grep -n "TabStopMap\|insertion_history\|SumTree\|enum TabStopOperation" tab_stop.rs` → struct `:11`、field `:13`/`:15`、enum `:19-23` |
| keymap 是 JSON、按 key context 匹配 | ✅ 属实 | `docs/key_dispatch.md` 全篇（100 行）含 `"context": "menu"` / `"bindings"` JSON 例 |
| `FocusHandle`/`FocusId` | ✅ 存在；补位置 | `grep -rn "pub struct FocusHandle\|pub struct FocusId"` → `window.rs:543`/`:339` |

### A6. §2.6 无障碍

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `_accessibility.rs` 集成 AccessKit、两大能力、身份用 `ElementId`/`GlobalElementId` | ✅ 属实；补位置 | `_accessibility.rs:15`（AccessKit）、`:22-24`（两大能力）、`:30`（ID 小节）；`GlobalElementId` = `element.rs:220` |

### A7. §2.7 `Scene` 图元表

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `scene.rs:215-230`：`Primitive` / `StartLayer(Bounds)` / `Shadow` … `Surface` | **❌ 不实（成员表混类）**：`Primitive` 枚举在 `:222-230`，成员只有 `Shadow`/`Quad`/`Path`/`Underline`/`MonochromeSprite`/`SubpixelSprite`/`PolychromeSprite`/`Surface`；**`StartLayer(Bounds)` 属 `PaintOperation`（`:214-216`）**；另有 `PrimitiveKind`（`:202-211`） | `awk 'NR>=198&&NR<=232' scene.rs` |
| `:478-495` 按类型分段 `Range`（`Quads(Range)`…） | ✅ 属实（`enum PrimitiveBatch` 在 `:477-496`，变体 `:478-495`） | `awk 'NR>=472&&NR<=500' scene.rs` |
| 外加 `bounds_tree` 做空间索引 | **⚠️ 精确化**：字段是 `Scene.primitive_bounds: BoundsTree<ScaledPixels>`（`scene.rs:43`），模块 `src/bounds_tree.rs`（472 行） | `grep -n "BoundsTree" scene.rs` → `:9`/`:43` |

### A8. §2 其它体量核实（供 N3/N4）

| 文件 | 文档原说法 | 实测 | 证据 |
|---|---|---|---|
| `gestures.rs` | 95 KB | **2331 行 / 98284 B（≈96 KiB）** | `wc -l` / `ls -la` |
| `hot_reload.rs` | （与另两者并列「80 KB」） | **248 行 / 9055 B** | 同上 |
| `inspector.rs` | 同上 | **271 行 / 9851 B** | 同上 |
| `profiler.rs` | 80 KB | **2225 行 / 82441 B（≈80.5 KiB）**；profiler 模块另含 `journal.rs` 3540 行、`hang.rs` 1865 行 | 同上 |
| `text_system.rs` | （N2 提到） | **1505 行** + `text_system/` 子模块 | 同上 |

> N3 原文「`hot_reload.rs` / `inspector.rs` / `profiler.rs` 80 KB」读起来像三者都是 80 KB；实际只有 `profiler.rs` 大约 80 KB。已在两份文档中拆开写。

---

## B. §3「我们这一侧的家底」——逐条

### B1. 行号直接实测

| 原断言 | 核实结果 | 实测证据（HEAD `e798ef7`） |
|---|---|---|
| `DisplayObjectContainer_addChild` `src/emit.ts:10607` | ✅ 属实 | `sed -n '10607p'` = `this.line('DisplayObject* DisplayObjectContainer_addChild(void* _this, DisplayObject* child) {');` |
| `as_render_object` `:22235` / `as_render_object_content` `:22477` | ✅ 属实 | 两行均为 `this.line('static void as_render_object…`） |
| 矩阵**轴对齐特化** `emit.ts:~21740` | **❌ 不实**：`:21740` 是九宫格求解的仿射残差 `double ia = cs / sx…`。真正的轴对齐包围盒特化是 `as_do_extents` **`:21464`**（非轴对齐回落 `as_bounds_xform` `:21168`） | `grep -n "as_do_extents\|as_bounds_xform" src/emit.ts`；`sed -n '21442-21480p'` 注释明说 "Exact extents for the axis-aligned case… Returns 0 when the map is not axis-aligned" |
| `Stage_showWindow` `:23979` | ✅ 属实 | `grep -n` |
| `as_skia_surface_show_window[_gpu]` `src/runtime.ts:9194` | ✅ 属实（`:9194` 与 `:9215` 两形） | `grep -n` |
| `sk_window_show` / `sk_pump_frame`(`window_glue.cc:758`) | **⚠️ 只有 `sk_pump_frame` 在 `:758`**；`sk_window_show` 在 **`:1751`** | `grep -n "static double sk_pump_frame\|int sk_window_show" vendor/window_glue.cc` |
| `ASC_window_on_redraw`(`:23621`) | ✅ 属实 | `grep -n "ASC_window_on_redraw(int id)"` |
| `ASC_window_render`(`:23197`) | ✅ 属实 | `grep -n` |
| `as_render_object(canvas, stage)`(`:23304`) | ✅ 属实（`:23304` = `as_render_object(canvas, (DisplayObject*)st);`） | `sed -n '23304p'` |
| `present_frame`(`window_glue.cc:496`) | ✅ 属实 | `grep -n` |
| 内容指纹块 `emit.ts:21749-21766` | **⚠️ 缩为 `:21749-21764`**（`:21764` 是 `#define ASC_AUTO_BAKE_FRAMES 3`，`:21765` 起已是另一段注释） | `sed -n '21749-21769p'` |
| `as_bake_scale`(`:21795`) | **⚠️ 定义在 `:21797`**（`:21795` 还在上一段注释里） | `grep -n "static double as_bake_scale\b"` |
| `WinCtx.dirty`(`window_glue.cc:387`) | ✅ 属实（`int dirty;`） | `grep -n` |
| 只重绘 dirty 窗口 `:809-820` | ✅ 属实（`if (c->visible && c->dirty && c->on_redraw != NULL)…present_frame…; c->dirty = 0;`） | `sed -n '809-820p'` |
| 应用级帧时钟标脏所有可见窗口 `:775-800` | ✅ 属实（`:776`、`:796` 两处 `c->dirty = 1`） | `grep -n "c->dirty = 1" vendor/window_glue.cc` |
| `as_show_redraw_regions`(`src/runtime.ts:179-188`) | **⚠️ `:177-188`**（注释起于 `:177`，关键句 "this render walk has no AIR-style region list" 在 **`:178`**） | `sed -n '177-188p' src/runtime.ts` |
| `as_disp_target`(`:10046-10070`) | **⚠️ `:10043-10070`**，函数定义在 **`:10052`**；"目标自身 capture 监听器从不执行"的注释在 `:10045-10051` 与 `:10058-10065` | `sed -n '10040-10075p'` |
| `as_pick_hit_local` → `as_obj_region_hit_local`(`:15872`/`:15961`/`:16043`) | **⚠️ 三个数对应三个不同函数**：`as_pick_hit_local` 定义 **`:15998`**、`as_obj_region_hit_local` 定义 **`:16043`**、`as_obj_hit_local` 定义 **`:15961`**；`:15872`/`:15873` 是前置声明 | `grep -n "as_pick_hit_local\|as_obj_region_hit_local\|as_obj_hit_local"` |
| `as_tf_paragraph`(`:18493`) | ✅ 属实 | `grep -n "static void\* as_tf_paragraph(TextField\* tf) {"` |
| `TextField_get_textWidth`(`:18796`)→`as_skia_textlayout_max_width` / `TextField_get_textHeight`(`:18808`)→`as_skia_textlayout_height` | ✅ 两定义行都对；内部调用分别在 `:18805`/`:18828` | `grep -n "TextField_get_textWidth\|TextField_get_textHeight"` |
| `sk_text_measure`(`vendor/skia_text_glue.cc:308`) | ✅ 属实 | `grep -n "double sk_text_measure"` |
| `as_focus_obj`(`:10782`) | ✅ 属实（且 `gc_mark_ptr((void*)as_focus_obj)` 在 `:5686`，确为永久 GC 根） | `grep -n "as_focus_obj" src/emit.ts` |
| `as_set_focus`(`:10828`) | **⚠️ `:10827`** | `grep -n "static void as_set_focus(DisplayObject\* obj) {"` |
| `as_tab_scan`(`:10850`) | **⚠️ `:10860`** | `grep -n "static void as_tab_scan("` |
| `as_focus_tab`(`:10876`) | **⚠️ `:10881`** | `grep -n "static void as_focus_tab("` |
| Tab 硬上限 **64**（注释自述） | ✅ 属实；补位置：注释在 **`:10857`**（"64-object cap … beyond it Tab simply stops moving"），`tabs[64]` 与 `cap` 参数在 `:10884-10886` | `grep -n "64-object cap"`；`sed -n '10883-10886p'` |
| `tabIndex` 初始化为 `-1`(`:10548`) | ✅ 属实（`o->tabIndex = -1;`） | `grep -n "tabIndex" src/emit.ts` |
| `SDL_KEYDOWN`→`keyCode`(`window_glue.cc:1360`) | ✅ 属实（`case SDL_KEYDOWN:` 在 `:1360`） | `grep -n "SDL_KEYDOWN" vendor/window_glue.cc` |
| `TouchEvent` 类完整(`:11987-12018`，阶段九十三) | ✅ 属实（`:11987` 起注释、`:11996` ctor、`:12014-12018` new） | `grep -n "TouchEvent" src/emit.ts` |
| `Multitouch.maxTouchPoints` 恒 `0`(`:10333`) | ✅ 属实（`return 0.0`，注释直说"no backend here ever delivers a touch point"） | `grep -n "maxTouchPoints"` |
| `SDL_TEXTEDITING`/`SDL_TEXTINPUT`(`:1421`/`:1440`) | ✅ 属实 | `grep -n "SDL_TEXTEDITING\|SDL_TEXTINPUT" vendor/window_glue.cc` |
| `NativeWindow` 43 成员(`symbols.ts:1783-1891`) | ✅ 43 属实（**23 getter + 16 方法 + 4 静态常量**）；**⚠️ 行区间应到 `:1894`**（setter 表 `:1880-1894`；另有 11 个 setter 与 getter 同名成对） | `awk 'NR>=1788&&NR<=1894' src/symbols.ts` 数 getters(23)/methods(16)/staticFields(4)/setters(11) |

### B2. §§3 的结论性断言（用 grep 自验，未照抄）

| 原断言 | 核实结果 | 证据命令与输出 |
|---|---|---|
| 自动布局零命中：`grep -riE "flexbox\|yoga\|taffy\|layout_engine" src/*.ts` | ✅ 属实 | 该命令无输出、`grep` 退出码 **1** |
| actions/keymap 零命中 | ✅ 属实 | `grep -riE "keymap\|actionregistry\|key_context" src/*.ts` 无输出、退出码 **1** |
| 键盘只走 `SDL_KEYDOWN` → `keyCode` 直投；无 context/绑定表 | ✅ 属实（`vendor/window_glue.cc` 无 keymap/context 概念） | 见 B1 行；另 `vendor/window_glue.cc:941` 注释明说 SDL 无键盘布局查询 |
| 窗口后端不转发触摸：`grep FINGER\|TOUCH` 于 `window_glue.cc` 零命中 | ✅ 属实 | `grep -nE "FINGER\|TOUCH" vendor/window_glue.cc` 无输出、退出码 **1**（`SDL_FINGER*` 只出现在 `vendor/sdl2/.../SDL_events.h` 头文件里，未被后端使用） |
| `flash.accessibility` 整包缺失 | ✅ 属实 | `grep -rn "flash.accessibility\|AccessibilityProperties\|AccessibilityImplementation" src/*.ts` **零命中**；`grep -rin "accessibility" src/*.ts` 只命中 `src/emit.ts:26272`（讲可见性测试的 `ACCESSIBILITY` 标记） |
| 证据话术「除 `Sound`/`Keyboard.isAccessible` 等无关命中外」 | **❌ 不实**：`grep -rn "accessibility"`（大小写敏感）**零命中**；`Keyboard.isAccessible`(`emit.ts:14848`) 与 `SoundMixer.areSoundsInaccessible`(`:12981`) 的拼写里都没有 `accessibility`，不构成「命中」 | 同上 |
| 控件集：219 个 `examples/*.as` 中无 Button/Slider/List…；`lib/` 无 `.as` 库 | ✅ 属实 | `ls examples/*.as \| wc -l` = **219**；`find lib -name '*.as' \| wc -l` = **0**（lib 下只有 `asaot.h`/`asaot_host.c` + 预编译库） |
| 「另有 `textfield/`、`air-starling-demo/`、`shmup-stage3d/` 等 **8 个目录**」 | **❌ 不实：实为 12 个子目录** | `find examples -mindepth 1 -maxdepth 1 -type d \| sort` → `air-native, air-starling-demo, ane, ane-app, audio, embed-assets, fqn-static, shmup-stage3d, stage12, textfield, wasm-native, web`（12 个；其中 `air-starling-demo`/`embed-assets` 当前不含 `.as`） |
| 「与显示/交互/事件相关的示例 **39 个**顶层 `.as`」 | 🟡 无法客观复核（「相关」是人工归类）；顶层 `.as` 总数 219 属实，39 作为子集不算错，保留原值 | `ls examples/*.as \| wc -l` = 219 |
| GC 红线引文与先例（`as_disp_key` ~39 KB/s、阶段五十六） | ✅ 与 AGENTS.md / TODO.md / gc.md 一字不差 | `.talkmed-agentpilot/AGENTS.md:133`「禁止在每帧/每循环的热路径里产生进 arena 的临时分配」、`:135`「像 `as_disp_key` 那样造成 ~39 KB/s 的静默泄漏（阶段五十六）」；`TODO.md:1238` 实测「~39 KB/s」、`:1236`「阶段五十六」；`docs/zh-cn/gc.md:12` 同 |
| GC-4 增量「单帧停顿 O(budget) 而非 O(堆)」 | ✅ 属实 | `AGENTS.md:126`；`docs/zh-cn/gc.md:321`/`:495`；gc.md §6（`:310`「增量标记完整设计」） |

---

## C. 交叉引用与 §6/§7 的核实

| 原断言 | 核实结果 | 证据 |
|---|---|---|
| `rust-text-backend.md`「**§3**（文本 glue 的 15 函数不透明接缝）」 | **❌ 节错**：15 函数接缝在 **§1.1**（`### 1.1 接缝就只有 15 个函数`，`docs/zh-cn/rust-text-backend.md:60`）；§3 是「第二步的账」的体积表 | `grep -n "15 个" docs/zh-cn/rust-text-backend.md`；`grep -n "^## \|^### "` |
| `rust-text-backend.md`「**§1** 第 ② 刀」（`-Wl,-dead_strip`） | **❌ 节错**：② 刀写在 **§0 摘要**（`:8-12`）与 **§3.1（L1）**；§1 是「现状：文本管线是四层」 | `sed -n '8-12p' docs/zh-cn/rust-text-backend.md` |
| `rust-text-backend.md` §9「已经算过换引擎的账」 | ✅ 属实（§9 = 劣势与代价清单（逐条）） | `grep -n "^## 9"` |
| 19.43 MB → 6.05 MB | ✅ 属实 | `docs/zh-cn/rust-text-backend.md:10-12`（①②③ 三步） |
| `skia.md` §8 = 文本渲染两档方案 | ✅ 属实 | `grep -n "^## 8" docs/zh-cn/skia.md` → `:642` |
| §7「写本文时 `TODO.md` 末尾为**阶段二百三十一**，另有更高编号在途」 | **⚠️ 前半属实、后半不实**：`TODO.md` 最后一个 `### 阶段` 确为**阶段二百三十一**（`:13774`，`v0.4.202 → v0.4.203`）；但 `阶段二百三十二` 及以上在 `TODO.md` 里**零命中**，「更高编号在途」不成立 | `grep -n "^### 阶段" TODO.md \| tail`；`grep -noE "阶段二百三十[二三四五六七八九]\|阶段二百四十" TODO.md` 无输出 |
| §7/§9「`TODO.md` 末尾有「UI 工具链待定项（未排期）」段」 | ✅ **确实存在** | `grep -n "UI 工具链待定项" TODO.md` → `:14086`（在 `### 增强待做` `:14060` 之后、`备注` 之前） |
| 该段内容与文档是否一致 | 🟡 大体一致，但**它自己抄了修正前的旧值**：TODO.md `:14090` 仍写 `as_tab_scan`（`src/emit.ts:10850`）、`:14089` 仍写 `grep -rn "accessibility"` 除 `Sound`/`Keyboard.isAccessible` 外零结果。**`as3compiler/TODO.md` 只读，本次不改**；两份可行性文档已按实测值修正并在 §9/§10 注明 | `sed -n '14086,14099p' TODO.md` |

---

## D. 本次修改的文件

1. `asaotui/ui-toolkit-feasibility.md`（就地改，保持中文 `§` 分节 / 表格 / `文件:行` 风格）
2. `asaotui/ui-toolkit-feasibility-en.md`（英文镜像，同步全部修正；结构与中文一一对应）
3. `asaotui/reviews/doc-verify-2026-10-22.md`（本文件）

**顺带修的结构问题**：中文版 §3 表格在 `IME/合成输入` 与 `窗口能力面` 两行之间原本有一个空行，
把一张表切成了两段（英文版无此问题）；已删除该空行。另在中/英 §4 表前各加一行路径约定说明
（`style.rs:NNN` 等短引用的全路径为 `gpui-src/crates/gpui/src/<file>`）。

**未改动**：`as3compiler/` 下任何文件（含 `TODO.md`）；`asaotui/gpui-src/`。
