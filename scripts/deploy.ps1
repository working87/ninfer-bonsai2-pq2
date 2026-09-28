<#
  一键部署：极速档 PQ2 —— 三元 Bonsai-2-27B on ninfer（Windows x64 + NVIDIA RTX 40/50 系）
  原作者：沈三殊（shensanshu）。本仓库仅为转发整理。
    B站   https://space.bilibili.com/85280961
    魔搭  https://www.modelscope.cn/models/shensanshu/ninfer-ada-ternary

  所有下载均走国内源（魔搭 ModelScope / 清华 PyPI 镜像），不访问海外站点：
    引擎 + ffmpeg dll : 魔搭 working87/ninfer-bonsai2-pq2-engine（沈三殊编译，原样转发）
    模型权重          : 魔搭 w3c0929/Ternary-Bonsai-2-27B-NInfer（与原包 SHA256 逐位一致）
    VC++ 运行库       : 清华 PyPI 镜像 msvc-runtime（仅在系统缺失时）

  用法（在仓库根目录，PowerShell）：
    powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1                 # 自动选模型、下载、启动、验证
    powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -Model all      # 两份模型都下（约 18.8 GB）
    powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 -NoStart        # 只下载校验，不启动
  参数：
    -Model      auto（默认：显存 >= 15 GB 下 dflash2，否则下 base）| base | dflash2 | all
                base    = bonsai2_27b_ternary_v2.ninfer          8.31 GB，start-8084/8086/8087 与视觉用它
                dflash2 = bonsai2_27b_ternary_v2-dflash2.ninfer 10.53 GB，start-8085/8088 用它，最快
    -Engine     auto（默认：按显卡算力只下对应那份）| all（两份引擎都下）
    -Port       启动端口，默认 8085
    -NoStart    只下载校验，不启动
