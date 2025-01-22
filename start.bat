@echo off
echo Starting Twin Tool System...

:: Start the PowerShell server with admin privileges
powershell -Command "Start-Process powershell -ArgumentList '-NoExit -Command "".\src\server\server.ps1""' -Verb RunAs"

:: Wait for server to initialize
timeout /t 2 /nobreak > nul

:: Get the server port from the server
for /f "tokens=5 delims=: " %%p in ('netstat -ano ^| findstr "LISTENING" ^| findstr "9[0-9][0-9][0-9]"') do (
    set PORT=%%p
    goto :found_port
)

:found_port
if not defined PORT (
    set PORT=9000
)

:: Open the HTML interface with the correct port
powershell -Command "(Get-Content .\src\client\public\index.html) -replace 'localhost:8080', 'localhost:%PORT%' | Set-Content .\src\client\public\index.html"
start "" "src\client\public\index.html"

echo Server started successfully
echo Interface: src\client\public\index.html 