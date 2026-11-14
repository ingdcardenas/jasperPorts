@echo off
rem logout.bat - Ejecuta logout.ps1 sin depender de la ExecutionPolicy. Propaga el codigo de salida.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0logout.ps1" %*
set RC=%ERRORLEVEL%
rem Doble clic (cmd /c): pausa para poder leer la salida.
echo %cmdcmdline% | find /i "%~nx0" >nul && pause
exit /b %RC%
