@echo off
echo Starting Twin Tool System...

cd /d "%~dp0"

:: Create logs directory if it doesn't exist
if not exist "logs" mkdir logs

:: Start the PowerShell server
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','.\src\server\server.ps1' -Verb RunAs"

:: Wait for initial server startup
timeout /t 3 /nobreak > nul
echo Waiting for server to initialize...

:: Check for available port (9000-9010)
:check_server
for /l %%p in (9000,1,9010) do (
    netstat -ano | findstr "LISTENING" | findstr ":%%p" > nul
    if not errorlevel 1 (
        echo Server detected on port %%p
        echo Server started at http://localhost:%%p/
        start http://localhost:%%p/
        goto :browser_opened
    )
)
timeout /t 1 /nobreak > nul
goto :check_server

:browser_opened
echo Server is running. Press Ctrl+C to stop the server...
pause > nul

:end
echo Press any key to exit...
pause > nul 