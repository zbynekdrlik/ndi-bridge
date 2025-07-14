@echo off
REM Script to generate DeckLink API files from IDL
REM Run this from Visual Studio Developer Command Prompt from the project root or scripts directory

echo Generating DeckLink API files...

REM Check if midl.exe is available
where midl >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: midl.exe not found!
    echo Please run this script from Visual Studio Developer Command Prompt
    pause
    exit /b 1
)

REM Determine paths based on where script is run from
if exist "scripts\generate-decklink-api.bat" (
    REM Running from project root
    set REFERENCE_DIR=docs\reference
) else if exist "generate-decklink-api.bat" (
    REM Running from scripts directory
    set REFERENCE_DIR=..\docs\reference
) else (
    echo ERROR: Cannot determine project structure!
    echo Please run this script from the project root or scripts directory
    pause
    exit /b 1
)

REM Check if DeckLinkAPI.idl exists in reference directory
if not exist "%REFERENCE_DIR%\DeckLinkAPI.idl" (
    echo ERROR: DeckLinkAPI.idl not found in %REFERENCE_DIR%!
    echo.
    echo Please copy the following files from DeckLink SDK to %REFERENCE_DIR%:
    echo - DeckLinkAPI.idl
    echo - DeckLinkAPI_i.c (if it exists pre-generated)
    echo.
    echo From: Blackmagic DeckLink SDK\Win\include\
    echo To:   %REFERENCE_DIR%\
    pause
    exit /b 1
)

REM Change to reference directory
pushd "%REFERENCE_DIR%"

REM Generate the files
echo Running MIDL compiler in %CD%...
midl /h DeckLinkAPI_h.h /iid DeckLinkAPI_i.c DeckLinkAPI.idl

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Success! Generated files:
    echo - %CD%\DeckLinkAPI_h.h
    echo - %CD%\DeckLinkAPI_i.c
    echo.
    echo These files are now ready for building the project.
    
    REM Clean up MIDL temporary files
    if exist DeckLinkAPI.tlb del /q DeckLinkAPI.tlb
    if exist dlldata.c del /q dlldata.c
    if exist DeckLinkAPI_p.c del /q DeckLinkAPI_p.c
) else (
    echo.
    echo ERROR: MIDL compilation failed!
    echo Check the error messages above.
)

REM Return to original directory
popd

pause
