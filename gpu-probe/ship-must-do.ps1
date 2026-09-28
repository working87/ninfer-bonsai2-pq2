# ship-must-do.ps1 -- install the machine-readable must-do list into ONE package.
#
# Produces, in the package root:
#   agent\must-do.json   single source of truth (copied from must-do.content.json)
#   agent\state.json     per-machine "what I already did" ledger (created empty, never overwritten)
#   MUST-DO.md           one-screen human-readable list, points at the json
#
# ASCII-only script on purpose: PowerShell 5.1 reads a BOM-less file as ANSI
# (codepage 936 here), so ANY Chinese text inside a .ps1 breaks the parser with
# nonsense "Missing ')' in method call" errors. All Chinese content lives in the
# two json data files and is read as UTF-8 bytes.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File ship-must-do.ps1 `
#       -Root <package root> -Content <must-do.content.json> -Labels <must-do.labels.json> [-Stamp 2026-09-27]
param(
  [string]$Root = '',
  [Parameter(Mandatory=$true)][string]$Content,
  [Parameter(Mandatory=$true)][string]$Labels,
  [string]$Stamp = ''
)
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
# ---- GUARD (2026-09-27): agent\must-do.json is the SINGLE SOURCE OF TRUTH ----
# It was edited directly (A3 promotion, KVMem default-off, path cleanup). This generator
# would overwrite it from the gpu-probe\must-do.*.json sources, which are now STALE.
# Only run it after folding your changes back into those sources.
if (-not $env:INFER_ALLOW_MUSTDO_REGEN) {
  Write-Host '[BLOCKED] ship-must-do.ps1 would overwrite agent\must-do.json from stale sources.'
  Write-Host '          Fold your changes into gpu-probe\must-do.*.json first, then set'
  Write-Host '          $env:INFER_ALLOW_MUSTDO_REGEN=1 and run again.'
  exit 3
}
$ErrorActionPreference = 'Stop'
[void][Reflection.Assembly]::LoadWithPartialName('System.Web.Extensions')
function Read-Utf8([string]$p) { return [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false))) }
function Write-Utf8([string]$p, [string]$t) { [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false))) }

$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not (Test-Path -LiteralPath $Content)) { throw ('content file not found: ' + $Content) }
if (-not (Test-Path -LiteralPath $Labels))  { throw ('labels file not found: '  + $Labels) }

$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue

$raw = Read-Utf8 $Content
$L   = $ser.DeserializeObject((Read-Utf8 $Labels))
$data = $ser.DeserializeObject($raw)

if (-not $Stamp) {
  if ($raw -match '"version"\s*:\s*"([^"]+)"') { $Stamp = $Matches[1] } else { $Stamp = (Get-Date -Format 'yyyy-MM-dd') }
}
if ($raw -match '"generated"') { $raw = $raw -replace '"generated"\s*:\s*"[^"]*"', ('"generated": "' + $Stamp + '"') }

$agentDir = Join-Path $Root 'agent'
if (-not (Test-Path -LiteralPath $agentDir)) { throw ('no agent directory in ' + $Root) }

Write-Utf8 (Join-Path $agentDir 'must-do.json') $raw
Write-Host ('WROTE ' + (Join-Path $agentDir 'must-do.json'))

# ---- state.json: the per-machine ledger. Never overwrite an existing one. ----
$statePath = Join-Path $agentDir 'state.json'
if (-not (Test-Path -LiteralPath $statePath)) {
  $machine = $env:COMPUTERNAME
  $state = @"
{
  "_what": "must-do state ledger: what has already been done / verified ON THIS MACHINE, with evidence",
  "_why": "so the next agent does not repeat work, and does not believe work was done when it was not",
  "_how_to_write": "append to done[] : {\"id\":\"E1\",\"at\":\"<ISO8601>\",\"evidence\":\"<sha256 or log path>\",\"note\":\"...\"}. This file is MEANT to be written.",
  "_machine": "$machine",
  "done": [],
  "skipped": [],
  "notes": []
}
"@
  Write-Utf8 $statePath $state
  Write-Host ('WROTE ' + $statePath + '  (empty ledger)')
} else {
  Write-Host ('KEPT  ' + $statePath + '  (already exists)')
}

