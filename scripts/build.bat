@echo off
REM CloudAudiobook 构建脚本 (Windows)
REM 用法: scripts\build.bat [windows|android|all] [debug|profile|release]
REM 默认: scripts\build.bat all release

setlocal enabledelayedexpansion

set PLATFORM=%1
set MODE=%2
if "%PLATFORM%"=="" set PLATFORM=all
if "%MODE%"=="" set MODE=release

set PROJECT_ROOT=%~dp0..
set BUILD_APPS_DIR=%PROJECT_ROOT%\..\app

cd /d "%PROJECT_ROOT%"

echo ========================================
echo   云听书 CloudAudiobook 构建脚本
echo   平台: %PLATFORM%  模式: %MODE%
echo ========================================
echo.

REM 获取依赖
echo [依赖] 获取 Flutter 依赖...
call flutter pub get
echo.

REM 获取版本号
for /f "tokens=2" %%v in ('findstr "^version:" pubspec.yaml') do set VERSION=%%v
set VERSION=%VERSION: =%

if "%PLATFORM%"=="windows" goto build_windows
if "%PLATFORM%"=="android" goto build_android
if "%PLATFORM%"=="all" goto build_all
echo 用法: build.bat [windows^|android^|all] [debug^|profile^|release]
exit /b 1

:build_all
call :build_windows
call :build_android
goto done

:build_windows
echo [Windows] 构建 %MODE% 版本...

REM 确保 mpv 文件存在
set MPV_FILE=build\windows\x64\mpv-dev-x86_64-20230924-git-652a1dd.7z
if not exist "%MPV_FILE%" (
    echo [Windows] 下载 mpv 音频库...
    mkdir build\windows\x64 2>nul
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z' -OutFile '%MPV_FILE%'"
)

call flutter build windows --%MODE%

REM 归档
set MODE_CAP=%MODE%
for %%c in (Release Profile Debug) do if /i "%MODE%"=="%%c" set MODE_CAP=%%c
set DEST=%BUILD_APPS_DIR%\%MODE_CAP%\windows
mkdir "%DEST%" 2>nul
rmdir /s /q "%DEST%" 2>nul
xcopy /e /y "build\windows\x64\runner\%MODE_CAP%" "%DEST%\" >nul
echo [Windows] 完成 ^> %DEST%
exit /b

:build_android
echo [Android] 构建 %MODE% 版本...
call flutter build apk --%MODE%

set MODE_CAP=%MODE%
for %%c in (Release Profile Debug) do if /i "%MODE%"=="%%c" set MODE_CAP=%%c
set DEST=%BUILD_APPS_DIR%\%MODE_CAP%\android
mkdir "%DEST%" 2>nul
copy /y "build\app\outputs\flutter-apk\app-%MODE%.apk" "%DEST%\" >nul
echo [Android] 完成 ^> %DEST%\app-%MODE%.apk
exit /b

:done
echo.
echo ========================================
echo   构建完成! 版本: %VERSION%
echo   产物目录: %BUILD_APPS_DIR%
echo ========================================
dir "%BUILD_APPS_DIR%" 2>nul
endlocal
