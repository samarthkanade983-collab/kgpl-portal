@echo off
title KGPL Backend REST API (Port 5001)
cd /d "%~dp0backend"
set PORT=5001
echo Starting KGPL Node.js REST API on http://localhost:5001 ...
call npm.cmd run start
pause
