@echo off
title Windows Update Repair Tool
color 0A
echo ====================================
echo Windows Update Repair Tool
echo ====================================
echo.
echo [1/4] Stop services
Stop-Service "wuauserv" -Force | Stop-Service "cryptSvc" -Force | Stop-Service "bits" -Force | Stop-Service "msiserver" -Force
echo.
echo [2/4] Delete Windows Update Repository
echo.
remove-item “C:\Windows\SoftwareDistribution” -recurse | remove-item “SoftwareDistribution.old” -recurse
echo [3/4] Start Services
echo.
Start-Service "wuauserv" | Start-Service "cryptSvc" | Start-Service "bits" | Start-Service "msiserver"
echo.
echo [4/4] Checking Windows Update
wuauclt.exe /detectnow
