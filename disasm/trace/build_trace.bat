@echo off
rem Builds tgtrace.exe (the ROM tracing harness) with Visual Studio 2022.
setlocal
cd /d "%~dp0"
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cl /nologo /O2 /EHsc /std:c++17 /W3 /D_CRT_SECURE_NO_WARNINGS /I. tgtrace.cpp /Fe:tgtrace.exe /Fo:tgtrace.obj || exit /b 1
del tgtrace.obj
