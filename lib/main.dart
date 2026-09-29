
import 'package:flutter/material.dart';

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
      'OMNEX hazır. Şimdilik yerel demo modundayım; riskli işlemler senden onay almadan çalıştırılmaz.',
      fromUser: false,
    ),
  ];

  bool _allowNotifications = false;
  bool _allowMicrophone = false;
  bool _allowFiles = false;

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text, fromUser: true));
      _messages.add(
        ChatMessage(
          _demoReply(text),
          fromUser: false,
        ),
      );
      _controller.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _demoReply(String input) {
    final lower = input.toLowerCase();
    if (lower.contains('dosya') || lower.contains('sil')) {
      return 'Bu işlem dosyalarda değişiklik yapabilir. Güvenlik nedeniyle önce açık onay gerekir.';
    }
    if (lower.contains('mikrofon')) {
      return _allowMicrophone
          ? 'Mikrofon izni OMNEX ayarlarında açık görünüyor.'
          : 'Mikrofon izni kapalı. İzinler ekranından açabilirsin.';
    }
    return 'Mesajını aldım: "$input". Bu sürümde yanıt motoru demo modunda; sonraki adımda gerçek model bağlantısı eklenebilir.';
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
                      'İzinler varsayılan olarak kapalıdır. İhtiyacın olmayan erişimleri açma.',
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
            child: const Text(
              'Yerel demo modu • Hassas işlemler açık onay gerektirir',
              textAlign: TextAlign.center,
            ),
          ),
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
                    child: Text(message.text),
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
                    onPressed: _sendMessage,
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
