@echo off
REM NDI SDK Setup Helper for NDI Bridge
REM This script helps set up the NDI SDK in the deps/ndi directory

echo ========================================
echo NDI SDK Setup Helper for NDI Bridge
echo ========================================
echo.

REM Check if we're in the right directory
if not exist "CMakeLists.txt" (
    echo ERROR: Please run this script from the ndi-bridge project root directory
    echo        The directory containing CMakeLists.txt
    pause
    exit /b 1
)

REM Create deps/ndi directory structure
echo Creating directory structure...
if not exist "deps" mkdir deps
if not exist "deps\ndi" mkdir deps\ndi
if not exist "deps\ndi\include" mkdir deps\ndi\include
if not exist "deps\ndi\lib" mkdir deps\ndi\lib
if not exist "deps\ndi\lib\x64" mkdir deps\ndi\lib\x64

echo.
echo Directory structure created:
echo   deps\ndi\
echo   ├── include\
echo   └── lib\
echo       └── x64\
echo.

REM Check for NDI SDK in common locations
echo Searching for NDI SDK installation...
set NDI_FOUND=0

REM Check NDI 6 SDK
if exist "C:\Program Files\NDI\NDI 6 SDK\Include\Processing.NDI.Lib.h" (
    echo Found NDI 6 SDK
    set NDI_PATH=C:\Program Files\NDI\NDI 6 SDK
    set NDI_FOUND=1
    goto :copy_files
)

REM Check NDI 5 SDK
if exist "C:\Program Files\NDI\NDI 5 SDK\Include\Processing.NDI.Lib.h" (
    echo Found NDI 5 SDK
    set NDI_PATH=C:\Program Files\NDI\NDI 5 SDK
    set NDI_FOUND=1
    goto :copy_files
)

REM Check NewTek location
if exist "C:\Program Files\NewTek\NDI SDK\Include\Processing.NDI.Lib.h" (
    echo Found NDI SDK at NewTek location
    set NDI_PATH=C:\Program Files\NewTek\NDI SDK
    set NDI_FOUND=1
    goto :copy_files
)

REM Check environment variable
if defined NDI_SDK_DIR (
    if exist "%NDI_SDK_DIR%\Include\Processing.NDI.Lib.h" (
        echo Found NDI SDK via NDI_SDK_DIR environment variable
        set NDI_PATH=%NDI_SDK_DIR%
        set NDI_FOUND=1
        goto :copy_files
    )
)

:copy_files
if %NDI_FOUND%==1 (
    echo.
    echo Copying NDI SDK files from: %NDI_PATH%
    
    REM Copy header files
    echo Copying header files...
    xcopy /Y "%NDI_PATH%\Include\*" "deps\ndi\include\" > nul
    
    REM Copy library files
    echo Copying library files...
    xcopy /Y "%NDI_PATH%\Lib\x64\*" "deps\ndi\lib\x64\" > nul
    
    echo.
    echo NDI SDK files copied successfully!
    echo.
    echo You can now build the project.
) else (
    echo.
    echo WARNING: NDI SDK not found in standard locations!
    echo.
    echo Please:
    echo 1. Download the NDI SDK from https://ndi.video/for-developers/ndi-sdk/
    echo 2. Install it or extract it somewhere
    echo 3. Either:
    echo    a) Install to default location (C:\Program Files\NDI\NDI x SDK\)
    echo    b) Set NDI_SDK_DIR environment variable to your NDI SDK path
    echo    c) Manually copy the files to deps\ndi\:
    echo       - Copy Include\* to deps\ndi\include\
    echo       - Copy Lib\x64\* to deps\ndi\lib\x64\
    echo.
)

pause
