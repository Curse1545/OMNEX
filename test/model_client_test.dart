import 'package:flutter_test/flutter_test.dart';
import 'package:omnex/model_client.dart';

void main() {
  test('Extracts all message text while ignoring reasoning items', () {
    expect(readResponseText({'status': 'completed', 'output': [
      {'type': 'reasoning', 'summary': []},
      {'type': 'message', 'content': [
        {'type': 'output_text', 'text': 'Merhaba'},
        {'type': 'output_text', 'text': 'Arda'},
      ]},
    ]}), 'Merhaba\nArda');
  });
  test('Shows a refusal as a reply', () {
    expect(readResponseText({'status': 'completed', 'output': [
      {'type': 'message', 'content': [{'type': 'refusal', 'refusal': 'Yardımcı olamam.'}]},
    ]}), 'Yardımcı olamam.');
  });
  test('Incomplete or empty output is not reported as success', () {
    expect(() => readResponseText({'status': 'incomplete'}), throwsA(isA<ModelFailure>()));
    expect(() => readResponseText({'status': 'completed', 'output': []}), throwsA(isA<ModelFailure>()));
  });
}
