import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ModelFailure implements Exception {
  final String message;
  const ModelFailure(this.message);
}

String readResponseText(Map<String, dynamic> body) {
  if (body['status'] != 'completed') {
    throw const ModelFailure('Yanıt tamamlanamadı. Yeniden deneyebilirsin.');
  }
  final texts = <String>[];
  for (final item in (body['output'] as List? ?? [])) {
    if (item is! Map || item['type'] != 'message') continue;
    for (final part in (item['content'] as List? ?? [])) {
      if (part is! Map) continue;
      if (part['type'] == 'output_text' && part['text'] is String) {
        texts.add(part['text'] as String);
      } else if (part['type'] == 'refusal' && part['refusal'] is String) {
        texts.add(part['refusal'] as String);
      }
    }
  }
  if (texts.join().trim().isEmpty) {
    throw const ModelFailure('Model bir metin yanıtı döndürmedi.');
  }
  return texts.join('\n');
}

class ModelClient {
  Future<String> reply({
    required String apiKey,
    required String model,
    required List<Map<String, String>> history,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        final request = await client.postUrl(Uri.parse('https://api.openai.com/v1/responses'));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({
          'model': model,
          'store': false,
          'instructions': 'Sen OMNEX adlı Türkçe konuşan bir asistansın. Açık ve doğru yanıt ver. Cihaza, dosyalara veya mikrofona erişimin yok. Yapmadığın bir işlemi yaptığını söyleme.',
          'input': history,
          'max_output_tokens': 2048,
        }));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) {
          throw ModelFailure(switch (response.statusCode) {
            401 => 'API anahtarı geçersiz. Bağlantı ayarlarını kontrol et.',
            403 => 'Bu modele erişim izni yok.',
            404 => 'Model bulunamadı. Model kimliğini kontrol et.',
            429 => 'API kotası veya istek sınırı aşıldı. API hesabını kontrol et.',
            _ => 'Model servisine ulaşılamadı (HTTP ${response.statusCode}).',
          });
        }
        return readResponseText(jsonDecode(body) as Map<String, dynamic>);
      })().timeout(const Duration(seconds: 90));
    } on ModelFailure {
      rethrow;
    } on TimeoutException {
      throw const ModelFailure('İstek zaman aşımına uğradı. Yeniden deneyebilirsin.');
    } on SocketException {
      throw const ModelFailure('İnternet bağlantısını kontrol et.');
    } catch (_) {
      throw const ModelFailure('Yanıt alınamadı. Lütfen yeniden dene.');
    } finally {
      client.close(force: true);
    }
  }
}

const localModel = 'qwen3:1.7b';

List<Map<String, String>> localHistory(List<Map<String, String>> history) {
  // Keep recent whole turns; do not split a user/assistant pair.
  var start = history.length > 5 ? history.length - 5 : 0;
  while (start < history.length && history[start]['role'] != 'user') {
    start++;
  }
  return history.sublist(start).map((m) => {
    'role': m['role']!,
    'content': m['content']!.length > 1200
        ? '${m['content']!.substring(0, 1200)} [kısaltıldı]'
        : m['content']!,
  }).toList();
}

String readLocalResponse(Map<String, dynamic> body) {
  final message = body['message'];
  if (body['done'] != true || message is! Map || message['content'] is! String ||
      (message['content'] as String).trim().isEmpty) {
    throw const ModelFailure('Yerel model metin döndürmedi. Yeniden deneyebilirsin.');
  }
  return message['content'] as String;
}

class LocalModelClient {
  final int port;
  LocalModelClient({this.port = 11434});

  Future<Map<String, dynamic>> _call(String path, Map<String, dynamic>? payload) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final request = await client.openUrl(payload == null ? 'GET' : 'POST',
          Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path));
        request.followRedirects = false;
        if (payload != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(payload));
        }
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 404) {
          throw const ModelFailure('Model henüz indirilmemiş. Paketteki OMNEX-Yerel-Baslat.cmd dosyasını çalıştır.');
        }
        if (response.statusCode != 200) {
          throw ModelFailure('Ollama yanıt veremedi (HTTP ${response.statusCode}). Bellek için diğer uygulamaları kapat.');
        }
        return jsonDecode(body) as Map<String, dynamic>;
      })().timeout(Duration(seconds: payload == null ? 8 : 180));
    } on ModelFailure {
      rethrow;
    } on SocketException {
      throw const ModelFailure('Ollama açık değil. OMNEX-Yerel-Baslat.cmd dosyasını çalıştır.');
    } on TimeoutException {
      throw const ModelFailure('Yerel model zaman aşımına uğradı. Diğer uygulamaları kapatıp tekrar dene.');
    } catch (_) {
      throw const ModelFailure('Ollama yanıtı okunamadı. Yerel kurulumu kontrol et.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> check() async {
    final body = await _call('/api/tags', null);
    final models = body['models'] as List? ?? [];
    if (!models.any((m) => m is Map && (m['name'] == localModel || m['model'] == localModel))) {
      throw const ModelFailure('Qwen3 modeli eksik. OMNEX-Yerel-Baslat.cmd dosyasını çalıştır.');
    }
  }

  Future<String> reply(List<Map<String, String>> history) async {
    final body = await _call('/api/chat', {
      'model': localModel,
      'stream': false,
      'think': false,
      'keep_alive': '1m',
      'options': {'num_ctx': 2048, 'num_predict': 384, 'num_thread': 2},
      'messages': [
        {'role': 'system', 'content': 'Sen OMNEX adlı Türkçe asistansın. Kısa, doğru ve anlaşılır yanıt ver. Cihaz kontrolün yok; yapmadığın işlemleri yaptığını söyleme.'},
        ...localHistory(history),
      ],
    });
    return readLocalResponse(body);
  }
}
