@echo off
setlocal
cd /d "%~dp0"
echo OMNEX - model dosyalari D:\OMNEX-Modeller konumuna indirilecek.
echo Bu baslatici mevcut oturumdaki Ollama'yi yeniden baslatir.
if not exist "D:\" (
  echo HATA: D surucusu bulunamadi.
  goto failed
)
if not exist "omnex.exe" (
  echo HATA: Bu dosyayi omnex.exe ile ayni klasore koyun.
  goto failed
)
set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
if exist "%OLLAMA_EXE%" goto found
set "OLLAMA_EXE="
for /f "delims=" %%I in ('where ollama.exe 2^>nul') do if not defined OLLAMA_EXE set "OLLAMA_EXE=%%I"
if not defined OLLAMA_EXE (
  echo HATA: Ollama kurulu degil. Kurulum hatasinin ekran goruntusunu paylasin.
  goto failed
)
:found
set "OLLAMA_MODELS=D:\OMNEX-Modeller"
set "OLLAMA_HOST=127.0.0.1:11434"
powershell -NoProfile -Command "try { New-Item -ItemType Directory -Force -Path $env:OLLAMA_MODELS -ErrorAction Stop | Out-Null; $p=Join-Path $env:OLLAMA_MODELS ([guid]::NewGuid().ToString()+'.tmp'); [IO.File]::WriteAllText($p,'test'); Remove-Item -LiteralPath $p; if ((Get-PSDrive D).Free -lt 3GB) { throw 'D surucusunda en az 3 GB bos alan gerekli.' }; exit 0 } catch { Write-Host $_; exit 1 }"
if errorlevel 1 goto failed
powershell -NoProfile -Command "try { [Environment]::SetEnvironmentVariable('OLLAMA_MODELS',$env:OLLAMA_MODELS,'User'); $session=(Get-Process -Id $PID).SessionId; Get-Process -Name 'ollama','ollama app' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session } | Stop-Process -Force -ErrorAction Stop; Start-Sleep -Seconds 3; $c=New-Object Net.Sockets.TcpClient; try { $c.Connect('127.0.0.1',11434); $busy=$true } catch { $busy=$false } finally { $c.Dispose() }; if ($busy) { throw 'Ollama hala acik. Saat yanindaki Ollama simgesinden cikis yapip yeniden deneyin.' }; exit 0 } catch { Write-Host $_; exit 1 }"
if errorlevel 1 goto failed
start "OMNEX Ollama - D" /min "%OLLAMA_EXE%" serve
powershell -NoProfile -Command "for ($i=0; $i -lt 30; $i++) { try { Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null; exit 0 } catch { Start-Sleep -Seconds 1 } }; exit 1"
if errorlevel 1 goto failed
echo Model D surucusune indiriliyor. Pencereyi kapatmayin.
"%OLLAMA_EXE%" pull qwen3:1.7b
if errorlevel 1 goto failed
start "" "%~dp0omnex.exe"
exit /b 0
:failed
echo Islem tamamlanamadi. Bu pencerenin ekran goruntusunu paylasabilirsiniz.
pause
exit /b 1