#>
param(
  [ValidateSet('auto','base','dflash2','all')][string]$Model = 'auto',
  [ValidateSet('auto','all')][string]$Engine = 'auto',
  [int]$Port = 8085,
  [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSScriptRoot

# ---------------- 国内下载源 ----------------
$MS          = 'https://www.modelscope.cn/models'
$EngineRepo  = 'working87/ninfer-bonsai2-pq2-engine'
$ModelRepo   = 'w3c0929/Ternary-Bonsai-2-27B-NInfer'
$PipMirror   = 'https://pypi.tuna.tsinghua.edu.cn/simple'

$Dlls = @(
  @{ Name='avcodec-63.dll';   Sha='1A43CF4B22BCE33DFC3853C8373A9FCFF90F532F3B1E34254BA418824D60A4A7' },
  @{ Name='avdevice-63.dll';  Sha='0B4363087576EA75C97082F8D6C54A843660D3FC55069A8E84EF5003888180B7' },
  @{ Name='avfilter-12.dll';  Sha='CC227B1ED66D36482B80D807F198166927B0102E51314847803689B3CBB42C8B' },
  @{ Name='avformat-63.dll';  Sha='8DA0B1708A0E320AAE895474DC48FE76030444D44A72004B2E4CE2FD4C1FC9D7' },
  @{ Name='avutil-61.dll';    Sha='00FCD925ECD35A723EF5085EA00B5835D3535C32AB7AC683378FBBB13067A5B6' },
  @{ Name='swresample-7.dll'; Sha='F63082A912994464C7ABD6187D35D7AF0C58C5D9AF6D86AB93D7C58343CBEDF0' },
  @{ Name='swscale-10.dll';   Sha='5D941DC3791ED917650E50C9464A9EFB6237599B9533F005767155EDEFB1EE68' }
)
$Exes = @{
  '8.9'  = @{ Name='ninfer-serve.exe';       Sha='566F0D0ED8FF23E0FDBFD66E8B5C8C704228F883E728923E87565766FB2BACB8'; Bytes=264173568 }
  '12.0' = @{ Name='ninfer-serve-sm120.exe'; Sha='FE170EB23FFDBFF5EB9F9D70A390EC639910BEAB420F30DCB937AF2CD0269C42'; Bytes=198689792 }
}
$Models = @{
  'base'    = @{ Name='bonsai2_27b_ternary_v2.ninfer';         Sha='05BBBF01090C6F61113B54556DAA22AD0B45036A078AF6CD6F02A3FDE47AD76C'; Bytes=8306927628 }
  'dflash2' = @{ Name='bonsai2_27b_ternary_v2-dflash2.ninfer'; Sha='F66C8300EFF996A58893E7D567A3E000D7B6347F3A72B2124EAC11791720E148'; Bytes=10533733120 }
}

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

function Get-Verified([string]$Url, [string]$Dst, [string]$Sha) {
  if ((Test-Path -LiteralPath $Dst) -and (Get-FileHash -LiteralPath $Dst -Algorithm SHA256).Hash -eq $Sha) {
    Write-Host "已存在且校验通过：$(Split-Path $Dst -Leaf)"; return
  }
  Write-Host "下载 $(Split-Path $Dst -Leaf)  <-  $Url"
  for ($i = 1; $i -le 5; $i++) {
    & curl.exe -L --fail --retry 5 --retry-delay 3 -C - -o $Dst $Url
    if ($LASTEXITCODE -eq 0) { break }
    Write-Warning "curl 退出码 $LASTEXITCODE，第 $i 次重试"
    Start-Sleep 3
  }
  $h = (Get-FileHash -LiteralPath $Dst -Algorithm SHA256).Hash
  if ($h -ne $Sha) {
    Remove-Item -LiteralPath $Dst -Force
    throw "SHA256 不符：$(Split-Path $Dst -Leaf)（期望 $Sha，实际 $h）。已删除，请重跑本脚本。"
  }
  Write-Host "校验通过：$(Split-Path $Dst -Leaf)" -ForegroundColor Green
}

# ---------------- 1. 环境检查 ----------------
Step '检查环境'
if ($Root -match '[^\x00-\x7F]') {
  throw "仓库所在路径含中文/非 ASCII 字符：$Root`n引擎遇到这种路径会报 invalid UTF-8。请把仓库 clone 到纯英文路径（例如某个盘下的 ai\ninfer-pq2）后重跑。"
}
if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
  throw '找不到 nvidia-smi：请先安装 NVIDIA 显卡驱动（只需驱动，不需要装 CUDA Toolkit）'
}
$q = & nvidia-smi --query-gpu=name,compute_cap,memory.total,driver_version --format=csv | Select-Object -Skip 1 -First 1
$g = $q.Split(',') | ForEach-Object { $_.Trim() }
$gpuName = $g[0]; $cc = $g[1]; $vram = [int]($g[2] -replace '[^\d]', ''); $driver = $g[3]
Write-Host "GPU: $gpuName   算力: $cc   显存: $vram MiB   驱动: $driver"
if (-not $Exes.ContainsKey($cc)) {
  throw @"
本包只带 cc 8.9（RTX 40 系）和 cc 12.0（RTX 50 系）两份引擎，你的卡是 cc $cc。
引擎运行时源码里有硬门，30 系 / A100 / H100 不是"没测过"，而是明确不支持。
要支持得改门 + 自己编译：见 docs\兜底方案-从源码自己编译.md 与 08-从零复现方案书（兜底路线）.md，源码在 src-tree\。
"@
}
if ($vram -lt 10000) { Write-Warning '显存 < 10 GB，大概率跑不起来（基础档最低实测占用 8.54 GiB）' }

$wantModels = switch ($Model) {
  'auto'    { if ($vram -ge 15000) { @('dflash2') } else { @('base') } }
  'all'     { @('base', 'dflash2') }
  default   { @($Model) }
}
$wantCc = if ($Engine -eq 'all') { @('8.9', '12.0') } else { @($cc) }
Write-Host "将下载模型：$($wantModels -join ', ')   引擎：$(($wantCc | ForEach-Object { $Exes[$_].Name }) -join ', ')"

$needBytes = 200MB
foreach ($m in $wantModels) { $p = Join-Path $Root "model\$($Models[$m].Name)"; if (-not (Test-Path $p)) { $needBytes += $Models[$m].Bytes } }
foreach ($c in $wantCc)     { $p = Join-Path $Root "engine\$($Exes[$c].Name)";  if (-not (Test-Path $p)) { $needBytes += $Exes[$c].Bytes } }
$drive = (Split-Path -Qualifier $Root).TrimEnd(':')
$free = (Get-PSDrive $drive).Free
if ($free -lt $needBytes + 1GB) { throw "磁盘 ${drive}: 剩余 $([math]::Round($free/1GB,1)) GB，本次至少需要 $([math]::Round(($needBytes+1GB)/1GB,1)) GB" }

# ---------------- 2. 引擎（魔搭） ----------------
Step "下载引擎（魔搭 $EngineRepo）"
New-Item -ItemType Directory -Force (Join-Path $Root 'engine'), (Join-Path $Root 'model') | Out-Null
foreach ($c in $wantCc) {
  $e = $Exes[$c]
  Get-Verified "$MS/$EngineRepo/resolve/master/engine/$($e.Name)" (Join-Path $Root "engine\$($e.Name)") $e.Sha
}
foreach ($d in $Dlls) {
  Get-Verified "$MS/$EngineRepo/resolve/master/engine/$($d.Name)" (Join-Path $Root "engine\$($d.Name)") $d.Sha
}
# 源码树的 ffmpeg\bin 需要同一批 dll（自己编译时用）；git 里没放，从 engine\ 复制过去
$ffBin = Join-Path $Root 'src-tree\ninfer-4090w-ternary\ffmpeg\bin'
if (Test-Path $ffBin) { foreach ($d in $Dlls) { Copy-Item (Join-Path $Root "engine\$($d.Name)") $ffBin -Force } }

# ---------------- 3. 模型（魔搭，断点续传） ----------------
Step "下载模型权重（魔搭 $ModelRepo，支持断点续传，文件很大请耐心等）"
foreach ($m in $wantModels) {
  $x = $Models[$m]
  Get-Verified "$MS/$ModelRepo/resolve/master/$($x.Name)" (Join-Path $Root "model\$($x.Name)") $x.Sha
}

# ---------------- 4. VC++ 运行库（缺才补，走清华 PyPI 镜像） ----------------
if (-not (Test-Path "$env:WINDIR\System32\msvcp140.dll") -or -not (Test-Path "$env:WINDIR\System32\vcruntime140_1.dll")) {
  Step '系统缺 VC++ 运行库，从清华 PyPI 镜像取 msvc-runtime 放进 engine 目录'
  $tmp = Join-Path $env:TEMP 'msvc-rt'
  New-Item -ItemType Directory -Force $tmp | Out-Null
  $idx = (Invoke-WebRequest "$PipMirror/msvc-runtime/" -UseBasicParsing).Links.href | Where-Object { $_ -match 'win_amd64\.whl' } | Select-Object -Last 1
  $whlUrl = [Uri]::new([Uri]"$PipMirror/msvc-runtime/", $idx).AbsoluteUri
  & curl.exe -L --fail -o "$tmp\msvc.zip" $whlUrl
  Expand-Archive "$tmp\msvc.zip" "$tmp\x" -Force
  Get-ChildItem "$tmp\x" -Recurse -Include msvcp140*.dll, vcruntime140*.dll, concrt140.dll | Copy-Item -Destination (Join-Path $Root 'engine') -Force
}

if ($NoStart) {
  Write-Host "`n下载与校验完成。下一步：powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 start -Port $Port" -ForegroundColor Green
  return
}

# ---------------- 5. 启动 + 就绪 + 真推理 ----------------
$agent = Join-Path $Root 'agent\ninfer-agent.ps1'
Step '体检（agent\ninfer-agent.ps1 doctor）'
& powershell -NoProfile -ExecutionPolicy Bypass -File $agent doctor | Out-Host

Step "启动引擎（端口 $Port，按显卡自动选引擎/模型/KV/上下文）"
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($busy) { throw "端口 $Port 已被进程 $($busy.OwningProcess) 占用。换端口：-Port 8096，或释放：Stop-Process -Id $($busy.OwningProcess) -Force" }
$startJson = & powershell -NoProfile -ExecutionPolicy Bypass -File $agent start -Port $Port
$code = $LASTEXITCODE
$startJson | Out-Host
if ($code -ne 0) { throw "引擎未就绪（agent 退出码 $code）。按 00-从这里开始.md → 02-排错手册 · 预案与处方.md 处理；退出码含义见 agent\AGENT.md。" }

$body = '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"用一句话介绍你自己"}],"max_tokens":64,"temperature":0}'
$r = Invoke-RestMethod "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 300
Write-Host "`n模型回答：$($r.choices[0].message.content)" -ForegroundColor Green
Write-Host @"

部署成功
  OpenAI 兼容地址：http://127.0.0.1:$Port/v1    模型名：qwen3.8-27b（请求体必须带 model 字段）
  停止：powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 stop -Port $Port
  测速：powershell -NoProfile -ExecutionPolicy Bypass -File agent\ninfer-agent.ps1 bench -Port $Port -Kind code -Runs 3
  以后手动启动也可以双击 start-*.bat（选哪个见 README.md「启动件总表」）

原作者：沈三殊（shensanshu） B站 https://space.bilibili.com/85280961  觉得好用请去原作者主页点赞支持
"@
