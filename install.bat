@echo off
setlocal enabledelayedexpansion
title Sunny multi-agent system - Windows installer

REM ============================================================================
REM  Sunny multi-agent system - Windows prerequisite installer
REM  Stack: React frontend . JHipster microservices (Spring Boot / Java)
REM         . PostgreSQL . Docker Compose (app repo, build/dev)
REM         . Minikube + kubectl + Helm (production deploy / local K8s smoke)
REM         . PM2 (frontend on VPS edge) . Graphify
REM         . optional Newman / Playwright / k6 / JHipster CLI
REM
REM  - Idempotent: re-run it any time. Already-installed tools are skipped.
REM  - Uses winget (built into Windows 10 2004+ / Windows 11).
REM  - Re-open the terminal once after the first run so new PATH entries load,
REM    then run install.bat again to finish the project bootstrap steps.
REM ============================================================================

set "ROOT=%~dp0"
pushd "%ROOT%" >nul
set "FAILED=0"

echo(
echo ============================================================
echo   Sunny installer  -  %ROOT%
echo ============================================================
echo(

REM --- winget availability -----------------------------------------------------
where winget >nul 2>&1
if errorlevel 1 (
  echo [ERROR] winget not found.
  echo         Install "App Installer" from the Microsoft Store, or update Windows,
  echo         then re-run this script. https://aka.ms/getwinget
  goto :end_fail
)

echo Accepting winget source agreements...
winget source update >nul 2>&1

REM --- Core prerequisites (winget) --------------------------------------------
call :need git           "Git.Git"                          git
call :need docker        "Docker.DockerDesktop"             docker
call :need java          "EclipseAdoptium.Temurin.17.JDK"   java
call :need node          "OpenJS.NodeJS.LTS"                node
call :need python        "Python.Python.3.12"               python
call :need uv            "astral-sh.uv"                      uv
call :need jq            "jqlang.jq"                         jq

REM --- Production deploy toolchain (Rajesh / Suresh / Manoj on VPS or local smoke) -
REM     Production runs on Linux VPS; Windows install helps local testing and SSH dev.
call :need kubectl      "Kubernetes.kubectl"               kubectl
call :need minikube     "Kubernetes.minikube"              minikube
call :need helm         "Helm.Helm"                        helm

REM --- Optional: k6 for API performance tests (Pawan agent) --------------------
where k6 >nul 2>&1
if errorlevel 1 (
  echo [ optional ] Installing k6 ^(load testing^)...
  winget install -e --id Grafana.k6 --accept-package-agreements --accept-source-agreements --silent >nul 2>&1
)

REM --- Cursor CLI (headless agent runner) -------------------------------------
where cursor-agent >nul 2>&1
if not errorlevel 1 (
  echo [ skip ] Cursor CLI already installed.
) else (
  where agent >nul 2>&1
  if not errorlevel 1 (
    echo [ skip ] Cursor CLI already installed.
  ) else (
    echo [install] Cursor CLI ^(native Windows^)...
    REM  Use Windows PowerShell 5.1 via powershell.exe - NOT PowerShell 7 / pwsh -
    REM  otherwise the upstream installer fails on Get-WmiObject.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://cursor.com/install?win32=true' | iex"
    if errorlevel 1 (
      echo [WARN] Cursor CLI install failed. Run manually in Windows PowerShell 5.1:
      echo        irm 'https://cursor.com/install?win32=true' ^| iex
      set "FAILED=1"
    )
  )
)

REM --- Make freshly installed tools usable in THIS session --------------------
call :addpath "%ProgramFiles%\Git\cmd"
call :addpath "%ProgramFiles%\nodejs"
call :addpath "%ProgramFiles%\Docker\Docker\resources\bin"
call :addpath "%ProgramFiles%\Kubernetes\Minikube"
call :addpath "%LOCALAPPDATA%\Programs\minikube"
call :addpath "%USERPROFILE%\.local\bin"
call :addpath "%APPDATA%\npm"

echo(
echo ------------------------------------------------------------
echo   Tool versions
echo ------------------------------------------------------------
call :ver git "git --version"
call :ver docker "docker --version"
call :ver kubectl "kubectl version --client"
call :ver minikube "minikube version"
call :ver helm "helm version"
call :ver java "java -version"
call :ver node "node -v"
call :ver npm "npm -v"
call :ver python "python --version"
call :ver uv "uv --version"
call :ver cursor-agent "cursor-agent --version"
where pm2 >nul 2>&1
if errorlevel 1 (
  echo   pm2 : NOT FOUND yet
) else (
  for /f "delims=" %%v in ('pm2 --version 2^>^&1') do echo   pm2 %%v
)

REM --- Graphify (token-efficient context graph) -------------------------------
echo(
echo ------------------------------------------------------------
echo   Graphify (knowledge graph)
echo ------------------------------------------------------------
where uv >nul 2>&1
if errorlevel 1 (
  echo [WARN] uv not on PATH yet. Re-open the terminal and run install.bat again.
  set "FAILED=1"
) else (
  where graphify >nul 2>&1
  if errorlevel 1 (
    echo Installing graphify CLI ^(PyPI: graphifyy^)...
    uv tool install graphifyy
    call :addpath "%USERPROFILE%\.local\bin"
  ) else (
    echo graphify already installed - skipping.
  )
  where graphify >nul 2>&1
  if not errorlevel 1 (
    graphify install
    if exist "%ROOT%graphify-out\graph.json" (
      echo graphify-out exists - refreshing graph...
      graphify update .
    ) else (
      echo Bootstrapping knowledge graph...
      graphify .
    )
  ) else (
    echo [WARN] graphify still not on PATH. Re-open the terminal and re-run install.bat.
    set "FAILED=1"
  )
)

REM --- Global Node tooling used by agents -------------------------------------
echo(
echo ------------------------------------------------------------
echo   Node tooling (Newman + JHipster CLI + PM2)
echo ------------------------------------------------------------
where npm >nul 2>&1
if errorlevel 1 (
  echo [WARN] npm not on PATH yet. Re-open the terminal and run install.bat again.
  set "FAILED=1"
) else (
  call :npmglobal newman          "Newman (API collection CI)"
  call :npmglobal jhipster         "JHipster CLI (generator-jhipster)" generator-jhipster
  call :npmglobal pm2              "PM2 (frontend process manager on VPS edge)"
)

REM --- Frontend dependencies ---------------------------------------------------
echo(
echo ------------------------------------------------------------
echo   Frontend dependencies
echo ------------------------------------------------------------
if exist "%ROOT%frontend\package.json" (
  where npm >nul 2>&1
  if errorlevel 1 (
    echo [WARN] npm not ready - skipping. Re-run after re-opening the terminal.
  ) else (
    echo Installing frontend deps with npm ci ...
    pushd "%ROOT%frontend"
    if exist package-lock.json (
      call npm ci || call npm install
    ) else (
      call npm install
    )
    popd
  )
) else (
  echo [info] No .\frontend\package.json found.
  echo        Clone your React frontend into:  %ROOT%frontend
  echo        then re-run install.bat to install its dependencies.
)

REM --- Notes -------------------------------------------------------------------
echo(
echo ------------------------------------------------------------
echo   Notes
echo ------------------------------------------------------------
echo  * Docker Desktop: launch it once, enable the WSL2 backend, and reboot if
echo    prompted. It must be RUNNING before Sunny builds the stack or Minikube starts.
echo  * Production deploy (Rajesh-Om): Minikube uses Docker as driver on the VPS.
echo    Config lives in deploy\  -  see DEPLOY-ASSETS.md and deploy\README.md.
echo    Local smoke:  minikube start --driver=docker --cpus=4 --memory=8192
echo  * Redis + PostgreSQL run as Docker services (JHipster compose in app repo) -
echo    no host Postgres install needed for local dev.
echo  * Playwright (E2E) browsers install per-project on demand:
echo      cd frontend ^&^& npm i -D @playwright/test ^&^& npx playwright install --with-deps chromium
echo  * .env + all secrets are auto-generated by Maya at intake - do NOT create them.

echo(
if "%FAILED%"=="1" (
  echo ============================================================
  echo   DONE WITH WARNINGS - re-open a NEW terminal and run
  echo   install.bat once more to finish the bootstrap steps.
  echo ============================================================
) else (
  echo ============================================================
  echo   ALL SET. Start Docker Desktop, then invoke Sunny in Cursor.
  echo   Deploy assets: deploy\helm  deploy\minikube  deploy\grafana
  echo ============================================================
)
goto :end_ok

REM ============================================================================
REM  Helpers
REM ============================================================================

:need
REM  %1 = command to probe, %2 = winget id, %3 = friendly label
where %1 >nul 2>&1
if not errorlevel 1 (
  echo [ skip ] %3 already installed.
  goto :eof
)
echo [install] %3  ^(%~2^)...
winget install -e --id %~2 --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 (
  echo [WARN] winget could not install %3. Install it manually if needed.
  set "FAILED=1"
)
goto :eof

:npmglobal
REM  %1 = command to probe, %2 = label, %3 = package (defaults to %1)
set "PKG=%~3"
if "%PKG%"=="" set "PKG=%~1"
where %1 >nul 2>&1
if not errorlevel 1 (
  echo [ skip ] %~2 already installed.
  goto :eof
)
echo [install] %~2 ...
call npm install -g %PKG%
goto :eof

:addpath
REM  Prepend a dir to PATH for this session if it exists and isn't already there
if exist "%~1" (
  echo ;%PATH%; | find /i ";%~1;" >nul
  if errorlevel 1 set "PATH=%~1;%PATH%"
)
goto :eof

:ver
REM  %1 = command, %2 = command line to print version
where %1 >nul 2>&1
if errorlevel 1 (
  echo   %1 : NOT FOUND yet
) else (
  for /f "delims=" %%v in ('%~2 2^>^&1') do (
    echo   %%v
    goto :eof
  )
)
goto :eof

:end_fail
popd >nul
endlocal
exit /b 1

:end_ok
popd >nul
endlocal
exit /b 0
