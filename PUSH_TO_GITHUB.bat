@echo off
title Push KGPL Portal to GitHub
cd /d "%~dp0"
echo ========================================================
echo Pushing KGPL Portal to GitHub repository:
echo https://github.com/samarthkanade983-collab/kgpl-portal.git
echo ========================================================
echo.
echo If GitHub asks for login, please sign in or paste your Personal Access Token.
echo.
"C:\Users\HP\Documents\Qoder\2026-11-18\d96c402f\.tools\flutter\bin\mingit\cmd\git.exe" push -u origin main
echo.
if errorlevel 1 (
  echo [ERROR] Push failed. Please check your credentials.
) else (
  echo [SUCCESS] Code pushed to GitHub successfully!
)
pause
