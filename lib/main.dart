import 'dart:io';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'desktop_tools.dart';
import 'hud_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_store.dart';
import 'model_client.dart';

void main() => runApp(const OmnexApp());

class OmnexApp extends StatefulWidget {
  const OmnexApp({super.key});
  @override
  State<OmnexApp> createState() => _OmnexAppState();
}
class _OmnexAppState extends State<OmnexApp> {
  bool _dark = true;
  @override
  void initState() { super.initState(); _loadTheme(); }
  Future<void> _loadTheme() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() => _dark = p.getBool('omnex.dark') ?? true);
    } catch (_) { /* The default theme remains usable. */ }
  }
  Future<void> _toggleTheme() async {
    setState(() => _dark = !_dark);
    try { await (await SharedPreferences.getInstance()).setBool('omnex.dark', _dark); } catch (_) { /* Theme is still changed for this session. */ }
  }
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'OMNEX',
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6366f1))),
    darkTheme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xff10121b), colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xffa5b4fc), brightness: Brightness.dark)),
    home: OmnexHomePage(onToggleTheme: _toggleTheme),
  );
}

class OmnexHomePage extends StatefulWidget {
  final VoidCallback? onToggleTheme;
  const OmnexHomePage({super.key, this.onToggleTheme});
  @override
  State<OmnexHomePage> createState() => _OmnexHomePageState();
}
class _OmnexHomePageState extends State<OmnexHomePage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _store = ChatStore();
  final _tools = DesktopTools();
  bool _voiceBusy = false, _speaking = false, _detailed = false;
  int _voiceEpoch = 0;
  String _voiceStatus = '', _notes = '', _attached = '', _attachmentName = '';
  String _style = 'Dengeli';
  String get _instructions => '$assistantInstructions\nYanıt biçimi: $_style. ${_detailed ? 'Gerektiğinde örneklerle açıkla.' : 'Gereksiz uzatmadan yanıtla.'}\nKullanıcının özel talimatları: $_notes';
  final _localClient = LocalModelClient();
  final _cloudClient = ModelClient();
  List<Conversation> _chats = [];
  Conversation _chat = Conversation.empty();
  bool _loading = true, _busy = false, _storageBlocked = false;
  bool _local = Platform.isWindows;
  String _key = '', _model = '', _search = '', _pending = '', _partial = '';
  String? _error;
  int _requestId = 0;

  @override
  void initState() { super.initState(); _load(); _loadAssistantSettings(); }
  Future<void> _load() async {
    try {
      final saved = await _store.load();
      if (!mounted) return;
      setState(() {
        _chats = saved;
        if (_chats.isEmpty) _chats.add(_chat);
        _chat = _chats.first;
        _loading = false;
      });
    } catch (_) {
      if (mounted) { setState(() {
        _loading = false; _storageBlocked = true; _chats = [_chat];
        _error = 'Kayıtlı geçmiş okunamadı. Eski kayıtların üzerine yazılmayacak; bu oturum kaydedilmiyor.';
      }); }
    }
  }
  Future<void> _save() async {
    if (_storageBlocked) return;
    try { await _store.save(_chats); }
    catch (_) { if (mounted) setState(() => _error = 'Sohbet kaydedilemedi. Disk alanını kontrol et; uygulamayı kapatmadan metni kopyalayabilirsin.'); }
  }
  void _newChat() {
    if (_busy || _loading || _voiceBusy) return;
    setState(() {
      _chat = Conversation.empty(); _chats.insert(0, _chat);
      _error = null; _input.clear(); _attached = ''; _attachmentName = '';
    });
    _save();
  }
  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }
  Future<void> _send() async {
    final text = _input.text.trim();
    if (_loading || _busy || _voiceBusy || text.isEmpty) return;
    if (!_local && (_key.isEmpty || _model.isEmpty)) { await _connection(); return; }
    if (text.length > (_local ? 1200 : 12000)) {
      setState(() => _error = _local ? 'Yerel modda en fazla 1200 karakter gönder.' : 'En fazla 12000 karakter gönder.'); return;
    }
    final request = ++_requestId;
    final target = _chat;
    setState(() { _busy = true; _error = null; _pending = text; _partial = ''; _input.clear(); });
    _bottom();
    final outgoing = _attached.isEmpty ? text : '$text\n\nEKLİ METİN ($_attachmentName):\n$_attached';
    final history = [...target.messages, {'role': 'user', 'content': outgoing}];
    try {
      if (_local) {
        await for (final token in _localClient.streamReply(history, instructions: _instructions, detailed: _detailed)) {
          if (!mounted || request != _requestId) return;
          setState(() => _partial += token);
          _bottom();
        }
      } else {
        final answer = await _cloudClient.reply(apiKey: _key, model: _model, history: history, instructions: _instructions);
        if (!mounted || request != _requestId) return;
        setState(() => _partial = answer);
      }
      if (!mounted || request != _requestId) return;
      if (_partial.trim().isEmpty) throw const ModelFailure('Boş yanıt geldi. Tekrar deneyebilirsin.');
      setState(() {
        target.messages.addAll([{'role': 'user', 'content': outgoing}, {'role': 'assistant', 'content': _partial}]);
        if (target.title == 'Yeni sohbet') target.title = text.length > 45 ? '${text.substring(0, 45)}…' : text;
        _chats.remove(target); _chats.insert(0, target);
        _pending = ''; _partial = ''; _busy = false; _attached = ''; _attachmentName = '';
      });
      await _save();
    } on ModelFailure catch (e) {
      if (mounted && request == _requestId) setState(() { _error = e.message; _input.text = text; });
    } catch (_) {
      if (mounted && request == _requestId) setState(() { _error = 'Yanıt alınamadı. Mesajın korunuyor; yeniden deneyebilirsin.'; _input.text = text; });
    } finally {
      if (mounted && request == _requestId) { setState(() { _busy = false; _pending = ''; _partial = ''; }); _bottom(); }
    }
  }
  void _stop() {
    ++_requestId; _localClient.cancel(); _cloudClient.cancel();
    setState(() { _input.text = _pending; _pending = ''; _partial = ''; _busy = false; _error = 'İstek durduruldu. Mesajın yeniden göndermek için hazır.'; });
  }
  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopyalandı'), duration: Duration(seconds: 1)));
    } catch (_) { if (mounted) setState(() => _error = 'Panoya kopyalanamadı. Metni seçerek kopyalamayı dene.'); }
  }
  Future<void> _rename(Conversation chat) async {
    final c = TextEditingController(text: chat.title);
    final title = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Sohbetin adı'), content: TextField(controller: c, maxLength: 70, autofocus: true),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Kaydet'))],
    ));
    if (mounted && title != null && title.isNotEmpty) { setState(() => chat.title = title); await _save(); }
    await Future<void>.delayed(const Duration(milliseconds: 300)); c.dispose();
  }
  Future<void> _delete(Conversation chat) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Sohbet silinsin mi?'), content: Text('“${chat.title}” bu cihazdan silinecek.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil'))],
    ));
    if (ok != true || !mounted) return;
    setState(() { _chats.remove(chat); if (_chats.isEmpty) _chats.add(Conversation.empty()); if (identical(chat, _chat)) { _chat = _chats.first; _input.clear(); } });
    await _save();
  }

  Future<void> _loadAssistantSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() { _notes = p.getString('omnex.notes') ?? ''; _style = p.getString('omnex.style') ?? 'Dengeli'; _detailed = p.getBool('omnex.detailed') ?? false; });
    } catch (_) { /* Defaults remain available. */ }
  }
  Future<void> _assistantSettings() async {
    final notes = TextEditingController(text: _notes);
    var style = _style;
    var detailed = _detailed;
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const Text('Asistanı kişiselleştir'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: style, decoration: const InputDecoration(labelText: 'Yanıt tarzı'), items: [for (final v in ['Dengeli', 'Adım adım öğretmen', 'Kodlama yardımcısı', 'Yaratıcı yazar']) DropdownMenuItem(value: v, child: Text(v))], onChanged: (v) => refresh(() => style = v!)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Daha ayrıntılı yanıtlar'), subtitle: const Text('Yerel modelde daha uzun sürebilir.'), value: detailed, onChanged: (v) => refresh(() => detailed = v)),
        TextField(controller: notes, maxLength: 600, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Özel talimatların', hintText: 'Örneğin: Bana Arda de. Türkçe ve sade açıkla.')),
        const Text('Bu notlar cihazda saklanır ve seçtiğin modele her istekte gönderilir. Modelin kendisi değişmez; küçük modelin yanıtları hatalı olabilir.'),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet'))],
    )));
    if (accepted == true && mounted) {
      setState(() { _notes = notes.text.trim(); _style = style; _detailed = detailed; });
      try { final p = await SharedPreferences.getInstance(); await p.setString('omnex.notes', _notes); await p.setString('omnex.style', _style); await p.setBool('omnex.detailed', _detailed); }
      catch (_) { if (mounted) setState(() => _error = 'Ayarlar bu oturumda geçerli; diske kaydedilemedi.'); }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300)); notes.dispose();
  }
  Future<bool> _confirm(String title, String body) async => await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
    title: Text(title), content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Devam et'))],
  )) ?? false;
  Future<void> _attach() async {
    try {
      final f = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'Metin', extensions: ['txt', 'md', 'csv', 'json', 'log'])]);
      if (f == null || !mounted) return;
      if (await f.length() > 1024 * 1024) throw const ModelFailure('En fazla 1 MB metin dosyası seç.');
      final text = utf8.decode(await f.readAsBytes(), allowMalformed: false);
      if (!mounted) return;
      final excerpt = text.length > 2800 ? text.substring(0, 2800) : text;
      if (!await _confirm('Metin eklensin mi?', '${f.name}: ${text.length > 2800 ? 'yalnızca ilk 2800 karakter' : 'metin içeriği'} sonraki mesajına eklenecek. ${_local ? 'Yerel modelde işlenecek.' : 'Gönder dediğinde OpenAI’a iletilecek.'}')) return;
      if (mounted) setState(() { _attached = excerpt; _attachmentName = f.name; if (_input.text.isEmpty) _input.text = 'Bu metni özetle ve önemli noktaları açıkla.'; });
    } on ModelFailure catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Dosya okunamadı. UTF-8 biçiminde bir metin dosyası seç.'); }
  }
  Future<void> _voiceInput() async {
    if (!await _confirm('Sesle mesaj yaz', 'Mikrofon 8 saniyeye kadar kayıt yapacak. Ses cihazında yazıya çevrilir ve kaydedilmez. İlk kullanım ses modeli indirmeyi gerektirir. Metni kontrol edip kendin göndereceksin.')) return;
    if (!mounted) return;
    _tools.stopSpeaking();
    final epoch = ++_voiceEpoch;
    setState(() { _voiceBusy = true; _speaking = false; _voiceStatus = 'Ses modeli hazırlanıyor; ilk kullanımda indirme gerekebilir…'; _error = null; });
    try {
      await _tools.call('/voice/prepare', timeoutSeconds: 600);
      if (!mounted || epoch != _voiceEpoch) return;
      setState(() => _voiceStatus = 'Mikrofon açık • 8 saniye konuşabilirsin…');
      final response = await _tools.call('/voice/listen', timeoutSeconds: 180);
      if (!mounted || epoch != _voiceEpoch) return;
      final text = response['text']?.toString() ?? '';
      setState(() { if (text.isNotEmpty) { _input.text = '${_input.text} $text'.trim(); } else { _error = 'Konuşma algılanmadı. Mikrofonunu kontrol edip yeniden dene.'; } });
    } on ModelFailure catch (e) { if (mounted && epoch == _voiceEpoch) setState(() => _error = e.message); }
    catch (_) { if (mounted && epoch == _voiceEpoch) setState(() => _error = 'Ses aracı açılamadı. Kamera ve ses araçlarını kur.'); }
    finally { if (mounted && epoch == _voiceEpoch) setState(() => _voiceBusy = false); }
  }
  void _cancelVoice() {
    ++_voiceEpoch;
    _tools.call('/voice/stop', timeoutSeconds: 5).catchError((Object _) => <String, dynamic>{});
    setState(() => _voiceBusy = false);
  }
  Future<void> _readAloud(String text) async {
    if (_speaking) { _tools.stopSpeaking(); setState(() => _speaking = false); return; }
    setState(() => _speaking = true);
    try { await _tools.speak(text); }
    on ModelFailure catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Sesli okuma açılamadı.'); }
    finally { if (mounted) setState(() => _speaking = false); }
  }
  Future<void> _installTools() async {
    if (!await _confirm('Kamera ve ses araçlarını kur', 'Python, OpenCV ve ses tanıma bileşenleri indirilecek. Kurulum D sürücüsünü kullanır ve birkaç GB boş alan gerekir. Kamera veya mikrofon kurulum sırasında açılmaz.')) return;
    try { await _tools.installTools(); } catch (_) { if (mounted) setState(() => _error = 'Kurulum açılamadı. Kurulum paketinin tamamını yeniden yükle.'); }
  }
  Future<void> _installLocal() async {
    if (!await _confirm('Yerel modeli hazırla', 'Kurulu Ollama yeniden başlatılır ve model D sürücüsüne indirilir. İnternet ve en az 3 GB boş alan gerekir.')) return;
    try { await _tools.installLocal(); } catch (_) { if (mounted) setState(() => _error = 'Yerel model kurulumu açılamadı.'); }
  }
  Future<void> _computerTools() async {
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Bilgisayar araçları'),
      content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Seçtiğin uygulama onayından sonra açılır. Model kendi başına komut çalıştıramaz.'),
        for (final pair in [('notepad', 'Not Defteri'), ('calculator', 'Hesap Makinesi'), ('files', 'Dosya Gezgini')])
          ListTile(leading: const Icon(Icons.open_in_new), title: Text(pair.$2), onTap: () async {
            Navigator.pop(ctx);
            if (!await _confirm('Uygulama açılsın mı?', '${pair.$2} bilgisayarında açılacak.')) return;
            try { await _tools.launchApp(pair.$1); } catch (_) { if (mounted) setState(() => _error = '${pair.$2} açılamadı.'); }
          }),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
    ));
  }
  Future<void> _connection() async {
    final key = TextEditingController(text: _key);
    final model = TextEditingController(text: _model);
    var local = _local;
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const Text('Model bağlantısı'),
      content: SizedBox(width: 430, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (Platform.isWindows) SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ücretsiz yerel model'), subtitle: const Text('Qwen3 1.7B • Ollama'), value: local, onChanged: (v) => refresh(() => local = v)),
        if (local) ...[
          const Text('Model bu bilgisayarda çalışır. İlk kurulum için yerel başlatıcıyı aç. Son birkaç mesaj modele aktarılır; daha eski mesajlar yalnızca geçmişte saklanır.'),
          const SizedBox(height: 8),
          TextButton(onPressed: () async {
            try { await _localClient.check(); if (mounted) setState(() => _error = 'Ollama ve model hazır.'); }
            on ModelFailure catch (e) { if (mounted) setState(() => _error = e.message); }
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Bağlantıyı kontrol et')),
        ] else ...[
          const Text('OpenAI API ayrıca ücretlidir. Anahtar yalnızca bu oturumda tutulur. Bu sohbetin mesajları yanıt için OpenAI’a gönderilir.'),
          const SizedBox(height: 12),
          TextField(controller: key, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'API anahtarı')),
          TextField(controller: model, autocorrect: false, decoration: const InputDecoration(labelText: 'Model kimliği')),
          if (Platform.isAndroid) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Telefonda ücretsiz yerel model henüz desteklenmiyor.')),
        ],
        if (Platform.isWindows) ...[
          const Divider(),
          TextButton.icon(onPressed: () { Navigator.pop(ctx); _installTools(); }, icon: const Icon(Icons.build_outlined), label: const Text('Kamera ve ses araçlarını kur')),
          TextButton.icon(onPressed: () { Navigator.pop(ctx); _installLocal(); }, icon: const Icon(Icons.download), label: const Text('Yerel modeli D sürücüsüne kur')),
        ],
        const SizedBox(height: 12),
        const Text('Sohbetler bu cihazda şifrelenmeden saklanır. Ses, kamera ve bilgisayar araçları yalnızca Windows’ta kullanıcı eylemiyle çalışır. İnternet araması yoktur.'),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')), FilledButton(onPressed: () {
        setState(() { _local = local; _key = local ? '' : key.text.trim(); _model = model.text.trim(); _error = null; });
        Navigator.pop(ctx);
      }, child: const Text('Uygula'))],
    )));
    await Future<void>.delayed(const Duration(milliseconds: 300)); key.dispose(); model.dispose();
  }
  void _plans() => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
    title: const Text('OMNEX planları'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ÜCRETSİZ', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
      const Text('0 TL • Windows yerel modeli', style: TextStyle(fontSize: 22)),
      const SizedBox(height: 8), const Text('Sohbet geçmişi, canlı yanıt, kopyalama ve açık/koyu tema. Yerel model için uygun bilgisayar gerekir.'),
      const Divider(height: 32),
      Text('OMNEX PRO • TASLAK', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.primary, letterSpacing: 1)),
      const Text('Örnek fiyat: 100 TL / ay', style: TextStyle(fontSize: 22)),
      const SizedBox(height: 8), const Text('Planlanan: daha güçlü bulut modeli ve daha yüksek kullanım hakkı. Model, kullanım sınırları ve gerçek fiyat henüz belirlenmedi.'),
      const SizedBox(height: 20),
      const FilledButton(onPressed: null, child: Text('Henüz satışta değil')),
      const SizedBox(height: 12), const Text('Bu ekran yalnızca plan taslağıdır. Ödeme alınmaz, abonelik açılmaz ve model yükseltilmez. OpenAI API kullanımı bu örnek fiyata dahil değildir.'),
    ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
  ));
  Widget _sidebar({bool drawer = false}) {
    final filtered = _chats.where((c) => c.title.toLowerCase().contains(_search.toLowerCase()) || c.messages.any((m) => m['content']!.toLowerCase().contains(_search.toLowerCase()))).toList();
    return SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.all(24), child: Text('OMNEX', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 3))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: FilledButton.icon(onPressed: _busy || _loading || _voiceBusy ? null : () { _newChat(); if (drawer) Navigator.pop(context); }, icon: const Icon(Icons.add), label: const Text('Yeni sohbet'))),
      Padding(padding: const EdgeInsets.all(16), child: TextField(onChanged: (s) => setState(() => _search = s), decoration: const InputDecoration(hintText: 'Sohbetlerde ara', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))),
      Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (ctx, i) {
        final c = filtered[i];
        return ListTile(selected: identical(c, _chat), leading: const Icon(Icons.chat_bubble_outline, size: 18), title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: _busy || _voiceBusy ? null : () { setState(() { _chat = c; _error = null; _input.clear(); _attached = ''; _attachmentName = ''; }); if (drawer) Navigator.pop(context); _bottom(); },
          trailing: PopupMenuButton<String>(enabled: !_busy, tooltip: 'Sohbet seçenekleri', onSelected: (v) { if (v == 'rename') { _rename(c); } else { _delete(c); } }, itemBuilder: (_) => [const PopupMenuItem(value: 'rename', child: Text('Adını değiştir')), const PopupMenuItem(value: 'delete', child: Text('Sil'))]),
        );
      })),
      SizedBox(height: 220, child: ListView(children: [
      const Divider(),
      ListTile(leading: const Icon(Icons.tune), title: const Text('Asistanı kişiselleştir'), onTap: _busy ? null : _assistantSettings),
      if (Platform.isWindows) ListTile(leading: const Icon(Icons.view_in_ar), title: const Text('Görüş paneli'), onTap: _busy || _voiceBusy ? null : () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => HudPage(tools: _tools)))),
      if (Platform.isWindows) ListTile(leading: const Icon(Icons.computer), title: const Text('Bilgisayar araçları'), onTap: _computerTools),
      ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Planları keşfet'), subtitle: const Text('Pro • Yakında'), onTap: _plans),
      ListTile(leading: const Icon(Icons.contrast), title: const Text('Temayı değiştir'), onTap: widget.onToggleTheme),
      const Padding(padding: EdgeInsets.all(16), child: Text('OMNEX 0.5 • Sohbetlerin bu cihazda', style: TextStyle(fontSize: 11))),
      ])),
    ]));
  }
  Widget _bubble(String text, bool user, {bool pending = false}) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(constraints: const BoxConstraints(maxWidth: 760), margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: user ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(user ? 'SEN' : 'OMNEX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 10),
        if (user || pending) SelectableText(text, style: const TextStyle(fontSize: 15, height: 1.5))
        else MarkdownBody(data: text, selectable: true, sizedImageBuilder: (config) => Text(config.alt ?? 'Görsel bağlantısı'), onTapLink: (text, href, title) { if (href != null) _copy(href); }),
        if (!pending) Row(mainAxisSize: MainAxisSize.min, children: [
          if (!user && Platform.isWindows) IconButton(tooltip: _speaking ? 'Sesli okumayı durdur' : 'Sesli oku', icon: Icon(_speaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined, size: 18), onPressed: _voiceBusy ? null : () => _readAloud(text)),
          IconButton(tooltip: 'Kopyala', icon: const Icon(Icons.copy_outlined, size: 17), onPressed: () => _copy(text)),
          if (user) IconButton(tooltip: 'Düzenleyip yeniden sor', icon: const Icon(Icons.edit_outlined, size: 17), onPressed: _busy ? null : () => setState(() => _input.text = text)),
        ]),
      ]),
    ),
  );
  Widget _welcome() => Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.auto_awesome, size: 52, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 20), const Text('Birlikte ne yapalım?', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
    const SizedBox(height: 12), const Text('Fikrini geliştir, bir konuyu öğren veya bir şeyler yaz.', textAlign: TextAlign.center),
    const SizedBox(height: 28), Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
      for (final prompt in ['Bir bilimkurgu sahnesi yazalım', 'Bugün için bir çalışma planı yap', 'Yapay zekâyı basitçe anlat', 'Bir oyun fikri geliştirelim'])
        ActionChip(label: Text(prompt), onPressed: () => setState(() => _input.text = prompt)),
    ]),
  ])));
  Widget _conversation() => Column(children: [
    Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Row(children: [
      Icon(_local ? Icons.computer : Icons.cloud_outlined, size: 16), const SizedBox(width: 8),
      Expanded(child: Text(_local ? 'Yerel • Qwen3 1.7B • API ücreti yok' : (_key.isEmpty ? 'Bağlantı ayarlarını tamamla' : 'OpenAI • $_model'), style: const TextStyle(fontSize: 12))),
    ])),
    if (_error != null) MaterialBanner(content: Text(_error!), actions: [TextButton(onPressed: () => setState(() => _error = null), child: const Text('Kapat'))]),
    Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : (_chat.messages.isEmpty && !_busy ? _welcome() : ListView(
      controller: _scroll, padding: const EdgeInsets.all(20), children: [
        for (final m in _chat.messages) _bubble(m['content']!, m['role'] == 'user'),
        if (_busy) _bubble(_pending, true, pending: true),
        if (_busy) _bubble(_partial.isEmpty ? 'Yanıt hazırlanıyor…' : _partial, false, pending: true),
      ],
    ))),
    if (_busy) const LinearProgressIndicator(minHeight: 2),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(children: [
      if (_voiceBusy) Padding(padding: const EdgeInsets.all(8), child: Row(children: [const Icon(Icons.mic, color: Colors.redAccent), const SizedBox(width: 8), Expanded(child: Text(_voiceStatus)), TextButton(onPressed: _cancelVoice, child: const Text('İptal'))])),
      if (_attached.isNotEmpty) InputChip(label: Text('$_attachmentName • ${_attached.length} karakter'), onDeleted: _busy ? null : () => setState(() { _attached = ''; _attachmentName = ''; })),
      Row(children: [
        IconButton(tooltip: 'Metin dosyası ekle', onPressed: _busy || _voiceBusy ? null : _attach, icon: const Icon(Icons.attach_file)),
        if (Platform.isWindows) IconButton(tooltip: 'Sesle yaz', onPressed: _busy || _voiceBusy ? null : _voiceInput, icon: const Icon(Icons.mic_none)),
        const SizedBox(width: 8), Text(_style, style: const TextStyle(fontSize: 12)),
        TextButton(onPressed: _busy ? null : _assistantSettings, child: Text(_detailed ? 'Ayrıntılı yanıt' : 'Kısa yanıt')),
      ]),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _input, enabled: !_loading && !_busy && !_voiceBusy, minLines: 1, maxLines: 6, textInputAction: TextInputAction.newline,
        decoration: InputDecoration(hintText: 'OMNEX’e bir şey sor…', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)))),
        const SizedBox(width: 10), IconButton.filled(tooltip: _busy ? 'Yanıtı durdur' : 'Gönder', onPressed: _loading || _voiceBusy ? null : (_busy ? _stop : _send), icon: Icon(_busy ? Icons.stop : Icons.arrow_upward)),
      ]),
      const SizedBox(height: 8), const Text('OMNEX hata yapabilir. Önemli bilgileri doğrula.', style: TextStyle(fontSize: 11)),
    ]))),
  ]);
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final wide = constraints.maxWidth >= 900;
    return Scaffold(
      drawer: wide ? null : Drawer(child: _sidebar(drawer: true)),
      appBar: AppBar(title: Text(_chat.title, maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
        IconButton(tooltip: 'Sohbeti kopyala', onPressed: _chat.messages.isEmpty ? null : () => _copy(_chat.messages.map((m) => '${m['role'] == 'user' ? 'Sen' : 'OMNEX'}: ${m['content']}').join('\n\n')), icon: const Icon(Icons.ios_share)),
        IconButton(tooltip: 'Model bağlantısı', onPressed: _busy ? null : _connection, icon: const Icon(Icons.settings_outlined)),
      ]),
      body: Row(children: [if (wide) ...[SizedBox(width: 280, child: _sidebar()), const VerticalDivider(width: 1)], Expanded(child: _conversation())]),
    );
  });
  @override
  void dispose() { ++_voiceEpoch; _tools.close(); ++_requestId; _localClient.cancel(); _cloudClient.cancel(); _input.dispose(); _scroll.dispose(); super.dispose(); }
}
