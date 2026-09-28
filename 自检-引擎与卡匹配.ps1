# 自检-引擎与卡匹配.ps1 -- 30 seconds: does this engine run on this card, and should you rebuild for it?
#
# WHY: two stories about "which cards work" are circulating -- one says "all of them" (community
# deployments), one says "only 40/50 series". Do not trust either: ask THIS card and THIS binary.
#
# WHAT IT DOES (read-only: starts no engine, writes no file):
#   1) ask the card what it is (name / compute_cap / driver)
#   2) RUN gpu-probe.exe TO READ THE REAL SM COUNT / cc / shared-memory caps   <-- added 2026-09-27
#      nvidia-smi CANNOT report the SM count; only the CUDA runtime can. A card-name table is
#      used ONLY as a fallback, and it is labelled as a REFERENCE value, never as measured.
#   3) scan every exe in engine\ for the two hard gate strings (the engine prints them itself)
#   4) if cuobjdump exists, list each exe's cubin/PTX architectures (skipped otherwise)
#   5) verdict: which engine to use on this arch + which KV dtypes this card can use
#   6) REBUILD-FOR-YOUR-CARD: fill the real probe value into -DNINFER_SM_COUNT and print the
#      assertion that proves the macro actually reached the compile line
#
# USAGE (from the package root, next to engine\ and model\):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\自检-引擎与卡匹配.ps1
#
# ASCII-only content on purpose (PowerShell 5.1 reads a BOM-less file as ANSI).
# Chinese explanations live in docs\引擎-模型-参数对照表.md; every line printed here is ASCII
# so the output survives codepage 936.
param([string]$Root = '')

$ErrorActionPreference = 'Continue'
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = (Resolve-Path -LiteralPath $Root).Path

Write-Host ''
Write-Host '=========================================================='
Write-Host ' engine <-> GPU match self-check'
Write-Host '=========================================================='

# --- 1) the card ---
Write-Host ''
Write-Host '[1] This card (nvidia-smi)'
$cc = ''
try {
  $info = & nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv,noheader 2>$null
  foreach ($l in @($info)) { if ($l) { Write-Host ('    ' + $l) } }
  $cc = ((& nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null) | Select-Object -First 1)
  if ($cc) { $cc = $cc.Trim() }
} catch { }
if (-not $cc) {
  Write-Host '    (nvidia-smi unavailable / no NVIDIA card) -- the verdict below will be half-blind'
}

