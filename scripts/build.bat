@echo off
setlocal enabledelayedexpansion

set PLATFORM=%1
set MODE=%2
if "%PLATFORM%"=="" set PLATFORM=all
if "%MODE%"=="" set MODE=release

set PROJECT_ROOT=%~dp0..
set BUILD_APPS_DIR=%PROJECT_ROOT%\..\app

cd /d "%PROJECT_ROOT%"

echo ========================================
echo   YunTingShu build script
echo   Platform: %PLATFORM%  Mode: %MODE%
echo ========================================
echo.

echo [INFO] Getting Flutter dependencies...
call flutter pub get
echo.

for /f "tokens=2" %%v in ('findstr "^version:" pubspec.yaml') do set VERSION=%%v

if "%PLATFORM%"=="windows" call :build_windows
if "%PLATFORM%"=="android" call :build_android
if "%PLATFORM%"=="all" call :build_all
if "%PLATFORM%"=="windows" goto done
if "%PLATFORM%"=="android" goto done
if "%PLATFORM%"=="all" goto done

echo Usage: build.bat [windows^|android^|all] [debug^|profile^|release]
exit /b 1

:build_all
call :build_windows
call :build_android
exit /b

:build_windows
echo [Windows] Building %MODE% ...

set MPV_FILE=build\windows\x64\mpv-dev-x86_64-20230924-git-652a1dd.7z
if not exist "%MPV_FILE%" (
    echo [Windows] Downloading mpv library...
    mkdir build\windows\x64 2>nul
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z' -OutFile '%MPV_FILE%'"
)

call flutter build windows --%MODE%

if /i "%MODE%"=="release" set MODE_CAP=Release
if /i "%MODE%"=="profile" set MODE_CAP=Profile
if /i "%MODE%"=="debug" set MODE_CAP=Debug

set DEST=%BUILD_APPS_DIR%\%MODE_CAP%\windows
mkdir "%DEST%" 2>nul
rmdir /s /q "%DEST%" 2>nul
xcopy /e /y "build\windows\x64\runner\%MODE_CAP%" "%DEST%\" >nul
echo [Windows] Done: %DEST%
exit /b

:build_android
echo [Android] Building %MODE% ...

call flutter build apk --%MODE%

if /i "%MODE%"=="release" set MODE_CAP=Release
if /i "%MODE%"=="profile" set MODE_CAP=Profile
if /i "%MODE%"=="debug" set MODE_CAP=Debug

set DEST=%BUILD_APPS_DIR%\%MODE_CAP%\android
mkdir "%DEST%" 2>nul
copy /y "build\app\outputs\flutter-apk\app-%MODE%.apk" "%DEST%\" >nul
echo [Android] Done: %DEST%\app-%MODE%.apk
exit /b

:done
echo.
echo ========================================
echo   Build complete! Version: %VERSION%
echo   Output: %BUILD_APPS_DIR%
echo ========================================
dir "%BUILD_APPS_DIR%" 2>nul
endlocal