# ---- MUST-DO.md ----
$tier = Split-Path $Root -Leaf
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine(([string]$L['h1']).Replace('{tier}', $tier).Replace('{stamp}', $Stamp))
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['why'])
[void]$sb.AppendLine([string]$L['why2'])
[void]$sb.AppendLine([string]$L['why3'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['conflict_title'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['conflict'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['legend_title'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['tbl_head'])
[void]$sb.AppendLine([string]$L['tbl_sep'])
foreach ($c in @('A','B','C','D','E','F')) {
  [void]$sb.AppendLine('| **' + $c + '** | ' + [string]$L['cls'][$c] + ' | ' + [string]$L['cls_act'][$c] + ' |')
}
[void]$sb.AppendLine('')
$counts = @{}
$total = 0
$byLevel = @{}
$byTier = @{}
$costByTier = @{}

# ---- collect first (the staircase needs the tier buckets, so it must be rendered in a second pass)
$rowsBuf = New-Object System.Collections.ArrayList
foreach ($it in $data['items']) {
  $cls = [string]$it['class']
  if (-not $counts.ContainsKey($cls)) { $counts[$cls] = 0 }
  $counts[$cls] = $counts[$cls] + 1
  $total = $total + 1
  $lvl = [string]$it['evidence_level']
  $ordNo = [int]$it['order']
  $tierNo = [int]$it['order_tier']
  $tKey = [string]$tierNo
  if (-not ($byTier.ContainsKey($tKey))) { $byTier[$tKey] = New-Object System.Collections.ArrayList }
  [void]$byTier[$tKey].Add($it)
  $costByTier[$tKey] = [string]$it['cost']
  if (-not $byLevel.ContainsKey($lvl)) { $byLevel[$lvl] = New-Object System.Collections.ArrayList }
  [void]$byLevel[$lvl].Add([string]$it['id'])
  $rb = if ($it['rebuild_required']) { [string]$L['yes'] } else { [string]$L['no'] }
  $lvlTick = '`' + $lvl + '`'
  [void]$rowsBuf.Add('| ' + $ordNo + ' | **' + $it['id'] + '** | ' + $cls + ' | ' + $lvlTick + ' | ' + $it['title'] + ' | ' + $rb + ' | ' + [string]$it['applies_to'] + ' |')
}

# ---- THE ORDER STAIRCASE (rendered before the flat list: it is the "what do I do next" view) ----
[void]$sb.AppendLine([string]$L['order_title'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['order_head'])
[void]$sb.AppendLine([string]$L['order_sep'])
foreach ($tn in @(0,1,2,3,4,5,6)) {
  $key = [string]$tn
  if (-not ($byTier.ContainsKey($key))) { continue }
  $tItems = @($byTier[$key] | Sort-Object -Property @{ Expression = { [int]$_['order'] } })
  $ids = (@($tItems | ForEach-Object { [string]$_['id'] }) -join ' ')
  $row = [string]$L['order_row_fmt']
  $row = $row.Replace('{tier}', "$tn")
  $row = $row.Replace('{what}', [string]$L['tier_name'][$key])
  $row = $row.Replace('{cost}', [string]$L['cost_label'][[string]$costByTier[$key]])
  $row = $row.Replace('{ids}', $ids)
  [void]$sb.AppendLine($row)
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['order_note'])
[void]$sb.AppendLine([string]$L['moe_line'])
[void]$sb.AppendLine('')

# ---- flat list, already in `order` ----
[void]$sb.AppendLine([string]$L['list_title'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['list_head'])
[void]$sb.AppendLine([string]$L['list_sep'])
foreach ($r in $rowsBuf) { [void]$sb.AppendLine($r) }
[void]$sb.AppendLine('')
$summary = (@($counts.Keys | Sort-Object | ForEach-Object { $_ + '=' + $counts[$_] }) -join '  ')
[void]$sb.AppendLine((([string]$L['count_fmt']).Replace('{total}', "$total")).Replace('{summary}', $summary))
[void]$sb.AppendLine('')

# ---- evidence-level distribution: "what we measured" vs "what we only guess", at a glance ----
[void]$sb.AppendLine([string]$L['level_counts_title'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['level_head'])
[void]$sb.AppendLine([string]$L['level_sep'])
foreach ($lvl in @('measured','author','hypothesis','pending')) {
  if (-not $byLevel.ContainsKey($lvl)) { continue }
  $ids = @($byLevel[$lvl])
  $lvlTick2 = '`' + $lvl + '`'
  [void]$sb.AppendLine('| ' + $lvlTick2 + ' | ' + $ids.Count + ' | ' + ($ids -join ', ') + ' |')
}
[void]$sb.AppendLine('')

# ---- per-card guidance: card -> applies_to_ids -> evidence level ----
[void]$sb.AppendLine(([string]$L['card_title']))
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['card_note'])
[void]$sb.AppendLine([string]$L['card_note2'])
[void]$sb.AppendLine('')
$cards = @($data['card_guidance']['cards'])
foreach ($series in @('50','40','30','laptop','lowvram')) {
  $group = @($cards | Where-Object { [string]$_['series'] -eq $series })
  if ($group.Count -eq 0) { continue }
  $label = [string]$L['card_series_label'][$series]
  [void]$sb.AppendLine((([string]$L['cards_title']).Replace('{series_label}', $label)))
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine([string]$L['card_head'])
  [void]$sb.AppendLine([string]$L['card_sep'])
  foreach ($c in $group) {
    $smv = [string]$c['sm']
    $sm = [string]$L['sm_pending']
    if ($smv) { $sm = $smv }
    $ids = (@($c['applies_to_ids']) -join ' ')
    $cTick = '`' + [string]$c['evidence_level'] + '`'
    [void]$sb.AppendLine('| ' + $c['card'] + ' | ' + $sm + ' | ' + $ids + ' | ' + $cTick + ' |')
  }
  [void]$sb.AppendLine('')
}

[void]$sb.AppendLine([string]$L['footer_title'])
[void]$sb.AppendLine('')
[void]$sb.AppendLine([string]$L['foot1'])
[void]$sb.AppendLine([string]$L['foot2'])
[void]$sb.AppendLine([string]$L['foot3'])
[void]$sb.AppendLine([string]$L['foot4'])
[void]$sb.AppendLine([string]$L['foot5'])
[void]$sb.AppendLine('')
Write-Utf8 (Join-Path $Root 'MUST-DO.md') $sb.ToString()
Write-Host ('WROTE ' + (Join-Path $Root 'MUST-DO.md') + '  (' + $total + ' items, ' + $cards.Count + ' cards)')
