# 调参 · 按卡重拟合 int8 档起点（**自改配方**，老卡 / 中低端卡优先）

> **这份是给谁用的**：**你的卡原生 int8 张量核很强，但 prefill 偏慢**的场景（30 系、中低端 Ada、以及一切"只有 int8 加速"的老卡）。
> **一句话**：三元线性层按 `T`（该层看到的 token 数）选内核档，**int8 档的起点阈值写死在源码里 = 33**；
> 这个值**不是普适最优**，它是**卡的属性**。改它需要**自己重编一次引擎**——好在源码树与编译 SOP 都在包内。

---

## 0. 先判断"你该不该动它"

| 你的情况 | 结论 |
|---|---|
| 卡是 **30 系（sm_86）** 或中低端 Ada（SM 数少） | **值得试**（int8 张量核有，但 SM 少 ⇒ s8 可能更早赢） |
| 卡是 40/50 系大卡（SM 多） | 大概率**保持 33**（我们实测就是） |
| 卡是 **10/16 系（无张量核）** | **别动这份**，那条路是 SIMT/GEMV，与本配方无关 |
| 你的瓶颈是 **decode** 而不是 prefill | **别动**：这个阈值只影响 prefill（decode 的 T=1..8 走小批档） |

---

## 1. 机理（为什么有这个阈值，为什么"卡不同"）

三元线性层的档位（同一个权重，按这次调用看到的 T 选）：

| T | 走哪档 |
|---|---|
| 1 | 小批 tensor-core（decode） |
| 2..8 | 小批 tensor-core（**投机验证轮**） |
| 9..16 | 小批（8 宽 tile；**每 8 个 token 重入一次**） |
| **17..32** | **同一档继续重入**（`ceil(T/8)` 遍）←**交叉区** |
| **≥33（写死的默认）** | **int8 档**：激活 absmax 量化成 int8 × int8 张量核 |

**为什么"卡不同"**：int8 档是 **grid-heavy** 内核（`gridX = div_up(N,64)`，本模型 `gate_up` 就有 544 个 CTA），
而小批档是**延迟受限**的。⇒ **SM 越少的卡，int8 档越早开始赢。**

**两条实测（都来自真机，不是估算）**：

- **我们这张卡**（SM 多的 Ada）：交叉点在 **T≈32~40** ⇒ 默认 33 基本就是最优（见 §2 的表）。
- **社区一张 66 SM 的 Ada 卡**（RTX 4070 Ti SUPER）：交叉点在 **T≈17** ⇒ 那边把阈值降到 17 是**正收益**。

**结论：这个数不能跨卡抄，只能自己在自己卡上量。**

---

## 2. 我们卡上的证据（供你对照：322 个真实张量加权，ms/forward，越小越快）

| T | 小批档 | int8 档 | int8 相对 |
|---|---:|---:|---|
| 9 | 993 | 2,085 | **+110%（更慢）** |
| 11 | 963 | 2,158 | +124% |
| 16 | 1,020 | 2,120 | +108% |
| **24** | 1,456 | 1,966 | **+35%（更慢）** |
| **32** | 1,995 | 2,117 | **+6%（更慢）** |
| **40** | 2,498 | 2,166 | **−13%（更快）** ✓ |

⇒ 在我们这张卡上把阈值降到 17 是**倒退**（T=17..31 会慢 6~35%），所以我们**默认留在 33**。
**你的卡如果 SM 比我们少、int8 相对更强，这张表会整体下移**——这就是你要量的东西。

---

## 3. 改成"可调"需要改哪三处（精确 diff）

> 量阈值**必须先做成 env 可切**（同二进制 A/B），否则每试一个值都要重编。
> 源码在包内：`src-tree\ninfer-4090w-ternary\`；编译步骤见 `docs\构建与ABI校验-SOP.md`。

**① `src\ops\linear\ternary\ternary_s8_scratch.h`** —— 加"分配阈值"和一个 env 读取函数：

```cpp
// 策略阈值（原有，保持不变）
inline constexpr int kTernaryS8MinTokens = 33;

// ★ 新增：从哪个 T 起"申请"int8 档要用的临时缓冲。
//   必须与策略阈值拆开！两者绑在一起时，把策略阈值降下去但缓冲仍按老阈值分配，
//   分支会【静默落回慢档】——不报错、不崩、读数正好等于基线臂（这是前人踩过的坑）。
inline constexpr int kTernaryS8ScratchMinTokens = 9;

