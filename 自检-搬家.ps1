<#
自检-搬家.ps1 —— **路径无关 / 可搬运性自检**（发布前门禁，也是接手后的第一条命令）

为什么有它：这个包会被下载到**任意目录、任意盘**（可能改名、可能放在中文路径下）。
所以包内**不许有绝对路径**、**不许引用包外文件**、**每个脚本必须自定位**。
这份脚本把"能不能搬"从"希望"变成**可验证事实**。

用法（在包根、或任意目录、或别的盘，都一样）：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\自检-搬家.ps1

判据（五项全 PASS 才 rc=0）：
  A 静态：包内文本件不得出现绝对路径（C:\ / D:\ / E:\ …）与包外引用
  B 静态：所有 .ps1 必须自定位（含 $PSScriptRoot）且能被 PowerShell 解析器解析
  C 静态：所有 .bat/.cmd 必须纯 ASCII（含非 ASCII 会让 cmd 撕碎命令；裸 LF 另警告）
  D 实测：把"小件"复制到临时目录，在副本里重跑 A/B/C ⇒ 证明换盘换目录后仍成立
  E 清单：SHA256SUMS.txt 存在，且按它自己的工具 -Check 通过（工具缺失时明确跳过并提示）

注意：engine\ / model\ / src-tree\ 是**二进制大件**，本检查只做"存在性"，不做路径扫描。
#>
[CmdletBinding()]
param(
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

# ---- 自定位：不依赖调用者当前目录（param() 默认值里 $PSScriptRoot 是空的，所以放这里）----
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = (Get-Location).Path }
$Root = (Resolve-Path -LiteralPath $Root).Path

$script:Fail = 0
$script:Warn = 0
function Say($m) { if (-not $Quiet) { Write-Host $m } }
function Pass($m) { Write-Host ("  [PASS] " + $m) }
function Fail($m) { Write-Host ("  [FAIL] " + $m) -ForegroundColor Red; $script:Fail++ }
function Warn($m) { Write-Host ("  [warn] " + $m) -ForegroundColor Yellow; $script:Warn++ }

# 文本件（会被引用检查的）与跳过的大目录
$TextExt = @('.md', '.json', '.txt', '.bat', '.cmd', '.ps1')
$SkipDir = @('src-tree', 'model', 'engine', '_dist', '.git')

function Get-SmallFiles([string]$base) {
  Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $rel = $_.FullName.Substring($base.Length).TrimStart('\')
      $top = ($rel -split '\\')[0]
      ($SkipDir -notcontains $top) -and ($TextExt -contains $_.Extension)
    }
}

# 绝对路径 / 包外引用（按行判，允许出现在"反例示例"里时由人工处理；这里一律报出）
# 正则写法（★ 别再多转义）：单引号 PS 字符串里的 \\ 就是"字面一个反斜杠"
$AbsPatterns = @(
  @{ name = '本机绝对路径'; rx = '[A-Za-z]:\\' },
  @{ name = 'UNC 路径';     rx = '\\\\[A-Za-z0-9]' },
  @{ name = '包外引用 E:\infer-docs';  rx = 'E:\\infer-docs' },
  @{ name = '包外引用 E:\infer-build'; rx = 'E:\\infer-build' },
  @{ name = '包外引用 E:\ninfer';      rx = 'E:\\ninfer' },
  @{ name = '包外引用 E:\视频';        rx = 'E:\\视频' }
)

