# patch-pkg-src-tree.ps1 -- make -DNINFER_SM_COUNT=<n> actually work in a PACKAGED src-tree.
#
# WHY THIS EXISTS
#   The packaged src-tree only had per-arch hardcoded defaults in src\core\device.h
#   (NINFER_SM89 -> 128 / NINFER_SM86 -> 82) and the root CMakeLists never forwarded
#   NINFER_SM_COUNT. So every "rebuild for your own card" instruction in our docs was a
#   NO-OP: cmake accepted -DNINFER_SM_COUNT=80, the build succeeded, and the macro was
#   ignored -- the exact "compile succeeded != compiled correctly" trap we warn about.
#   This patch adds the branch plus the forwarding define, and (with -Verify) proves by
#   configure-only that the macro really lands in the compile definitions.
#
# WHAT IT CHANGES (2 files, idempotent, anchor-exact, backups kept)
#   1) src\core\device.h
#        #if defined(NINFER_SM_COUNT) -> kTargetSmCount = NINFER_SM_COUNT  (your card wins)
#        #elif defined(NINFER_SM89)   -> 128   (existing fallback, kept verbatim)
#        #elif defined(NINFER_SM86)   -> 82    (existing fallback, kept verbatim)
#        #elif defined(NINFER_SM120)  -> 170   (new arm; matches the shipped sm_120 engine)
#        #else #error ...
#   2) CMakeLists.txt
#        set(NINFER_SM_COUNT "0" CACHE STRING ...)          -- 0 = per-arch default
#        add_compile_definitions(NINFER_SM_COUNT=${NINFER_SM_COUNT})   -- the forwarding
#        plus accepting CMAKE_CUDA_ARCHITECTURES=120 as an alias of 120a.
#
# Replacement bodies live in sibling text files (cmake-patch-a.txt / cmake-patch-b.txt and
# the device.h block below) so that no CMake text has to survive PowerShell string quoting.
#
# ASCII-only script. Chinese text in a .ps1 breaks the Windows PowerShell 5.1 parser.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File patch-pkg-src-tree.ps1 -Tree <src-tree\ninfer-4090w-ternary>
#   powershell ... -Tree <...> -Verify [-TempDir <ascii dir>]     # + configure-only proof
param(
  [Parameter(Mandatory=$true)][string]$Tree,
  [string]$TempDir = '',
  [string]$PatchDir = '',
  [switch]$Verify
)
$ErrorActionPreference = 'Stop'
function Read-Utf8([string]$p) { return [IO.File]::ReadAllText($p, (New-Object Text.UTF8Encoding($false))) }
function Write-Utf8([string]$p, [string]$t) { [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false))) }

