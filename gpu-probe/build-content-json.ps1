# build-content-json.ps1 -- assemble agent\must-do.json from the pieces under lib\:
#   must-do.base.json       the existing items (id/title/class/why/how/judgement/evidence/artifact)
#   must-do.extra.json      items added later (B5: weight selection)
#   must-do.levels.json     id -> evidence_level + evidence_source (per-item grading)
#   card-guidance.json      per-card guidance for 40/50 series (+ laptop, + lowvram)
#   card-guidance-30.json   per-card guidance for the 30 series (framework, mostly pending)
#
# Why: "what we measured" and "what we only guess" must never be confusable again, and every card
# must get its own entry point. Both live in the json, so an agent reads them without any document.
#
# ASCII-only script: ALL Chinese lives in the json inputs, read/written as UTF-8 bytes.
#
# THREE PowerShell traps this script hit (each looked like a data bug, each cost a round):
#  1) PARAMETER SHADOWING: parameter names are case-INsensitive, so `$base = ...` silently
#     overwrote the -Base parameter (a String) and `$base['items']` then indexed that string ->
#     the character 'i'. Hence the Obj-suffixed names. Never reuse a parameter name as a local.
#  2) `$id` collides with the automatic $PID and reads back empty.
#  3) Do not hand JavaScriptSerializer a PSObject graph (ConvertFrom-Json output): it dies with
#     "A circular reference was detected while serializing an object of type
#     'System.Management.Automation.PSParameterizedProperty'". Build plain .NET objects, or
#     serialise with ConvertTo-Json. This script uses ConvertTo-Json.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File build-content-json.ps1 -Lib <dir> -Out <must-do.content.json> [-Stamp 2026-09-27]
param(
  [string]$Lib,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$Stamp = '2026-09-27'
)
# --- self-location: never depends on the caller current directory ---
if (-not $Lib) { $Lib = $PSScriptRoot }
$ErrorActionPreference = 'Stop'
[void][Reflection.Assembly]::LoadWithPartialName('System.Web.Extensions')
function Read-Utf8([string]$p) { return [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false))) }
function Write-Utf8([string]$p, [string]$t) { [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false))) }
$js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$js.MaxJsonLength = [int]::MaxValue

$baseObj   = $js.DeserializeObject((Read-Utf8 (Join-Path $Lib 'must-do.base.json')))
# $extraObj comes back as a fixed-size array, so copy it into a growable list first
$extraList = New-Object System.Collections.ArrayList
foreach ($e in @($js.DeserializeObject((Read-Utf8 (Join-Path $Lib 'must-do.extra.json'))))) { [void]$extraList.Add($e) }
# F-class items live in their own file so the A/B/C/D/E set stays untouched.
$extraFPath = Join-Path $Lib 'must-do.extra-F.json'
if (Test-Path -LiteralPath $extraFPath) {
  foreach ($fItem in @($js.DeserializeObject((Read-Utf8 $extraFPath)))) { [void]$extraList.Add($fItem) }
}
$extraObj = $extraList
$lvObj     = $js.DeserializeObject((Read-Utf8 (Join-Path $Lib 'must-do.levels.json')))
$guideObj  = $js.DeserializeObject((Read-Utf8 (Join-Path $Lib 'card-guidance.json')))
$guide30   = $js.DeserializeObject((Read-Utf8 (Join-Path $Lib 'card-guidance-30.json')))
$levelMap  = $lvObj['level']
$srcMap    = $lvObj['source']

# ---- 1) items = base + extra, each stamped with its evidence grade ----
$itemList = New-Object System.Collections.ArrayList
foreach ($it in $baseObj['items']) { [void]$itemList.Add($it) }
foreach ($it in $extraObj)         { [void]$itemList.Add($it) }
foreach ($it in $itemList) {
  $nid = [string]$it['id']
  $nclass = [string]$it['class']
  if ($nid -eq '' -or $nclass -eq '') { throw ('item without id/class: x=' + $it) }
  if ($levelMap[$nid]) {
    $it['evidence_level'] = $levelMap[$nid]
    $it['evidence_source'] = $srcMap[$nid]
  } else {
    throw ('no evidence_level for item [' + $nid + ']')
  }
}

