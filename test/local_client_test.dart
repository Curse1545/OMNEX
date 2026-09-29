import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnex/model_client.dart';

void main() {
  test('Local chat sends bounded history without any API credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      expect(request.uri.path, '/api/chat');
      expect(request.headers.value('authorization'), isNull);
      final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(data['model'], 'qwen3:1.7b');
      expect(data['think'], false);
      expect(data['options']['num_ctx'], 2048);
      expect(data['messages'].length, lessThanOrEqualTo(6));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'done': true, 'message': {'content': 'Merhaba Arda'}}));
      await request.response.close();
    });
    try {
      final reply = await LocalModelClient(port: server.port).reply([
        for (var i = 0; i < 11; i++) {'role': i.isEven ? 'user' : 'assistant', 'content': 'Test $i'},
      ]);
      expect(reply, 'Merhaba Arda');
      await handled;
    } finally {
      await server.close(force: true);
    }
  });
  test('Local model missing gives setup instruction', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      request.response.statusCode = 404;
      request.response.write('{}');
      await request.response.close();
    });
    try {
      await expectLater(LocalModelClient(port: server.port).reply([{'role': 'user', 'content': 'Hi'}]),
        throwsA(isA<ModelFailure>().having((e) => e.message, 'message', contains('OMNEX-Yerel-Baslat.cmd'))));
      await handled;
    } finally { await server.close(force: true); }
  });
  test('Long history is bounded and starts with user', () {
    final history = localHistory([for (var i = 0; i < 13; i++)
      {'role': i.isEven ? 'user' : 'assistant', 'content': 'x' * 2000}]);
    expect(history.length, 5);
    expect(history.first['role'], 'user');
    expect(history.last['content']!.length, lessThan(1250));
  });
}
