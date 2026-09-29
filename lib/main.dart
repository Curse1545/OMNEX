import 'dart:io';
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
  void initState() { super.initState(); _load(); }
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
      if (mounted) setState(() {
        _loading = false; _storageBlocked = true; _chats = [_chat];
        _error = 'Kayıtlı geçmiş okunamadı. Eski kayıtların üzerine yazılmayacak; bu oturum kaydedilmiyor.';
      });
    }
  }
  Future<void> _save() async {
    if (_storageBlocked) return;
    try { await _store.save(_chats); }
    catch (_) { if (mounted) setState(() => _error = 'Sohbet kaydedilemedi. Disk alanını kontrol et; uygulamayı kapatmadan metni kopyalayabilirsin.'); }
  }
  void _newChat() {
    if (_busy || _loading) return;
    setState(() {
      _chat = Conversation.empty(); _chats.insert(0, _chat);
      _error = null; _input.clear();
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
    if (_loading || _busy || text.isEmpty) return;
    if (!_local && (_key.isEmpty || _model.isEmpty)) { await _connection(); return; }
    if (text.length > (_local ? 1200 : 12000)) {
      setState(() => _error = _local ? 'Yerel modda en fazla 1200 karakter gönder.' : 'En fazla 12000 karakter gönder.'); return;
    }
    final request = ++_requestId;
    final target = _chat;
    setState(() { _busy = true; _error = null; _pending = text; _partial = ''; _input.clear(); });
    _bottom();
    final history = [...target.messages, {'role': 'user', 'content': text}];
    try {
      if (_local) {
        await for (final token in _localClient.streamReply(history)) {
          if (!mounted || request != _requestId) return;
          setState(() => _partial += token);
          _bottom();
        }
      } else {
        final answer = await _cloudClient.reply(apiKey: _key, model: _model, history: history);
        if (!mounted || request != _requestId) return;
        setState(() => _partial = answer);
      }
      if (!mounted || request != _requestId) return;
      if (_partial.trim().isEmpty) throw const ModelFailure('Boş yanıt geldi. Tekrar deneyebilirsin.');
      setState(() {
        target.messages.addAll([{'role': 'user', 'content': text}, {'role': 'assistant', 'content': _partial}]);
        if (target.title == 'Yeni sohbet') target.title = text.length > 45 ? '${text.substring(0, 45)}…' : text;
        _chats.remove(target); _chats.insert(0, target);
        _pending = ''; _partial = ''; _busy = false;
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
        const SizedBox(height: 12),
        const Text('Sohbetler bu cihazda şifrelenmeden saklanır. Mikrofon, internet araması ve cihaz kontrolü yoktur.'),
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
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: FilledButton.icon(onPressed: _busy || _loading ? null : () { _newChat(); if (drawer) Navigator.pop(context); }, icon: const Icon(Icons.add), label: const Text('Yeni sohbet'))),
      Padding(padding: const EdgeInsets.all(16), child: TextField(onChanged: (s) => setState(() => _search = s), decoration: const InputDecoration(hintText: 'Sohbetlerde ara', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))),
      Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (ctx, i) {
        final c = filtered[i];
        return ListTile(selected: identical(c, _chat), leading: const Icon(Icons.chat_bubble_outline, size: 18), title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: _busy ? null : () { setState(() { _chat = c; _error = null; _input.clear(); }); if (drawer) Navigator.pop(context); _bottom(); },
          trailing: PopupMenuButton<String>(enabled: !_busy, tooltip: 'Sohbet seçenekleri', onSelected: (v) { if (v == 'rename') { _rename(c); } else { _delete(c); } }, itemBuilder: (_) => [const PopupMenuItem(value: 'rename', child: Text('Adını değiştir')), const PopupMenuItem(value: 'delete', child: Text('Sil'))]),
        );
      })),
      const Divider(),
      ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Planları keşfet'), subtitle: const Text('Pro • Yakında'), onTap: _plans),
      ListTile(leading: const Icon(Icons.contrast), title: const Text('Temayı değiştir'), onTap: widget.onToggleTheme),
      const Padding(padding: EdgeInsets.all(16), child: Text('OMNEX 0.4 • Sohbetlerin bu cihazda', style: TextStyle(fontSize: 11))),
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
        else MarkdownBody(data: text, selectable: true, imageBuilder: (uri, title, alt) => Text(alt ?? 'Görsel bağlantısı'), onTapLink: (text, href, title) { if (href != null) _copy(href); }),
        if (!pending) Row(mainAxisSize: MainAxisSize.min, children: [
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
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _input, enabled: !_loading && !_busy, minLines: 1, maxLines: 6, textInputAction: TextInputAction.newline,
        decoration: InputDecoration(hintText: 'OMNEX’e bir şey sor…', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none)))),
        const SizedBox(width: 10), IconButton.filled(tooltip: _busy ? 'Yanıtı durdur' : 'Gönder', onPressed: _loading ? null : (_busy ? _stop : _send), icon: Icon(_busy ? Icons.stop : Icons.arrow_upward)),
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
  void dispose() { ++_requestId; _localClient.cancel(); _cloudClient.cancel(); _input.dispose(); _scroll.dispose(); super.dispose(); }
}
