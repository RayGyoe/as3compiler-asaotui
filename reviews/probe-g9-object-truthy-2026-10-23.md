# 实测：`Boolean(x)` 在 `x` 声明为 `Object` 时把箱装 `false` 读成 `true`（G9）

日期：2026-10-23　工作区：`asaotui/`　编译器仓库：**零改动**

## 0 起因

`probes/widgets/form/`（表单控件组：radio / switch / slider / progress）的探针报出 3 处失败：

```
FAIL  program verdict: FAIL DIAG r2.checked=TRUE; radio binding not written: false; switch binding not written: false;
FAIL  pixel (18,56)  want #FFFFFF got #2563eb
FAIL  pixel (38,124) want #D1D5DB got #ffffff
```

三处**同一根因**，只是表现不同：

- `r2` 是绑定到 `model.radioSel = false` 的 radio，却被画成**选中**（圆形指示器内部被实心点填成蓝
  `#2563EB`，正好盖住 `(18,56)` 这个「圆心」采样点）；
- `s2` 是绑定到 `model.switchOn = false` 的开关，却被画成**打开**（白色旋钮右移到 `local x=26`，
  正好盖住 `(38,124)` 这个「关闭态轨道」采样点）。

⇒ 两个控件都把**模型的 `false` 读成了 `true`**。

## 1 不猜症结，先量语言行为

候选机制有两条，后果完全不同，所以先分清：

- (a) **kit 的错**——`radio()` 工厂里 `Boolean(opts.selected)` 把没被 `is Binding` 认出的 Binding 对象
  当成真值（对象非空）；
- (b) **编译器的错**——`Binding.get():*` 的值在进入 `Object` 声明的局部量时丢了语义。

`probes/bind-truthy/BindProbe.as` 逐项打印，结论是 **(b)**，而且是 (b) 里非常窄的一种。

## 2 结论：真值矩阵（**全部实测，非推测**）

`Binding.get()` 读一个值为 **`false`** 的 `Boolean` 字段：

| 写法 | 实测结果 | 应为 | 判定 |
|---|---|---|---|
| `var s:Object = b.get(); Boolean(s)` | **`true`** | `false` | ✘ **错** |
| `var s:Object = b.get(); String(s)` | `"false"` | `"false"` | ✔ |
| `var s:Object = b.get(); s == null` | `false` | `false` | ✔ |
| `var s:Object = b.get(); s is Boolean` | `true` | `true` | ✔ |
| `var t:* = b.get(); Boolean(t)` | `false` | `false` | ✔ |
| `var q:Boolean = b.get(); q` | `false` | `false` | ✔ |
| `var q:Object = b.get(); if (q)` | `false`（不进分支） | 不进 | ✔ |

影响半径（每一格的值都是 `false`，正确答案每行都应是 `false`）：

| 写法 | 实测 | | 写法 | 实测 |
|---|---|---|---|---|
| `Boolean(m.flagFalse)` 类型化字段 | `false` ✔ | | `Boolean(arr[0])` 数组元素 | `false` ✔ |
| `Boolean(m["flagFalse"])` 类型化下标 | `false` ✔ | | `Boolean(vt)` 数组元素经 `*` | `false` ✔ |
| `Boolean(dyn.flagFalse)` `Object` 接收者 | `false` ✔ | | `Boolean(num)` `Number 0` | `false` ✔ |
| `Boolean(dynStar.flagFalse)` `*` 接收者 | `false` ✔ | | `Boolean(str)` 空 `String` | `false` ✔ |
| `Boolean(lit.flag)` 对象字面量 | `false` ✔ | | `Boolean(opts2.visible)` 选项包 | `false` ✔ |
| `Boolean(lit["flag"])` 字面量下标 | `false` ✔ | | `if (opts2.tabEnabled)` | 不进 ✔ |
| `Boolean(litStar.flag)` 字面量经 `*` | `false` ✔ | | `if (tf)`（`*` 副本） | 不进 ✔ |

⇒ **作者侧的每一种拼写都是对的**。唯一出错的是「把局部量**静态声明成 `Object`**，再对它用
`Boolean()`」。这也修正了 `compiler-gaps.md` §3 里「`Boolean(obj.prop)` 动态属性读」那条**过宽**的正面结论。

## 3 根因：生成 C 逐行实读

`Boolean(sS)` 那一行降级为：

```c
static Object* g_sS = NULL;                                   // `:Object` 的局部量是裸指针
g_sS = ((Object*)as_value_to_obj(....get(...)));              // 箱装标量被包成 Object* 包装体
...
bool _once381 = (g_sS != NULL);                               // ← Boolean(Object*) 退化成指针测试
say("Object-typed: Boolean(v)", as_v_bool(_once381));
```

对照同一段里的其他三路（**全部正确**）：

