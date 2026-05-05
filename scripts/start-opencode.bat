@echo off
REM OpenCode Serve Launcher for Windows

echo ========================================
echo   OpenCode Serve Launcher
echo ========================================

REM Default config
set PORT=4096
set USERNAME=devcode
set PASSWORD=devcode123

REM Check arguments
if not "%1"=="" set USERNAME=%1
if not "%2"=="" set PASSWORD=%2

REM Set auth env vars
set OPENCODE_SERVER_USERNAME=%USERNAME%
set OPENCODE_SERVER_PASSWORD=%PASSWORD%

REM Get local IP
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
    set LOCAL_IP=%%a
    goto :got_ip
)
:got_ip
set LOCAL_IP=%LOCAL_IP: =%

if "%LOCAL_IP%"=="" set LOCAL_IP=127.0.0.1

echo.
echo ========================================
echo   Connection Info (for mobile app)
echo ========================================
echo IP: %LOCAL_IP%
echo Port: %PORT%
echo Username: %USERNAME%
echo Password: %PASSWORD%
echo ========================================
echo.

REM Check if port is already in use
netstat -ano | findstr ":%PORT%" | findstr "LISTENING" >nul
if %errorlevel%==0 (
    echo Port %PORT% is already in use.
    echo OpenCode Serve is likely already running.
    echo Please use the connection info above to connect.
    goto :end
)

REM Start OpenCode Serve
echo Starting OpenCode Serve on port %PORT%...
opencode serve --port %PORT% --hostname 0.0.0.0

:end
echo.
pause