if (-not $PatchDir) { $PatchDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Tree = (Resolve-Path -LiteralPath $Tree).Path
$devH = Join-Path $Tree 'src\core\device.h'
$cml  = Join-Path $Tree 'CMakeLists.txt'
if (-not (Test-Path -LiteralPath $devH)) { throw ('not a src-tree (no src\core\device.h): ' + $Tree) }
if (-not (Test-Path -LiteralPath $cml))  { throw ('not a src-tree (no CMakeLists.txt): ' + $Tree) }
Write-Host ('tree = ' + $Tree)

# ---------------------------------------------------------------- 1) device.h
$h = Read-Utf8 $devH
if ($h.Contains('NINFER_SM_COUNT')) {
  Write-Host 'device.h       : already patched (NINFER_SM_COUNT present) -- skipped'
} else {
  $anchor = "#if defined(NINFER_SM89)`n"
  if (-not $h.Contains($anchor)) { throw 'device.h: anchor "#if defined(NINFER_SM89)" not found; refuse to guess' }
  $newHead = @(
    '// --- fork/package patch (2026-09-27) --------------------------------------------',
    '// -DNINFER_SM_COUNT=<n> (forwarded into the compile definitions by the top-level',
    '// CMakeLists) names the card this build will run on and WINS over the per-arch',
    '// default below, so a non-flagship card (4090 D / 4080 SUPER / 4080 / 4070 Ti SUPER /',
    '// 4070 Ti / 4070 SUPER / 4070 / 4060 Ti / 4060 ...) gets exact wave-filling instead of',
    '// being scheduled as if it were a 4090.',
    '//',
    '// NOTHING passed -> the per-arch defaults below are used unchanged, so every build that',
    '// worked before this patch keeps working and keeps the same constant.',
    '// --------------------------------------------------------------------------------',
    '#if defined(NINFER_SM_COUNT)',
    'inline constexpr int kTargetSmCount = NINFER_SM_COUNT; // your card, from -DNINFER_SM_COUNT',
    '#elif defined(NINFER_SM89)',
    ''
  ) -join "`n"
  $h2 = $h.Replace($anchor, $newHead)
  $tailOld = @(
    '#else',
    '#error "NInfer requires NINFER_SM86 or NINFER_SM89"',
    '#endif',
    ''
  ) -join "`n"
  $tailNew = @(
    '#elif defined(NINFER_SM120)',
    'inline constexpr int kTargetSmCount = 170; // NVIDIA GeForce RTX 5090 (shipped sm_120 engine)',
    '#else',
    '#error "NInfer requires NINFER_SM86, NINFER_SM89 or NINFER_SM120"',
    '#endif',
    ''
  ) -join "`n"
  if (-not $h2.Contains($tailOld)) { throw 'device.h: fallback tail not found verbatim; refuse to guess' }
  $h2 = $h2.Replace($tailOld, $tailNew)
  Write-Utf8 $devH $h2
  Write-Host 'device.h       : PATCHED'
}

# ---------------------------------------------------------------- 2) CMakeLists.txt
$c = Read-Utf8 $cml
if ($c.Contains('NINFER_SM_COUNT')) {
  Write-Host 'CMakeLists.txt : already patched (NINFER_SM_COUNT present) -- skipped'
} else {
  $blockA = Read-Utf8 (Join-Path $PatchDir 'cmake-patch-a.txt')
  $blockB = Read-Utf8 (Join-Path $PatchDir 'cmake-patch-b.txt')
  $anchor2 = 'project(ninfer LANGUAGES C CXX CUDA)'
  if (-not $c.Contains($anchor2)) { throw 'CMakeLists.txt: anchor "project(ninfer ...)" not found' }
  $c2 = $c.Replace($anchor2, $blockA + $anchor2)
  $c2 = $c2.Replace('if(NOT CMAKE_CUDA_ARCHITECTURES MATCHES "^(120a|89)$")',
                    'if(NOT CMAKE_CUDA_ARCHITECTURES MATCHES "^(120a|120|89)$")')
  $oldArch = @(
    'if(CMAKE_CUDA_ARCHITECTURES MATCHES "89")',
    '  add_compile_definitions(NINFER_SM89=1)',
    'endif()',
    ''
  ) -join "`n"
  if (-not $c2.Contains($oldArch)) { throw 'CMakeLists.txt: NINFER_SM89 arch block not found verbatim; refuse to guess' }
  $c2 = $c2.Replace($oldArch, $blockB)
  Write-Utf8 $cml $c2
  Write-Host 'CMakeLists.txt : PATCHED'
}

# ---------------------------------------------------------------- 3) verify (configure only)
if ($Verify) {
  if (-not $TempDir) { $TempDir = Join-Path $env:TEMP 'ninfer-smcount-verify' }
  New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
  $vs = if ($env:VS_ROOT) { $env:VS_ROOT } else { Join-Path $env:SystemDrive 'Program Files (x86)\Microsoft Visual Studio\18\BuildTools' }
  $cmake = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
  if (-not (Test-Path -LiteralPath $cmake)) { throw ('cmake not found: ' + $cmake) }
  $ninjaDir = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
  $cudaBin = if ($env:CUDA_PATH) { Join-Path $env:CUDA_PATH 'bin' } else { Join-Path (Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit\CUDA\v13.3') 'bin' }
$env:PATH = $ninjaDir + ';' + (Split-Path $cmake -Parent) + ';' + $cudaBin + ';' + (Join-Path $cudaBin 'x64') + ';' + $env:PATH
  if (-not $env:CUDA_PATH) { $env:CUDA_PATH = Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit\CUDA\v13.3' }

  $cases = @(
    @{ n = 'pass80';  extra = @('-DNINFER_SM_COUNT=80') },
    @{ n = 'default'; extra = @() }
  )
  foreach ($case in $cases) {
    $bd = Join-Path $TempDir $case.n
    if (Test-Path -LiteralPath $bd) { Remove-Item -LiteralPath $bd -Recurse -Force }
    $a = @('-B', $bd, '-S', $Tree, '-G', 'Ninja', '-DCMAKE_CUDA_ARCHITECTURES=89',
           '-DNINFER_ENABLE_AVX2=ON', '-DNINFER_BUILD_MEDIA_ACQUIRE=ON', '-DBUILD_TESTING=OFF',
           '-DNINFER_BUILD_BENCHMARKS=OFF') + $case.extra
    Write-Host ('--- configure case=' + $case.n + '  (' + (($case.extra) -join ' ') + ')')
    $log = & $cmake @a 2>&1
    $keep = @($log | Where-Object { $_ -match 'NINFER_SM_COUNT|SM_COUNT=|Configuring done|Generating done|CMake Error' })
    foreach ($l in $keep) { Write-Host ('    ' + $l) }
    $nin = Join-Path $bd 'build.ninja'
    if (Test-Path -LiteralPath $nin) {
      $hits = @(Select-String -Path $nin -Pattern 'NINFER_SM_COUNT=\d+' -AllMatches |
                ForEach-Object { $_.Matches } | ForEach-Object { $_.Value } | Sort-Object -Unique)
      Write-Host ('    build.ninja DEFINES hits: ' + ($hits -join '   '))
    } else {
      Write-Host '    build.ninja NOT produced'
    }
  }
  Write-Host ('    (build dirs: ' + $TempDir + ')')
}
