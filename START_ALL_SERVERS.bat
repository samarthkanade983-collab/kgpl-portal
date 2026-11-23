@echo off
title KGPL Portal
cd /d "%~dp0"
if exist "%~dp0mongodb-portable\bin\mongod.exe" (
  netstat -ano | findstr ":27017" >nul
  if errorlevel 1 start "KGPL MongoDB" /min /d "%~dp0mongodb-portable" "bin\mongod.exe" --config "mongod.cfg"
)
echo Starting the API and the web portal together...
node start.js
if errorlevel 1 pause
