@echo off
pushd "%~dp0"
"fasm\fasm.exe" "main.asm" "debug86-win32.exe"
start "" "debug86-win32.exe"
popd
pause