@echo off
pushd "%~dp0"
"fasm\fasm.exe" "main.asm" "main.exe"
start "" "main.exe"
popd
pause