# ---- 1b) ORDER: stamp every item with `order` (and prepend its cost label to `how`) ----
# The user asked for the list to be sorted by "biggest win x shortest time", so the order lives in
# its own data file (must-do.order.json) and is materialised onto each item here.
$orderPath = Join-Path $Lib 'must-do.order.json'
$orderList = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $orderPath) {
  $orderObj = $js.DeserializeObject((Read-Utf8 $orderPath))
  $howPre = @{}
  foreach ($k in @($orderObj['item_how_prefix'].Keys)) { $howPre[[string]$k] = [string]$orderObj['item_how_prefix'][$k] }
  $byId = @{}
  foreach ($o in @($orderObj['items'])) { $byId[[string]$o['id']] = $o }
  foreach ($it in $itemList) {
    $oid = [string]$it['id']
    if (-not $byId.ContainsKey($oid)) { throw ('item [' + $oid + '] has no entry in must-do.order.json') }
    $it['order'] = [int]$byId[$oid]['order']
    $it['order_tier'] = [int]$byId[$oid]['tier']
    $it['cost'] = [string]$byId[$oid]['cost']
    $pre = ''
    if ($howPre.ContainsKey([string]$it['cost'])) { $pre = $howPre[[string]$it['cost']] + "`n" }
    $it['how'] = $pre + [string]$it['how']
  }
  # stable sort by order (ArrayList.Sort with a comparison delegate)
  $sorted = $itemList | Sort-Object -Property @{ Expression = { [int]$_['order'] } }
  $itemList = New-Object System.Collections.ArrayList
  foreach ($s in $sorted) { [void]$itemList.Add($s) }
  $o2 = $orderObj['tiers']
  $rootOrderTiers = [ordered]@{}
  foreach ($k in @('0','1','2','3','4','5','6')) { $rootOrderTiers[$k] = [string]$o2[$k] }
}

# ---- 2) cards = 40/50 (with laptop + lowvram) + 30 series; every card graded ----
$cardList = New-Object System.Collections.ArrayList
foreach ($c in $guideObj['cards']) { [void]$cardList.Add($c) }
foreach ($c in $guide30)           { [void]$cardList.Add($c) }
foreach ($c in $cardList) {
  if (-not $c['evidence_level']) { $c['evidence_level'] = 'measured' }
  if (-not $c['applies_to_ids']) { throw ('card without applies_to_ids: ' + $c['card']) }
  if (-not $c['series'])         { throw ('card without series: ' + $c['card']) }
}

# ---- 3) root object, keys in a fixed readable order ----
$rootObj = [pscustomobject][ordered]@{
  schema = $baseObj['schema']
  version = $Stamp
  why = $baseObj['why']
  rule = $baseObj['rule']
  classes = $baseObj['classes']
  class_meanings = $lvObj['class_meanings']
  order_tiers = $rootOrderTiers
  applies_to_note = $baseObj['applies_to_note']
  evidence_levels = $guideObj['evidence_levels']
  levels_note = $guideObj['levels_note']
  unmeasured_gap_estimate = $guideObj['unmeasured_gap_estimate']
  conflict_policy = $guideObj['conflict_policy']
  items = $itemList
  card_guidance = [pscustomobject][ordered]@{ cards = $cardList }
}
$jsonText = $rootObj | ConvertTo-Json -Depth 14
Write-Utf8 $Out $jsonText

# ---- 4) validate with the SAME parser the agent uses ----
$chk = $js.DeserializeObject((Read-Utf8 $Out))
$nItems = @($chk['items']).Count
$nCards = @($chk['card_guidance']['cards']).Count
$graded = 0
foreach ($it in $chk['items']) { if ($it['evidence_level']) { $graded++ } }
$cardGraded = 0
foreach ($c in $chk['card_guidance']['cards']) { if ($c['evidence_level']) { $cardGraded++ } }
$s30 = @($chk['card_guidance']['cards'] | Where-Object { [string]$_['series'] -eq '30' }).Count
Write-Host ('WROTE ' + $Out)
Write-Host ('  items=' + $nItems + ' graded=' + $graded + ' | cards=' + $nCards + ' graded=' + $cardGraded + ' (30series=' + $s30 + ') | chars=' + $jsonText.Length)
if ($nCards -lt 25)          { throw ('card_guidance has only ' + $nCards + ' cards; expected >= 25') }
if ($s30 -lt 9)              { throw ('30-series cards = ' + $s30 + '; expected >= 9') }
if ($graded -ne $nItems)     { throw ('only ' + $graded + '/' + $nItems + ' items carry evidence_level') }
if ($cardGraded -ne $nCards) { throw ('only ' + $cardGraded + '/' + $nCards + ' cards carry evidence_level') }
