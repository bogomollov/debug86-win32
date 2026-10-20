@echo off
pushd "%~dp0"
"fasm\fasm.exe" "source/main.asm" "debug86-win32.exe"
popd
