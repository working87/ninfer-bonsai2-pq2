param([string]$Tier = '')
$ErrorActionPreference = 'Stop'
$agentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $agentDir
if (-not $Tier) { $Tier = Split-Path $root -Leaf }
$built = (Get-Date).ToString('yyyy-MM-dd')

function Info([string]$rel) {
  $p = Join-Path $root $rel
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $i = Get-Item -LiteralPath $p
  return [ordered]@{ file = ($rel -replace '\\','/'); size = $i.Length; sha256 = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
}

$engines = @()
$e1 = Info 'engine\ninfer-serve.exe'
if ($e1) { $engines += ([ordered]@{ arch='sm_89'; cards='RTX 40 series (Ada, compute capability 8.9)' } + $e1) }
$e2 = Info 'engine\ninfer-serve-sm120.exe'
if ($e2) { $engines += ([ordered]@{ arch='sm_120a'; cards='RTX 50 series (Blackwell, compute capability 12.0)' } + $e2) }

$artifacts = @()
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $root 'model') -File -Filter '*.ninfer' -ErrorAction SilentlyContinue | Sort-Object Name)) {
  $kind = 'base'
  $spec = 'mtp (draft head lives inside the artifact)'
  if ($f.Name -match 'dflash2') { $kind = 'dflash2'; $spec = 'dflash2 only; --lm-head-draft is MANDATORY' }
  elseif ($f.Name -match 'ptq1') { $kind = 'ptq1'; $spec = 'mtp; PTQ1_0 quantization class (the balanced tier)' }
  $i = Info ('model\' + $f.Name)
  if ($i) { $artifacts += ([ordered]@{ kind=$kind; spec_options=$spec } + $i) }
}

$eps = [ordered]@{}
foreach ($pair in @(
  @('agent_cli',             'agent\ninfer-agent.ps1'),
  @('manifest_generator',    'agent\gen-manifest.ps1'),
  @('launcher_check',        '自检-启动件.ps1'),
  @('engine_card_selfcheck', '自检-引擎与卡匹配.ps1'),
  @('rung_probe',            '档位探针.ps1')
)) {
  if (Test-Path -LiteralPath (Join-Path $root $pair[1])) { $eps[$pair[0]] = ($pair[1] -replace '\\','/') }
}

$exitCodes = [ordered]@{ '0'='ok'; '2'='bad usage'; '3'='artifact missing'; '4'='no engine matches this card'; '5'='context does not fit in VRAM'; '6'='engine did not become ready (or, in agent mode, a prompt was needed)'; '7'='not running'; '8'='request failed'; '9'='nvidia-smi unusable' }

$configMatrix = @(
  [ordered]@{ vram_mib_min=30000; artifact='dflash2'; spec='dflash2'; draft_tokens=7; ctx=131072; kv='fp8'; lm_head_draft=$true;  note='best measured configuration on a 32 GB 50-series card: 512.9 t/s on highly predictable content, 154.7 t/s on prose' }
  [ordered]@{ vram_mib_min=20000; artifact='dflash2'; spec='dflash2'; draft_tokens=7; ctx=131072; kv='fp8'; lm_head_draft=$true;  note='dflash2 weights are about 10.2 GiB; 131072 needs about 4 GiB of fp8 KV' }
  [ordered]@{ vram_mib_min=15000; artifact='dflash2'; spec='dflash2'; draft_tokens=5; ctx=32768;  kv='fp8'; lm_head_draft=$true;  note='16 GB cards: keep ctx at 32768 and use K=5' }
  [ordered]@{ vram_mib_min=0;     artifact='base';    spec='mtp';     draft_tokens=3; ctx=16384;  kv='fp8'; lm_head_draft=$false; note='small cards: MTP drafts 3 tokens; 4-bit KV (rk4v4 on 8.9, nvfp4 on 12.0) halves the KV term when ctx must grow' }
)

$envSwitches = @(
  [ordered]@{ name='NINFER_AGENT_CC'; default='(unset)'; rebuild_required=$false; effect='forces the card family in every start-*.bat (8.9 or 12.0) and removes the interactive prompt entirely' }
  [ordered]@{ name='NINFER_AGENT'; default='(unset)'; rebuild_required=$false; effect='set to 1: the .bat files stop on nothing (no pause; a needed prompt becomes a hard error, exit 6)' }
  [ordered]@{ name='NINFER_TERNARY_S8_MIN_TOKENS'; default='33'; rebuild_required=$false; effect='int8 rung admission threshold. The crossing point is a property of the CARD (66-SM Ada about 17; 76-SM Ada about 32-40), so it must be measured per card. Same-binary A/B.' }
  [ordered]@{ name='NINFER_TERNARY_WIDE_MIN_TOKENS'; default='41'; rebuild_required=$false; effect='wide-tile (bf16 mma) admission threshold; same-binary A/B' }
  [ordered]@{ name='NINFER_TERNARY_S8'; default='on'; rebuild_required=$false; effect='0 disables the whole int8 rung (changes numerics; A/B only)' }
  [ordered]@{ name='NINFER_TERNARY_S8_DEBUG'; default='off'; rebuild_required=$false; effect='1 prints one stderr line per ternary call naming the rung actually taken plus the admission bits; pair with _DEBUG_MIN_T and _DEBUG_BUDGET' }
  [ordered]@{ name='NINFER_TERNARY_MMA'; default='on'; rebuild_required=$false; effect='0 disables every tensor-core rung, forcing the SIMT fallback (slower); diagnostic only' }
  [ordered]@{ name='NINFER_TERNARY_PTQ1_FAST'; default='on'; rebuild_required=$false; effect='0 with a PTQ1 artifact rejects the mma rungs and is silently slower' }
  [ordered]@{ name='NINFER_SM_COUNT'; default='170 via arch 120a'; rebuild_required=$true; effect='compile-time kTargetSmCount used for wave/occupancy. 120a implies 170 (RTX 5090); other 50-series cards need -DNINFER_SM_COUNT=<their SM count> plus a rebuild. The size of the gain is NOT measured.' }
)

$faults = @(
  [ordered]@{ symptom='exits immediately, prints nothing'; cause='engine arch does not match the card (sm_89 on a 50-series card or sm_120 on a 40-series card), or the 7 ffmpeg dlls are missing next to the exe'; action='run doctor; start with the engine whose arch matches the reported compute capability; keep exe and dlls together' }
  [ordered]@{ symptom='one CPU core near 95 percent, GPU idle, no output'; cause='same arch mismatch: the engine spins instead of failing cleanly'; action='kill it, run doctor, use the matching engine' }
  [ordered]@{ symptom='FATAL server failed during startup | capacity'; cause='the requested context does not fit in VRAM'; action='lower --max-context, or use a 4-bit KV dtype (rk4v4 on 8.9, nvfp4 on 12.0)' }
  [ordered]@{ symptom='linear_topk: unsupported head profile'; cause='a dflash2 artifact was started without --lm-head-draft'; action='add --lm-head-draft (mandatory for dflash2)' }
  [ordered]@{ symptom="kv-dtype 'rk4v4' requires compute capability 8.9"; cause='Ada-only KV dtype requested on a Blackwell card'; action='use fp8 (both arches) or nvfp4 (12.0 only)' }
  [ordered]@{ symptom='candidate token ledger does not match prompt length, then 503 inference engine is unavailable'; cause='old engine binary: the prefix-reuse ledger guard is wrong and only fires on the SECOND request reusing the same prefix'; action='use the engine in this package (fixed builds reproduce 200/200/200 where the old build gave 200/500/503)' }
  [ordered]@{ symptom='Option noheader is not recognized, and the card is then called unsupported'; cause='old launcher: --format=csv,noheader inside for /f is split into two arguments'; action='use this package launchers, or run the launcher self-check' }
  [ordered]@{ symptom='a stray file appears next to the launcher (for example about or 128K)'; cause='banner echo contained an unescaped > which cmd treated as redirection'; action='use this package launchers, or run the launcher self-check' }
  [ordered]@{ symptom='. was unexpected at this time, launcher stops'; cause='an unescaped ) in an echo line inside an if-block closes the block early'; action='use this package launchers, or run the launcher self-check' }
  [ordered]@{ symptom='FATAL ... [json.exception.type_error.316] invalid UTF-8 byte 0xBC, or a CreateFileW that shows question marks where your path has CJK'; cause='a path handed to the engine contains non-ASCII characters. The model path cannot be opened at all; a --request-log-jsonl path crashes the JSON writer because those bytes are GBK, not UTF-8. Measured twice on 2026-09-26'; action='keep the whole package on an ASCII path (any drive and folder name, as long as no CJK appears anywhere above it); the agent CLI already forces its own logs into %TEMP%\ninfer-agent-logs and refuses a non-ASCII artifact path with exit 5' }
  [ordered]@{ symptom='bench shows a low first run and normal later runs (for example 62 then 212 t/s)'; cause='the first request after a cold start runs while the GPU clocks are still ramping'; action='discard the first run and take the median of at least three; the agent CLI reports every run so the pattern is visible' }
  [ordered]@{ symptom='engine path not found, the launcher reports no such command'; cause='the executable is ninfer-serve.exe (with the n), not infer-serve.exe'; action='run the launcher self-check, which now compares every ENGINE= path against the real files in engine\' }
  [ordered]@{ symptom='two arms that should differ return the same number'; cause='most often the arm never ran (env not applied, wrong binary, value ignored)'; action='prove the arm with the rung probe before believing a tie' }
)

$invariants = @(
  'Report the content kind with every number: the same card differs by up to 3x between highly predictable content and prose/code.',
  'Report the accept rate with every number. Throughput = step-rate x (1 + K x accept-rate). Step-rate belongs to the card; accept-rate belongs to the content and reproduces to the exact integer across cards.',
  'A/B on ONE binary whenever an env switch exists. When only a rebuild can change the value, alternate the two binaries and verify both sha256 values. Never run them sequentially and call the difference a result.',
  'Discard the first run after a cold start (clocks ramp), then take the median of at least three alternating runs.',
  'Long prompt (at least 1k tokens) and long output (at least 400 tokens), greedy decoding.',
  'The engine log is the authoritative source: read the req#N done line (decode X tok/s, accepted a/b (p percent), cache hit, TTFT) from the stderr log that start returns. The HTTP-side timing includes prefill and the first-token wait, so it understates decode.'
  'Cross-card absolute numbers are not comparable. Cross-card accept rates are.'
)

$anchors = @(
  [ordered]@{ card='RTX 4080 SUPER (ours, sm_89, 76 SM)'; kind='counting'; config='dflash2 K=7'; tok_per_s='353.8'; accept='-'; source='our measurement' }
  [ordered]@{ card='RTX 4080 SUPER (ours)'; kind='prose'; config='dflash2 K=7'; tok_per_s='112.1'; accept='-'; source='our measurement' }
  [ordered]@{ card='RTX 4080 SUPER (ours)'; kind='counting'; config='MTP d4'; tok_per_s='211.9'; accept='-'; source='our measurement' }
  [ordered]@{ card='RTX 4080 SUPER (ours)'; kind='counting'; config='no speculation'; tok_per_s='63.7'; accept='-'; source='our measurement' }
  [ordered]@{ card='RTX 5090 D (volunteer, sm_120, 32 GB)'; kind='counting'; config='dflash2 K=7'; tok_per_s='512.9'; accept='522/533 (97.9%)'; source='volunteer, no rebuild' }
  [ordered]@{ card='RTX 5090 D (volunteer)'; kind='prose'; config='dflash2 K=7'; tok_per_s='154.7'; accept='346/1763 (19.6%)'; source='volunteer' }
  [ordered]@{ card='RTX 5090 D (volunteer)'; kind='counting'; config='MTP (best)'; tok_per_s='343.8'; accept='-'; source='volunteer' }
  [ordered]@{ card='RTX 5090 D (volunteer)'; kind='counting'; config='MTP d3 (what we first shipped)'; tok_per_s='250-268'; accept='447/454 -> 522/533 (98.5%, cross-card)'; source='volunteer' }
)

$never = @(
  'drive a .bat interactively from an agent',
  'trust a tie between two arms without proving the arm ran',
  'report a number without content kind and accept rate',
  'assume the engine matches the card without doctor'
)

$manifest = [ordered]@{
  schema = 'ninfer-agent-manifest/1'
  package = [ordered]@{ tier = $Tier; built = $built; root = '.'; audience = 'agent' }
  audience_note = 'Built for an agent to drive. The .bat banners are a fallback; never drive them interactively.'
  entrypoints = $eps
  supported_compute_caps = @('8.9','12.0')
  engines = $engines
  artifacts = $artifacts
  commands = [ordered]@{
    doctor = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 doctor'
    plan   = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 plan -Artifact auto'
    start  = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 start -Artifact auto -Port <p> [-Ctx <n>] [-Kv auto|fp8|nvfp4|rk4v4|k8v4|int8|bf16] [-Spec auto|mtp|dflash2|none] [-K <n>]'
    status = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 status -Port <p>'
    stop   = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 stop -Port <p>'
    bench  = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 bench -Port <p> -Kind code|prose|counting -Runs 3'
    sweep  = 'powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 sweep -Port <p> -Kind code -Values 17,24,33,48'
  }
  exit_codes = $exitCodes
  config_matrix = $configMatrix
  env_switches = $envSwitches
  faults = $faults
  invariants = $invariants
  perf_anchors = $anchors
  routing = [ordered]@{
    first_step = 'doctor'
    then = 'plan, start, bench on the same port, stop'
    on_coding_workloads = 'bench -Kind code: accept-rate-limited content. Expect about one third of the predictable-content rate; tune K through 1 + K x accept, not by K alone'
    on_tuning = 'sweep for the int8 threshold (same binary); NINFER_TERNARY_WIDE_MIN_TOKENS is a plain env A/B'
    never = $never
  }
}
$jsonPath = Join-Path $agentDir 'manifest.json'
[IO.File]::WriteAllText($jsonPath, ($manifest | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

$md = New-Object Collections.Generic.List[string]
$md.Add('# AGENT.md -- machine interface for this package')
$md.Add('')
$md.Add('tier `' + $Tier + '` | generated ' + $built + ' | machine copy: `agent/manifest.json` (same facts, parseable)')
$md.Add('')
$md.Add('**This package is built for an AGENT to drive.** The `.bat` files are a fallback and they are agent-safe now:')
$md.Add('`NINFER_AGENT=1` suppresses every pause and turns a needed prompt into a hard error (exit 6);')
$md.Add('`NINFER_AGENT_CC=8.9|12.0` removes card detection entirely. The supported interface is')
$md.Add('`agent/ninfer-agent.ps1`: no prompts, JSON on stdout, distinct exit codes.')
$md.Add('')
$md.Add('## 1. Drive it in five calls')
$md.Add('```')
$md.Add('powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 doctor')
$md.Add('powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 plan   -Artifact auto')
$md.Add('powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 start  -Artifact auto -Port 8096')
$md.Add('powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 bench  -Port 8096 -Kind code -Runs 3')
$md.Add('powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 stop   -Port 8096')
$md.Add('```')
$ec = @()
foreach ($k in $exitCodes.Keys) { $ec += ($k + '=' + $exitCodes[$k]) }
$md.Add('Exit codes: ' + ($ec -join ', '))
$md.Add('')
$md.Add('## 2. What is here (hashes are the truth)')
$md.Add('')
$md.Add('| file | role | bytes | sha256 |')
$md.Add('|---|---|---|---|')
foreach ($e in $engines)   { $md.Add('| `' + $e.file + '` | engine ' + $e.arch + ' (' + $e.cards + ') | ' + $e.size + ' | `' + $e.sha256 + '` |') }
foreach ($a in $artifacts) { $md.Add('| `' + $a.file + '` | artifact ' + $a.kind + ' | ' + $a.size + ' | `' + $a.sha256 + '` |') }
$md.Add('')
$md.Add('## 3. Configuration from measured facts, not taste')
$md.Add('')
$md.Add('| VRAM at least | artifact | spec | K | ctx | KV | lm-head-draft | note |')
$md.Add('|---|---|---|---|---|---|---|---|')
foreach ($c in $configMatrix) { $md.Add('| ' + $c.vram_mib_min + ' MiB | ' + $c.artifact + ' | ' + $c.spec + ' | ' + $c.draft_tokens + ' | ' + $c.ctx + ' | ' + $c.kv + ' | ' + $c.lm_head_draft + ' | ' + $c.note + ' |') }
$md.Add('')
$md.Add('## 4. Fault routing (each of these has already been diagnosed once)')
$md.Add('')
$md.Add('| symptom | cause | action |')
$md.Add('|---|---|---|')
foreach ($f in $faults) { $md.Add('| ' + $f.symptom + ' | ' + $f.cause + ' | ' + $f.action + ' |') }
$md.Add('')
$md.Add('## 5. Switches (the rebuild column says how the value can be changed)')
$md.Add('')
$md.Add('| name | default | rebuild needed | effect |')
$md.Add('|---|---|---|---|')
foreach ($s in $envSwitches) {
  $rb = 'no'
  if ($s.rebuild_required) { $rb = '**yes**' }
  $md.Add('| `' + $s.name + '` | ' + $s.default + ' | ' + $rb + ' | ' + $s.effect + ' |')
}
$md.Add('')
$md.Add('## 6. Measurement invariants (violating these yields confident nonsense)')
$md.Add('')
foreach ($i in $invariants) { $md.Add('- ' + $i) }
$md.Add('')
$md.Add('## 7. Performance anchors -- is this machine normal?')
$md.Add('')
$md.Add('| card | content | config | t/s | accept | source |')
$md.Add('|---|---|---|---|---|---|')
foreach ($a in $anchors) { $md.Add('| ' + $a.card + ' | ' + $a.kind + ' | ' + $a.config + ' | ' + $a.tok_per_s + ' | ' + $a.accept + ' | ' + $a.source + ' |') }
$md.Add('')
$md.Add('## 8. Never')
$md.Add('')
foreach ($n in $never) { $md.Add('- ' + $n) }
$md.Add('')
$mdPath = Join-Path $agentDir 'AGENT.md'
[IO.File]::WriteAllLines($mdPath, $md, (New-Object Text.UTF8Encoding($true)))
Write-Host ('  manifest.json ' + [math]::Round((Get-Item -LiteralPath $jsonPath).Length/1KB,1) + ' KB ; AGENT.md ' + [math]::Round((Get-Item -LiteralPath $mdPath).Length/1KB,1) + ' KB')
