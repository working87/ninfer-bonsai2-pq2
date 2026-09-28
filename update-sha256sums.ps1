# update-sha256sums.ps1 -- recompute a package's SHA256SUMS.txt (never hand-edit it)
#
# Why it exists: we just added gpu-probe.exe to the package root, and hand-editing
# SHA256SUMS always misses or mistypes an entry. This script rewrites the whole
# file in the EXISTING format:
#     "HASH   relative\path"   (64 uppercase hex, TWO spaces, backslash, no BOM, CRLF)
# The file set comes from the OLD manifest (so extra scratch files never sneak in);
# new files must be passed explicitly with -Add.
#
# ASCII-only on purpose (same reason as 自检-*.ps1): a BOM-less file with Chinese
# text gets read as ANSI by PowerShell 5.1 and the parser dies with nonsense errors.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File update-sha256sums.ps1 -Root <pkg root>
#     [-Add <relpath>]...   # extra files to include (repeatable)
#     [-Prune]              # instead: take the on-disk file list as the truth
#     [-Check]              # verify only, write nothing; exit 1 when there is drift
param(
  [string]$Root = '',
  [string[]]$Add = @(),
  [switch]$Prune,
  [switch]$Check
)
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path -LiteralPath $Root).Path
$sums = Join-Path $Root 'SHA256SUMS.txt'

# --- 1) read the old manifest to learn which paths it tracks ---
$old = @()
if (Test-Path -LiteralPath $sums) {
  foreach ($line in [IO.File]::ReadAllLines($sums)) {
    if ($line -match '^\s*([0-9A-Fa-f]{64})\s\s(.+?)\s*$') { $old += $Matches[2] }
  }
} else {
  Write-Host ('[warn] no existing manifest, generating from disk: ' + $sums)
}

$paths = New-Object System.Collections.Generic.List[string]
if ($Prune -or $old.Count -eq 0) {
  $onDisk = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
      Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
      ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\') })
  $paths.AddRange([string[]]$onDisk)
} else {
  foreach ($p in $old) { $paths.Add($p) }
}
foreach ($p in $Add) { if (-not $paths.Contains($p)) { $paths.Add($p) } }

# --- 2) hash every entry ---
$rows = @()
$missing = @()
foreach ($rel in ($paths | Sort-Object -Unique)) {
  $full = Join-Path $Root $rel
  if (-not (Test-Path -LiteralPath $full)) { $missing += $rel; continue }
  $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
  $rows += [pscustomobject]@{ Hash = $h; Rel = $rel }
}

# --- 3) diff against the old manifest ---
$oldMap = @{}
if (Test-Path -LiteralPath $sums) {
  foreach ($line in [IO.File]::ReadAllLines($sums)) {
    if ($line -match '^\s*([0-9A-Fa-f]{64})\s\s(.+?)\s*$') { $oldMap[$Matches[2]] = $Matches[1].ToUpperInvariant() }
  }
}
$changed = @(); $added = @(); $dropped = @()
foreach ($r in $rows) {
  if (-not $oldMap.ContainsKey($r.Rel)) { $added += $r.Rel; continue }
  if ($oldMap[$r.Rel] -ne $r.Hash) { $changed += $r.Rel }
}
$rels = @($rows | ForEach-Object { $_.Rel })
foreach ($k in $oldMap.Keys) { if ($rels -notcontains $k) { $dropped += $k } }

Write-Host ('root    = ' + $Root)
Write-Host ('entries = ' + $rows.Count + '  changed = ' + $changed.Count + '  added = ' + $added.Count + '  dropped = ' + $dropped.Count + '  missing = ' + $missing.Count)
foreach ($x in $changed) { Write-Host ('  CHANGED  ' + $x) }
foreach ($x in $added)   { Write-Host ('  ADDED    ' + $x) }
foreach ($x in $dropped) { Write-Host ('  DROPPED  ' + $x) }
foreach ($x in $missing) { Write-Host ('  MISSING  ' + $x) }

if ($Check) {
  if ($changed.Count -or $added.Count -or $dropped.Count -or $missing.Count) { exit 1 } else { exit 0 }
}

# --- 4) write back (CRLF, UTF-8 without BOM -- same as the existing file) ---
$sb = New-Object System.Text.StringBuilder
foreach ($r in $rows) { [void]$sb.Append($r.Hash).Append('  ').Append($r.Rel).Append("`r`n") }
[IO.File]::WriteAllText($sums, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('WROTE ' + $sums + '  (' + $rows.Count + ' lines)')