// ★ 新增：策略阈值的 A/B 旋钮
[[nodiscard]] inline int ternary_s8_min_tokens() {
    static const int threshold = [] {
        const char* value = std::getenv("NINFER_TERNARY_S8_MIN_TOKENS");
        if (value == nullptr) { return kTernaryS8MinTokens; }
        const int parsed = std::atoi(value);
        return parsed > 0 ? parsed : kTernaryS8MinTokens;
    }();
    return threshold;
}
```

**② `src\ops\linear\ternary\ternary_dispatch.cpp`** —— 分配缓冲时用**新**那个常量：

```diff
 TernaryS8Scratch allocate_ternary_s8_scratch(WorkspaceArena& workspace, std::int32_t k,
                                              std::int32_t tokens) {
     TernaryS8Scratch scratch{};
-    if (tokens < kTernaryS8MinTokens) {
+    if (tokens < kTernaryS8ScratchMinTokens) {
         return scratch;
     }
```

**③ `src\ops\linear\ternary\ternary_rowsplit_gemm.cu`** —— int8 那一支的判定改用函数：

```diff
         (w.qtype == QType::PQ2_0_G128 || ptq1_repack_admits(w)) &&
-        mma_wide_admits(w, out_row_stride) && x.ne[1] >= kTernaryS8MinTokens) {
+        mma_wide_admits(w, out_row_stride) && x.ne[1] >= ternary_s8_min_tokens()) {
         note_rung("s8");
```

**④ 改完 `.h` 之后必做**（本树 MSVC 的头依赖扫描是坏的，不做会"no work to do"然后链接期报未解析符号）：

```powershell
powershell -NoProfile -File <包内>\tools\touch-dependents.ps1 -Header <你改的.h> -Root <tree>\src
```
然后重编，并**核对二进制时间戳**（"编译成功"和"编译了"是两件事）。

---

## 4. 怎么验（三层，缺一不可）

**① 结构层——先证"档真的换了"**（最容易被跳过、也最容易骗人）

```powershell
$env:NINFER_TERNARY_S8_DEBUG = '1'
$env:NINFER_TERNARY_S8_DEBUG_BUDGET = '30000'   # 默认 24，会被 CUDA 图捕获期调用吃光
$env:NINFER_TERNARY_S8_DEBUG_MIN_T = '9'        # 只看 T>=9，滤掉捕获期的 T<=8
# 起服 → 发几个不同长度的提示词 → 在 stderr 里看探针打的 rung=
```
**判据**：T=20/24/32 应从 `rung=small_t` 变成 `rung=s8`。
⚠️ **"两个本该不同的臂给出同一个数" ⇒ 先怀疑臂没跑**（探针没打印、env 没继承、缓冲没分配，三者都会造成这个假象）。
⚠️ **env 是进程级只读一次**（它决定哪颗内核进 CUDA 图）⇒ 换值必须**重启进程**。

**② 时间层——同二进制、只用 env 切**

```powershell
# 两臂交替跑（不要先跑完 A 再跑 B：GPU 温度漂移会整段记到 B 头上）
# 每次请求换一个随机 nonce，否则命中前缀复用 ⇒ 根本没发生 prefill
```
- 值就扫这档：**17 / 24 / 33**（再往上意义不大）。
- **看绝对时间，不要看 `prefill t/s` 的比值**：短提示的 t/s 被固定开销淹没（T=35 时"154 t/s"听着吓人，整趟其实只有 0.23 s）。
- **丢掉开头 1~2 次**（刚起服/刚重编时 GPU 时钟还在爬升，实测能差 10%+）。
- 取**中位数**，不要取最好值。

**③ 数值层——这一步不能省（int8 档会改数值）**

- int8 档把**激活**量化成 int8，**PPL 一定会动**，量级应该在 **+0.0015% ~ +0.05%**（≈ int8 激活量化误差本身）。
- ⚠️ **标准 PPL 口径（`--context 512`）的 T=508 根本不覆盖 T=9..31**，你改的正是那一段 ——
  所以要**另跑一次小 context**：`--context 32 --stride 16`（同一份 `ninfer-perplexity.exe`）。
- 再用 20 题（或你自己的题集）确认**不退化**；判据：不低于改动前的题数。
- 对照臂：`NINFER_TERNARY_S8=0`（**完全关掉** int8 档）——如果它与"阈值调到 17"读数一样，说明 int8 档压根没被走到。

---

## 5. 回退

| 想做什么 | 怎么做 |
|---|---|
| 完全关掉 int8 档（回到纯 bf16） | `set NINFER_TERNARY_S8=0`（不用重编） |
| 回到默认阈值 | 不设 `NINFER_TERNARY_S8_MIN_TOKENS`，或设成 `33` |
| 扔掉这次改动 | 源码回退到包内 `src-tree` 的原样，重编 |

---

## 6. 老卡额外注意事项

- **30 系（sm_86）**：**没有 FP8**（`mma with FP8 ... requires sm_89+`，编译期就会失败）⇒ KV 只能用 `bf16`/`int8`；
  但 **int8 张量核是有的** ⇒ **本配方对你很可能有正收益**，值得量。
- **50 系（sm_120）**：int8 有；另外多了 `nvfp4`/`k8v4` 两个 KV 档（更省显存，但对速度帮助有限）。
- **10/16 系**：无张量核，走 SIMT/GEMV ⇒ 本配方**无收益**。
- 不管哪张卡：**先量结构层（探针），再量时间层**。跳过结构层是本项目最贵的一课。

---

## 7. 我们为什么把默认留在 33（如实交代）

我们完整按上面的流程做过一遍（含探针、同二进制 A/B 的设计、以及 §2 那张 322 张量加权表），
结论是：**在我们这张卡上降到 17 是倒退**，所以**默认保持 33**，只把"做成可调"这件事留下。
**这不代表你的卡也该是 33** —— 交叉点是卡的属性，请你按 §4 自己量一遍；量完如果 17 更快，
就把默认值**改回 17** 并记住：**你的卡上它才是对的。**