function Test-StaticChecks([string]$base, [switch]$Report) {
  $files = Get-SmallFiles $base
  $absHits = @()
  $psNoSelf = @()
  $psBadParse = @()
  $batBadAscii = @()
  $batBareLf = @()

  foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    $rel = $f.FullName.Substring($base.Length).TrimStart('\')

    # 本检查脚本自己会写出绝对路径的"模式"字符串（自指），跳过它的 A 段
    if ($f.Name -ne '自检-搬家.ps1') {
      $isJson = ($f.Extension -eq '.json')
      $inFence = $false
      $line = 0
      foreach ($l in ($text -split "`n")) {
        $line++
        $trim = $l.Trim()
        if ($trim -match '^```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }                       # 围栏代码块内 = 举例，不算依赖
        foreach ($p in $AbsPatterns) {
          if ($isJson -and $p.name -eq 'UNC 路径') { continue }   # JSON 里的 \\ 是转义，不是 UNC
          if ($l -notmatch $p.rx) { continue }
          # 文档/提示行不算依赖：注释、echo、markdown 引用、JSON 描述性字段、以及"e.g./例如"示例
          $isDocLine = ($trim -match '^(echo|rem|::|#|>|\||\*|-)') -or
                       ($trim -match '^"(action|doc|evidence|evidence_source|why|how|judgement|title|note|expected|source|caveats|labels|moe_line|reason|hint|foot\d*)"') -or
                       ($l -match 'e\.g\.|例如|for example') -or
                       ($l -match 'rx\s*=|notmatch|-match\s|Replace\(')
          if ($isDocLine) { continue }
          $absHits += ("{0}:{1} ({2})" -f $rel, $line, $p.name)
          break
        }
      }
    }

    if ($f.Extension -eq '.ps1') {
      # 自定位有两种等价写法，都算通过：$PSScriptRoot 或 $MyInvocation.MyCommand.Path
      if ($text -notmatch '\$PSScriptRoot|\$MyInvocation\.MyCommand\.Path') { $psNoSelf += $rel }
      $errs = $null
      [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
      if (@($errs).Count -gt 0) { $psBadParse += ("{0} ({1})" -f $rel, @($errs)[0].Message) }
    }

    if ($f.Extension -eq '.bat' -or $f.Extension -eq '.cmd') {
      $bytes = [IO.File]::ReadAllBytes($f.FullName)
      $high = 0
      foreach ($x in $bytes) { if ($x -gt 127) { $high++ } }
      if ($high -gt 0) { $batBadAscii += ("{0} (non-ASCII bytes={1})" -f $rel, $high) }
      $t = [Text.Encoding]::ASCII.GetString($bytes)
      if ($t -match "(?<!`r)`n") { $batBareLf += $rel }
    }
  }

  if ($Report) {
    Say ("  [A] 文本件 " + $files.Count + " 个；绝对路径/包外引用命中 " + $absHits.Count + " 处")
    if ($absHits.Count -eq 0) { Pass 'A 无绝对路径、无包外引用' } else { foreach ($h in $absHits) { Fail ("A " + $h) } }

    if ($psNoSelf.Count -eq 0) { Pass 'B 全部 .ps1 自定位（$PSScriptRoot）' } else { foreach ($h in $psNoSelf) { Fail ("B 未自定位: " + $h) } }
    if ($psBadParse.Count -eq 0) { Pass 'B 全部 .ps1 可解析' } else { foreach ($h in $psBadParse) { Fail ("B 解析失败: " + $h) } }

    if ($batBadAscii.Count -eq 0) { Pass 'C 全部 .bat/.cmd 纯 ASCII' } else { foreach ($h in $batBadAscii) { Fail ("C 非 ASCII: " + $h) } }
    if ($batBareLf.Count -gt 0) { foreach ($h in $batBareLf) { Warn ("C 含裸 LF（cmd 超 4 KB 会错位解析）: " + $h) } }
  }
  return @{ Abs = $absHits.Count; NoSelf = $psNoSelf.Count; BadParse = $psBadParse.Count; BadAscii = $batBadAscii.Count }
}

Say '================ 自检 · 搬家 / 路径无关 ================'
Say ("包根：" + $Root)
Say ''

# ---- 0) 必备件存在性（骨架）----
Say '[0] 必备件'
$must = @('SHA256SUMS.txt')
foreach ($m in $must) {
  if (Test-Path -LiteralPath (Join-Path $Root $m)) { Pass ("有 " + $m) } else { Fail ("缺 " + $m) }
}
$entry = @(Get-ChildItem -LiteralPath $Root -File -Filter 'README*.md' -ErrorAction SilentlyContinue) +
         @(Get-ChildItem -LiteralPath $Root -File -Filter '00-*.md'  -ErrorAction SilentlyContinue)
if ($entry.Count -gt 0) { Pass ('有入口页（' + ($entry[0].Name) + '）') } else { Fail '缺入口页（README*.md / 00-*.md）' }
$mustAgent = @('agent\AGENT.md', 'agent\must-do.json')
foreach ($m in $mustAgent) {
  if (Test-Path -LiteralPath (Join-Path $Root $m)) { Pass ("有 " + $m) } else { Warn ("本包缺 " + $m + "（按四包同骨架的要求应补；先记 warn 不阻塞）") }
}
$mustAny = @('gpu-probe\gpu-probe.exe')
foreach ($m in $mustAny) {
  if (Test-Path -LiteralPath (Join-Path $Root $m)) { Pass ("有 " + $m) } else { Warn ("缺 " + $m + "（工具缺失会影响自检能力）") }
}
if (@(Get-ChildItem -LiteralPath $Root -File -Filter 'start-*.bat' -ErrorAction SilentlyContinue).Count -gt 0) { Pass '有 start-*.bat' } else { Warn '没有 start-*.bat' }
Say ''

# ---- A/B/C 静态 ----
Say '[A/B/C] 静态检查（本包）'
$before = Test-StaticChecks -base $Root -Report
Say ''

# ---- D 实测搬家到临时目录 ----
Say '[D] 搬家实测（把小件复制到临时目录后重跑 A/B/C）'
$tmpBase = Join-Path $env:TEMP ('pkgmove-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
  New-Item -ItemType Directory -Force -Path $tmpBase | Out-Null
  $tmpBase = (Resolve-Path -LiteralPath $tmpBase).Path
  $small = Get-SmallFiles $Root
  foreach ($f in $small) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
    $dst = Join-Path $tmpBase $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
  }
  Say ("  复制 " + $small.Count + " 个小件 -> " + $tmpBase)
  $after = Test-StaticChecks -base $tmpBase -Report
  $gate = Join-Path $tmpBase '自检-启动件.ps1'
  if (Test-Path -LiteralPath $gate) {
    Say '  在副本里跑 自检-启动件.ps1（启动件与引擎名一致性）…'
    $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $gate 2>&1
    if ($LASTEXITCODE -eq 0) { Pass 'D 副本里 自检-启动件.ps1 rc=0' } else { Warn ('D 副本里 自检-启动件.ps1 rc=' + $LASTEXITCODE + '（engine\ 不在小件里属正常，请看它自己的结论）') }
  }
  if ($after.Abs -eq 0 -and $after.NoSelf -eq 0 -and $after.BadParse -eq 0 -and $after.BadAscii -eq 0) {
    Pass 'D 换目录后 A/B/C 仍全绿（路径无关成立）'
  } else {
    Fail 'D 换目录后仍失败 —— 见上面 A/B/C 明细'
  }
} finally {
  if (Test-Path -LiteralPath $tmpBase) { Remove-Item -LiteralPath $tmpBase -Recurse -Force -ErrorAction SilentlyContinue }
}
Say ''

# ---- E 清单 ----
Say '[E] 清单自洽'
$sums = Join-Path $Root 'SHA256SUMS.txt'
$tool = Join-Path $Root 'update-sha256sums.ps1'
if (-not (Test-Path -LiteralPath $sums)) {
  Fail '缺 SHA256SUMS.txt'
} elseif (Test-Path -LiteralPath $tool) {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Root $Root -Check 2>&1
  if ($LASTEXITCODE -eq 0) { Pass 'E SHA256SUMS.txt -Check rc=0（逐条 sha 对得上）' }
  else { Fail ('E SHA256SUMS.txt -Check rc=' + $LASTEXITCODE); $out | Select-String -Pattern 'CHANGED|ADDED|DROPPED|MISSING' | ForEach-Object { Say ('      ' + $_) } }
} else {
  Warn 'E 本包没有 update-sha256sums.ps1 ⇒ 只断言清单存在，未逐条核对'
}

# ---- F 覆盖面：清单必须覆盖包内每个文件 ----
# 为什么要有这一条：-Check 只核对"清单里已列的文件"，**漏列查不出来** ⇒ rc=0 是假绿。
Say '[F] 清单覆盖面（防"漏列但 -Check 仍绿"）'
if (Test-Path -LiteralPath $sums) {
  $listed = @{}
  foreach ($line in [IO.File]::ReadAllLines($sums)) {
    if ($line -match '^\s*[0-9A-Fa-f]{64}\s\s(.+?)\s*$') { $listed[$Matches[1]] = $true }
  }
  $onDisk = Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\src-tree\\' -and $_.FullName -notmatch '\\\.git\\' -and $_.Name -ne 'SHA256SUMS.txt' }
  $miss = @()
  foreach ($f in $onDisk) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\')
    if (-not $listed.ContainsKey($rel)) { $miss += $rel }
  }
  if ($miss.Count -eq 0) {
    Pass ('F 清单覆盖全部 ' + $onDisk.Count + ' 个文件（src-tree\ 除外）')
  } else {
    Fail ('F 清单漏列 ' + $miss.Count + ' 个文件 —— -Check 查不出这种漏列')
    $miss | Select-Object -First 12 | ForEach-Object { Say ('      ' + $_) }
    Say '      ⇒ 修法：把这批文件交给清单工具；注意经 powershell -File 传 -Add 数组只会过第一个元素，用进程内调用或逗号串。'
  }
} else {
  Warn 'F 没有清单可对'
}

