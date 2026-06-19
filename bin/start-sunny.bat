@echo off
REM ============================================================================
REM  bin/start-sunny.bat — Sunny bootstrap (Windows)
REM ----------------------------------------------------------------------------
REM  Mirror of bin/start-sunny.sh for Windows hosts. WSL/Git-Bash can run the
REM  .sh directly; this .bat is for native cmd.exe / PowerShell users.
REM
REM  Windows prerequisites (run install.bat first):
REM    - git, curl, jq, openssl on PATH
REM    - Bash via WSL OR Git for Windows (used for the actual work)
REM
REM  This .bat wraps the .sh by spawning Git-Bash or WSL bash.
REM ============================================================================
setlocal enabledelayedexpansion
title Sunny multi-agent system - bootstrap

set "ROOT=%~dp0"
pushd "%ROOT%" >nul

REM Prefer WSL bash; fall back to Git for Windows bash.
set "BASH_BIN="
where wsl >nul 2>&1
if not errorlevel 1 (
  set "BASH_BIN=wsl bash"
  goto :run
)
where bash >nul 2>&1
if not errorlevel 1 (
  set "BASH_BIN=bash"
  goto :run
)

echo [ERROR] No bash found. Install WSL (wsl --install) or Git for Windows.
exit /b 1

:run
echo.
echo ============================================================
echo   Sunny bootstrap - %ROOT%
echo ============================================================
echo.

%BASH_BIN% "%ROOT%start-sunny.sh" %*

set "RC=%errorlevel%"
popd
exit /b %RC%