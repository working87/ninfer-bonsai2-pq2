<#
gen-skeleton-extra.ps1 —— 在 gen-skeleton.ps1 之后运行，补三件契约件：

  * 03 页补「三档线 + 时间盒」（C3）
  * 08 页补「授权前置条件 + 路线尝试台账」（C5）
  * 新增 10 页（可选挂载第 4 包 Swift 档，仅 ninfer 档）与 11 页（按卡差异速查）
  * 写 agent\governance.json（C4 分权表：blocking / timebox_min / fallback，与 must-do.json 的 id 对应）

仍然遵守：全相对引用、不覆盖既有其它文件、可重跑。
用法：powershell -NoProfile -ExecutionPolicy Bypass -File gen-skeleton-extra.ps1 -Root <包根> -Tier <档名>
#>
[CmdletBinding()]
param([string]$Root = '', [string]$Tier = '')
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not $Tier) { $Tier = Split-Path $Root -Leaf }
$enc = New-Object Text.UTF8Encoding($false)

# ---- 03 页：三档线 + 时间盒 ----
$p03 = @"
# 03 · 基础部署后的调优方案（$Tier）

> **薄索引页**：本页只做路由与判据 —— 参数**真值**在包内 ``docs\`` 那本参数对照表 / 扫参手册里。

## 这一槽是干什么的
部署完成后**再榨性能**：按「**路径 × 预期收益 × 成本 × 排序**」给你清单，按卡与内容类型分支，并写明"什么情况下别做"。

## 每条性能项的**三档线**（照这个记，别自己造）
| 档 | 定义 | 你要做什么 |
|---|---|---|
| **达标** | ≥ 按带宽比折算的预期（``预期 ≈ 353.8 × 你的带宽 ÷ 736 GB/s``；decode 是带宽绑） | 记下来，继续下一条 |
| **可用** | ≥ 折算值的 **70%**（prefill 用 60%） | 记下来，标"可用"，**继续** |
| **不接受** | 低于可用线，或抖动/报错/退化 | **登记 SKIP**，继续；**这不是部署失败** |

## 时间盒（防"卡在一个参数上过不去"）
- 每条性能项给自己 **30 分钟或 3 次交替实验**（先到为准）。
- 到点就登记 SKIP：**读数 + 已试步骤 + 为什么停**，然后**往下走** —— 后续步骤不许被它阻塞。
- **只有可行性失败**（起不来 / 数值崩 / 显存炸）才允许真的停下。

## 排序原则
**收益 ÷ 成本**：``0 成本 > 一次编译 > 需长跑 A/B``。机器可读的排序在 ``agent\must-do.json`` 的 ``order`` / ``order_tier``；
分权（能不能跳、给多久、跳了下一步做什么）在 ``agent\governance.json``。

## 判据
真交替 + 丢首轮 + **3 次取中位数**；报数必须带 **内容类型 + 接受率 + 引擎 sha256**；提升 <1% 视为噪声。

## 容易踩的
- 性能不达标**不是**部署失败；
- 别拿我们的绝对数当目标（跨卡不可比，只比接受率与带宽比）；
- "改了参数但计数器一模一样" ⇒ 先怀疑**开关没生效**，不是"这个参数不重要"。
"@
[IO.File]::WriteAllText((Join-Path $Root '03-基础部署后的调优方案.md'), $p03, $enc)

# ---- 08 页：兜底路线 + 授权门 ----
$p08 = @"
# 08 · 从零复现方案书（兜底路线 · $Tier）

> 这是**最后一条路**，不是捷径：自己编一支引擎。包内对应的来源与步骤见 ``docs\`` 里的兜底/复现手册与 ``src-tree\``。

## ⛔ 进入本页的**授权前置条件**（是门，不是建议）
先交**路线尝试台账**，缺一项不授权：

| # | 台账项 | 格式 |
|---|---|---|
| 1 | 探针读数 | ``gpu-probe.exe`` 输出（cc / SM / shared / 带宽） |
| 2 | 各启动件的失败原文 | 逐条命令 + **报错原文**（含"差多少字节"这类数字） |
| 3 | 已试过的处方 | 02 页的**节号** + 结果 |
| 4 | 每条为什么不适配你的机器 | 一句话 + 依据（读数或报错） |

> 为什么设这道门：把"从零编译"当第一条路，会浪费你半天，而且**编出来的东西没有参照物**（不知道对不对）。

## 本页自己的三道门（构建成功 ≠ 可用）
1. **构建成功自证**：``rc`` + 产物 **mtime** + **编译日志里出现目标文件名**。
   ⚠️ **不许**拿 ``obj`` 尺寸或文件 hash 当"编对了"的证据（本构建树目标文件不逐位可复现，同源两次编译 hash 不同）。
