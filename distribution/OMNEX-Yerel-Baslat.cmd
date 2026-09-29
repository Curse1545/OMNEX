@echo off
setlocal
cd /d "%~dp0"
echo OMNEX yerel kurulum - API anahtari gerekmez.
echo Ilk kurulumda Ollama ve yaklasik 1.4 GB model indirilir.
set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
if exist "%OLLAMA_EXE%" goto ready
where ollama >nul 2>nul
if not errorlevel 1 (
  set "OLLAMA_EXE=ollama"
  goto ready
)
where winget >nul 2>nul
if errorlevel 1 (
  echo Ollama kurulumu gerekli. Acilan resmi sayfadan kur ve bu dosyayi yeniden calistir.
  start "" "https://ollama.com/download/windows"
  pause
  exit /b 1
)
winget install --id Ollama.Ollama --exact --source winget
if errorlevel 1 goto failed
if not exist "%OLLAMA_EXE%" goto failed
:ready
set "OLLAMA_HOST=127.0.0.1:11434"
powershell -NoProfile -Command "try { Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 goto pull
start "OMNEX yerel model servisi" /min "%OLLAMA_EXE%" serve
powershell -NoProfile -Command "for ($i=0; $i -lt 30; $i++) { try { Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null; exit 0 } catch { Start-Sleep -Seconds 1 } }; exit 1"
if errorlevel 1 goto failed
:pull
"%OLLAMA_EXE%" pull qwen3:1.7b
if errorlevel 1 goto failed
if not exist "omnex.exe" goto failed
start "" "%~dp0omnex.exe"
exit /b 0
:failed
echo Kurulum tamamlanamadi. Yukaridaki hata mesajini paylasabilirsin.
pause
exit /b 1
