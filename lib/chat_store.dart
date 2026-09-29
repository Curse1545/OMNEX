import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Conversation {
  final String id;
  String title;
  final List<Map<String, String>> messages;
  Conversation({required this.id, required this.title, List<Map<String, String>>? messages})
      : messages = messages ?? [];
  factory Conversation.empty() => Conversation(id: DateTime.now().microsecondsSinceEpoch.toString(), title: 'Yeni sohbet');
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'messages': messages};
  factory Conversation.fromJson(Map<String, dynamic> data) {
    final messages = (data['messages'] as List).map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      if ((m['role'] != 'user' && m['role'] != 'assistant') || m['content'] is! String) {
        throw const FormatException('Invalid message');
      }
      return {'role': m['role'] as String, 'content': m['content'] as String};
    }).toList();
    return Conversation(id: data['id'] as String, title: data['title'] as String, messages: messages);
  }
}

class ChatStore {
  static const storageKey = 'omnex.chats.v1';
  Future<void> _writes = Future.value();
  Future<List<Conversation>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Conversation.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
  Future<void> save(List<Conversation> chats) {
    final snapshot = jsonEncode(chats.map((c) => c.toJson()).toList());
    final next = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, snapshot)) {
        throw StateError('History could not be saved');
      }
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
