@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$listeners = Get-NetTCPConnection -LocalPort 34872 -State Listen -ErrorAction SilentlyContinue; foreach ($listener in $listeners) { Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue }"

echo Rojo en arriere-plan a ete arrete.
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2"
endlocal
