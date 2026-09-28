<#
gen-skeleton.ps1 —— 生成"四包同骨架"的编号索引页（00–09）

设计约束（与用户确认过）：
  * **只加骨架、不搬内容**：00–09 都是**薄索引页**，指向包里既有的文件；
    真值仍然只有一个 home（参数 = docs\引擎-模型-参数对照表.md；必做项 = agent\must-do.json …）。
  * **全相对路径**：页内只出现"本包内的文件名/关键词"，不出现任何盘符（R1/R5）。
  * **可重跑**：重复运行只覆盖它自己生成的 00–09 页，不动任何既有文件。

用法：powershell -NoProfile -ExecutionPolicy Bypass -File gen-skeleton.ps1 -Root <包根> -Tier <档名>
#>
[CmdletBinding()]
param(
  [string]$Root = '',
  [string]$Tier = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not $Tier) { $Tier = Split-Path $Root -Leaf }

function Find-First([string[]]$names, [string[]]$hints) {
  # 先按精确文件名找，再按关键词在包内小件里找；只返回**文件名**（相对引用）
  foreach ($n in $names) {
    $h = Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $n -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\src-tree\\' } | Select-Object -First 1
    if ($h) { return $h.FullName.Substring($Root.Length).TrimStart('\') }
  }
  foreach ($k in $hints) {
    $h = Get-ChildItem -LiteralPath $Root -Recurse -File -Include '*.md', '*.txt' -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -notmatch '\\src-tree\\' } |
         Where-Object { $_.Name -like ('*' + $k + '*') } | Select-Object -First 1
    if ($h) { return $h.FullName.Substring($Root.Length).TrimStart('\') }
  }
  return ''
}
function P([string]$rel) { if ($rel) { return ('`' + $rel + '`') } else { return '**（本包没有这一件，走 08 兜底路线）**' } }

# 路由：每一槽先按文件名，再按关键词
$r01 = Find-First @('README.md')            @('复现手册', '部署', '白皮书', '构建与')
$r02 = Find-First @()                        @('排错', '处方', '预案', '判据')
$r03 = Find-First @()                        @('调参与扫参', '参数对照表', '调参')
$r04 = Find-First @('gpu-probe.exe')         @('自检', '探针', '工具')
$r05 = if (Test-Path (Join-Path $Root 'engine')) { 'engine\' } else { '' }
$r06 = if (Test-Path (Join-Path $Root 'src-tree')) { 'src-tree\' } else { '' }
$r07 = if (Test-Path (Join-Path $Root 'model')) { 'model\' } else { '' }
$r08 = Find-First @()                        @('兜底', '从源码', '复现手册')
$r09 = if (Test-Path (Join-Path $Root 'licenses')) { 'licenses\' } else { '' }
$must = Find-First @('must-do.json')         @()
$agentmd = Find-First @('AGENT.md')          @()
$sched = if (Test-Path (Join-Path $Root 'sched3-patch')) { 'sched3-patch\' } else { '' }
$movecheck = Find-First @('自检-搬家.ps1')    @()

$stamp = Get-Date -Format 'yyyy-MM-dd'

# ---------------- 00 ----------------
$p00 = @"
# 00 · 从这里开始（$Tier）—— **唯一入口，先读这一页**

> 生成于 $stamp ｜ 本页只做三件事：**说清本包是什么、给你固定五步、出问题指向哪一页**。
> 真值不在本页：**参数真值**在 $(P $r03)；**必做项与排序**在 $(P $must)。

## 🚫 两条先记住（比任何参数都重要）

1. **权限条款**：你对"能不能部署"**只有建议权，没有否决权**。
   提交"不可行"结论前，必须已经完成：① 跑过 ``gpu-probe.exe`` 建档 ② 按 01 页走到第 4 步 ③ **至少一条路线失败的原文输出** ④ 证伪命令 + 读数 + 引擎 sha256。四项不全 = 议案退回。
2. **可行性 ≠ 性能**：判"不可行"**只能用可行性判据** —— ``HTTP 200`` + 一次真推理返回 + 数值门不崩 + 显存/host 不炸。
   **性能没达标不是"不可部署"**，只记一条 SKIP（见下面第 4 步）。

## 五步契约（照这个走，别跳）

| 步 | 做什么 | 期望输出 | 不符就去 |
|---|---|---|---|
| **1 探针建档** | 跑 ``gpu-probe\gpu-probe.exe``，记 cc / SM / shared / 带宽 | 一份机器档案（写进 ``agent\state.json``） | 04 页 |
| **2 选件** | 按 cc 与显存选制品与启动件（**cc 只接受 8.9 / 12.0**） | 选定的 ``start-*.bat`` | 01 页 / 03 页按卡分支 |
| **3 起服务** | 跑启动件（**非交互**；agent 场景设 ``NINFER_AGENT=1``） | 日志 ``listening`` + ``curl /v1/models`` = **200** | 02 页 |
| **4 过四道门** | ① 起得来 ② **数值门** ③ **质量门**（可核对答案 + 负控变红）④ **性能门** | 四门各自的读数 | 02 页 → 08 页兜底 |
| **5 留痕回执** | 写回执：命令 + 读数 + 引擎 sha256 | 一份可复核的回执 | 00 本页 §回执 |

## 偏离与证否（你可以不照抄我们的路径，但要按这个来）

- 我们的步骤是**推荐路径，不是执行脚本**。换档 / 换参 / 换路线之前，先做**最小证伪**：一条命令、≤10 分钟、读数可判读，证明我们那条在**你这台机器上**确实不可行 —— 然后才切，并把证否证据写进回执。
- **禁止**"看着不合理就直接跳过"；**禁止**拿我们的绝对数当目标（跨卡不可比，按带宽比折算：``预期 ≈ 353.8 × 你的带宽 ÷ 736 GB/s``）。

## 时间盒与跳过（别卡在一个参数上）

- 每个**性能类**条目给自己 **30 分钟或 3 次交替实验**（先到为准）。
- 超时或只到"可用线"⇒ **允许继续**：登记一条 SKIP（读数 + 已试步骤 + 为什么停），**后续步骤不得因此阻塞**。
- **只有"可行性失败"才允许真的停下**。跳过**不需要等我们回话**，但必须留痕。

## 进"从零编译"的前置门

``08`` 是**最后一条路**。授权条件 = **路线尝试台账**：① 探针读数 ② 各启动件失败原文 ③ 已试过的处方（02 的节号）④ 每条为什么不适配你的机器。
08 自己还要过：构建环境自检 → **构建成功自证**（rc + 产物 mtime + 编译日志点名目标文件；**不许拿 obj 尺寸/哈希当证据**）→ ABI 校验 → 数值门 → 性能门。

## 回执（我们需要的五样）

``矛盾点`` + ``命令`` + ``读数`` + ``引擎/制品 sha256`` + ``你的结论``。顺序：**证否优先 → 实测裁决 → 回执沉淀**。

## 骨架导航（本包）

| 页 | 内容 | 本包对应 |
|---|---|---|
| 00 | 本页（入口 + 契约 + 路由） | 你正在读 |
| 01 | 部署与编译总白皮书 | $(P $r01) |
| 02 | 排错手册 · 预案与处方 | $(P $r02) |
| 03 | 基础部署后的调优方案 | $(P $r03) |
| 04 | 工具包与工具清单 | $(P $r04) |
| 05 | 引擎包（冻结，只读） | $(P $r05) |
| 06 | 源码树与科研过程 | $(P $r06) |
| 07 | 模型与制品 | $(P $r07) |
| 08 | 从零复现方案书（兜底） | $(P $r08) |
| 09 | 声明与链接 | $(P $r09) |
| — | **必做项（机器可读，带排序）** | $(P $must) |
| — | **机读接口（英文）** | $(P $agentmd) |
| — | 调度补丁（A3，自编才生效） | $(P $sched) |
| — | **搬家自检（接手第一条命令）** | $(P $movecheck) |

> 先跑一次搬家自检：``powershell -NoProfile -ExecutionPolicy Bypass -File .\自检-搬家.ps1``
> 它断言"这个包换到任意目录/盘符后依然自洽"（无绝对路径、脚本自定位、清单可验）。**它红了就别往下走。**
"@
[IO.File]::WriteAllText((Join-Path $Root '00-从这里开始.md'), $p00, (New-Object Text.UTF8Encoding($false)))

# ---------------- 01–09（薄索引页） ----------------
$slots = @(
  @{ n = '01'; t = '部署与编译总白皮书'; src = $r01
     purpose = '对外**唯一**的"怎么装、怎么编、按什么规范"的入口：前置检查 → 选件 → 起服务 → 四道门，每一步都带**期望输出**与**不符时去哪**。'
     judge   = '① `listening` + `HTTP 200` ② 数值门（双口径 PPL / 逐位要求）③ 质量门（可核对答案 + 负控变红）④ 性能读数落在**带宽比折算**区间内。'
     pit     = '别把我们的**绝对数**当门槛；**别跳步**（跳过探针 ⇒ 后面全是猜）；`-j 8` 别 `-j 24`（会杀 `cl.exe` 且不报错）。' }
  @{ n = '02'; t = '排错手册 · 预案与处方'; src = $r02
     purpose = '症状 → 根因（**源码 `文件:行`**）→ 处方 → 判据 → **本地适配提示**。四道门任何一门红了先来这里。'
     judge   = '每条处方都带"改完看哪个字段/哪行日志才算好了"。'
     pit     = '本页没覆盖的 ⇒ 走 08 兜底，别自己硬猜；**报错原文**要原样保留（回执要用）。' }
  @{ n = '03'; t = '基础部署后的调优方案'; src = $r03
     purpose = '部署完成后再榨性能：**路径 × 预期收益 × 成本 × 排序**，按卡与内容类型分支；含"什么情况下别做"。'
     judge   = '真交替 + 丢首轮 + 3 次中位数；报数带**内容类型 + 接受率 + 引擎 sha**；提升 <1% 视为噪声。'
     pit     = '性能不达标**不是**部署失败；每个性能项都给自己**时间盒**，超时就登记 SKIP 往下走。' }
  @{ n = '04'; t = '工具包与工具清单'; src = $r04
     purpose = '包里带的工具：探针 / 自检 / 清单工具 / 调度补丁。每个工具写清**用途、输入、输出、何时跑、期望输出**。'
     judge   = '`gpu-probe.exe` 能读 cc/SM/shared；`自检-搬家.ps1` rc=0；`自检-启动件.ps1` rc=0。'
     pit     = '工具**不搬位置**（脚本靠自身路径定位）；别用"obj 尺寸/哈希"当编译证据。' }
  @{ n = '05'; t = '引擎包（冻结，只读）'; src = $r05
     purpose = '冻结引擎：**是什么 / 不是什么**。它是 dev fork；运行时只接受 **cc 8.9 与 12.0**；缓存档 `rk4v4` 只 40 系、`nvfp4` 只 50 系。'
     judge   = '引擎 sha256 与 `SHA256SUMS.txt` 一致；起得来（`HTTP 200`）。'
     pit     = '**别覆盖/替换它**（要自编就另存一支并报 sha）；KVMem 开关默认关，别开。' }
  @{ n = '06'; t = '源码树与科研过程'; src = $r06
     purpose = '我们改了什么、为什么改、**否证过什么**（否决清单最省你时间），以及 `src-tree` 结构与 MANIFEST。'
     judge   = 'MANIFEST 与磁盘一致；改动地图能指到 `文件:行`。'
     pit     = '改 `.h` 之后必须重编**两个目标**（`ninfer-serve` 与 `ninfer-perplexity`），只重链一个会拿到旧数字。' }
  @{ n = '07'; t = '模型与制品'; src = $r07
     purpose = '本档制品清单：文件名 / 大小 / sha256 / 用途，以及"**哪个件才跑得起哪个投机后端**"。'
     judge   = 'sha256 与 `SHA256SUMS.txt` 一致；按后端选件（`mtp` 要 MTP 头；`dflash2` 要带 `dflash2/*` 载荷的件且 `--lm-head-draft` 必开）。'
     pit     = '本包**没有** dflash(v1) 制品 ⇒ 跑不起 `--spec dflash`；权重换档（Swift）会掉分，默认别换。' }
  @{ n = '08'; t = '从零复现方案书（兜底路线）'; src = $r08
     purpose = '前面都不通时的**最后一条路**：自己编一支引擎。含构建环境自检 → 编译 → ABI 校验 → 数值门 → 性能门。'
     judge   = '构建成功要**自证**（rc + 产物 mtime + 编译日志点名目标文件）；编完**先过数值门**再谈速度。'
     pit     = '**进入本页要授权**（先交路线尝试台账，见 00 页）；本页不是捷径，是一条更长的路。' }
  @{ n = '09'; t = '声明与链接'; src = $r09
     purpose = '许可与署名：模型权重、引擎来源、上游链接、以及我们改动过的部分；另有回执渠道。'
     judge   = '许可文件在场且与制品对应；上游链接可打开。'
     pit     = '再分发请保留署名与许可全文；若上游另有附加条款，以上游为准。' }
)
foreach ($s in $slots) {
  $body = @"
# $($s.n) · $($s.t)（$Tier）

> **薄索引页**：本页不复制内容，只做路由 —— **真值只有一处**，避免"两处互相矛盾"。
> 本槽对应的包内件：$(P $s.src)

## 这一槽是干什么的
$($s.purpose)

## 判据（过不了就别往下走）
$($s.judge)

## 容易踩的
$($s.pit)

## 与其它槽的关系
- 入口与行为契约（权限 / 证否 / 时间盒 / 兜底授权）：``00-从这里开始.md``
- 机器可读的必做项与排序：$(P $must)
- 搬家 / 路径无关自检：$(P $movecheck)
"@
  [IO.File]::WriteAllText((Join-Path $Root ($s.n + '-' + ($s.t -replace '[\\/:*?"<>|]', '') + '.md')), $body, (New-Object Text.UTF8Encoding($false)))
}
Write-Host ("skeleton written to " + $Root)
