@echo off
rem Build WPlayer: scripts\build.cmd [Release|Debug] [path\to\Qt\msvc2022_64]
setlocal

set "CONFIG=%~1"
if "%CONFIG%"=="" set "CONFIG=Release"
set "QT_DIR=%~2"
if "%QT_DIR%"=="" set "QT_DIR=C:\Qt\6.8.3\msvc2022_64"

set "ROOT=%~dp0.."
set "BUILD=%ROOT%\build\%CONFIG%"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (
    echo Visual Studio with C++ tools not found
    exit /b 1
)

call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

cmake -S "%ROOT%" -B "%BUILD%" -G Ninja -DCMAKE_BUILD_TYPE=%CONFIG% "-DCMAKE_PREFIX_PATH=%QT_DIR%" || exit /b 1
cmake --build "%BUILD%" || exit /b 1

echo.
echo Done: %BUILD%\WPlayer.exe
