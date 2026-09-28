@echo off
REM ============================================================================
REM  verify-sm-count-configure.bat -- CONFIGURE-ONLY proof that -DNINFER_SM_COUNT
REM  really reaches the compiler in a PACKAGED src-tree.
REM
REM  It never compiles anything (configure only: cmake generates build.ninja, and we
REM  grep the DEFINES line). Two cases:
REM     A) -DNINFER_SM_COUNT=80   -> expect DEFINES ... NINFER_SM_COUNT=80
REM     B) no -DNINFER_SM_COUNT   -> expect the per-arch fallback NINFER_SM_COUNT=128
REM  If A does not show 80, the macro is being ignored and every "rebuild for your
REM  card" instruction in the docs is a no-op.
REM
REM  Usage: verify-sm-count-configure.bat <src-tree> <temp build root>
REM  ASCII only (cmd reads a BOM-less file as OEM codepage 936 here).
REM ============================================================================
setlocal
if "%~1"=="" ( echo USAGE: verify-sm-count-configure.bat ^<src-tree^> ^<temp-root^> & exit /b 20 )
if "%~2"=="" ( echo USAGE: verify-sm-count-configure.bat ^<src-tree^> ^<temp-root^> & exit /b 20 )
set "TREE=%~1"
set "ROOT=%~2"

rem ---- toolchain: from env, else auto-discover (no drive letter is assumed) ----
if not defined VCVARS (
  for %%P in ("%ProgramFiles%\Microsoft Visual Studio\2022\Community" "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools" "%SystemDrive%\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" "%SystemDrive%\Program Files (x86)\Microsoft Visual Studio\18\BuildTools") do (
    if not defined VCVARS if exist "%%~P\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=%%~P\VC\Auxiliary\Build\vcvars64.bat"
  )
)
if not defined VCVARS ( echo [ERROR] set VCVARS=your vcvars64.bat path and run again & exit /b 90 )
call "%VCVARS%" >nul 2>&1
if errorlevel 1 ( echo VCVARS_FAILED & exit /b 90 )
for %%P in ("%ProgramFiles%\Microsoft Visual Studio\2022\Community" "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools" "%SystemDrive%\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" "%SystemDrive%\Program Files (x86)\Microsoft Visual Studio\18\BuildTools") do (
  if exist "%%~P\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja" set "PATH=%%~P\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%%~P\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;%PATH%"
)
if not defined CUDA_PATH (
  for %%V in (v13.3 v13.2 v13.1 v13.0 v12.9 v12.8 v12.6 v12.4) do (
    if not defined CUDA_PATH if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\%%V\bin\nvcc.exe" set "CUDA_PATH=%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\%%V"
  )
)
if not defined CUDA_PATH ( echo [ERROR] set CUDA_PATH=your CUDA toolkit root and run again & exit /b 92 )
set "PATH=%CUDA_PATH%\bin;%CUDA_PATH%\bin\x64;%PATH%"
where cmake.exe >nul 2>&1 || ( echo NO_CMAKE_IN_PATH & exit /b 91 )
where ninja.exe >nul 2>&1 || ( echo NO_NINJA_IN_PATH & exit /b 92 )

echo TREE=%TREE%
echo ROOT=%ROOT%
echo.

set "FAILED=0"

echo ==================== CASE A: -DNINFER_SM_COUNT=80 ====================
if exist "%ROOT%\pass80" rmdir /s /q "%ROOT%\pass80"
cmake -B "%ROOT%\pass80" -S "%TREE%" -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_ARCHITECTURES=89 -DNINFER_CUDA_ARCH=89 ^
  -DNINFER_SM_COUNT=80 ^
  -DNINFER_ENABLE_AVX2=ON -DNINFER_BUILD_MEDIA_ACQUIRE=ON ^
  -DBUILD_TESTING=OFF -DNINFER_BUILD_BENCHMARKS=OFF
