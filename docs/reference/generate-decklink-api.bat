@echo off
REM Generate DeckLink API files from IDL
REM Run this from Visual Studio Developer Command Prompt in the docs/reference directory

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
    echo Please copy DeckLinkAPI.idl from the DeckLink SDK to this directory
    pause
    exit /b 1
)

REM Generate the files
echo Running MIDL compiler...
midl /h DeckLinkAPI_h.h /iid DeckLinkAPI_i.c DeckLinkAPI.idl

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Success! Generated files:
    dir /b DeckLinkAPI_h.h DeckLinkAPI_i.c
    echo.
    
    REM Clean up MIDL temporary files
    if exist DeckLinkAPI.tlb del /q DeckLinkAPI.tlb
    if exist dlldata.c del /q dlldata.c
    if exist DeckLinkAPI_p.c del /q DeckLinkAPI_p.c
    
    echo Build files are ready. You can now build the project with DeckLink support.
) else (
    echo.
    echo ERROR: MIDL compilation failed!
)

pause
