@echo off
setlocal
cd /d "%~dp0"
echo OMNEX kamera ve ses araclari kurulumu
echo Internet gerekir. Araclar ve ses modeli D surucusunde tutulur.
if not exist "D:\" (
  echo D surucusu bulunamadi.
  goto failed
)
set "TOOLS_ROOT=D:\OMNEX-Araclar"
set "PIP_CACHE_DIR=%TOOLS_ROOT%\pip-cache"
set "TEMP=%TOOLS_ROOT%\temp"
set "TMP=%TEMP%"
if not exist "%TEMP%" mkdir "%TEMP%"
set "PYTHON_EXE=%TOOLS_ROOT%\Python\python.exe"
if exist "%PYTHON_EXE%" goto python_ready
set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if exist "%PYTHON_EXE%" goto python_ready
where winget >nul 2>nul
if errorlevel 1 (
  echo Windows Uygulama Yukleyicisi ^(winget^) gerekli. Kurulum ekraninin goruntusunu paylasin.
  goto failed
)
winget install --id Python.Python.3.13 --exact --source winget --location "%TOOLS_ROOT%\Python"
if errorlevel 1 goto failed
set "PYTHON_EXE=%TOOLS_ROOT%\Python\python.exe"
if exist "%PYTHON_EXE%" goto python_ready
set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if not exist "%PYTHON_EXE%" goto failed
:python_ready
if not exist "%TOOLS_ROOT%\env\Scripts\python.exe" (
  "%PYTHON_EXE%" -m venv "%TOOLS_ROOT%\env"
  if errorlevel 1 goto failed
)
"%TOOLS_ROOT%\env\Scripts\python.exe" -m pip install --no-cache-dir --only-binary=:all: -r "%~dp0tools-requirements.txt"
if errorlevel 1 goto failed
"%TOOLS_ROOT%\env\Scripts\python.exe" -c "import cv2, sounddevice, faster_whisper"
if errorlevel 1 goto failed
>"%~dp0omnex-tools-path.txt" echo %TOOLS_ROOT%\env\Scripts\python.exe
echo Tamamlandi. OMNEX icindeki mikrofon veya kamera dugmesini kullanabilirsin.
echo Kamera ve mikrofon bu kurulum tarafindan acilmaz.
pause
exit /b 0
:failed
echo Kurulum tamamlanamadi. Hata ekranini paylasabilirsiniz.
pause
exit /b 1
