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
