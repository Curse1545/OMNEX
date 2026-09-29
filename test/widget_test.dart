import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omnex/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Connection dialog preserves composed input', (tester) async {
    await tester.pumpWidget(const OmnexApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Merhaba');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Model bağlantısı'), findsOneWidget);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Merhaba'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('Pro draft does not offer an active payment', (tester) async {
    await tester.pumpWidget(const OmnexApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planları keşfet'));
    await tester.pumpAndSettle();
    expect(find.text('Örnek fiyat: 100 TL / ay'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Henüz satışta değil'));
    expect(button.onPressed, isNull);
  });
}
