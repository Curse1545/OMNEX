
import 'package:flutter/material.dart';
import 'model_client.dart';
import 'dart:io';

void main() {
  runApp(const OmnexApp());
}

class OmnexApp extends StatelessWidget {
  const OmnexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OMNEX',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4FC3F7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const OmnexHomePage(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool fromUser;

  const ChatMessage(this.text, {required this.fromUser});
}

class OmnexHomePage extends StatefulWidget {
  const OmnexHomePage({super.key});

  @override
  State<OmnexHomePage> createState() => _OmnexHomePageState();
}

class _OmnexHomePageState extends State<OmnexHomePage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [
    const ChatMessage(
      'Merhaba, ben OMNEX. Windows’ta ücretsiz yerel mod hazır. İlk kurulum için paketteki OMNEX-Yerel-Baslat.cmd dosyasını çalıştır. Bağlantı seçenekleri sağ üstte.',
      fromUser: false,
    ),
  ];

  bool _allowNotifications = false;
  bool _allowMicrophone = false;
  bool _allowFiles = false;

  bool _local = Platform.isWindows;
  String _apiKey = '';
  String _model = '';
  bool _busy = false;
  String? _error;
  final _history = <Map<String, String>>[];

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    if (!_local && (_apiKey.isEmpty || _model.isEmpty)) {
      await _showConnection();
      return;
    }
    if (_local && text.length > 1200) {
      setState(() => _error = 'Yerel modda mesajını 1200 karakterden kısa tut.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _messages.add(ChatMessage(text, fromUser: true));
      _controller.clear();
    });
    _scrollToEnd();
    final pending = {'role': 'user', 'content': text};
    try {
      final reply = _local
          ? await LocalModelClient().reply([..._history, pending])
          : await ModelClient().reply(apiKey: _apiKey, model: _model, history: [..._history, pending]);
      if (!mounted) return;
      setState(() {
        _history.addAll([pending, {'role': 'assistant', 'content': reply}]);
        _messages.add(ChatMessage(reply, fromUser: false));
      });
    } on ModelFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _messages.removeLast();
        _controller.text = text;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _showConnection() async {
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Model bağlantısı'),
      content: const Text('Yerel mod: API anahtarı ve API ücreti yok. Model bilgisayarında çalışır. 8 GB RAM için kısa yanıtlar ve sınırlı sohbet bağlamı kullanılır. OpenAI seçeneği ayrı API hesabı gerektirir.'),
      actions: [
        if (Platform.isWindows) FilledButton(onPressed: () {
          setState(() { _local = true; _apiKey = ''; _history.clear(); _messages.clear(); _error = null; });
          Navigator.pop(dialogContext);
        }, child: const Text('Ücretsiz yerel mod')),
        if (Platform.isWindows) TextButton(onPressed: () async {
          Navigator.pop(dialogContext);
          try {
            await LocalModelClient().check();
            if (mounted) setState(() => _error = 'Ollama ve Qwen3 modeli bulundu. Mesaj gönderebilirsin.');
          } on ModelFailure catch (e) {
            if (mounted) setState(() => _error = e.message);
          }
        }, child: const Text('Yerel bağlantıyı kontrol et')),
        TextButton(onPressed: () { Navigator.pop(dialogContext); _showOpenAI(); },
          child: const Text('OpenAI API (ücretli)')),
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Kapat')),
      ],
    ));
  }

  Future<void> _showOpenAI() async {
    final key = TextEditingController(text: _apiKey);
    final model = TextEditingController(text: _model);
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Model bağlantısı'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Kişisel kullanım: kendi OpenAI API anahtarını gir. Anahtar yalnızca bu oturumda tutulur; dosyaya kaydedilmez. Gönderdiğin mesajlar ve bu sohbetin geçmişi OpenAI’a iletilir. API kullanımı ayrıca ücretlenebilir.'),
        const SizedBox(height: 16),
        TextField(controller: key, obscureText: true, autocorrect: false,
          enableSuggestions: false, decoration: const InputDecoration(labelText: 'OpenAI API anahtarı')),
        TextField(controller: model, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Hesabındaki model kimliği')),
      ])),
      actions: [
        TextButton(onPressed: () {
          setState(() { _apiKey = ''; _model = ''; });
          Navigator.pop(dialogContext);
        }, child: const Text('Bağlantıyı temizle')),
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('İptal')),
        FilledButton(onPressed: () {
          setState(() { _local = false; _history.clear(); _messages.clear(); _apiKey = key.text.trim(); _model = model.text.trim(); });
          Navigator.pop(dialogContext);
        }, child: const Text('Bu oturumda kullan')),
      ],
    ));
    // Wait for the closing dialog animation before disposing its fields.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    key.dispose();
    model.dispose();
  }

  Future<void> _showPermissions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'OMNEX İzinleri',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Bu anahtarlar yalnızca arayüz demosudur; cihaz izni vermez. Mikrofon ve dosya işlemleri henüz desteklenmiyor.',
                    ),
                  ),
                  SwitchListTile(
                    value: _allowNotifications,
                    onChanged: (v) {
                      setState(() => _allowNotifications = v);
                      setModalState(() {});
                    },
                    title: const Text('Bildirimler'),
                  ),
                  SwitchListTile(
                    value: _allowMicrophone,
                    onChanged: (v) {
                      setState(() => _allowMicrophone = v);
                      setModalState(() {});
                    },
                    title: const Text('Mikrofon'),
                  ),
                  SwitchListTile(
                    value: _allowFiles,
                    onChanged: (v) {
                      setState(() => _allowFiles = v);
                      setModalState(() {});
                    },
                    title: const Text('Dosya erişimi'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _requestSensitiveAction() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Onay gerekli'),
        content: const Text(
          'Bu demo, hassas bir işlemden önce OMNEX’in senden açık onay istemesi gerektiğini gösterir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          approved == true
              ? 'İşlem onaylandı. Demo sürümünde gerçek sistem değişikliği yapılmadı.'
              : 'İşlem iptal edildi.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.memory),
            SizedBox(width: 10),
            Text('OMNEX'),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Model bağlantısı', onPressed: _busy ? null : _showConnection, icon: const Icon(Icons.settings_outlined)),
          IconButton(tooltip: 'Yeni sohbet', onPressed: _busy ? null : () { setState(() { _history.clear(); _messages.clear(); _error = null; }); }, icon: const Icon(Icons.add_comment_outlined)),
          IconButton(
            tooltip: 'İzinler',
            onPressed: _showPermissions,
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
          IconButton(
            tooltip: 'Onay akışı testi',
            onPressed: _requestSensitiveAction,
            icon: const Icon(Icons.verified_user_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              _local ? 'Ücretsiz yerel mod • Qwen3 1.7B • Cihaz kontrolü yok' : (_apiKey.isEmpty || _model.isEmpty ? 'Model bağlantısı gerekli' : 'OpenAI • $_model • Cihaz erişimi yok'),
              textAlign: TextAlign.center,
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.fromUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 620),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: message.fromUser
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(message.text),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'OMNEX’e yaz...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
