# ninfer-agent.ps1 -- machine interface for driving this tier (AGENTS, not humans)
#
#  WHY THIS EXISTS
#  The .bat launchers in this folder are for humans: they print a banner, and they
#  stop on `pause` / ask with `choice` when detection fails.  An agent that shells
#  out to them BLOCKS FOREVER on those prompts.  This script is the agent-facing
#  entry point: no prompts, no banner, machine-readable JSON on stdout, distinct
#  exit codes, and every decision (engine, KV dtype, speculative backend, context)
#  chosen automatically from what the machine actually reports.
#
#  USAGE (all output is ASCII JSON on stdout; diagnostics go to stderr)
#    pwsh -NoProfile -File .\ninfer-agent.ps1 doctor
#    pwsh -NoProfile -File .\ninfer-agent.ps1 plan  -Artifact auto
#    pwsh -NoProfile -File .\ninfer-agent.ps1 start -Artifact dflash2 -Port 8096 -Ctx 131072
#    pwsh -NoProfile -File .\ninfer-agent.ps1 status -Port 8096
#    pwsh -NoProfile -File .\ninfer-agent.ps1 stop   -Port 8096
#    pwsh -NoProfile -File .\ninfer-agent.ps1 bench  -Port 8096 -Kind code -Runs 3
#    pwsh -NoProfile -File .\ninfer-agent.ps1 probe  -Port 8096 -Reqs 2
#    pwsh -NoProfile -File .\ninfer-agent.ps1 sweep  -Kind code -Values 17,24,33,48
#    pwsh -NoProfile -File .\ninfer-agent.ps1 must-do            # the MUST-DO list (tuning items)
#    pwsh -NoProfile -File .\ninfer-agent.ps1 must-do -Json      # same, machine readable
#
#  MUST-DO: every command below also carries a "must_do" summary (agent\must-do.json), and
#  `doctor` promotes the first pending items into `actions`, so the mandatory tuning items
#  reach an agent without it reading any document. The per-machine ledger of what has already
#  been done is agent\state.json.
#
#  Exit codes: 0 ok | 2 bad usage | 3 artifact missing | 4 no engine for this card
#              5 VRAM too small for the requested context | 6 failed to become ready
#              7 not running (status/stop) | 8 request failed | 9 nvidia-smi unusable
#
param(
  [Parameter(Position=0)][string]$Command = 'doctor',
  [string]$Artifact = 'auto',
  [int]$Port = 0,
  [int]$Ctx = 0,
  [string]$Kv = 'auto',
  [string]$Spec = 'auto',
  [int]$K = 0,
  [switch]$NoLmHeadDraft,
  [string]$ExtraArgs = '',
  [int]$WaitSec = 300,
  [string]$Kind = 'code',
  [int]$Runs = 3,
  [int]$MaxTokens = 400,
  [int]$Reqs = 2,
  [string]$Values = '17,24,33,48',
  [int]$SweepTokens = 200,
  [string]$LogDir = '',
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path $root -Leaf) -eq 'agent') { $root = Split-Path -Parent $root }
$env:NINFER_AGENT = '1'

function Fail([int]$code, [string]$msg, $extra) {
  $o = @{ ok = $false; error = $msg; exit_code = $code }
  if ($extra) { $o.detail = $extra }
  $o | ConvertTo-Json -Depth 6 -Compress
  exit $code
}
function Emit($obj) { $obj | ConvertTo-Json -Depth 6 -Compress; exit 0 }
# Package defaults live in agent\defaults.json so that "the default configuration" is DATA, not code
# scattered across launchers. Measured values only; the CLI applies them unless a flag overrides.
$defaultsPath = Join-Path $root 'agent\defaults.json'
$DEF = $null
if (Test-Path -LiteralPath $defaultsPath) {
  try { $DEF = [IO.File]::ReadAllText($defaultsPath) | ConvertFrom-Json } catch { $DEF = $null }
}
# ASCII guard: the engine refuses a non-ASCII model path (CreateFileW gets "????ninfer?") and its JSON
# request log dies on a non-ASCII path ("invalid UTF-8 byte ... json.exception.type_error.316", where the
# byte is the first byte of the CJK character in GBK). Measured twice on 2026-09-26. Logs therefore go to
# an ASCII temp path by default, and a non-ASCII artifact path is refused here with a clear message
# instead of surfacing as a confusing engine FATAL.
function Test-Ascii([string]$s) { foreach ($c in $s.ToCharArray()) { if ([int]$c -gt 126) { return $false } }; return $true }
function Note($m) { [Console]::Error.WriteLine($m) }

