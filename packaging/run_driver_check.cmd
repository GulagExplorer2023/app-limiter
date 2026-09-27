@echo off
cd /d "%~dp0"
set "report=%TEMP%\AppLimiter-Driver-Check.txt"
echo App Limiter driver check > "%report%"
echo %DATE% %TIME% >> "%report%"
ver >> "%report%"
echo. >> "%report%"
driver_compat_probe.exe >> "%report%" 2>&1
set "result=%ERRORLEVEL%"
echo Exit code: %result% >> "%report%"
type "%report%"
echo.
echo Report saved to %report%
if "%result%"=="2" echo If the Windows error is 5, right-click this file and choose Run as administrator.
pause
exit /b %result%
