@echo off
setlocal
set OTM=otime.otm
set SRC=src/program.odin

if not exist "build" ( mkdir build )

otime.exe -begin %OTM%
echo Compiling with opt=%1...
odin build %SRC% -opt=%1 -collection=mantle=../odin-mantle
set ERR=%ERRORLEVEL%

if %ERR%==0 ( goto :build_success ) else ( goto :build_failed )

:build_success
    mv -f ./src/*.exe ./build
    echo Build Success
    otime -end %OTM% %ERR%
exit

:build_failed
    echo Build Failed
    otime -end %OTM% %ERR%
exit