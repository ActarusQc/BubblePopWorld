@echo off
setlocal
cd /d "%~dp0"

if not exist "%~dp0rojo.exe" (
    echo ERREUR: rojo.exe est introuvable dans ce dossier.
    pause
    exit /b 1
)

if not exist "%~dp0logs" mkdir "%~dp0logs"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$listener = Get-NetTCPConnection -LocalPort 34872 -State Listen -ErrorAction SilentlyContinue; if ($listener) { exit 10 }; Start-Process -FilePath '%~dp0rojo.exe' -ArgumentList @('serve','default.project.json','--address','127.0.0.1','--port','34872','--color','never') -WorkingDirectory '%~dp0' -WindowStyle Hidden -RedirectStandardOutput '%~dp0logs\rojo-output.log' -RedirectStandardError '%~dp0logs\rojo-error.log'"

if errorlevel 10 (
    echo Rojo roule deja en arriere-plan sur le port 34872.
) else if errorlevel 1 (
    echo ERREUR: Rojo n'a pas pu demarrer.
    pause
    exit /b 1
) else (
    echo Rojo a ete lance en arriere-plan sur le port 34872.
)

powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2"
endlocal
