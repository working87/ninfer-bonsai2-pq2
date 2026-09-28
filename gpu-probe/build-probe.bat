@echo off
rem ============================================================================
rem  build-probe.bat -- build the SELF-CONTAINED gpu-probe.exe
rem  (end users do NOT need a CUDA toolkit; -cudart=static = no cudart64_*.dll)
rem
rem  ASCII-only on purpose: cmd.exe reads a BOM-less file as OEM codepage (936
rem  here), so a comment containing UTF-8 Chinese text gets chopped into bogus
rem  commands. Keep this file ASCII.
rem
rem  What it does:
rem    nvcc -O2 with sm_89 cubin + compute_89 PTX embedded.
rem    8.9 cards run the sm_89 cubin natively; newer cards (12.0) JIT the PTX.
rem  Known pitfall (cost us a round): the .cu carries Chinese comments in UTF-8,
rem    but cmd/CL default to codepage 936 (GBK). Without /utf-8 the compiler
rem    mis-reads those bytes and the parser dies with a nonsense
rem    "expected a declaration" on the line AFTER the comment - it looks like a
rem    missing semicolon and sends you hunting in the wrong place. Always pass
rem    -Xcompiler "/utf-8" (also silences the C4819 warning).
rem  Pitfall 2: cudart_static.lib ships objects built against the old static CRT
rem    (libcmt); mixing it with /MT gives LNK2005/LNK4098. Do NOT "fix" that
rem    with /NODEFAULTLIB:libcmt - that strips the whole CRT and you get 75
rem    unresolved externals (atexit, printf, memset, mainCRTStartup...).
rem    Correct combination: dynamic CRT (/MD, msvcrt.dll - present on every
rem    Windows) + -cudart=static (so no cudart64_*.dll next to the exe).
rem ============================================================================
setlocal
rem ---- toolchain: from env, else auto-discover (no drive letter is assumed) ----
if not defined VCVARS (
  for %%P in ("%ProgramFiles%\Microsoft Visual Studio\2022\Community" "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools" "%SystemDrive%\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" "%SystemDrive%\Program Files (x86)\Microsoft Visual Studio\18\BuildTools") do (
    if not defined VCVARS if exist "%%~P\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=%%~P\VC\Auxiliary\Build\vcvars64.bat"
  )
)
if not defined VCVARS ( echo [ERROR] set VCVARS=your vcvars64.bat path and run again & exit /b 90 )
call "%VCVARS%" >nul 2>&1
if errorlevel 1 ( echo VCVARS_FAILED & exit /b 90 )
if not defined CUDA_PATH (
  for %%V in (v13.3 v13.2 v13.1 v13.0 v12.9 v12.8 v12.6 v12.4) do (
    if not defined CUDA_PATH if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\%%V\bin\nvcc.exe" set "CUDA_PATH=%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\%%V"
  )
)
if not defined CUDA_PATH ( echo [ERROR] set CUDA_PATH=your CUDA toolkit root and run again & exit /b 92 )
set "PATH=%CUDA_PATH%\bin;%CUDA_PATH%\bin\x64;%PATH%"
set "SRC=%~dp0gpu-probe.cu"
set "OUT=%~dp0gpu-probe.exe"

nvcc -O2 -o "%OUT%" "%SRC%" ^
  -gencode arch=compute_89,code=sm_89 ^
  -gencode arch=compute_89,code=compute_89 ^
  -cudart=static -Xcompiler "/utf-8"
echo NVCC_EXIT=%ERRORLEVEL%
if not exist "%OUT%" ( echo [FAIL] no output: %OUT% & exit /b 5 )
for %%F in ("%OUT%") do echo SIZE=%%~zF
endlocal
