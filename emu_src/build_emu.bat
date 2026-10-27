@echo off
rem Build tailgunner_emu.exe: the Tail Gunner ROM on AAE's CCPU core (cpu\ccpu.cpp
rem and cpu\cinematronics_video.cpp, compiled UNMODIFIED from cpu\)
rem behind the vendored Windows backend in platform\ (x64, VS2022 cl).
rem Modelled on the Tempest emulator's build_emu.bat.
rem   /Iaae /Iplatform : find our deftypes.h / aae_mame_driver.h (cpu\ has neither)
rem   /Icpu            : finds ccpu.h / cinematronics_video.h
rem Objects go to obj\.
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -no_logo
cd /d "%~dp0"

for %%f in (cpu\ccpu.cpp cpu\ccpu.h cpu\cinematronics_video.cpp tg_main.cpp tg_board.cpp tg_sound.cpp) do if not exist %%f (echo MISSING %%f & exit /b 1)
if not exist obj mkdir obj

rem ---- vendored framework (C), their own warning level -------------------
cl /nologo /O2 /W3 /MD /D_CRT_SECURE_NO_WARNINGS /DUNICODE /D_UNICODE /c ^
   platform\sys_gl.c platform\glew.c platform\log.c platform\vector_draw.c ^
   platform\mat4.c platform\rawinput.c platform\mixer.c platform\fileio.c ^
   platform\miniz.c platform\ini.c platform\joystick.c ^
   /Foobj\ || exit /b 1

rem ---- vendored monitor_select (C++) and the AAE cpu\ files, /W3 ---------
cl /nologo /O2 /W3 /EHsc /std:c++17 /MD /D_CRT_SECURE_NO_WARNINGS /DUNICODE /D_UNICODE /Iaae /Iplatform /c ^
   platform\monitor_select.cpp /Foobj\ || exit /b 1
cl /nologo /O2 /W3 /EHsc /std:c++17 /MD /D_CRT_SECURE_NO_WARNINGS /Iaae /Iplatform /c ^
   cpu\ccpu.cpp cpu\cinematronics_video.cpp /Foobj\ || exit /b 1

rem ---- our files (/W4) and the link ---------------------------------------
echo === tailgunner_emu.exe
cl /nologo /O2 /W4 /EHsc /std:c++17 /MD /D_CRT_SECURE_NO_WARNINGS /Iaae /Iplatform /Icpu /Foobj\ ^
   tg_main.cpp tg_board.cpp tg_sound.cpp ^
   obj\ccpu.obj obj\cinematronics_video.obj obj\monitor_select.obj ^
   obj\sys_gl.obj obj\glew.obj obj\log.obj obj\vector_draw.obj ^
   obj\mat4.obj obj\rawinput.obj obj\mixer.obj obj\fileio.obj ^
   obj\miniz.obj obj\ini.obj obj\joystick.obj ^
   /Fe:tailgunner_emu.exe ^
   /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib winmm.lib ole32.lib dwmapi.lib || exit /b 1

echo EMU BUILD OK
