# 档位探针 / RUNG PROBE  (read-only diagnostics; changes nothing)
#
#  ANSWER TO "did we set gemv_tile for you?": there is nothing to set.
#  The rung ladder is decided at RUNTIME by shape+switches, not by any env of its own:
#     s8        T >= 33   (needs scratch + NINFER_TERNARY_S8!=0 + NINFER_TERNARY_MMA!=0 + mma_wide_admits)
#     wide_t    T >= 41   (NINFER_TERNARY_WIDE_MIN_TOKENS overrides 41; needs mma_wide_admits)
#     small_t   T >= 2    (needs mma_admits; this is the speculative verify pass)
#     gemv_tile T <= 4    (SIMT fallback; reached at T=1 and whenever the mma rungs reject the shape)
#     reference otherwise (launch_by_qtype<8>)
#  This script proves which rung YOUR config actually takes, by turning on the engine's own probe
#  and reading its stderr. It starts your launcher, sends two requests, stops it, prints the table.
#
#  Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File .\档位探针.ps1
#          powershell ... -File .\档位探针.ps1 -Launcher start-3-dflash2-k7.bat
#
param(
  [string]$Launcher = '',
  [int]$Budget = 600,
  [int]$WaitSec = 240,
  [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

function Say($m) { Write-Host $m }

Say ''
Say '=== 档位探针 (rung probe) ==='
Say '  作用: 用引擎自带探针证明"每个 T 实际走哪一档"，不测速度、不改任何配置。'
Say ''

if (-not $Launcher) {
  $cands = Get-ChildItem -LiteralPath $root -File -Filter 'start-*.bat' | Sort-Object Name
  if (-not $cands) { Say '[ERROR] 这个目录里没有 start-*.bat —— 请在档位根目录运行本脚本。'; exit 2 }
  $Launcher = $cands[0].Name
}
$batPath = Join-Path $root $Launcher
if (-not (Test-Path -LiteralPath $batPath)) { Say ("[ERROR] 找不到启动件: " + $batPath); exit 2 }
Say ('  启动件: ' + $Launcher)

# --- 从启动件里读出 port / model / model-id（不猜，照抄它自己的参数） ---
$batText = Get-Content -LiteralPath $batPath -Raw
$port = 8092
$m = [regex]::Match($batText, '--port\s+(\d+)');           if ($m.Success) { $port = [int]$m.Groups[1].Value }
$modelId = 'local'
$m = [regex]::Match($batText, '--model-id\s+(\S+)');       if ($m.Success) { $modelId = $m.Groups[1].Value }
$kv = '(launcher default)'
$m = [regex]::Match($batText, '--kv-dtype\s+(\S+)');       if ($m.Success) { $kv = $m.Groups[1].Value }
$spec = '(launcher default)'
$m = [regex]::Match($batText, '--spec\s+(\S+)');           if ($m.Success) { $spec = $m.Groups[1].Value }
$draft = '(launcher default)'
$m = [regex]::Match($batText, '--draft-tokens\s+(\d+)');   if ($m.Success) { $draft = $m.Groups[1].Value }
Say ('  port=' + $port + '  model-id=' + $modelId + '  kv-dtype=' + $kv + '  spec=' + $spec + '  draft=' + $draft)

# --- 探针 env：必须在起服前设好（引擎在 CUDA graph capture 时把它读死） ---
$env:NINFER_TERNARY_S8_DEBUG = '1'
$env:NINFER_TERNARY_S8_DEBUG_MIN_T = '1'
$env:NINFER_TERNARY_S8_DEBUG_BUDGET = [string]$Budget
Say ('  探针: NINFER_TERNARY_S8_DEBUG=1  MIN_T=1  BUDGET=' + $Budget)

if ($DryRun) {
  Say ''
  Say '  [DryRun] 只解析、只打印，不启动引擎、不发请求。'
  $eng = Join-Path $root 'engine\ninfer-serve.exe'
  if (Test-Path -LiteralPath $eng) { Say ('  引擎存在: ' + $eng) } else { Say ('  [warn] 没找到 ' + $eng) }
  $eng120 = Join-Path $root 'engine\ninfer-serve-sm120.exe'
  Say ('  sm_120 引擎: ' + $(if (Test-Path -LiteralPath $eng120) { '存在' } else { '不存在（50 系会缺这支）' }))
  Say ('  本机卡: ' + (& nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader 2>$null))
  Say ('  将写出的日志: 档位探针-stderr.log / 档位探针-结果.txt')
  Say '  DryRun 结束。'
  exit 0
}

$errLog = Join-Path $root '档位探针-stderr.log'
$outLog = Join-Path $root '档位探针-stdout.log'
Remove-Item -LiteralPath $errLog, $outLog -ErrorAction SilentlyContinue

Say ''
Say '  [1/4] 启动引擎（stderr 落到 档位探针-stderr.log）...'
$proc = Start-Process -FilePath $env:ComSpec -ArgumentList '/c', ('"' + $batPath + '"') `
        -WorkingDirectory $root -RedirectStandardError $errLog -RedirectStandardOutput $outLog -PassThru
if (-not $proc) { Say '[ERROR] 启动失败'; exit 3 }

Say '  [2/4] 等端口就绪...'
$ready = $false
$deadline = (Get-Date).AddSeconds($WaitSec)
while ((Get-Date) -lt $deadline) {
  if ($proc.HasExited) { break }
  try {
    $tcp = New-Object Net.Sockets.TcpClient; $tcp.Connect("127.0.0.1", $port); $tcp.Close()
    $ready = $true; break
  } catch { Start-Sleep -Seconds 3 }
}
if (-not $ready) {
  Say '  [ERROR] 引擎没有就绪。下面是它自己的输出尾部（通常这里就写着原因）：'
  Get-Content -LiteralPath $outLog, $errLog -Tail 40 -ErrorAction SilentlyContinue | ForEach-Object { '      ' + $_ }
  if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
  Get-Process -Name 'ninfer-serve','ninfer-serve-sm120' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  exit 4
}
Say '        就绪。'

function Ask($text, $maxTokens) {
  $body = @{ model = $modelId; messages = @(@{ role = 'user'; content = $text }); max_tokens = $maxTokens; temperature = 0 } | ConvertTo-Json -Depth 6 -Compress
  $bytes = [Text.Encoding]::UTF8.GetBytes($body)
  try {
    $r = Invoke-RestMethod -Uri ("http://127.0.0.1:$port/v1/chat/completions") -Method Post `
         -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 600
    $c = 0; if ($r.usage) { $c = $r.usage.completion_tokens }
    Say ('        请求完成: completion_tokens=' + $c)
  } catch { Say ('        [warn] 请求失败: ' + $_.Exception.Message) }
}

