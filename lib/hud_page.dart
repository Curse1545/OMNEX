import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'desktop_tools.dart';
import 'model_client.dart';

class HudPage extends StatefulWidget {
  final DesktopTools tools;
  const HudPage({super.key, required this.tools});
  @override
  State<HudPage> createState() => _HudPageState();
}
class _HudPageState extends State<HudPage> with WidgetsBindingObserver {
  bool _active = false, _working = false, _fetching = false;
  int _camera = 0, _epoch = 0;
  Uint8List? _jpeg;
  List<List<int>> _faces = [];
  String? _error;
  Timer? _timer;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { if (state != AppLifecycleState.resumed) _stop(); }
  Future<void> _start() async {
    setState(() { _working = true; _error = null; });
    final epoch = ++_epoch;
    try {
      await widget.tools.call('/camera/start', data: {'index': _camera});
      if (!mounted || epoch != _epoch) { await widget.tools.call('/camera/stop'); return; }
      setState(() => _active = true);
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _frame());
      _frame();
    } on ModelFailure catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Kamera başlatılamadı. Araç kurulumunu kontrol et.'); }
    finally { if (mounted) setState(() => _working = false); }
  }
  Future<void> _frame() async {
    if (!_active || _fetching) return;
    _fetching = true;
    final epoch = _epoch;
    try {
      final frame = await widget.tools.call('/camera/frame', timeoutSeconds: 10);
      if (!mounted || !_active || epoch != _epoch) return;
      setState(() { _jpeg = base64Decode(frame['jpeg'] as String); _faces = (frame['faces'] as List).map((f) => List<int>.from(f as List)).toList(); });
    } catch (_) { if (mounted) { setState(() => _error = 'Kamera bağlantısı kesildi. Yeniden açabilirsin.'); _stop(); } }
    finally { _fetching = false; }
  }
  Future<void> _stop() async {
    ++_epoch; _timer?.cancel(); _timer = null;
    final wasActive = _active || _working;
    if (mounted) setState(() { _active = false; _jpeg = null; _faces = []; });
    if (wasActive) { try { await widget.tools.call('/camera/stop', timeoutSeconds: 5); } catch (_) { /* Helper watchdog also releases idle cameras. */ } }
  }
  @override
  void dispose() { ++_epoch; _timer?.cancel(); if (_active || _working) { widget.tools.call('/camera/stop', timeoutSeconds: 5).catchError((Object _) => <String, dynamic>{}); } WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff060f18),
    appBar: AppBar(title: const Text('OMNEX • Görüş paneli'), backgroundColor: const Color(0xff060f18)),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(_active ? '● KAMERA AÇIK' : '○ KAMERA KAPALI', style: TextStyle(color: _active ? Colors.cyanAccent : Colors.white70)),
        Text('ALGILANAN YÜZ: ${_faces.length}', style: const TextStyle(color: Colors.cyanAccent, letterSpacing: 2)),
      ])),
      Expanded(child: Center(child: AspectRatio(aspectRatio: 4 / 3, child: ClipRect(child: Stack(fit: StackFit.expand, children: [
        if (_jpeg != null) Image.memory(_jpeg!, fit: BoxFit.fill, gaplessPlayback: true) else const Center(child: Icon(Icons.view_in_ar, size: 100, color: Colors.cyan)),
        IgnorePointer(child: CustomPaint(painter: _HudPainter(_faces))),
        const Positioned(left: 16, bottom: 16, child: Text('OMNEX VISION / LOCAL', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 3, shadows: [Shadow(blurRadius: 8, color: Colors.black)]))),
      ]))))),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent))),
      Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<int>(value: _camera, dropdownColor: const Color(0xff142433), style: const TextStyle(color: Colors.white), items: [for (var i = 0; i < 4; i++) DropdownMenuItem(value: i, child: Text('Kamera ${i + 1}'))], onChanged: _active || _working ? null : (v) => setState(() => _camera = v!)),
        FilledButton.icon(onPressed: _working ? null : (_active ? _stop : _start), icon: Icon(_active ? Icons.videocam_off : Icons.videocam), label: Text(_working ? 'Açılıyor…' : (_active ? 'Kamerayı kapat' : 'Kamerayı aç'))),
      ])),
      const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 18), child: Text('Yalnızca yüz konumunu algılar; kimlik tanımaz. Görüntü kaydedilmez, modele veya internete gönderilmez. Bu panel gerçek hologram değildir.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 12))),
    ])),
  );
}
class _HudPainter extends CustomPainter {
  final List<List<int>> faces;
  _HudPainter(this.faces);
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0x2267e8f9)..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      canvas.drawLine(Offset(size.width * i / 8, 0), Offset(size.width * i / 8, size.height), grid);
      canvas.drawLine(Offset(0, size.height * i / 8), Offset(size.width, size.height * i / 8), grid);
    }
    final line = Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawCircle(size.center(Offset.zero), 32, line);
    canvas.drawLine(Offset(size.width / 2 - 48, size.height / 2), Offset(size.width / 2 + 48, size.height / 2), line);
    canvas.drawLine(Offset(size.width / 2, size.height / 2 - 48), Offset(size.width / 2, size.height / 2 + 48), line);
    for (final face in faces) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(face[0] * size.width / 640, face[1] * size.height / 480, face[2] * size.width / 640, face[3] * size.height / 480), const Radius.circular(12)), line);
    }
  }
  @override
  bool shouldRepaint(covariant _HudPainter oldDelegate) => true;
}
