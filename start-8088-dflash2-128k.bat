@echo off
REM ============================================================
REM  STEP 5 (tier build) -- DFlash2 K=7 at 128K context: the FAST long-context
REM  launcher for the 128K-context variant (port 8088; weights 9.10 GiB + fp8 KV ~4 GiB).
REM
REM  Why this is the recommended default on a big card (measured on an
REM  RTX 5090 D, SAME binary, NO rebuild):
REM      MTP d3              250-268 t/s
REM      best MTP            343.8   t/s
REM      DFlash2 K=7 counting 512.9  t/s   accept 522/533 = 97.9%
REM      DFlash2 K=7 prose    154.7  t/s   accept 346/1763 = 19.6%
REM    Throughput = step-rate x (1 + K x accept): 1 + 7*0.979 = 7.85
REM    tok/step, x 65.2 steps/s = 512 t/s.  Step-rate is a property of
REM    the CARD; accept-rate is a property of the CONTENT (it reproduces
REM    to the exact integer across cards).  Report both, always.
REM
REM  ASCII-only on purpose: cmd parses this file in the OEM/ANSI
REM  codepage, so non-ASCII text here corrupts the commands themselves.
REM ============================================================

REM  CUDA toolkit is NOT required: the engine uses the driver-side CUDA runtime.
REM  Set CUDA_BIN only if the engine dies with 0xC0000135.
set "CUDA_BIN="
if not defined CUDA_BIN (
  for /d %%D in ("%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v13*") do set "CUDA_BIN=%%~fD\bin"
)
if not defined CUDA_BIN (
  for /d %%D in ("%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v12*") do set "CUDA_BIN=%%~fD\bin"
)
if not defined CUDA_BIN set "CUDA_BIN=%~dp0engine"
set "PATH=%CUDA_BIN%;%CUDA_BIN%\x64;%PATH%"
cd /d "%~dp0engine"

echo   Config: max-context 131072  kv fp8  spec dflash2 7  + --lm-head-draft   Port 8088
echo   Expect: weights 9.10 GiB + fp8 KV about 4.0 GiB at 131072 =^> about 15 GB total
echo   Needs : a card with 24 GB or more (16 GB cards: use start-3 or start-4)
echo   --lm-head-draft is MANDATORY here: without it the engine dies at startup with
echo       FATAL server failed during startup ^| linear_topk: unsupported head profile
echo.
set "MODEL=%~dp0model\bonsai2_27b_ternary_v2-dflash2.ninfer"
if not exist "%MODEL%" (
  echo [MISSING] %MODEL%
  echo           This launcher needs the DFlash2 artifact. Steps 0-2 work with the file you have.
  echo.
if not defined NINFER_AGENT pause
  exit /b 2
)
REM ---- pick the engine that matches THIS card's architecture ------------------
REM  The two binaries are arch-specific and neither carries PTX for the other arch:
REM    ninfer-serve.exe = sm_89 (RTX 40)   ninfer-serve-sm120.exe = sm_120 (RTX 50)
REM  Running the wrong one does NOT fall back -- it dies/wedges with no kernel image.
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
REM ---- VRAM floor: 131072 context + DFlash2 needs about 15 GB in total ----
set "TOTALMB="
for /f "skip=1 tokens=1" %%M in ('nvidia-smi --query-gpu=memory.total --format=csv 2^>NUL') do if not defined TOTALMB set "TOTALMB=%%M"
set "V="
if defined TOTALMB set /a V=TOTALMB 2>nul
set "LOWVRAM="
if not defined V set "LOWVRAM=1"
if defined V if %V% LSS 24000 set "LOWVRAM=1"
if defined LOWVRAM (
  echo [WARN] this card reports less than 24 GB of VRAM, or VRAM could not be read.
  echo        131072 context + DFlash2 needs about 15 GB. If the engine refuses to start
  echo        ^(it prints how many bytes are missing^), use start-3 ^(32768^) instead.
  echo.
)
echo   Card  : compute capability %CAP%
echo   Engine: %ENGINE%
echo.

"%ENGINE%" "%MODEL%" ^
  --host 127.0.0.1 --port 8088 --model-id qwen3.8-27b ^
  --max-context 131072 --kv-capacity 131072 --kv-dtype fp8 ^
  --max-concurrency 1 --no-thinking --spec dflash2 --draft-tokens 7 --lm-head-draft

echo.
echo [engine exited] errorlevel=%ERRORLEVEL%
if not defined NINFER_AGENT pause
