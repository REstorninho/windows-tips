@echo off
title Windows Update Repair Tool
color 0A
echo ====================================
echo Windows Update Repair Tool
echo ====================================
echo.
echo [1/4] Stop services
Stop-Service -Name "wuauserv" -Force | Stop-Service -Name "cryptSvc" -Force | Stop-Service -Name "bits" -Force | Stop-Service -Name "msiserver" -Force
echo.
echo [2/4] Delete Windows Update Repository
echo.
remove-item “C:\Windows\SoftwareDistribution” -recurse | remove-item “SoftwareDistribution.old” -recurse
echo [3/4] Start Services
echo.
Start-Service -Name "wuauserv" | Start-Service -Name "cryptSvc" | Start-Service -Name "bits" | Start-Service -Name "msiserver"
echo.
echo [4/4] Checking Windows Update
wuauclt.exe /detectnow
