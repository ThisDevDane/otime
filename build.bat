@echo off
setlocal
set OTM=otime.otm
set SRC=src/program.odin
if %2 EQU 1 ( 
    set DEBUG=-debug
)

if not exist "build" ( mkdir build )

otime.exe -begin %OTM%
echo Compiling with opt=%1...
if %2 EQU 1 ( echo Compiling with debug )
odin build %SRC% -opt=%1 -collection=mantle=../odin-mantle %DEBUG%
set ERR=%ERRORLEVEL%

if %ERR%==0 ( goto :build_success ) else ( goto :build_failed )


:build_success
    mv -f ./src/*.exe ./build 2> nul
    mv -f ./src/*.pdb ./build 2> nul
    echo Build Success
    goto :end

:build_failed
    echo Build Failed
    goto :end

:end
    otime -end %OTM% %ERR%