# ---------------------------------------------------------------- must-do (tuning items)
# The tuning checklist lives in agent\must-do.json (a copy of docs section 4.8, machine readable)
# and the per-machine ledger of finished items lives in agent\state.json. Both are UTF-8 and are
# read/written as bytes on purpose: PowerShell 5.1 would otherwise read them as ANSI and mangle
# every CJK character. Nothing here may throw -- a missing or broken file must not break doctor.
function Read-Utf8Text([string]$p) {
  try { return [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false))) } catch { return $null }
}
$js = $null
try { $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $js.MaxJsonLength = [int]::MaxValue } catch { $js = $null }
function From-Json2([string]$txt) {
  if (-not $txt -or -not $js) { return $null }
  try { return $js.DeserializeObject($txt) } catch { return $null }
}
$mustDoPath  = Join-Path $root 'agent\must-do.json'
$stateJsonPath = Join-Path $root 'agent\state.json'
if (-not (Test-Path -LiteralPath $stateJsonPath)) {
  try {
    $seed = '{"_what":"must-do ledger: what has been done/verified ON THIS MACHINE, with evidence","_machine":"' + $env:COMPUTERNAME + '","done":[],"skipped":[],"notes":[]}'
    [IO.File]::WriteAllText($stateJsonPath, $seed, (New-Object Text.UTF8Encoding($false)))
  } catch { Note ('could not create agent\state.json: ' + $_.Exception.Message) }
}
function Get-MustDo {
  # returns a plain hashtable-ish object (works on PowerShell 5.1 and 7 alike)
  $o = New-Object PSObject -Property ([ordered]@{ available = $false; total = 0; done = 0; pending_estimate = 0; ids = @(); pending = @(); file = 'agent/must-do.json'; state_file = 'agent/state.json'; evidence_levels = ''; card_guidance = $null })
  if (-not $js) { return $o }
  $d = From-Json2 (Read-Utf8Text $mustDoPath)
  if (-not $d -or -not $d['items']) { return $o }
  $o.available = $true
  $ids = @(); $titles = @(); $mustMd = @{}
  foreach ($it in $d['items']) { $ids += [string]$it['id']; $mustMd[[string]$it['id']] = $it }
  $doneIds = @()
  $s = From-Json2 (Read-Utf8Text $stateJsonPath)
  if ($s -and $s['done']) { foreach ($r in $s['done']) { if ($r['id']) { $doneIds += [string]$r['id'] } } }
  $pend = @()
  foreach ($id in $ids) { if ($doneIds -notcontains $id) { $pend += $mustMd[$id] } }
  $o.total = $ids.Count
  $o.done = ($ids.Count - $pend.Count)
  $o.pending_estimate = $pend.Count
  $o.ids = $ids
  $o.pending = $pend
  # evidence-level split: "what we measured" must never again be confused with "what we guess".
  # Rendered as a STRING on purpose: assigning a hashtable into a PSObject property whose initial
  # value was @{} makes PowerShell coerce the keys to Int32 (measured: "Cannot convert value
  # 'hypothesis' to type System.Int32"). A string cannot be coerced into that trap.
  $lvl = @{}
  foreach ($id2 in $ids) {
    $g = [string]$mustMd[$id2]['evidence_level']
    if (-not $g) { $g = 'unlabelled' }
    if (-not $lvl.ContainsKey($g)) { $lvl[$g] = 0 }
    $lvl[$g] = $lvl[$g] + 1
  }
  $o.evidence_levels = (@($lvl.Keys | Sort-Object | ForEach-Object { $_ + '=' + $lvl[$_] }) -join '  ')
  return $o
}
function Get-CardGuidance([string]$probeName, $probeSm, [string]$probeCc) {
  # find the card_guidance entry that matches this machine, so `doctor` can say what applies HERE
  if (-not $js) { return $null }
  $d = From-Json2 (Read-Utf8Text $mustDoPath)
  if (-not $d -or -not $d['card_guidance'] -or -not $d['card_guidance']['cards']) { return $null }
  $cards = $d['card_guidance']['cards']
  foreach ($c in $cards) {
    if ($probeName -and [string]$c['card'] -and $probeName -like ('*' + [string]$c['card'] + '*')) { return $c }
  }
  if ($probeSm) {
    foreach ($c in $cards) { if ($c['sm'] -ne $null -and [int]$c['sm'] -eq [int]$probeSm) { return $c } }
  }
  # 30 series: the engine refuses 8.6 outright, so point at that card explicitly
  if ($probeCc -eq '8.6') { foreach ($c in $cards) { if ([string]$c['series'] -eq '30') { return $c } } }
  return $null
}
function Get-MustDoBrief {
  # the one-line form that rides along in every JSON response
  $m = Get-MustDo
  if (-not $m.available) { return @{ total = 0; file = 'agent/must-do.json'; note = 'must-do.json not found next to agent\state.json' } }
  $n = 'all items are marked done in agent/state.json'
  if ($m.pending.Count -gt 0) { $n = 'first pending: [' + $m.pending[0]['id'] + '] ' + $m.pending[0]['title'] }
  return @{ total = $m.total; done = $m.done; pending_estimate = $m.pending_estimate; file = 'agent/must-do.json'; evidence_levels = $m.evidence_levels; note = $n }
}

# ---------------------------------------------------------------- card discovery
function Get-Card {
  $o = @{ name = $null; compute_cap = $null; vram_mib = $null; driver = $null }
  try {
    $csv = & nvidia-smi --query-gpu=name,compute_cap,memory.total,driver_version --format=csv 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $csv) { return $o }
    $line = @($csv | Where-Object { $_ -match ',' } | Select-Object -Last 1)
    if (-not $line) { return $o }
    $p = ($line -split ',') | ForEach-Object { $_.Trim() }
    $o.name = $p[0]
    $o.compute_cap = $p[1]
    if ($p[2] -match '(\d+)') { $o.vram_mib = [int]$Matches[1] }
    $o.driver = $p[3]
  } catch { Note ('nvidia-smi failed: ' + $_.Exception.Message) }
  return $o
}

