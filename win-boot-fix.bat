@echo off
title Ultimate Windows Repair Tool
color 0A
echo ====================================
echo Starting Windows Repair...
echo ====================================
echo.
echo [1/8] Checking System Files...
sfc /scannow
echo.
echo [2/8] Repairing Windows Image...
DISM /Online /Cleanup-Image /RestoreHealth
echo.
echo [3/8] Checking Component Store...
DISM /Online /Cleanup-Image /ScanHealth
echo.
echo [4/8] Cleaning Component Store...
DISM /Online /Cleanup-Image /StartComponentCleanup
echo.
echo [5/8] Checking Disk...
chkdsk C: /f
echo.
echo [6/8] Repairing Network Stack...
ipconfig /flushdns
netsh winsock reset
netsh int ip reset
echo.
echo [7/8] Generating System Report...
systeminfo > System_Report.txt
echo.
echo [8/8] Boot Repair Commands
echo These typically require Windows Recovery Environment.
bootrec /fixmbr
bootrec /fixboot
bootrec /rebuildbcd
echo.
echo ====================================
echo Repair Process Complete
echo Restart your PC.
echo ====================================
pause