# --- 2) the probe: the REAL SM count (this section is the entry point of card adaptation) ---
# nvidia-smi cannot report the SM count, but kTargetSmCount (src/core/device.h) is a COMPILE-TIME
# constant that the kernels use for large-block wave/occupancy decisions, so it must be read from
# the CUDA runtime. Fall back to the name table only when the probe cannot run.
Write-Host ''
Write-Host '[2] Real SM count / cc  (gpu-probe.exe; the name table is only a fallback and is REFERENCE data)'
$probeJson = $null
$probePath = Join-Path $Root 'gpu-probe.exe'
$sm    = $null
$smSrc = ''
if (Test-Path -LiteralPath $probePath) {
  $raw = $null
  try { $raw = (& $probePath --json 2>$null | Select-Object -First 1) } catch { $raw = $null }
  if ($raw) { try { $probeJson = $raw | ConvertFrom-Json } catch { $probeJson = $null } }
  if ($probeJson -and $probeJson.device_count -ge 1 -and $probeJson.devices) {
    $d = $probeJson.devices[0]
    $sm    = [int]$d.sm
    $smSrc = 'MEASURED by gpu-probe.exe (CUDA runtime)'
    Write-Host ('    ' + $d.name + ' | cc ' + $d.cc + ' | SM=' + $sm + ' | vram=' + $d.vram_mib + ' MiB')
    Write-Host ('    shared/block static=' + $d.shared_per_block + ' B, opt-in=' + $d.shared_per_block_optin + ' B, shared/SM=' + $d.shared_per_sm + ' B, regs/SM=' + $d.regs_per_sm)
    if ([int]$d.shared_per_block_optin -ge 98304) {
      Write-Host '    => opt-in cap >= 98304 B: the 32-row tier can be saved with DYNAMIC shared memory (MUST-DO E2)'
    }
  } else {
    Write-Host ('    (gpu-probe.exe present but reported no device; exit code ' + $LASTEXITCODE + ')')
  }
} else {
  Write-Host ('    (no gpu-probe.exe in the package root: ' + $probePath + ')')
}
if (-not $sm) { Write-Host '    => no measured SM count; falling back to the card-name table (REFERENCE ONLY)' }
# Fallback table. Used ONLY when the probe fails. Sources: see the 40-series table in
# docs\引擎-模型-参数对照表.md, which carries a per-row source column.
$smTable = @{
  'RTX 5090' = 170; 'RTX 5090 D' = 170; 'RTX 5080' = 84; 'RTX 5070 Ti' = 70; 'RTX 5070' = 48
  'RTX 4090 D' = 114; 'RTX 4090' = 128; 'RTX 4080 SUPER' = 80; 'RTX 4080' = 76
  'RTX 4070 Ti SUPER' = 66; 'RTX 4070 Ti' = 60; 'RTX 4070 SUPER' = 60; 'RTX 4070' = 46
  'RTX 4060 Ti' = 34; 'RTX 4060' = 24
  'RTX 3090 Ti' = 84; 'RTX 3090' = 82; 'RTX 3060' = 28
}
$gpuName = ''
try { $gpuName = ((& nvidia-smi --query-gpu=name --format=csv,noheader 2>$null) | Select-Object -First 1) } catch { }
if ($gpuName) { $gpuName = $gpuName.Trim() }
if (-not $sm -and $gpuName) {
  foreach ($k in ($smTable.Keys | Sort-Object { -1 * $k.Length })) {
    if ($gpuName -like ('*' + $k + '*')) { $sm = $smTable[$k]; $smSrc = ('card-name table (REFERENCE, not measured): ' + $k); break }
  }
}
if ($sm) { Write-Host ('    => SM count in use = ' + $sm + '   source: ' + $smSrc) }
else     { Write-Host '    => SM count UNKNOWN (neither the probe nor the table produced one)' }

# --- 3) gate strings inside the engines ---
Write-Host ''
Write-Host '[3] exe files in engine\: do they carry the two hard gates'
$gateArch  = 'requires compute capability 12.0 or 8.9'   # accepts 8.9 and 12.0 only
$gateRk4v4 = 'requires compute capability 8.9'           # rk4v4 accepts 8.9 only
$engDir = Join-Path $Root 'engine'
$exes = @()
if (Test-Path -LiteralPath $engDir) {
  $exes = @(Get-ChildItem -LiteralPath $engDir -File -Filter '*.exe')
} else {
  Write-Host ('    (no engine\ directory: ' + $engDir + ')')
}
foreach ($e in $exes) {
  $txt = ''
  try { $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($e.FullName)) } catch { }
  $hasArch = $txt.Contains($gateArch)
  $hasRk   = $txt.Contains($gateRk4v4)
  $sha = ''
  try { $sha = (Get-FileHash -LiteralPath $e.FullName -Algorithm SHA256).Hash.Substring(0,16) } catch { }
  Write-Host ('    ' + $e.Name.PadRight(24) + ' sha=' + $sha + '  arch-gate=' + $(if ($hasArch) { 'YES' } else { 'no' }) + '  rk4v4-gate=' + $(if ($hasRk) { 'YES' } else { 'no' }))
}