if errorlevel 1 ( echo CONFIGURE_FAILED_A & set "FAILED=1" )
echo --- build.ninja NINFER_SM_COUNT hits (case A):
findstr /c:"NINFER_SM_COUNT=" "%ROOT%\pass80\build.ninja" | findstr /c:"DEFINES" | findstr /c:"NINFER_SM_COUNT=80" >nul && (echo   ASSERT_OK: NINFER_SM_COUNT=80 is in the compile definitions) || (echo   ASSERT_FAIL: 80 NOT found in DEFINES & set "FAILED=1")
findstr /c:"NINFER_SM_COUNT=80" "%ROOT%\pass80\build.ninja" >nul && (echo   raw grep: NINFER_SM_COUNT=80 present) || (echo   raw grep: MISSING & set "FAILED=1")
echo.
echo sample DEFINES line (case A):
for /f "tokens=1,* delims=:" %%a in ('findstr /c:"NINFER_SM_COUNT=80" "%ROOT%\pass80\build.ninja"') do (echo   %%b & goto :afterA)
:afterA
echo.

echo ==================== CASE B: no -DNINFER_SM_COUNT ====================
if exist "%ROOT%\default" rmdir /s /q "%ROOT%\default"
cmake -B "%ROOT%\default" -S "%TREE%" -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_ARCHITECTURES=89 -DNINFER_CUDA_ARCH=89 ^
  -DNINFER_ENABLE_AVX2=ON -DNINFER_BUILD_MEDIA_ACQUIRE=ON ^
  -DBUILD_TESTING=OFF -DNINFER_BUILD_BENCHMARKS=OFF
if errorlevel 1 ( echo CONFIGURE_FAILED_B & set "FAILED=1" )
echo --- build.ninja NINFER_SM_COUNT hits (case B, expect the 128 fallback):
findstr /c:"NINFER_SM_COUNT=128" "%ROOT%\default\build.ninja" >nul && (echo   ASSERT_OK: fallback NINFER_SM_COUNT=128 present) || (echo   ASSERT_FAIL: fallback 128 missing & set "FAILED=1")
findstr /c:"NINFER_SM120" "%ROOT%\default\build.ninja" >nul && (echo   ASSERT_WARN: NINFER_SM120 unexpectedly defined) || (echo   OK: no NINFER_SM120 in a 89 build)
findstr /c:"NINFER_SM89=1" "%ROOT%\default\build.ninja" >nul && (echo   ASSERT_OK: NINFER_SM89=1 present) || (echo   ASSERT_FAIL: NINFER_SM89=1 missing & set "FAILED=1")
echo.

echo ==================== CASE C: 120a accepts and yields 170 ====================
if exist "%ROOT%\pass120" rmdir /s /q "%ROOT%\pass120"
cmake -B "%ROOT%\pass120" -S "%TREE%" -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_ARCHITECTURES=120a -DNINFER_CUDA_ARCH=120a ^
  -DNINFER_SM_COUNT=170 ^
  -DBUILD_TESTING=OFF -DNINFER_BUILD_BENCHMARKS=OFF
if errorlevel 1 ( echo CONFIGURE_FAILED_C & set "FAILED=1" )
findstr /c:"NINFER_SM_COUNT=170" "%ROOT%\pass120\build.ninja" >nul && (echo   ASSERT_OK: NINFER_SM_COUNT=170 present) || (echo   ASSERT_FAIL: 170 missing & set "FAILED=1")
findstr /c:"NINFER_SM120=1" "%ROOT%\pass120\build.ninja" >nul && (echo   ASSERT_OK: NINFER_SM120=1 present) || (echo   ASSERT_FAIL: NINFER_SM120=1 missing & set "FAILED=1")
echo.

if "%FAILED%"=="0" ( echo ==== VERIFY_RESULT=PASS ==== ) else ( echo ==== VERIFY_RESULT=FAIL ==== )
exit /b %FAILED%
