# 启动件自检 / LAUNCHER SELF-CHECK  (read-only, safe: nothing is started for real)
#
#  为什么有这个脚本：
#  2026-09-26 一天里，同一类"启动件"缺陷被踩到 4 次，而且修完又复发过一次 ——
#    (1) 认卡行用 for /f + --format=csv,noheader  → cmd 把逗号拆开 → nvidia-smi 报
#        "Option noheader is not recognized" → 明明支持的卡被判"不支持"直接退出；
#    (2) 横幅里 echo ... => 或裸 | 未转义 → '>' 被当重定向 → 在 engine\ 里凭空生成垃圾文件
#        （实测生成过 ~12.3-12.6 / 128K / about），裸 | 更狠：后半行会被当命令执行；
#    (3) if (...) 块内的 echo 文本里带未转义的 ) → 提前闭合块 → ". was unexpected at this time."
#        并中断启动（这一条是我自己修 (2) 时新引入的）。
#  这个脚本把这三类全部机器化检查，并且真的把每个启动件**在沙盒目录里跑一遍**看副作用。
#
#  用法（包根目录）：
#     powershell -NoProfile -ExecutionPolicy Bypass -File .\自检-启动件.ps1
#
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

function Line($m) { Write-Host $m }

$bats = @(Get-ChildItem -LiteralPath $root -File -Filter 'start-*.bat' | Sort-Object Name)
Line ''
Line '=== 启动件自检 (launcher self-check) ==='
if ($bats.Count -eq 0) { Line '  这个目录里没有 start-*.bat —— 请在档位根目录运行本脚本。'; exit 2 }
Line ('  找到 ' + $bats.Count + ' 个启动件')
Line ''