# 提示词用 ASCII，避免任何编码问题；探针只关心 T 的取值，不关心内容。
$short = ('Probe one. ' * 26)
$long  = ('The quick brown fox jumps over the lazy dog near the river bank at dawn. ' * 90)

Say '  [3/4] 请求 A：短提示（命中 s8/prefill 小 T 段）+ 8 token 输出（decode 走 T=1）'
Ask $short 8
Say '  [4/4] 请求 B：长提示（~1.3k token prefill）+ 8 token 输出'
Ask $long 8

Say '        停引擎...'
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
Get-Process -Name 'ninfer-serve','ninfer-serve-sm120' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# --- 解析 ---
$lines = @()
if (Test-Path -LiteralPath $errLog) { $lines = Get-Content -LiteralPath $errLog }
$rows = @()
foreach ($l in $lines) {
  $mm = [regex]::Match($l, 'rung=(\S+).*?\bT=(\d+)\b')
  if ($mm.Success) { $rows += [pscustomobject]@{ Rung = $mm.Groups[1].Value; T = [int]$mm.Groups[2].Value } }
}
Say ''
Say ('=== 结果（探针原始行 ' + $rows.Count + ' 条）===')
if ($rows.Count -eq 0) {
  Say '  没抓到任何 rung= 行。常见原因：'
  Say '   1) 引擎是通过别的窗口启动的（探针 env 只对由本脚本启动的进程生效）——请让本脚本启动；'
  Say '   2) 启动件把 stderr 重定向掉了；'
  Say '   3) 请求没打到这个 port。'
  Say ('  原始日志: ' + $errLog)
  exit 5
}
$byT = $rows | Group-Object T | Sort-Object { [int]$_.Name }
Say ''
Say '  T     次数   实际泳道'
Say '  ----- ------ ----------------------------'
foreach ($g in $byT) {
  $rungs = ($g.Group | Group-Object Rung | ForEach-Object { $_.Name + 'x' + $_.Count }) -join ', '
  Say ('  {0,-5} {1,-6} {2}' -f $g.Name, $g.Count, $rungs)
}