```c
bool _once383 = as_v_is_bool_obj((void*)(g_sS))               // s is Boolean
             || (as_is_number_obj((void*)(g_sS)) && as_number_obj_val((void*)(g_sS)) != 0.0);
...
say("Object-typed: == null", as_v_bool(as_v_loose_eq(as_obj_to_value((void*)(g_sS)), as_v_null())));
char* _once382 = as_obj_to_str(g_sS);                         // String(sS) -> "false"

static as_value g_sA = (as_value){0, 0.0, NULL};              // `*` 的局部量是带标签的 as_value
bool _once384 = as_v_truthy(g_sA);                            // Boolean(*) -> 正确
static bool g_sB = false;                                     // Boolean 的局部量
say("Boolean-typed (coerced)", as_v_bool(g_sB));              // 正确
```

**运行时本来就会拆箱**（`as_is_bool_obj` / `as_obj_to_str` / `as_v_loose_eq` 都在拆），
只有 `Boolean()` 这一路走了 `!= NULL` 的捷径。所以这不是「缺能力」，是**降级不一致**：

- `Object` 槽持有箱装标量在 AS3 里是**常规状态**（`Number`/`Boolean`/`String` 都可以是 `Object` 值）；
- `Boolean()` 是 AS3 定义的真值转换 ⇒ 此处应与 `as_v_truthy` 同口径。

按 `AGENTS.md` §1.5 硬判据：`adl` 能跑对、我们跑不出 ⇒ **遗留欠账**（不是平台边界，不是增强）。

## 4 对 UI 库的影响与处理

kit 的绑定路径恰好就是这个形状（`*.get()` → 声明成 `Object` → `Boolean()`）。全仓扫描后共 **6 处**：

| 文件 | 备注 |
|---|---|
| `kit/asaot/ui/radio.as` | 构造期读绑定（被每帧 `payload` 覆盖，非活路径——**变异 A 证明了这点**） |
| `kit/asaot/ui/toggle.as` | 同上 |
| `kit/asaot/ui/checkbox.as` | **既有隐患**，早于本轮 |
| `kit/asaot/ui/kind/RadioWidget.as` | **活路径**（变异 B 命中） |
| `kit/asaot/ui/kind/SwitchWidget.as` | 活路径 |
| `kit/asaot/ui/kind/CheckboxWidget.as` | **既有隐患**，且同样是活路径 |

6 处一律改为 `var x:* = ....get();` + 就地注释指向 G9。

**为什么 checkbox 的 bug 一直没暴露**：`CheckboxWidget` 既有实现的绑定回写路径是有的，但**从没有过
「绑定到一个值为 `false` 的字段」的用例**——`true` 的情形下 `(ptr != NULL)` 恰好给出正确答案。
这正是「测试用例的取值决定缺陷是否可见」的典型。

保留 `Object` 声明的 4 处（`kind/InputWidget.as`、`kind/SliderWidget.as`、`slider.as`、`textField.as`）
**是有意的**：它们只用 `== null` / `String()` / `Number()`，这三路实测全部正确。

## 5 变异证据（检查器必须有牙）

| # | 变异 | 结果 |
|---|---|---|
| A | `radio.as`：`var s:*` → `var s:Object` | **仍 PASS** ⇒ 该处非活路径（发现，非失败） |
| B | `kind/RadioWidget.as`：`var bv:*` → `var bv:Object` | `PROBE_EXIT=1`，`41 checks, 2 failures`，消息**点名 G9**：`FAIL r2.checked is true but the model says false (G9: boxed false read as truthy); radio binding not written: false;` + `FAIL pixel (18,56) want #FFFFFF got #2563eb` |
| C | `kind/ProgressWidget.as`：填充色 `0x2563EB` → `0x2563EC` | `PROBE_EXIT=1`，单像素命中：`FAIL pixel (110,262) want #2563EB got #2563ec` |
| E | 静态钉子：重引入 B 的写法 | `tools/find-bound-truthy.cjs` 报 `G9-RISK kit/asaot/ui/kind/RadioWidget.as:62` 并 **`SCAN_EXIT=1`**；还原后 `0 risky use(s)`、`SCAN_EXIT=0` |

变异 B 的价值在于它**同时**命中语义轴与视觉轴，且断言消息直接写出成因——将来复现时不用再走一遍本
文档的推理。

## 6 复现

```bash
cd asaotui && node tools/gates.cjs          # 7/7 PASS，含 gap 扫描
node tools/find-bound-truthy.cjs kit seam   # 静态钉子，0 risky use(s)
```

真值矩阵原始输出：[`reviews/bind-truthy.txt`](bind-truthy.txt)（`BindProbe` 自己写的文件；
AOT stdout 另存 [`reviews/bind-truthy-run.txt`](bind-truthy-run.txt)）。

## 7 没做 / 边界

- **未修改 `as3compiler/` 任何文件**（工作区承诺）。G9 只登记、不修。
- 本扫描是**行级**的，不是解析器；把变量名当文件作用域（**过近似**）⇒ 只会多报，不会漏报。
  这条局限写在脚本头部，不藏。
- 未测 `Boolean()` 作用在**其他**箱装来源（如 `Dictionary` 取值、`Vector` 元素）上的行为；
  已测的 17 格覆盖了作者侧所有常见拼写。