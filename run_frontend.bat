@echo off
title KGPL Flutter Web UI (Port 3002)
cd /d "%~dp0frontend"
set PORT=3002
set BACKEND_PORT=5001
echo Starting KGPL Flutter Web UI on http://localhost:3002 ...
call node serve.js
pause
