@echo off
REM ============================================================
REM  Ternary Bonsai-2-27B on ninfer -- tier PQ2
REM  Model : bonsai2_27b_ternary_v2.ninfer
REM  Port  : 8086   Vision: ON
REM  NOTE  : ASCII-only on purpose. Batch files are parsed in the
REM          OEM/ANSI codepage; non-ASCII text here corrupts the
REM          commands themselves.
REM ============================================================

REM  CUDA toolkit is NOT required: the engine uses the driver-side CUDA
REM  runtime (nvcuda.dll / nvcudart_hybrid64.dll). Verified: starts and
REM  reaches "listening" with only CUDA 12.8 on PATH.
REM  Set CUDA_BIN only if the engine dies with 0xC0000135.
set "CUDA_BIN="
if not defined CUDA_BIN (
  for /d %%D in ("%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v13*") do set "CUDA_BIN=%%~fD\bin"
)
if not defined CUDA_BIN (
  for /d %%D in ("%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v12*") do set "CUDA_BIN=%%~fD\bin"
)
if not defined CUDA_BIN set "CUDA_BIN=%~dp0engine"
set "CUDA_OK="
dir /b "%CUDA_BIN%\cudart64_*.dll" >NUL 2>&1 && set "CUDA_OK=1"
dir /b "%CUDA_BIN%\x64\cudart64_*.dll" >NUL 2>&1 && set "CUDA_OK=1"
if not defined CUDA_OK (
  echo [NOTE] no cudart64_*.dll found - this is NORMAL: the engine uses the
  echo        driver-side CUDA runtime. Keep going. Set CUDA_BIN only on 0xC0000135.
  echo.
)
set "PATH=%CUDA_BIN%;%CUDA_BIN%\x64;%PATH%"

cd /d "%~dp0engine"

echo.
echo   Tier  : PQ2
echo   Model : %~dp0model\bonsai2_27b_ternary_v2.ninfer
echo   URL   : http://127.0.0.1:8086
echo   Ready : curl.exe -s -o NUL -w "%%{http_code}" http://127.0.0.1:8086/v1/models
echo   Expect: 200
echo.

REM ---- pick the engine that matches THIS card's architecture ------------------
REM  Arch-specific binaries; neither carries PTX for the other arch, so the wrong
REM  one does NOT fall back -- it dies or wedges with no usable kernel image.
REM    ninfer-serve.exe = sm_89 (RTX 40)   ninfer-serve-sm120.exe = sm_120 (RTX 50)
set "ENGINE=%~dp0engine\ninfer-serve.exe"
set "CAP="
REM  Agent mode: an explicit capability makes this launcher fully non-interactive.
if defined NINFER_AGENT_CC set "CAP=%NINFER_AGENT_CC%"
REM  compute capability, header form + skip=1. Do NOT use --format=csv,noheader here: inside
REM  for /f some nvidia-smi builds split it and answer "Option noheader is not recognized",
REM  which used to abort this launcher on a perfectly supported card (measured, nvidia-smi 616.56).
for /f "skip=1 tokens=1" %%C in ('nvidia-smi --query-gpu=compute_cap --format=csv 2^>NUL') do if not defined CAP set "CAP=%%C"
if not defined CAP (
  echo [WARN] nvidia-smi did not report a compute capability for this GPU.
  echo        Pick your card family, then the launcher continues normally.
  if defined NINFER_AGENT (
    echo [AGENT] ERROR: compute capability could not be read from nvidia-smi.
    echo [AGENT]        Set NINFER_AGENT_CC=8.9 or 12.0 and rerun. Not prompting --
    echo [AGENT]        an interactive prompt would block a non-interactive caller forever.
    exit /b 6
  )
  choice /c 45 /n /m "  [4]=RTX 40 series (sm_89)   [5]=RTX 50 series (sm_120): "
  if errorlevel 2 (set "CAP=12.0") else (set "CAP=8.9")
)
if /i "%CAP%"=="12.0" set "ENGINE=%~dp0engine\ninfer-serve-sm120.exe"
if /i "%CAP%"=="8.9" set "ENGINE=%~dp0engine\ninfer-serve.exe"
REM  KV dtype is arch-gated: rk4v4/rk4v4-e8 = Ada/8.9 only, k8v4/nvfp4 = Blackwell/12.0 only.
set "KVTYPE=fp8"
if /i "%CAP%"=="12.0" set "KVTYPE=nvfp4"
if /i "%CAP%"=="8.9" set "KVTYPE=rk4v4"
if /i "%CAP%"=="12.0" if not exist "%ENGINE%" (
  echo [WARN] compute capability 12.0 but the sm_120 engine is missing; using the 8.9 engine.
  echo        A 50-series card will NOT run the 8.9 engine -- put ninfer-serve-sm120.exe
  echo        next to ninfer-serve.exe in engine\ ^(see README^).
  set "ENGINE=%~dp0engine\ninfer-serve.exe"
)
if not "%CAP%"=="8.9" if not "%CAP%"=="12.0" (
  echo [ERROR] this package ships engines for 8.9 ^(RTX 40^) and 12.0 ^(RTX 50^) only.
  echo         Your card reports compute capability %CAP%.
  echo         For 30 series / A100 / H100 use the matching kit, or build from source.
  echo.
if not defined NINFER_AGENT pause
  exit /b 5
)
echo   Card  : compute capability %CAP%
echo   Engine: %ENGINE%
echo.

"%ENGINE%" "%~dp0model\bonsai2_27b_ternary_v2.ninfer" ^
  --host 127.0.0.1 --port 8086 --model-id qwen3.8-27b ^
  --max-context 262144 --kv-capacity 262144 --kv-dtype fp8 ^
  --max-concurrency 1 --no-thinking --vision

echo.
echo [engine exited] errorlevel=%ERRORLEVEL%
if not defined NINFER_AGENT pause
