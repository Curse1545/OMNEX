import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'model_client.dart';

class DesktopTools {
  Process? _helper;
  Process? _speaker;
  int? _port;
  String _token = '';
  int _speechEpoch = 0;
  Future<void>? _starting;
  bool _closed = false;
  final String base = File(Platform.resolvedExecutable).parent.path;

  Future<void> ensureStarted() async {
    if (_closed) throw const ModelFailure('Araçlar kapalı.');
    if (_port != null && _helper != null) return;
    if (_starting != null) return _starting!;
    final attempt = _start();
    _starting = attempt;
    try { await attempt; } finally { _starting = null; }
  }
  Future<void> _start() async {
    if (!Platform.isWindows) throw const ModelFailure('Bu araç Windows içindir.');
    final config = File('$base/omnex-tools-path.txt');
    if (!await config.exists()) throw const ModelFailure('Önce Ayarlar > Kamera ve ses araçlarını kur seçeneğini kullan.');
    final python = (await config.readAsString()).trim();
    if (!await File(python).exists()) throw const ModelFailure('Araç kurulumu eksik; kamera ve ses kurulumunu yeniden çalıştır.');
    _token = base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    final proc = await Process.start(python, ['-u', '$base/omnex_tools.py'], environment: {
      'OMNEX_TOOLS_TOKEN': _token,
      'OMNEX_VOICE_CACHE': r'D:\OMNEX-Araclar\ses-modeli',
      'HF_HUB_DISABLE_TELEMETRY': '1',
    });
    if (_closed) { proc.kill(); return; }
    _helper = proc;
    proc.stderr.drain<void>();
    final ready = Completer<int>();
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (!ready.isCompleted) {
        try { final data = jsonDecode(line); if (data['port'] is int) ready.complete(data['port'] as int); } catch (_) { /* Ignore dependency startup messages. */ }
      }
    }, onDone: () { if (!ready.isCompleted) ready.completeError(const ModelFailure('Araç servisi başlatılamadı. Kurulumu kontrol et.')); });
    proc.exitCode.then((_) { if (identical(_helper, proc)) { _helper = null; _port = null; } });
    try { _port = await ready.future.timeout(const Duration(seconds: 25)); }
    catch (_) { proc.kill(); _port = null; rethrow; }
  }
  Future<Map<String, dynamic>> call(String path, {Map<String, dynamic> data = const {}, int timeoutSeconds = 30}) async {
    await ensureStarted();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final req = await client.postUrl(Uri(scheme: 'http', host: '127.0.0.1', port: _port, path: path));
        req.followRedirects = false;
        req.headers.set('X-OMNEX-Token', _token);
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(data));
        final res = await req.close();
        final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
        if (res.statusCode != 200) throw ModelFailure(body['error']?.toString() ?? 'Araç yanıt veremedi.');
        return body;
      })().timeout(Duration(seconds: timeoutSeconds));
    } on ModelFailure { rethrow; }
    catch (_) { throw const ModelFailure('Araç bağlantısı kesildi veya zaman aşımına uğradı.'); }
    finally { client.close(force: true); }
  }
  Future<void> installTools() => _runSetup('OMNEX-Araclari-Kur.cmd');
  Future<void> installLocal() => _runSetup('OMNEX-D-Baslat.cmd');
  Future<void> _runSetup(String filename) async {
    if (!Platform.isWindows) throw const ModelFailure('Kurulum Windows içindir.');
    if (!await File('$base/$filename').exists()) throw const ModelFailure('Kurulum dosyası eksik. Paketin tamamını yeniden kur.');
    // Fixed bundled script name, no user/model text is interpreted as a command.
    await Process.start('cmd.exe', ['/c', 'start', '', filename], workingDirectory: base, runInShell: false);
  }
  Future<void> speak(String text) async {
    stopSpeaking();
    final epoch = _speechEpoch;
    if (!Platform.isWindows) throw const ModelFailure('Sesli okuma Windows içindir.');
    const script = r'''$ErrorActionPreference='Stop'; Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; try { $v=$s.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -eq 'tr-TR' } | Select-Object -First 1; if (!$v) { exit 3 }; $s.SelectVoice($v.VoiceInfo.Name); $s.Speak($env:OMNEX_SPEAK_TEXT) } finally { $s.Dispose() }''';
    final encoded = base64Encode(script.codeUnits.expand((n) => [n & 255, n >> 8]).toList());
    final proc = await Process.start('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded], environment: {'OMNEX_SPEAK_TEXT': text.substring(0, min(5000, text.length))});
    if (_closed || epoch != _speechEpoch) { proc.kill(); return; }
    _speaker = proc;
    proc.stdout.drain<void>(); proc.stderr.drain<void>();
    final code = await proc.exitCode;
    if (!identical(_speaker, proc)) return;
    _speaker = null;
    if (code == 3) throw const ModelFailure('Windows’ta kullanılabilir Türkçe konuşma sesi yok. Windows dil/konuşma ayarlarından Türkçe ses yükle.');
    if (code != 0) throw const ModelFailure('Sesli okuma başlatılamadı. Windows konuşma ayarlarını kontrol et.');
  }
  void stopSpeaking() { ++_speechEpoch; final p = _speaker; _speaker = null; p?.kill(); }
  Future<void> launchApp(String id) async {
    const apps = {'notepad': 'notepad.exe', 'calculator': 'calc.exe', 'files': 'explorer.exe'};
    final exe = apps[id];
    if (!Platform.isWindows || exe == null) throw const ModelFailure('Bu işlem desteklenmiyor.');
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final path = id == 'files' ? '$root\\$exe' : '$root\\System32\\$exe';
    await Process.start(path, [], runInShell: false);
  }
  void close() { _closed = true; stopSpeaking(); _helper?.stdin.close(); _helper?.kill(); _helper = null; _port = null; }
}
