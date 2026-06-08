@echo off

net stop wuauserv | net stop cryptSvc | net stop bits | net stop msiserver

del /S /F /AH “C:\Windows\SoftwareDistribution” | del /S /F /AH “SoftwareDistribution.old”

net start wuauserv | net start cryptSvc | net start bits | net start msiserver


wuauclt.exe /detectnow