2. **ABI / 加载校验**：编出来的引擎能加载你的制品（``HTTP 200`` + 一次真推理）。
3. **数值门 → 性能门**：先过数值门（双口径 PPL / 逐位要求），再谈速度。

## 两条必带纪律
- **改完源码必须同批重建两个目标**（``ninfer-serve`` 与 ``ninfer-perplexity``）：只重链一个，会拿**旧二进制**复核，得到"改了没用"的错结论。
- 改 ``.h`` 之后要确认依赖被真正重编（本构建树的 MSVC 头依赖扫描不可靠）⇒ 断言产物 mtime 变化。

## 编译期常量（按你的卡）
``-DNINFER_SM_COUNT=<gpu-probe 读出的 SM>``（包内 ``src-tree`` 已内置该分支）；
**编完断言它真的进了编译行**：``findstr /c:"NINFER_SM_COUNT=<你的SM>" <build>\build.ninja``。
``-j 8``，**别 ``-j 24``**（会杀 ``cl.exe`` 且不打印错误，伪装成源码错误）。
"@
[IO.File]::WriteAllText((Join-Path $Root '08-从零复现方案书（兜底路线）.md'), $p08, $enc)

# ---- 10 页：可选挂载第 4 包（只给带 engine 的 ninfer 档） ----
if (Test-Path (Join-Path $Root 'engine')) {
  $p10 = @"
# 10 · 可选挂载 —— **第 4 包 · Swift 微调档**（默认不用）

> 本包**不含**第 4 包的权重，它是一份**独立包**（同骨架）。这里只说清：**什么时候值得去拿、代价多大、判据是什么**。

## 它是什么
同门微调（Swift-Bonsai-2）：**同架构、同引擎、同骨架**，与 base 的差异落在 ``text/*`` 权重上（容器同构）。

## 什么时候值得试
- 你**优先省 token**（同任务生成更短的思考链）且**愿意接受掉分风险**；或要复现"微调 vs base"的对比。

## 代价（我们实测，同引擎同口径）
| 项 | base | Swift |
|---|---|---|
| 20 题得分 | **19/20** | **16/20** |
| 思考 token 总量（DFlash2 K=7） | 63,984 | **109,970（+71.9%）** |
| decode（DFlash2 K=7） | 173.5 t/s | 182.5 t/s（+5.2%） |
| 端到端墙钟 | 419.8 s | **579.3 s（+38%）** |

⇒ **"decode 更快"被"话更多"吃光还倒亏** ⇒ **默认不切**。

## 判据（要切必须过）
1. 同一支引擎、**同口径对拍**（长提示 + 长输出 + 贪心 + 丢首轮 + 3 次中位数 + 报内容类型与接受率）；
2. **可核对答案**的题集不退化（我们的口径：20 题 ≥ base）；
3. 负控在场且能变红。
"@
  [IO.File]::WriteAllText((Join-Path $Root '10-可选挂载-第四包-Swift微调档.md'), $p10, $enc)
}

# ---- 11 页：按卡差异速查 ----
$p11 = @"
# 11 · 按卡差异速查（**同一份包，不同卡读不同行**）

> 先跑 ``gpu-probe.exe`` 拿到你的 **cc 与 SM**，再按下表选件。**别抄我们的绝对数**（跨卡不可比，只比接受率与带宽比）。

| 你的机器 | 能走哪条 | 选件 / 启动 | KV 档 | 上下文起点 |
|---|---|---|---|---|
| **cc 8.9（40 系）** | ninfer 档 | 按显存分档（见下） | ``fp8`` 要速度 / ``rk4v4`` 要长窗口 | 16 GB：65536~131072 |
| **cc 12.0（50 系）** | ninfer 档 | 同上，另可用 ``…-dflash2.ninfer`` | ``fp8`` / ``nvfp4``（``rk4v4`` 在 12.0 被拒） | 同左 |
| **cc 8.6（30 系）** | ❌ ninfer 档**今天走不了**（运行时只接受 8.9/12.0） | 走 **省显存档（llama+KVMem）** | ``bf16``/``int8``（FP8 张量核 sm_89 才有） | 按显存收 |
| **笔记本版** | 先探针 | 同名笔记本卡**不等于**桌面卡（SM 更少 + 功耗墙） | 同左 | **待实测，别照抄** |

**显存分档（同一份引擎）**
| 显存 | 建议 |
|---|---|
| **16 GB 及以上** | **首选 ``…-dflash2.ninfer`` + ``--spec dflash2 --draft-tokens 7 --lm-head-draft``**（该档启动件额定 ≥16 GB，权重 9.10 GiB；128K 上下文变体才另算 KV） |
| 12 GB | 基础 PQ2/PTQ1 + MTP K=3 + 4-bit KV（``rk4v4`` 40 系 / ``nvfp4`` 50 系） |
| 8~10 GB | 换 PTQ1（权重 5.52 GiB）+ 短上下文，或走省显存档 |

**K 的边界（引擎 vs 成本）**：引擎允许 ``mtp`` **1..5**、``dflash`` / ``dflash2`` **1..15**；
但 **K=8 起验证宽度越过小批档 ⇒ 单轮 13 ms → 约 40 ms**（实测 K=7 351 → K=8 248 → K=9 276）⇒ 工程甜点 **5 / 7**。

**默认关闭的开关（别开）**：``NINFER_TERNARY_KVMEM`` / ``_WINDOW_ASSEMBLY`` / ``_SEMANTIC``（KVMem，默认关且逐位不变）；
``NINFER_TERNARY_SMALL_T_ROWS=32``（A1 宽档：PTQ1 算错、PQ2 编不出）；``NINFER_TERNARY_KSPLIT=1``（A2：负收益）。
"@
[IO.File]::WriteAllText((Join-Path $Root '11-按卡差异速查.md'), $p11, $enc)

# ---- agent\governance.json（C4 分权表） ----
$agentDir = Join-Path $Root 'agent'
if (Test-Path $agentDir) {
  $gov = @'
{
  "schema": "governance/1",
  "note": "每条必做项的执行分权：blocking=不做后面就没意义；timebox_min=允许花多久（分钟）；fallback=达不到时的下一步（不是重试）。与 must-do.json 的 id 一一对应，两者合起来才是完整口径。",
  "rule": "除 blocking=true 者外，任何项超时或只到可用线 ⇒ 登记 SKIP（读数+已试+原因）后继续；只有可行性失败才允许停下。",
  "items": {
    "C1": { "blocking": true,  "timebox_min": 0,  "fallback": "按默认口径继续（不许用短提示/单 token 的数下结论）" },
    "C2": { "blocking": true,  "timebox_min": 0,  "fallback": "保持默认（前缀复用开）" },
    "C3": { "blocking": false, "timebox_min": 10, "fallback": "按默认：MTP 档不开、dflash2 档必开" },
    "C4": { "blocking": false, "timebox_min": 10, "fallback": "保持 1024" },
    "C5": { "blocking": true,  "timebox_min": 0,  "fallback": "补齐后才报数" },
    "C6": { "blocking": true,  "timebox_min": 0,  "fallback": "KVMem 开关一律不设（默认关）" },
    "B1": { "blocking": false, "timebox_min": 30, "fallback": "保持预设 33 并登记 SKIP" },
    "B2": { "blocking": false, "timebox_min": 30, "fallback": "保持预设 41 并登记 SKIP" },
    "B2b":{ "blocking": false, "timebox_min": 60, "fallback": "不在本包，跳过" },
    "B3": { "blocking": true,  "timebox_min": 10, "fallback": "按卡自动选（fp8 / 4-bit）" },
    "B4": { "blocking": false, "timebox_min": 30, "fallback": "保持预设 K=3（MTP）/ 5~7（dflash2）" },
    "B5": { "blocking": false, "timebox_min": 30, "fallback": "默认用 base，不切微调档" },
    "E1": { "blocking": false, "timebox_min": 60, "fallback": "不重编，直接用出厂引擎（收益未量化）" },
    "E2": { "blocking": false, "timebox_min": 60, "fallback": "跳过（单做它没有收益）" },
    "A1": { "blocking": false, "timebox_min": 30, "fallback": "零收益 ⇒ 跳过并登记" },
    "A2": { "blocking": false, "timebox_min": 30, "fallback": "负收益 ⇒ 默认关，跳过" },
    "A3": { "blocking": false, "timebox_min": 90, "fallback": "不想自编就跳过（+31% prefill 只在自编引擎上存在）" },
    "F1": { "blocking": false, "timebox_min": 30, "fallback": "前置未满足（没有自编引擎）⇒ 跳过" },
    "D1": { "blocking": false, "timebox_min": 0,  "fallback": "不做" },
    "D2": { "blocking": false, "timebox_min": 0,  "fallback": "不做" },
    "D3": { "blocking": false, "timebox_min": 0,  "fallback": "不做" },
    "D4": { "blocking": false, "timebox_min": 0,  "fallback": "不做" },
    "D5": { "blocking": false, "timebox_min": 0,  "fallback": "不做" },
    "D6": { "blocking": false, "timebox_min": 0,  "fallback": "不做" },
    "D7": { "blocking": false, "timebox_min": 0,  "fallback": "不做（T=1 留在 gemv_tile）" }
  },
  "skip_ledger": {
    "why": "跳过的项要留痕，回执时一并给我们（我们据此改文档与默认值）",
    "fields": ["id", "读数", "已试步骤", "为什么停"]
  }
}
'@
  [IO.File]::WriteAllText((Join-Path $agentDir 'governance.json'), $gov, $enc)
}
Write-Host ("extra skeleton written to " + $Root)