# 期望对照（s8 先判，因此 T>=41 也应是 s8；wide_t 只在 s8 被拒时出现）
$bad = @()
foreach ($g in $byT) {
  $t = [int]$g.Name
  $seen = ($g.Group | Select-Object -ExpandProperty Rung | Sort-Object -Unique) -join ','
  $want = 'reference'
  if ($t -eq 1)      { $want = 'gemv_tile' }
  elseif ($t -le 32) { $want = 'small_t' }
  else               { $want = 's8' }
  $ok = $false
  foreach ($s in ($seen -split ',')) { if ($s -eq $want) { $ok = $true } }
  if (-not $ok) { $bad += ('T=' + $t + ' 实际=' + $seen + ' 期望=' + $want) }
}
Say ''
if ($bad.Count -eq 0) {
  Say '  判定: 档位分布与设计一致（T=1 -> gemv_tile；T=2..32 -> small_t；T>=33 -> s8）。'
} else {
  Say '  判定: 以下 T 与设计不一致（不一定是错，但据此调优前必须先解释清楚）：'
  $bad | ForEach-Object { Say ('    - ' + $_) }
  Say '  提示: 若某形状未被 mma 准入，可能是 ①NINFER_TERNARY_MMA=0 ②NINFER_TERNARY_PTQ1_FAST=0'
  Say '        ③该形状 high plane 未 8 字节对齐 / K 被补齐 ④s8 的 scratch 没分配（部分入口不带工作区）。'
  Say '        探针原始行里 wide_admits / small_admits / gemv_admits / s8_scratch / mma 五个位就是答案。'
}

$sample = $rows | Select-Object -First 0
$raw = $lines | Where-Object { $_ -match 'rung=' } | Select-Object -First 3
Say ''
Say '  原始示例行（含准入位，回传给我们最有用）:'
$raw | ForEach-Object { Say ('    ' + $_) }

$report = Join-Path $root '档位探针-结果.txt'
$sb = New-Object Text.StringBuilder
$null = $sb.AppendLine('rung probe result')
$null = $sb.AppendLine('launcher = ' + $Launcher)
$null = $sb.AppendLine('port = ' + $port + '  model-id = ' + $modelId + '  kv = ' + $kv + '  spec = ' + $spec + '  draft = ' + $draft)
$null = $sb.AppendLine('')
$null = $sb.AppendLine('T      count  rungs')
foreach ($g in $byT) { $null = $sb.AppendLine(('{0,-5} {1,-6} {2}' -f $g.Name, $g.Count, (($g.Group | Group-Object Rung | ForEach-Object { $_.Name + 'x' + $_.Count }) -join ','))) }
$null = $sb.AppendLine('')
$null = $sb.AppendLine('verdict: ' + $(if ($bad.Count -eq 0) { 'matches design' } else { 'MISMATCH -> ' + ($bad -join ' | ') }))
$null = $sb.AppendLine('')
$null = $sb.AppendLine('raw probe lines:')
foreach ($l in ($lines | Where-Object { $_ -match 'rung=' } | Select-Object -First 40)) { $null = $sb.AppendLine($l) }
[IO.File]::WriteAllText($report, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
Say ''
Say ('  已写出: ' + $report + '   （回传报告时请带上它 + 档位探针-stderr.log）')
Say ''