function Get-FileInfo([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $i = Get-Item -LiteralPath $path
  return @{ file = (Split-Path $path -Leaf); size = $i.Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}

# ---------------------------------------------------------------- layout
$engineDir = Join-Path $root 'engine'
$modelDir  = Join-Path $root 'model'
$eng89     = Join-Path $engineDir 'ninfer-serve.exe'
$eng120    = Join-Path $engineDir 'ninfer-serve-sm120.exe'
$artBase   = Join-Path $modelDir 'bonsai2_27b_ternary_v2.ninfer'
$artDflash = Join-Path $modelDir 'bonsai2_27b_ternary_v2-dflash2.ninfer'
if (-not $LogDir) { $LogDir = Join-Path $env:TEMP 'ninfer-agent-logs' }

function Pick-Artifact([string]$want) {
  $hasBase = Test-Path -LiteralPath $artBase
  $hasDf   = Test-Path -LiteralPath $artDflash
  if ($want -eq 'base')    { if ($hasBase) { return @{ kind='base'; path=$artBase } } else { return $null } }
  if ($want -eq 'dflash2') { if ($hasDf)   { return @{ kind='dflash2'; path=$artDflash } } else { return $null } }
  # auto: dflash2 is worth 12-49% more throughput, so prefer it when the card can hold it
  $card = Get-Card
  if ($hasDf -and $card.vram_mib -and $card.vram_mib -ge 20000) { return @{ kind='dflash2'; path=$artDflash } }
  if ($hasBase) { return @{ kind='base'; path=$artBase } }
  if ($hasDf)   { return @{ kind='dflash2'; path=$artDflash } }
  return $null
}

function Pick-Engine($card) {
  # neither binary carries PTX for the other arch: the wrong one dies or wedges silently
  $cc = $card.compute_cap
  if ($cc -eq '12.0') { if (Test-Path -LiteralPath $eng120) { return $eng120 } else { return $null } }
  if ($cc -eq '8.9')  { if (Test-Path -LiteralPath $eng89)  { return $eng89 }  else { return $null } }
  if ($cc) { return $null }   # detected but unsupported -> do not guess
  # could not read the card: prefer what exists, but say so
  if (Test-Path -LiteralPath $eng89) { return $eng89 }
  if (Test-Path -LiteralPath $eng120) { return $eng120 }
  return $null
}

function Get-DefaultEngineArgs {
  if ($DEF -and $DEF.engine_args) { return @($DEF.engine_args) }
  return @()
}
function Get-DefaultRungSwitches {
  $o = [ordered]@{}
  if ($DEF -and $DEF.rung_switches) {
    foreach ($p in $DEF.rung_switches.PSObject.Properties) { $o[$p.Name] = [string]$p.Value }
  }
  return $o
}
function Pick-Kv($card, $artKind) {
  $cc = $card.compute_cap
  if ($DEF -and $DEF.kv_dtype) {
    $prop = $DEF.kv_dtype.PSObject.Properties[$cc]
    if ($prop -and $prop.Value) { return [string]$prop.Value }
  }
  if ($cc -eq '12.0') { return 'fp8' }
  if ($cc -eq '8.9')  { return 'fp8' }
  return 'fp8'
}

function Plan {
  $card = Get-Card
  if (-not $card.name) { Fail 9 'nvidia-smi could not report a GPU' @{ hint='put nvidia-smi on PATH, or pass -Ctx/-Kv explicitly' } }
  $art = Pick-Artifact $Artifact
  if (-not $art) { Fail 3 'requested artifact is not present' @{ artifact=$Artifact; base=(Test-Path $artBase); dflash2=(Test-Path $artDflash) } }
  $eng = Pick-Engine $card
  if (-not $eng) { Fail 4 'no shipped engine matches this compute capability' @{ compute_cap=$card.compute_cap; engines=@((Get-FileInfo $eng89),(Get-FileInfo $eng120)) } }

  $warnAscii = @()
  if (-not (Test-Ascii $art.path)) {
    Fail 5 'the artifact path contains non-ASCII characters; the engine cannot open it' @{
      path = $art.path
      evidence = 'CreateFileW received question marks instead of the CJK characters (measured 2026-09-26)'
      action = 'move the package to an ASCII path (any drive and folder name, as long as no CJK appears anywhere above it) or point a junction/ascii-named folder at it'
    }
  }
  foreach ($p in @($root, $eng)) {
    if (-not (Test-Ascii $p)) { $warnAscii += ('non-ASCII path in use: ' + $p + ' -- logs are redirected to ' + $LogDir + ', but keep the package on an ASCII path') }
  }
  $vram = if ($card.vram_mib) { $card.vram_mib } else { 0 }
  $kv   = if ($Kv -ne 'auto') { $Kv } else { Pick-Kv $card $art.kind }
  $preferSpec = 'mtp'; $preferK = 3
  if ($DEF -and $DEF.spec) { $preferSpec = [string]$DEF.spec.prefer; $preferK = [int]$DEF.spec.k }
  $spec = if ($Spec -ne 'auto') { $Spec } else { if ($art.kind -eq 'dflash2') { $preferSpec } else { if ($DEF -and $DEF.spec) { [string]$DEF.spec.fallback_spec } else { 'mtp' } } }
  $kk   = if ($K -gt 0) { $K } else {
    if ($spec -eq 'dflash2') { $preferK }
    elseif ($DEF -and $DEF.spec) { [int]$DEF.spec.fallback_k }
    else { 3 }
  }
  $ctxEff = if ($Ctx -gt 0) { $Ctx } else {
    $chosen = 0
    if ($DEF -and $DEF.ctx_by_vram_mib) {
      foreach ($row in ($DEF.ctx_by_vram_mib | Sort-Object { -1 * [int]$_.min })) {
        if ($vram -ge [int]$row.min) { $chosen = [int]$row.ctx; break }
      }
    }
    if ($chosen -le 0) {
      if     ($vram -ge 20000) { 131072 }
      elseif ($vram -ge 15000) { 32768 }
      else                     { 16384 }
    }
    $chosen
  }
  $lmHead = ($spec -eq 'dflash2') -and (-not $NoLmHeadDraft.IsPresent)

  # rough VRAM need: weights ~10.2 GiB for dflash2 / ~7.4 GiB for base, plus KV (fp8 ~32 KiB/token)
  $weightsMib = if ($art.kind -eq 'dflash2') { 10450 } else { 7600 }
  $kvMib = [int]($ctxEff * 32.2 / 1024)
  $needMib = $weightsMib + $kvMib + 1200
  $fits = ($vram -eq 0) -or ($needMib -le $vram)
  if (-not $fits) {
    Fail 5 'context does not fit in this card VRAM' @{ need_mib=$needMib; vram_mib=$vram; suggest_ctx=32768; suggest_kv='rk4v4 or nvfp4 (4-bit KV) cuts the KV term to about half' }
  }

  return @{
    card = $card
    engine = $eng
    artifact = @{ kind = $art.kind; path = $art.path }
    kv = $kv
    spec = $spec
    draft_tokens = $kk
    ctx = $ctxEff
    lm_head_draft = $lmHead
    vram_estimate_mib = $needMib
    argv = (@(Get-Argv $art.path $kv $spec $kk $ctxEff $lmHead $(if ($Port -gt 0) { $Port } else { 8096 })) + @(Get-DefaultEngineArgs))
    defaults_file = $(if ($DEF) { 'agent/defaults.json' } else { '(missing: built-in values used)' })
    rung_switches = (Get-DefaultRungSwitches)
    warnings = @(
      if ($spec -eq 'mtp' -and $art.kind -eq 'dflash2') { 'dflash2 artifact with mtp: the draft head is unused' }
      if ($vram -gt 0 -and $vram -lt 20000 -and $art.kind -eq 'dflash2') { 'dflash2 weights need about 10.2 GiB; on a 16 GB card keep ctx <= 32768' }
    )
  }
}

function Get-Argv([string]$modelPath, [string]$kv, [string]$spec, [int]$kk, [int]$ctx, [bool]$lmHead, [int]$port) {
  $a = @($modelPath, '--host', '127.0.0.1', '--port', "$port", '--model-id', 'qwen3.8-27b',
         '--max-context', "$ctx", '--kv-capacity', "$ctx", '--kv-dtype', $kv,
         '--max-concurrency', '1', '--no-thinking')
  if ($spec -ne 'none') {
    $a += @('--spec', $spec, '--draft-tokens', "$kk")
    if ($lmHead) { $a += '--lm-head-draft' }
  }
  return $a
}

function Get-PortOwner([int]$p) {
  $c = Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return [int]$c.OwningProcess }
  return $null
}

function Test-PortOpen([int]$p, [int]$timeoutMs = 800) {
  try {
    $t = New-Object Net.Sockets.TcpClient
    $iar = $t.BeginConnect('127.0.0.1', $p, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs)) { $t.Close(); return $false }
    $t.EndConnect($iar); $t.Close(); return $true
  } catch { return $false }
}

