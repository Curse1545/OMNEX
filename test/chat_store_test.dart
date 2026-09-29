import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omnex/chat_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Saved conversations survive a new store and rapid writes keep latest snapshot', () async {
    final store = ChatStore();
    final chat = Conversation.empty();
    chat.messages.addAll([{'role': 'user', 'content': 'Türkçe soru'}, {'role': 'assistant', 'content': 'Yanıt'}]);
    final first = store.save([chat]);
    chat.title = 'Son ad';
    final second = store.save([chat]);
    await Future.wait([first, second]);
    final saved = await ChatStore().load();
    expect(saved.single.title, 'Son ad');
    expect(saved.single.messages.last['content'], 'Yanıt');
    await store.save([]);
    expect(await ChatStore().load(), isEmpty);
  });
  test('Invalid history is reported instead of silently discarded', () async {
    SharedPreferences.setMockInitialValues({ChatStore.storageKey: 'broken json'});
    await expectLater(ChatStore().load(), throwsFormatException);
  });
}
