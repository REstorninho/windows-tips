@echo off
Windows Update Repair Tool
color 0A
echo ====================================
echo Windows Update Repair Tool
echo ====================================
echo.
echo [1/4] Stop services
net stop wuauserv | net stop cryptSvc | net stop bits | net stop msiserver
echo.
echo [2/4] Delete Windows Update Repository
echo.
del /S /F /AH “C:\Windows\SoftwareDistribution” | del /S /F /AH “SoftwareDistribution.old”
echo [3/4] Start Services
echo.
net start wuauserv | net start cryptSvc | net start bits | net start msiserver
echo.
echo [4/4] Checking Windows Update
wuauclt.exe /detectnow
