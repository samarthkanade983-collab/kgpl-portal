@echo off
title KGPL MongoDB
cd /d "%~dp0mongodb-portable"
if not exist "bin\mongod.exe" (
  echo MongoDB is not installed in mongodb-portable\bin.
  echo Download the MongoDB Community zip and extract it so that bin\mongod.exe exists.
  pause
  exit /b 1
)
if not exist "data" mkdir "data"
if not exist "log" mkdir "log"
echo Starting MongoDB on mongodb://127.0.0.1:27017 ...
echo Close this window or press Ctrl+C to stop it.
"bin\mongod.exe" --config mongod.cfg
pause
