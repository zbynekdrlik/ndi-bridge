@echo off
REM Script to generate DeckLink API files from IDL
REM Run this from Visual Studio Developer Command Prompt

echo Generating DeckLink API files...

REM Check if midl.exe is available
where midl >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: midl.exe not found!
    echo Please run this script from Visual Studio Developer Command Prompt
    pause
    exit /b 1
)

REM Check if DeckLinkAPI.idl exists
if not exist "DeckLinkAPI.idl" (
    echo ERROR: DeckLinkAPI.idl not found!
    echo Please run this script from the DeckLink SDK include directory
    pause
    exit /b 1
)

REM Generate the files
echo Running MIDL compiler...
midl /h DeckLinkAPI_h.h /iid DeckLinkAPI_i.c DeckLinkAPI.idl

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Success! Generated files:
    echo - DeckLinkAPI_h.h
    echo - DeckLinkAPI_i.c
    echo.
    echo Now copy these files to your project's docs/reference/ directory
) else (
    echo.
    echo ERROR: MIDL compilation failed!
)

pause
