@echo off
title KGPL Portal
cd /d "%~dp0"

REM Ensure MySQL 8.4 is running on port 3306
netstat -ano | findstr ":3306" | findstr "LISTENING" >nul
if errorlevel 1 (
  echo Starting portable MySQL 8.4 database...
  if exist "%~dp0..\mysql-portable\mysql-8.4.9-winx64\bin\mysqld.exe" (
    start "KGPL MySQL" /min "%~dp0..\mysql-portable\mysql-8.4.9-winx64\bin\mysqld.exe" --defaults-file="%~dp0..\mysql-portable\my.ini"
    timeout /t 3 /nobreak >nul
  )
)

echo Starting the API and the web portal together...
node start.js
if errorlevel 1 pause
