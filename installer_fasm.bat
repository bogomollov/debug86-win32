@echo off
setlocal

echo FASM installer for Windows
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; $dir = Join-Path (Get-Location) 'fasm'; if (Test-Path $dir) { Write-Host ('Existing folder found: ' + $dir); $answer = Read-Host 'Re-download and reinstall? (y/n)'; if ($answer -notmatch '^[yY]') { Write-Host 'Cancelled.'; exit 0 }; Write-Host 'Removing existing folder...'; Remove-Item -Path $dir -Recurse -Force }; Write-Host 'Checking latest version...'; $page = (Invoke-WebRequest -Uri 'https://flatassembler.net/download.php' -UseBasicParsing).Content; if ($page -match 'fasmw(\d+)\.zip') { $ver = $matches[1]; $url = 'https://flatassembler.net/fasmw' + $ver + '.zip'; Write-Host ('Version: ' + $ver); Write-Host ('Downloading ' + $url + '...'); Invoke-WebRequest -Uri $url -OutFile 'fasmw.zip' -UseBasicParsing; Write-Host ('Unzip to ' + $dir + '...'); New-Item -ItemType Directory -Path $dir -Force | Out-Null; Expand-Archive -Path 'fasmw.zip' -DestinationPath $dir -Force; Remove-Item 'fasmw.zip' -Force; Write-Host 'Done' } else { Write-Error 'Not found fasm url in downloading page' }"

if %errorlevel% neq 0 (
    echo.
    echo An error occurred. Check your internet connection and write permissions for the current folder
)

pause
endlocal