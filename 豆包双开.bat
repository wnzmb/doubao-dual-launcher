@echo off
chcp 437 >nul
title Doubao Dual Launcher
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo ============================================
echo        DOUBAO DUAL LAUNCHER
echo ============================================
echo.

rem ================= Config =================
set "EXTRA_COUNT=1"
rem set "DOUBAO_PATH=D:\Program Files\Doubao\app\Doubao.exe"
rem ==========================================

set "DOUBAO="
call :FindDoubaoPath
if not defined DOUBAO (
    echo [ERROR] Doubao.exe not found.
    echo.
    echo Please edit this .bat and set:
    echo   set "DOUBAO_PATH=C:\path\to\Doubao.exe"
    echo.
    pause
    exit /b 1
)
echo [1/3] Found: %DOUBAO%

set "PROFILE_ROOT=%~dp0profiles"
if not exist "%PROFILE_ROOT%" mkdir "%PROFILE_ROOT%"
echo [2/3] Profiles: %PROFILE_ROOT%

rem Check if main instance is already running
tasklist /fi "imagename eq Doubao.exe" /nh 2>nul | findstr /i "Doubao.exe" >nul
if errorlevel 1 (
    echo       - Main instance not running, starting it first...
    start "" "%DOUBAO%"
    timeout /t 3 /nobreak >nul
)

echo [3/3] Launching %EXTRA_COUNT% extra instance(s)...
set /a "LAST=2+EXTRA_COUNT-1"
for /l %%i in (2,1,%LAST%) do (
    set "PROFILE_DIR=%PROFILE_ROOT%\instance-%%i"
    if not exist "!PROFILE_DIR!" mkdir "!PROFILE_DIR!"
    echo       - instance %%i
    start "" "%DOUBAO%" --user-data-dir="!PROFILE_DIR!"
)

echo.
echo Done!
pause
exit /b 0

:FindDoubaoPath
if defined DOUBAO_PATH if exist "%DOUBAO_PATH%" set "DOUBAO=%DOUBAO_PATH%"

rem 1) Common fixed paths - scan all drive letters C: through Z:
if not defined DOUBAO (
    for %%d in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
        if not defined DOUBAO if exist "%%d:\Program Files\Doubao\app\Doubao.exe" set "DOUBAO=%%d:\Program Files\Doubao\app\Doubao.exe"
        if not defined DOUBAO if exist "%%d:\Program Files (x86)\Doubao\app\Doubao.exe" set "DOUBAO=%%d:\Program Files (x86)\Doubao\app\Doubao.exe"
    )
    if not defined DOUBAO if exist "%LOCALAPPDATA%\Programs\Doubao\app\Doubao.exe" set "DOUBAO=%LOCALAPPDATA%\Programs\Doubao\app\Doubao.exe"
    if not defined DOUBAO if exist "%LOCALAPPDATA%\Doubao\app\Doubao.exe" set "DOUBAO=%LOCALAPPDATA%\Doubao\app\Doubao.exe"
)

rem 2) Squirrel dynamic dir
if not defined DOUBAO (
    for /d %%d in ("%LOCALAPPDATA%\Doubao\app-*") do (
        if not defined DOUBAO if exist "%%d\Doubao.exe" set "DOUBAO=%%d\Doubao.exe"
    )
)

rem 3) Running process (wmic)
if not defined DOUBAO (
    for /f "delims=" %%e in ('wmic process where "name='Doubao.exe'" get ExecutablePath /value 2^>nul ^| findstr /r /c:"ExecutablePath=."') do (
        for /f "tokens=2 delims==" %%v in ("%%e") do (
            if not defined DOUBAO if exist "%%v" set "DOUBAO=%%v"
        )
    )
)

rem 4) Registry fallback via PowerShell (covers custom install dirs)
if not defined DOUBAO (
    for /f "delims=" %%v in ('powershell -NoProfile -OutputFormat Text -EncodedCommand RwBlAHQALQBJAHQAZQBtAFAAcgBvAHAAZQByAHQAeQAgACcASABLAEMAVQA6AFwAUwBPAEYAVABXAEEAUgBFAFwATQBpAGMAcgBvAHMAbwBmAHQAXABXAGkAbgBkAG8AdwBzAFwAQwB1AHIAcgBlAG4AdABWAGUAcgBzAGkAbwBuAFwAVQBuAGkAbgBzAHQAYQBsAGwAXAAqACcALAAnAEgASwBMAE0AOgBcAFMATwBGAFQAVwBBAFIARQBcAE0AaQBjAHIAbwBzAG8AZgB0AFwAVwBpAG4AZABvAHcAcwBcAEMAdQByAHIAZQBuAHQAVgBlAHIAcwBpAG8AbgBcAFUAbgBpAG4AcwB0AGEAbABsAFwAKgAnACwAJwBIAEsATABNADoAXABTAE8ARgBUAFcAQQBSAEUAXABXAE8AVwA2ADQAMwAyAE4AbwBkAGUAXABNAGkAYwByAG8AcwBvAGYAdABcAFcAaQBuAGQAbwB3AHMAXABDAHUAcgByAGUAbgB0AFYAZQByAHMAaQBvAG4AXABVAG4AaQBuAHMAdABhAGwAbABcACoAJwAgAC0ARQByAHIAbwByAEEAYwB0AGkAbwBuACAAUwBpAGwAZQBuAHQAbAB5AEMAbwBuAHQAaQBuAHUAZQAgAHwAIABXAGgAZQByAGUALQBPAGIAagBlAGMAdAAgAHsAJABfAC4ARABpAHMAcABsAGEAeQBOAGEAbQBlACAALQBtAGEAdABjAGgAIAAnAGQAbwB1AGIAYQBvAHwARowFUycAfQAgAHwAIABGAG8AcgBFAGEAYwBoAC0ATwBiAGoAZQBjAHQAIAB7ACAAJABpAD0AKAAkAF8ALgBEAGkAcwBwAGwAYQB5AEkAYwBvAG4AIAAtAHMAcABsAGkAdAAgACcALAAnACkAWwAwAF0ALgBUAHIAaQBtACgAWwBjAGgAYQByAF0AMwA0ACkAOwAgAGkAZgAoACQAaQApAHsAIABXAHIAaQB0AGUALQBPAHUAdABwAHUAdAAgACgASgBvAGkAbgAtAFAAYQB0AGgAIAAoAFMAcABsAGkAdAAtAFAAYQB0AGgAIAAkAGkAIAAtAFAAYQByAGUAbgB0ACkAIAAnAGEAcABwAFwARABvAHUAYgBhAG8ALgBlAHgAZQAnACkAIAB9ACAAfQA= 2^>nul') do (
        echo %%v | findstr /i ".exe" >nul && if not defined DOUBAO if exist "%%v" set "DOUBAO=%%v"
    )
)

goto :EOF