# --- 4) cubin / PTX architectures (optional) ---
Write-Host ''
Write-Host '[4] Native architectures per exe (needs cuobjdump; skipped when absent)'
$cu = $null
# 候选目录：环境变量 CUDA_PATH + Program Files 下的所有版本（不假设任何盘符）
$cudaRoots = @()
if ($env:CUDA_PATH) { $cudaRoots += $env:CUDA_PATH }
$cudaPf = Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit\CUDA'
if (Test-Path -LiteralPath $cudaPf) { $cudaRoots += @(Get-ChildItem -LiteralPath $cudaPf -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
foreach ($c in $cudaRoots) {
  if (-not (Test-Path -LiteralPath $c)) { continue }
  $hit = Get-ChildItem -LiteralPath $c -Recurse -File -Filter 'cuobjdump.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hit) { $cu = $hit.FullName; break }
}
if (-not $cu) {
  Write-Host '    (no cuobjdump.exe -- comes with a CUDA Toolkit install; this step does not change the verdict)'
} else {
  foreach ($e in $exes) {
    $elf = & $cu --list-elf $e.FullName 2>&1
    $arp = (($elf | Select-String -Pattern 'sm_(\d+)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { 'sm_' + $_.Groups[1].Value } | Group-Object | ForEach-Object { $_.Name + 'x' + $_.Count }) -join ' ')
    $ptx = (& $cu --list-ptx $e.FullName 2>&1 | Select-String -Pattern '\.ptx' | Measure-Object).Count
    Write-Host ('    ' + $e.Name.PadRight(24) + ' cubin=[' + $arp + ']  PTX=' + $ptx)
  }
}

# --- 5) verdict ---
Write-Host ''
Write-Host '[5] Verdict'
switch ($cc) {
  '8.9'  { Write-Host '    card = Ada (8.9)  -> use engine\ninfer-serve.exe; KV: bf16/int8/fp8/rk4v4/rk4v4-e8' }
  '12.0' { Write-Host '    card = Blackwell (12.0) -> use engine\ninfer-serve-sm120.exe (if present); KV: bf16/int8/fp8/k8v4/nvfp4; rk4v4 will refuse to start' }
  ''     { Write-Host '    card not detected, cannot judge' }
  default {
    Write-Host ('    card = compute capability ' + $cc + ':')
    Write-Host '    if [3] shows arch-gate=YES, this engine will throw at startup:'
    Write-Host '      "Qwen3.6 family runtime requires compute capability 12.0 or 8.9"'
    Write-Host '    => that is not a broken card or a bad config: this binary does not support that arch.'
    Write-Host '       Use a build that does, or build one (docs\引擎-模型-参数对照表.md section 6).'
  }
}
Write-Host ''
Write-Host '  Note: both gate strings are the engine''s own wording, so [3] literally answers'
Write-Host '        "will THIS binary refuse your card". To judge someone else''s build, drop that'
Write-Host '        exe into engine\ and run this script again.'
Write-Host ''

# ---- [6] rebuild for your card (probe-first; the table is only a reference) ----------------
# ARCH / SM_COUNT / TIER are compile-time constants.
# IMPORTANT: they do NOT decide whether the engine runs -- it runs either way. They only decide
# whether YOUR card can reach its ceiling (wave filling). So this is a TUNING item, not a gate.
Write-Host ''
Write-Host '[6] Rebuild for your card (not required to run; this section is "should I, how, how to prove it")'

# Which constant does the shipped engine carry? In the packaged src-tree it is a per-arch
# hardcoded default in src\core\device.h -- read that line to check for yourself.
$shippedSm  = $null
$shippedWhy = ''
if ($cc -eq '8.9')  { $shippedSm = 128; $shippedWhy = 'NINFER_SM89 default in src\core\device.h (RTX 4090 class)' }
if ($cc -eq '12.0') { $shippedSm = 170; $shippedWhy = 'NINFER_SM120 default in src\core\device.h (RTX 5090 class)' }
if ($shippedSm) {
  Write-Host ('    shipped engine SM constant = ' + $shippedSm + '   (' + $shippedWhy + ')')
  if ($sm) {
    if ($sm -eq $shippedSm) {
      Write-Host '    => your card MATCHES it: NO rebuild needed for the SM constant.'
    } else {
      Write-Host ('    => MISMATCH (your card has ' + $sm + ' SM): the engine still runs, but its wave/')
      Write-Host ('       occupancy decisions follow a ' + $shippedSm + '-SM card. Rebuild once if you want the ceiling.')
    }
  } else {
    Write-Host '    => your SM count is unknown; fix the probe (or look up the spec) before deciding.'
  }
}

if ($cc -eq '12.0') {
  Write-Host '    arch gate: -DNINFER_CUDA_ARCH=120a   tier: -DNINFER_TIER=blackwell'
  Write-Host ''
  Write-Host '    cmake -B build-120a -S <src-tree>\ninfer-4090w-ternary -G Ninja -DCMAKE_BUILD_TYPE=Release ^'
  Write-Host '      -DCMAKE_CUDA_ARCHITECTURES=120a -DNINFER_CUDA_ARCH=120a ^'
  Write-Host ('      -DNINFER_SM_COUNT=' + $(if ($sm) { $sm } else { '<SM>' }) + ' -DNINFER_TIER=blackwell')
  Write-Host '    (full steps: docs\构建与ABI校验-SOP.md; judgement: docs\引擎-模型-参数对照表.md section 4.8 E1)'
} elseif ($cc -eq '8.9') {
  Write-Host '    40 series: engine\ninfer-serve.exe is already built for 8.9. To rebuild for YOUR SM count:'
  Write-Host ''
  Write-Host '    cmake -B build-89 -S <src-tree>\ninfer-4090w-ternary -G Ninja -DCMAKE_BUILD_TYPE=Release ^'
  Write-Host '      -DCMAKE_CUDA_ARCHITECTURES=89 -DNINFER_CUDA_ARCH=89 ^'
  Write-Host ('      -DNINFER_SM_COUNT=' + $(if ($sm) { $sm } else { '<SM>' }) + ' -DNINFER_TIER=ada')
  Write-Host ('    (SM value from ' + $(if ($sm) { $smSrc } else { 'UNKNOWN -- run gpu-probe.exe first' }) + ')')
} else {
  Write-Host '    your architecture is outside this package: to build it yourself see docs\引擎-模型-参数对照表.md section 6.'
}

Write-Host ''
Write-Host '    THREE STEPS YOU MAY NOT SKIP (each one cost us a wasted build):'
Write-Host '      1) The packaged src-tree ALREADY has the NINFER_SM_COUNT branch (added 2026-09-27).'
Write-Host '         If you build from another tree, first confirm src\core\device.h contains'
Write-Host '         "#if defined(NINFER_SM_COUNT)" -- without it, -DNINFER_SM_COUNT is SILENTLY'
Write-Host '         IGNORED: the build succeeds and the macro was never read (a wasted build).'
Write-Host '      2) Assert the macro reached the compile line:'
Write-Host ('         findstr /c:"NINFER_SM_COUNT=' + $(if ($sm) { $sm } else { '<SM>' }) + '" build-89\build.ninja')
Write-Host '         Expect a DEFINES line containing -DNINFER_SM_COUNT=<your SM>.'
Write-Host '      3) Record sha256 + mtime. Build with -j 8, never -j 24 (24 way parallelism kills'
Write-Host '         cl.exe with no diagnostic and looks like a source error).'
Write-Host ''
Write-Host '    JUDGEMENT (all three must hold):'
Write-Host '      - structure: the findstr above hits and equals the probe value;'
Write-Host '      - numbers:   PPL unchanged in BOTH modes (--context 512 --stride 256 and'
Write-Host '                   --context 32 --stride 16);'
Write-Host '      - speed:     same content (counting / code), true interleaved A/B, drop the first,'
Write-Host '                   median of 3, and report acceptance rate next to t/s.'
Write-Host '      No clear gain => keep the shipped engine (saves a 190 MB rebuild).'
Write-Host ''