# ---- G 编码：.ps1 必须"纯 ASCII 或带 UTF-8 BOM" ----
# 为什么：PS 5.1 把无 BOM 的 .ps1 按 ANSI 解码 ⇒ 中文变乱码 ⇒ 整脚本解析失败（我们真踩过）。
Say '[G] 脚本编码（.ps1 = 纯 ASCII 或 BOM）'
$encBad = @()
foreach ($sf in (Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch '\\\\src-tree\\\\' })) {
  $sb = [IO.File]::ReadAllBytes($sf.FullName)
  $sbom = ($sb.Length -ge 3 -and $sb[0] -eq 0xEF -and $sb[1] -eq 0xBB -and $sb[2] -eq 0xBF)
  $shigh = 0; foreach ($sx in $sb) { if ($sx -gt 127) { $shigh++ } }
  if (-not $sbom -and $shigh -gt 0) { $encBad += $sf.FullName.Substring($Root.Length).TrimStart('\\') }
}
if ($encBad.Count -eq 0) { Pass 'G 全部 .ps1 都是"纯 ASCII 或带 BOM"' }
else { foreach ($h in $encBad) { Fail ('G 无 BOM 且含非 ASCII: ' + $h) } }
Say ''
Say ''
Say '================ 结论 ================'
Say ("FAIL=" + $script:Fail + "  warn=" + $script:Warn)
if ($script:Fail -eq 0) { Say '✅ 可搬运（路径无关）自检通过'; exit 0 } else { Say '❌ 未通过：先修上面 FAIL 项，再交给对方'; exit 1 }