# ---------- 静态检查部分 ----------
$static = @{}
Line '--- [1/3] 静态检查：认卡写法 / 转义 / 块内括号 ---'
foreach ($b in $bats) {
  $L = Get-Content -LiteralPath $b.FullName
  $issues = New-Object Collections.Generic.List[string]

  # (1) 可执行的 csv,noheader（REM 里提它没关系，那是注释）
  for ($i=0; $i -lt $L.Count; $i++) {
    $t = $L[$i]
    if ($t -notmatch '^\s*REM' -and $t -match 'csv,noheader') {
      $issues.Add(('L' + ($i+1) + ' 认卡行用了 --format=csv,noheader（for /f 里会被拆参数）'))
    }
  }
  # (2) echo 行里未转义的 > | <（排除有意的重定向）
  $depth = 0
  for ($i=0; $i -lt $L.Count; $i++) {
    $t = $L[$i]; $trim = $t.Trim()
    if ($trim.StartsWith('echo')) {
      $intentional = ($t -match '>\s*nul' -or $t -match '2>' -or $t -match '>\s*"%')
      if (-not $intentional) {
        if ([regex]::IsMatch($t,'(?<!\^)>')) { $issues.Add(('L' + ($i+1) + ' echo 里未转义的 >  (写成 =^>)')) }
        if ([regex]::IsMatch($t,'(?<!\^)\|')) { $issues.Add(('L' + ($i+1) + ' echo 里未转义的 |  (写成 ^|)')) }
        if ([regex]::IsMatch($t,'(?<!\^)<'))   { $issues.Add(('L' + ($i+1) + ' echo 里未转义的 <  (写成 ^<)')) }
        # (3) 块内 echo 里的括号
        if ($depth -gt 0) {
          if ([regex]::IsMatch($t,'(?<!\^)\(')) { $issues.Add(('L' + ($i+1) + ' 块内 echo 里未转义的 (  (写成 ^()')) }
          if ([regex]::IsMatch($t,'(?<!\^)\)')) { $issues.Add(('L' + ($i+1) + ' 块内 echo 里未转义的 )  (写成 ^))')) }
        }
      }
    }
    if ($trim.EndsWith('(')) { $depth++ }
    elseif ($trim -eq ')') { if ($depth -gt 0) { $depth-- } }
  }
  # (4) 认卡失败时是否还有"硬退出"（应当改成 choice 问一句）
  $text = ($L -join "`n")
  # (5) 引擎名必须与 engine\ 里的实际文件一致 —— 沙盒冒烟**测不出**这一条（沙盒里本来就没有引擎，
  #     "infer-serve.exe 不是命令"被当成预期结果了），所以 2026-09-26 我们把引擎名写错成
  #     infer-serve.exe（真实是 ninfer-serve.exe）时，13 个启动件全过自检却全部打不开。
  $engineDir = Join-Path $root 'engine'
  $realEngines = @(Get-ChildItem -LiteralPath $engineDir -File -Filter '*serve*.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
  if ($realEngines.Count -gt 0) {
    foreach ($m in [regex]::Matches($text, 'set "ENGINE=[^"]*\\([^"\\]+)"')) {
      $named = $m.Groups[1].Value
      if ($realEngines -notcontains $named) {
        $issues.Add('ENGINE 指向 ' + $named + '，但 engine\ 里实际是: ' + ($realEngines -join ', '))
      }
    }
    if ($text -match 'Get-Process -Name' ) {
      foreach ($m in [regex]::Matches($text, "Get-Process -Name '([^']+)'")) {
        $pn = $m.Groups[1].Value -replace '\.exe$',''
        if (($realEngines -replace '\.exe$','') -notcontains $pn) { $issues.Add('Get-Process 用了不存在的进程名: ' + $pn) }
      }
    }
  }
  if ($text -notmatch 'choice /c 45') { $issues.Add('没有认卡兜底（choice /c 45）：认卡失败时会直接退出') }

  $static[$b.Name] = $issues
  if ($issues.Count -eq 0) { Line ('  PASS  ' + $b.Name) }
  else {
    Line ('  FAIL  ' + $b.Name)
    $issues | ForEach-Object { Line ('          - ' + $_) }
  }
}

# ---------- 动态冒烟：在沙盒目录里真跑一遍 ----------
Line ''
Line '--- [2/3] 动态冒烟：沙盒目录里跑一遍，看有没有 cmd 语法错误与垃圾文件 ---'
$tmp = Join-Path $env:TEMP ('launcher-check-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'engine') | Out-Null
$dyn = @{}
foreach ($b in $bats) {
  Copy-Item -LiteralPath $b.FullName -Destination (Join-Path $tmp $b.Name)
  $out = cmd /c "`"$tmp\$($b.Name)`" < nul 2>&1"
  # 沙盒里本来就没有引擎 exe —— "engine\ninfer-serve.exe 不是命令" 是预期结果，不是缺陷。
  # 只有"其余"的 cmd 报错才算问题（. was unexpected / 语法错误 / 别的命令找不到）。
  $errLines = @($out | Where-Object { $_ -match 'unexpected|not recognized as an internal|syntax of the command' } |
                Where-Object { $_ -notmatch 'ninfer-serve(-sm120)?\.exe' })
  # engine\ 里出现的任何非预期文件 = 被 echo 重定向写出来的垃圾
  $junk = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'engine') -Recurse -File -ErrorAction SilentlyContinue)
  $rootJunk = @(Get-ChildItem -LiteralPath $tmp -File | Where-Object { $_.Extension -ne '.bat' })
  $dyn[$b.Name] = @{ Err = $errLines; Junk = @($junk + $rootJunk) }
  if ($errLines.Count -eq 0 -and ($junk.Count + $rootJunk.Count) -eq 0) {
    Line ('  PASS  ' + $b.Name)
  } else {
    Line ('  FAIL  ' + $b.Name)
    if ($errLines.Count) { $errLines | Select-Object -First 3 | ForEach-Object { Line ('          - cmd: ' + $_.Trim()) } }
    if ($junk.Count) { $junk | ForEach-Object { Line ('          - 垃圾文件 engine\' + $_.Name) } }
    if ($rootJunk.Count) { $rootJunk | ForEach-Object { Line ('          - 垃圾文件 ' + $_.Name) } }
  }
  # 清掉这一轮产生的垃圾，免得影响下一个启动件
  Get-ChildItem -LiteralPath (Join-Path $tmp 'engine') -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Get-ChildItem -LiteralPath $tmp -File | Where-Object { $_.Extension -ne '.bat' } | Remove-Item -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

# ---------- 汇总 ----------
Line ''
Line '--- [3/3] 汇总 ---'
$fail = 0
foreach ($b in $bats) {
  $s = $static[$b.Name]; $d = $dyn[$b.Name]
  if ($s.Count -gt 0 -or $d.Err.Count -gt 0 -or $d.Junk.Count -gt 0) { $fail++ }
}
if ($fail -eq 0) {
  Line ('  全部通过：' + $bats.Count + ' 个启动件 —— 认卡写法正确、横幅已转义、块内括号已转义、沙盒冒烟无副作用。')
  Line '  （注意：这是"不炸"的证明，不是"能起引擎"的证明。能不能起引擎要在真机上双击看那一行 Card/Engine 输出。）'
} else {
  Line ('  有 ' + $fail + ' 个启动件需要修（上面已逐条列出 行号 + 处方）。')
  Line '  处方速查：'
  Line '    认卡   -> for /f "skip=1 tokens=1" %%C in (''nvidia-smi --query-gpu=compute_cap --format=csv 2^>NUL'')'
  Line '    横幅   -> > 写 =^>   | 写 ^|   < 写 ^<'
  Line '    块内括号 -> ( 写 ^(   ) 写 ^)'
}
Line ''
exit $fail