# ---------------------------------------------------------------- commands
switch ($Command.ToLower()) {

  'doctor' {
    $card = Get-Card
    $engines = @((Get-FileInfo $eng89), (Get-FileInfo $eng120)) | Where-Object { $_ }
    $arts = @((Get-FileInfo $artBase), (Get-FileInfo $artDflash)) | Where-Object { $_ }
    $actions = New-Object Collections.Generic.List[string]
    $verdict = 'ok'

    if (-not $card.name) { $verdict = 'no-gpu'; $actions.Add('nvidia-smi could not report a GPU; fix that first') }
    elseif ($card.compute_cap -notin @('8.9','12.0')) {
      $verdict = 'unsupported-arch'
      $actions.Add('compute capability ' + $card.compute_cap + ' is not covered: rebuild from src-tree with -DNINFER_CUDA_ARCH and -DNINFER_SM_COUNT for this card')
    }
    if ($card.compute_cap -eq '12.0' -and -not (Test-Path -LiteralPath $eng120)) {
      $verdict = 'engine-missing'; $actions.Add('sm_120 engine is missing: build it with build-120a.bat in this package')
    }
    if ($card.compute_cap -eq '8.9' -and -not (Test-Path -LiteralPath $eng89)) {
      $verdict = 'engine-missing'; $actions.Add('sm_89 engine is missing: build it with build-89.bat in this package')
    }
    if ($arts.Count -eq 0) { $verdict = 'artifact-missing'; $actions.Add('no .ninfer artifact in model\') }
    if (-not (Test-Path -LiteralPath $artDflash) -and $arts.Count -gt 0) {
      $actions.Add('dflash2 artifact absent: base artifact + mtp works; dflash2 is worth 12-49% more t/s (see docs 4.5)')
    }
    if ($actions.Count -eq 0) { $actions.Add('nothing to fix to RUN it: run `start` (plan first with `plan`)') }

    # ---- gpu-probe: the card parameters an agent needs before any rebuild ----
    # (read BEFORE the must-do block, because the card guidance is matched against these values)
    $cardParams = @{ sm = $null; cc = $null; note = ''; name = '' }
    $probe = Join-Path $root 'gpu-probe.exe'
    if (Test-Path -LiteralPath $probe) {
      $raw = $null
      try { $raw = (& $probe --json 2>$null | Select-Object -First 1) } catch { $raw = $null }
      if ($raw) {
        $pj = From-Json2 ([string]$raw)
        if ($pj -and $pj['devices'] -and $pj['devices'].Count -gt 0) {
          $d0 = $pj['devices'][0]
          $cardParams.sm = $d0['sm']; $cardParams.cc = [string]$d0['cc']; $cardParams.name = [string]$d0['name']
          $cardParams.note = 'from gpu-probe.exe'
        } else { $cardParams.note = 'gpu-probe.exe ran but reported no device' }
      } else { $cardParams.note = 'gpu-probe.exe present but produced no JSON (exit code ' + $LASTEXITCODE + ')' }
    } else { $cardParams.note = 'gpu-probe.exe not in the package root; nvidia-smi cannot report the SM count, so the SM count is UNKNOWN' }

    # ---- MUST-DO: reach the agent even if it never opens a document ----
    # brief first, then the detail object: see the scoping note in the 'must-do' command
    $mustDo = Get-MustDoBrief
    $m = Get-MustDo
    $pendingReq = @($m.pending | Where-Object { $_['rebuild_required'] })
    $cardGuide = Get-CardGuidance ([string]$cardParams.name) $cardParams.sm ([string]$cardParams.cc)
    $mustBlock = [ordered]@{ total = $mustDo.total; done = $mustDo.done; pending_estimate = $mustDo.pending_estimate; file = 'agent/must-do.json'; state_file = 'agent/state.json'; evidence_levels = $mustDo.evidence_levels }
    if ($cardGuide) {
      $mustBlock.card_guidance = [ordered]@{
        card = $cardGuide['card']; series = $cardGuide['series']; sm = $cardGuide['sm']
        sm_source = $cardGuide['sm_source']; applies_to_ids = $cardGuide['applies_to_ids']
        expected = $cardGuide['expected']; evidence_level = $cardGuide['evidence_level']
      }
      $actions.Add('CARD-GUIDANCE: this machine matches [' + $cardGuide['card'] + '] (evidence_level=' + $cardGuide['evidence_level'] + '); applies_to_ids = ' + (@($cardGuide['applies_to_ids']) -join ' ') + ' -- read the entry in agent/must-do.json card_guidance.cards')
    }
    # 30 series: ninfer refuses compute capability 8.6 outright -- say what CAN run today
    if ($card.compute_cap -eq '8.6') {
      $actions.Add('CARD-GUIDANCE: compute capability 8.6 is REFUSED by both ninfer engines (unconditional gate: 8.9/12.0 only). What runs today on 30 series: the low-VRAM tier (llama.cpp + KVMem), which natively supports sm_86. Unlocking ninfer needs the cc gate widened + an amp-tier build (pending, not a promise).')
    }
    # evidence split: measured vs guessed, so a reader never confuses the two
    if ($mustDo.evidence_levels) {
      $lv = @()
      
      $actions.Add('EVIDENCE-LEVELS: ' + $mustDo.evidence_levels + '  (measured = our own measurements; author = upstream data; hypothesis/pending = NOT established)')
    }
    if ($m.available) {
      $top = @($m.pending | Select-Object -First 3)
      $mustBlock.top_pending = @($top | ForEach-Object { @{ id = [string]$_['id']; class = [string]$_['class']; title = [string]$_['title'] } })
      $rebuildCount = $pendingReq.Count
      $mustBlock.rebuild_required_pending = $rebuildCount
      $mustBlock.how_to_read = 'every item carries why / how / judgement / evidence; run `must-do` for the full list (human) or `must-do -Json` (machine)'
      # promote them into actions so they are impossible to miss
      if ($top.Count -gt 0) { $actions.Add('MUST-DO: ' + $mustDo.pending_estimate + ' tuning item(s) pending (nothing recorded in agent/state.json). First: ' + [string]$top[0]['id'] + ' -- ' + [string]$top[0]['title']) }
      if ($top.Count -gt 1) { $actions.Add('MUST-DO: ' + [string]$top[1]['id'] + ' -- ' + [string]$top[1]['title']) }
      if ($top.Count -gt 2) { $actions.Add('MUST-DO: ' + [string]$top[2]['id'] + ' -- ' + [string]$top[2]['title']) }
      if ($rebuildCount -gt 0) { $actions.Add('MUST-DO: ' + $rebuildCount + ' pending item(s) need a rebuild -> read agent/must-do.json for the judgement; never rebuild without it') }
      # the run is fine, but the package is NOT "done": say so explicitly
      if ($verdict -eq 'ok') { $verdict = 'ok-untuned' }
    } else {
      $mustBlock.note = 'agent/must-do.json missing or unreadable'
      if ($verdict -eq 'ok') { $verdict = 'ok-must-do-missing' }
    }
    # shipped-engine wave assumption. This must not be a guess: the shipped binaries were built
    # before the package src-tree gained the NINFER_SM_COUNT branch, so their constant is the
    # per-arch default (device.h). The package tree now supports -DNINFER_SM_COUNT, so a rebuild
    # for THIS card is possible when the two do not match.
    $engineSm = $null; $engineSmWhy = ''
    if ($card.compute_cap -eq '8.9')  { $engineSm = 128; $engineSmWhy = 'NINFER_SM89 default in src/core/device.h = RTX 4090 class (the shipped ninfer-serve.exe was built before the package src-tree gained the NINFER_SM_COUNT branch). Pass -DNINFER_SM_COUNT=<gpu-probe value> to target your card.' }
    if ($card.compute_cap -eq '12.0') { $engineSm = 170; $engineSmWhy = 'NINFER_SM120 default in src/core/device.h = RTX 5090 class (the shipped ninfer-serve-sm120.exe was built before the package src-tree gained the NINFER_SM_COUNT branch). Pass -DNINFER_SM_COUNT=<gpu-probe value> to target your card.' }
    $smMatch = $null
    if ($engineSm -and $cardParams.sm) { $smMatch = ([int]$cardParams.sm -eq $engineSm) }
    $actions.Add('CARD-ADAPT: gpu-probe reads SM=' + $(if ($cardParams.sm) { $cardParams.sm } else { 'unknown' }) + ' cc=' + $(if ($cardParams.cc) { $cardParams.cc } else { $card.compute_cap } ) + '; the shipped engine for this arch is built for SM=' + $(if ($engineSm) { $engineSm } else { 'unknown' }) + $(if ($smMatch -eq $false) { ' -> MISMATCH: your card will run, but its wave/occupancy decisions follow another card. See MUST-DO E1.' } elseif ($smMatch -eq $true) { ' -> match: no rebuild needed for the SM constant.' } else { ' -> compare the two before rebuilding.' }))
    if ($cardParams.cc -and $cardParams.cc -ne $card.compute_cap) { $actions.Add('CARD-ADAPT: gpu-probe and nvidia-smi disagree on compute capability (' + $cardParams.cc + ' vs ' + $card.compute_cap + '); trust gpu-probe and mention it in the report') }

    Emit @{
      ok = ($verdict -eq 'ok')
      verdict = $verdict
      card = $card
      card_params = $cardParams
      shipped_engine_sm_constant = @{ value = $engineSm; why = $engineSmWhy; sm_matches = $smMatch }
      engines = $engines
      artifacts = $arts
      dflash2_artifact_present = (Test-Path -LiteralPath $artDflash)
      must_do = $mustBlock
      actions = $actions
      next = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 must-do   (then: plan -Artifact auto)'
    }
  }

  'plan' { Emit (@{ ok = $true; must_do = (Get-MustDoBrief) } + (Plan)) }

  'start' {
    if ($Port -le 0) { Fail 2 'start needs -Port' }
    if (Get-PortOwner $Port) { Fail 6 'something is already listening on this port' @{ port=$Port; pid=(Get-PortOwner $Port) } }
    $p = Plan
    $argv = Get-Argv $p.artifact.path $p.kv $p.spec $p.draft_tokens $p.ctx $p.lm_head_draft $Port
    if ($ExtraArgs) { $argv += ($ExtraArgs -split '\s+' | Where-Object { $_ }) }
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $errLog = Join-Path $LogDir ('engine-' + $Port + '.err.log')
    $outLog = Join-Path $LogDir ('engine-' + $Port + '.out.log')
    $reqLog = Join-Path $LogDir ('requests-' + $Port + '.jsonl')
    $argv += @('--request-log-jsonl', $reqLog)

    # Detach through WMI on purpose. An agent runs inside some host process tree, and hosts kill the
    # whole tree when the tool call returns -- a Start-Process child would be killed with it (measured:
    # the engine was gone between two tool calls). A WMI-created process is owned by WmiPrvSE, so it
    # survives the caller, and cmd carries the redirections.
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    $quoted = @($p.engine) + $argv | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }
    $sw = Get-DefaultRungSwitches
    $sets = ''
    foreach ($rk in $sw.Keys) { $sets += ('set ' + $rk + '=' + $sw[$rk] + ' && ') }
    $cmdline = 'cmd.exe /c "' + $sets + ($quoted -join ' ') + ' > "' + $outLog + '" 2> "' + $errLog + '""'
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdline; CurrentDirectory = $engineDir }
    if ($created.ReturnValue -ne 0) { Fail 6 'could not create the engine process' @{ wmi_return = $created.ReturnValue; cmdline = $cmdline } }
    $enginePid = [int]$created.ProcessId
    $deadline = (Get-Date).AddSeconds($WaitSec)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
      if (Test-PortOpen $Port) { $ready = $true; break }
      Start-Sleep -Milliseconds 750
    }
    if (-not $ready) {
      $tail = @(Get-Content -LiteralPath $errLog, $outLog -Tail 40 -ErrorAction SilentlyContinue)
      $owner = Get-PortOwner $Port
      if ($owner) { try { Stop-Process -Id $owner -Force } catch {} }
      Get-Process -Name 'ninfer-serve' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
      Fail 6 'engine did not become ready' @{
        pid = $enginePid; err_log = $errLog; tail = $tail
        hint = 'read tail: "FATAL ... capacity" means the context does not fit; "linear_topk: unsupported head profile" means --lm-head-draft was not passed with dflash2; a CJK path in the model argument fails with "The filename, directory name, or volume label syntax is incorrect" -- use an ASCII path'
      }
    }
    Emit @{
      ok = $true; pid = $enginePid; port = $Port; ready = $true; detached = 'wmi'
      engine = (Split-Path $p.engine -Leaf)
      artifact = $p.artifact.kind; kv = $p.kv; spec = $p.spec; draft_tokens = $p.draft_tokens
      ctx = $p.ctx; lm_head_draft = $p.lm_head_draft
      logs = @{ stderr = $errLog; stdout = $outLog; requests = $reqLog }
      must_do = (Get-MustDoBrief)
      warnings = $p.warnings
      next = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 bench -Port ' + $Port + ' -Kind code -Runs 3'
    }
  }

  'status' {
    if ($Port -le 0) { Fail 2 'status needs -Port' }
    $owner = Get-PortOwner $Port
    Emit @{ ok = $true; port = $Port; listening = [bool]$owner; pid = $owner; accept = (Test-PortOpen $Port) }
  }

  'stop' {
    if ($Port -le 0) { Fail 2 'stop needs -Port' }
    $owner = Get-PortOwner $Port
    if (-not $owner) { Fail 7 'nothing is listening on that port' @{ port = $Port } }
    try { Stop-Process -Id $owner -Force -ErrorAction Stop } catch { Fail 7 'could not stop the process' @{ pid = $owner; message = $_.Exception.Message } }
    Start-Sleep -Milliseconds 500
    Emit @{ ok = $true; port = $Port; killed_pid = $owner; still_listening = [bool](Get-PortOwner $Port) }
  }

  'bench' {
    if ($Port -le 0) { Fail 2 'bench needs -Port' }
    if (-not (Test-PortOpen $Port)) { Fail 7 'nothing is listening on that port' @{ port = $Port } }
    $prompts = @{
      code     = ("Implement a C++ function that reads a file line by line and returns a vector of strings. " * 4) + "Then write a unit test for it, then refactor it to stream the file."
      prose    = ("The morning market opened quietly, and the vendors arranged their baskets along the narrow street while the town slowly woke up. " * 6)
      counting = ("Count from one to four hundred, one number per line, no other text. ")
    }
    if (-not $prompts.ContainsKey($Kind)) { Fail 2 'unknown -Kind (use code|prose|counting)' @{ kind = $Kind } }
    $mt = if ($MaxTokens -gt 0) { $MaxTokens } else { 400 }
    $reqLog = Join-Path $LogDir ('requests-' + $Port + '.jsonl')
    $before = 0
    if (Test-Path -LiteralPath $reqLog) { $before = (Get-Item -LiteralPath $reqLog).Length }
    $rows = @()
    for ($i = 1; $i -le $Runs; $i++) {
      $body = @{ model = 'qwen3.8-27b'; messages = @(@{ role = 'user'; content = $prompts[$Kind] }); max_tokens = $mt; temperature = 0 } | ConvertTo-Json -Depth 6 -Compress
      $bytes = [Text.Encoding]::UTF8.GetBytes($body)
      $sw = [Diagnostics.Stopwatch]::StartNew()
      try {
        $r = Invoke-RestMethod -Uri ("http://127.0.0.1:$Port/v1/chat/completions") -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 900
        $sw.Stop()
        $ct = if ($r.usage) { $r.usage.completion_tokens } else { $null }
        $pt = if ($r.usage) { $r.usage.prompt_tokens } else { $null }
        $tps = if ($ct -and $sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($ct / $sw.Elapsed.TotalSeconds, 1) } else { $null }
        $rows += @{ run = $i; ok = $true; prompt_tokens = $pt; completion_tokens = $ct; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); tok_per_s_approx = $tps }
      } catch {
        $sw.Stop()
        $rows += @{ run = $i; ok = $false; error = $_.Exception.Message }
      }
    }
    # pull whatever the engine wrote about this window (acceptance etc.) -- schema is engine-owned,
    # so report the keys we found instead of assuming them.
    $recs = @()
    if (Test-Path -LiteralPath $reqLog) {
      $all = Get-Content -LiteralPath $reqLog -ErrorAction SilentlyContinue
      $recs = $all | Select-Object -Last ($Runs * 4)
    }
    $keys = New-Object Collections.Generic.List[string]
    foreach ($line in $recs) {
      try { $o = $line | ConvertFrom-Json; foreach ($jk in $o.PSObject.Properties.Name) { if ($keys -notcontains $jk) { $keys.Add($jk) } } } catch {}
    }
    $ok = @($rows | Where-Object { $_.ok })
    $median = $null
    if ($ok.Count -gt 0) {
      $vals = @($ok | ForEach-Object { $_.tok_per_s_approx } | Where-Object { $_ }) | Sort-Object
      if ($vals.Count -gt 0) { $median = $vals[[int][math]::Floor($vals.Count / 2)] }
    }
    Emit @{
      ok = ($ok.Count -eq $Runs); port = $Port; kind = $Kind; runs = $Runs; max_tokens = $mt
      results = $rows
      median_tok_per_s_approx = $median
      request_log = $reqLog
      request_log_keys_seen = $keys
      must_do = (Get-MustDoBrief)
      notes = @(
        'tok_per_s_approx is wall-clock over completion_tokens: it INCLUDES prefill and the first-token wait,'
        'so it is lower than the decode rate the engine reports. Use the request log for the engine-reported rate.'
        'Content kind changes the result by up to 3x on the same card: always report kind + acceptance together.'
      )
    }
  }

  'must-do' {
    # The full tuning checklist (docs section 4.8), machine readable in agent\must-do.json.
    # Without -Json it prints a human list; with -Json it emits the whole document, plus the
    # per-machine done/pending split from agent\state.json.
    # NOTE: Get-MustDoBrief() itself calls Get-MustDo() internally and the helpers have no
    # parameter, so PowerShell's dynamic scoping makes that inner call clobber any $m/$mustDo in
    # THIS scope. Call the brief FIRST and re-fetch $m afterwards -- otherwise $m.total ends up
    # empty here (measured 2026-09-27), and doctor silently reports a blank total.
    $mustDo = Get-MustDoBrief
    $m = Get-MustDo
    if (-not $m.available) { Fail 2 'agent\must-do.json is missing or unreadable' @{ path = 'agent/must-do.json'; state = 'agent/state.json' } }
    if ($Json) {
      # re-emit the file verbatim so nothing is lost in a round trip
      $txt = Read-Utf8Text $mustDoPath
      $head = '{"ok":true,"total":' + $m.total + ',"done":' + $m.done + ',"pending_estimate":' + $m.pending_estimate + ',"file":"agent/must-do.json","state_file":"agent/state.json","document":'
      $body = $txt.Trim()
      $out = $head + $body + '}'
      Write-Output $out
      exit 0
    }
    Write-Output ('MUST-DO -- ' + $m.total + ' item(s), done=' + $m.done + ', pending=' + $m.pending_estimate)
    Write-Output ('file: agent/must-do.json     ledger: agent/state.json     card probe: gpu-probe.exe')
    Write-Output ''
    foreach ($it in $m.pending) {
      Write-Output ('[' + $it['id'] + '] (' + $it['class'] + ', applies_to=' + $it['applies_to'] + ', rebuild=' + $it['rebuild_required'] + ') ' + $it['title'])
      Write-Output ('    why      : ' + $it['why'])
      Write-Output ('    how      : ' + $it['how'])
      Write-Output ('    judgement: ' + $it['judgement'])
      Write-Output ('    evidence : ' + $it['evidence'])
      Write-Output ''
    }
    if ($m.pending.Count -eq 0) { Write-Output 'nothing pending: every id in must-do.json is recorded in agent/state.json' }
    Write-Output 'Record a finished item in agent/state.json done[] as {"id":"E1","at":"<ISO8601>","evidence":"<sha256 or log>","note":"..."}'
    exit 0
  }

  'probe' {
    if ($Port -le 0) { Fail 2 'probe needs -Port' }
    $probe = Join-Path $root '????.ps1'
    if (-not (Test-Path -LiteralPath $probe)) { Fail 2 '????.ps1 is not next to this script' }
    # the human probe starts its own server; for agents we only consume an ALREADY RUNNING one
    Fail 2 'probe-driven-by-agent is not wired yet: run `start` with NINFER_TERNARY_S8_DEBUG=1 in the environment, then send requests with `bench`, then read the engine stderr log (rung= lines)'
  }

  'sweep' {
    # The s8 crossing is a property of the CARD, and it used to require one rebuild per candidate value.
    # The engine now reads NINFER_TERNARY_S8_MIN_TOKENS at startup (default 33 = unchanged behaviour),
    # so an agent can sweep it on one binary: start, bench, stop, next value.
    if ($Port -le 0) { Fail 2 'sweep needs -Port' }
    $vals = @($Values -split ',' | ForEach-Object { [int]($_.Trim()) } | Where-Object { $_ -gt 0 })
    if ($vals.Count -eq 0) { Fail 2 'sweep needs -Values (e.g. 17,24,33,48)' }
    $art = Pick-Artifact 'auto'
    if (-not $art) { Fail 3 'no artifact present' }
    $rows = @()
    foreach ($v in $vals) {
      $env:NINFER_TERNARY_S8_MIN_TOKENS = "$v"
      $startOut = & $PSCommandPath start -Artifact $Artifact -Port $Port -Ctx $Ctx -Kv $Kv -Spec $Spec -K $K -WaitSec $WaitSec 2>$null
      try { $s = $startOut | ConvertFrom-Json } catch { $rows += @{ value = $v; ok = $false; error = 'start failed'; raw = $startOut }; continue }
      if (-not $s.ok) { $rows += @{ value = $v; ok = $false; error = $s.error }; continue }
      $benchOut = & $PSCommandPath bench -Port $Port -Kind $Kind -Runs $Runs -MaxTokens $SweepTokens 2>$null
      try { $b = $benchOut | ConvertFrom-Json } catch { $b = $null }
      $null = & $PSCommandPath stop -Port $Port 2>$null
      $rows += @{ value = $v; ok = $true; median_tok_per_s_approx = $(if ($b) { $b.median_tok_per_s_approx } else { $null }) }
      Remove-Item Env:\NINFER_TERNARY_S8_MIN_TOKENS -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 3
    }
    Emit @{ ok = $true; kind = $Kind; sweep = $rows; how_to_read = 'higher median wins; a tie across all values means the env did not reach the engine (verify with rung= lines in the engine stderr log)' }
  }

  default { Fail 2 ('unknown command: ' + $Command) @{ commands = @('doctor','plan','start','status','stop','bench','sweep','must-do') } }
}
