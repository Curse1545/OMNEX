import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnex/main.dart';

void main() {
  testWidgets('Sending without credentials opens setup and preserves input', (tester) async {
    await tester.pumpWidget(const OmnexApp());
    await tester.enterText(find.byType(TextField), 'Merhaba');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Model bağlantısı'), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Merhaba'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
