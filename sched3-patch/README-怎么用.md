# sched3-patch · 三条调度的**完整文件**（不是 diff）+ 判据

> **这份补丁给的是 A 类三条调度的「实现」，值要靠你自己扫**（见 `MUST-DO.md` / `agent\must-do.json` 的 **F1**）。
> **本目录不动 `engine\`**：它只提供"给用户自己编"的源码文件。
> **收益只有 A3 一条**（我们卡 prefill +31.1%）；**A1 零收益、A2 负收益** —— 详见 §4，别把三条当成三个收益。

---

## 1. 这里面是什么

| 位置 | 内容 |
|---|---|
| `files\ternary_rowsplit_mma_small_t.cuh` | **A1**（小批档行块按 n 分桶）+ **A2**（K 分片门）**+** A3 的 small_t 侧入口 |
| `files\ternary_rowsplit_gemm.cu` | **A3**（token 铺进 `blockIdx.y`）的 host 侧布网格 + 三条调度的 env 读取 |
| `files\ternary_rowsplit_mma_wide_t.cuh` | **A3** 的 wide_t 侧（宽档也吃 token 维） |
| `files\ternary_rowsplit_mma_s8.cuh` | **A3** 的 s8 侧（int8 张量核档） |
| `diff\ternary_rowsplit_gemm.cu.diff` | 相对**上游 `src-tree` 原文件**的 diff（`---` 是原文件、`+++` 是 `files\`）。本包若自带 `src-tree` 就是包内那份；不带 `src-tree` 的档用的是同一份上游内容（标签里写明） |
| `diff\ternary_rowsplit_mma_{small_t,wide_t,s8}*.diff` | 相对**我们源码快照**的 diff（这三个文件的快照与包内**逐字节相同**，所以 diff 直接可读） |
| `README-怎么用.md` | 本文件 |

> **为什么给完整文件而不是 diff**：包内 `src-tree` 与我们的开发树**不同源**，diff 未必能干净套上（行号/上下文可能对不上）。完整文件更稳：**直接替换**。

### ★ 2026-09-27 修正（必读，改的正是"编不过"这一条）

`files\ternary_rowsplit_gemm.cu` 的**上一版有两行调用了 `ternary_s8_min_tokens()`** —— 那是我们**另一条源码线**的函数（「int8 档起点 env 化」补丁引入），**包内 `src-tree` 里没有它** ⇒ 按 §2 直接替换后**根本编不过**。

我们原样复现并留证（包内树 + 上一版补丁，同一个 TU，同一个编译命令行）：

```
src\ops\linear\ternary\ternary_rowsplit_gemm.cu(577): error: identifier "ternary_s8_min_tokens" is undefined
src\ops\linear\ternary\ternary_rowsplit_gemm.cu(597): error: identifier "ternary_s8_min_tokens" is undefined
```

**现已改回包内常量 `kTernaryS8MinTokens`（＝33，与出厂引擎行为一致）**，并用**包内树原样编译通过**（同一 TU、同一命令行：`[PASS] compiled cleanly`）。
这是**唯一**一处跨源码线依赖；其余三个文件只依赖包内已有头文件。

> 若你另外按 `docs\` 的说明打了「int8 档起点 env 化」补丁（加 `ternary_s8_min_tokens()`），
> 请把这**两行**（`files\ternary_rowsplit_gemm.cu` 的调试打印行 + s8 档准入行）重新换回 `ternary_s8_min_tokens()`，
> 否则 `NINFER_TERNARY_S8_MIN_TOKENS` 对这个 TU 不起作用。

**替换前自己再比一次 sha**（4 个文件应该**都与包内不同**，因为都改了）：

```powershell
$pkg = ".\src-tree\ninfer-4090w-ternary\src\ops\linear\ternary"
foreach ($f in @('ternary_rowsplit_mma_small_t.cuh','ternary_rowsplit_gemm.cu','ternary_rowsplit_mma_wide_t.cuh','ternary_rowsplit_mma_s8.cuh')) {
  $a = (Get-FileHash "$pkg\$f" -Algorithm SHA256).Hash
  $b = (Get-FileHash ".\sched3-patch\files\$f" -Algorithm SHA256).Hash
  '{0}  pkg={1}  patch={2}  differ={3}' -f $f, $a.Substring(0,12), $b.Substring(0,12), ($a -ne $b)
}
```

---

## 2. 怎么用（四步）

1. **备份**包内那 4 个文件（复制到别处，别原地改）。
2. **替换**：把 `files\` 里的 4 个文件覆盖到
   `src-tree\ninfer-4090w-ternary\src\ops\linear\ternary\` 同名文件上。
   > `超低显存档` 走 llama.cpp 线，**本补丁对它不适用**（它的 `src-tree` 是 `llama-kvmem`）；那一档请用 `pr-ptq1-mmv` 那条。
3. **用你自己的 SM 数重编**（`gpu-probe.exe` 读 SM；断言宏真的进了编译行）：
   ```
   cmake -B build-89 -S src-tree\ninfer-4090w-ternary -G Ninja -DCMAKE_BUILD_TYPE=Release ^
     -DCMAKE_CUDA_ARCHITECTURES=89 -DNINFER_CUDA_ARCH=89 ^
     -DNINFER_SM_COUNT=<gpu-probe 读出的 SM> -DNINFER_TIER=ada
   cmake --build build-89 --config Release -j 8
   findstr /c:"NINFER_SM_COUNT=<你的SM>" build-89\build.ninja
   ```
   （50 系：`-DCMAKE_CUDA_ARCHITECTURES=120a -DNINFER_CUDA_ARCH=120a -DNINFER_TIER=blackwell`。
   **`-j 8` 不要 `-j 24`**：24 路会杀掉 `cl.exe` 且不打印错误，伪装成源码错误。）
   > **编不过先别看源码**：把 `ninfer-serve` 与 `ninfer-perplexity` **同一批重建** —— 只重链 serve 会留下旧 perplexity，
   > 拿旧件复核会让你误判"改了没用"。数值门必须同批两个目标。
4. **用三个 env 扫值**（**同一个二进制**，不用再编）：

| env | 管什么 | 取值 | 默认 | 备注 |
|---|---|---|---|---|
| `NINFER_TERNARY_TOKEN_GRID` | **A3** token 进 `grid.y` | `1` \| `0`（0 = 恢复串行走，**这就是 A/B 的对照臂**） | **开** | **唯一真正有收益的一条**（prefill +31.1%） |
| `NINFER_TERNARY_SMALL_T_ROWS` | **A1** 行块 | `auto` \| `16` \| `32` | `auto`（＝16 行档） | **32 行宽档默认已关**，见下 |
| `NINFER_TERNARY_KSPLIT` | **A2** K 分片门 | `1` \| `0`（门的形状条件：`T ≤ 8`、`n ≤ 6144`、每片剩 ≥4 个 K 步） | **关**（`0`） | 开了会**动数值且变慢**，见 §4 |

> ⚠️ **`NINFER_TERNARY_SMALL_T_ROWS=32` 是"复现开关"，不是调优旋钮**：宽档（32 行/warp）在我们卡上
> **没有任何格式同时"编得出 + 算得对"** —— PQ2 静态 shared 需要 57,600 B > 48 KB（nvlink 编译期拒绝 `0xe100 > 0xc000`），
> PTQ1 编得出但**算错**（PPL 121.16 → 674,249，根因未定位，源码里 `kTernaryMmaWideArmEnabled=false` 默认关）。
> 保持默认即可；想重复我们的否证，才去强制打开。
>
> 三个 env 都必须在**起服前**设好 —— 它们在 CUDA graph capture 时被读死。

---

## 3. ★ 判据（照这个走，别跳步）

**① A1 / A3 必须逐位相同**（它们只改调度，不该动数值）
- `--context 512 --stride 256` 与 `--context 32 --stride 16` 两种口径的 **PPL 数字必须完全相等**；
- **贪心输出 sha 必须完全相同**（同 prompt、`--greedy`、丢第一次）。
- 不成立 ⇒ 说明改错了地方，**回退**，不要继续测速度。

**② 过了数值门再看速度**
- **真交替**（on/off/on/off 或 auto/16/32 交错）、**丢第一轮**、**3 次取中位数**；
- **prefill 与 decode 分别报**（A3 主要吃 prefill；A1 主要吃 decode）；
- 报数带**内容类型 + 接受率 + 引擎 sha256**（否则读数不可比、不可复核）。

**③ A2 是唯一"非逐位相同"的**
- 它引入 1 次 reduce，**必须过 PPL 双口径 + 20 题**才谈收益；
- 门开太大（对所有填不满的形状都切）会由正收益变负收益。

**④ 提升不显著（<1%）就保持出厂默认**
- 不许把 0.x% 写进结论当成果 —— 那是噪声。

---

## 4. 我们卡上的实测（**已定稿**）

**`measured(ours, 4080S)`** —— RTX 4080 SUPER（`gpu-probe.exe` 实测 **80 SM**）。
同二进制、真交替（on/off 交错）、丢首轮、3 次取中位数：

| 臂 | decode t/s | prefill t/s | 接受率 | 贪心 sha |
|---|---|---|---|---|
| base（出厂默认口径） | 89.77 | 1,982.74 | 60.6% | 参照 |
| grid_off（A3 关） | 90.26 | 1,993.91 | 60.56% | 相同 ✅ |
| **sched3（默认，A3 开）** | **91.29** | **2,599.58** | 60.56% | **相同** ✅ |
| rows16 | 91.58 | 2,604.63 | 60.56% | 相同 ✅ |
| rows32（**强制**宽档） | 34.29 | 2,557.36 | **0.0%** | **不同** ❌ 模型退化（只出 4~10 token） |
| ksplit（A2 开） | 86.85 | 2,564.15 | **59.18%** | **不同**（每轮都变）❌ |

| 项 | 结论 |
|---|---|
| **A3**（token → `grid.y`） | **有效、逐位相同**：prefill **1,982.7 → 2,599.6 t/s（+31.1%）**、decode +1.7%（噪声内）⇒ **保留开启** |
| **A1**（行块分桶） | **零收益**：16 行档逐位正确但等于改前状态；32 行宽档对 PTQ1 算错、对 PQ2 编不出 ⇒ 默认关 |
| **A2**（K 分片门） | **负收益**：decode 86.9 低于同二进制默认臂 90.1、接受率 60.6%→59.2%、sha 每轮都变 ⇒ 默认关，**不建议开** |

数值门：PTQ1 与 PQ2 **两个格式 × 三个口径（8/4、32/16、512/256）的 PPL 与参照引擎逐位相等**
（121.157720 / 26.049634 / 6.448742），贪心 sha 四轮全同 ⇒ A3"逐位相同"是**实测**，不是论证。

⚠️ **别的卡上这些数字不适用** —— 桶的边界与门阈值是"每 SM 可用带宽 × 占用率 × SM 数"的函数。
**请用 §2 的 env 在你自己卡上重扫**（F1 就是这条要求）。如果扫出来提升 <1%，**保持出厂默认**并把这个结果回给我们。

---

## 5. 回执（我们需要的三样）

`矛盾点（或你的读数）` + `实测证据：命令 + 读数 + 引擎 sha256` + `你的结论`。
我们据此改文档与默认值，并**署名来源**。顺序是 **证否优先 → 实测裁决 → 回执沉淀**。
