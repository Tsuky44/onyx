import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/tr.dart';
import 'package:onyx/theme/lite_mode.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/lite_mode_suggestion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Des saccades mesurées proposent le mode léger, sans l'imposer
/// (ADR-0141) : une fenêtre qui se pilote à la télécommande, dont la réponse
/// se retrouve dans les réglages.
void main() {
  final navigatorKey = GlobalKey<NavigatorState>();

  setUpAll(() => LiteModeSuggestion.attach(navigatorKey));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LiteMode.resetForTest();
  });
  tearDown(LiteMode.resetForTest);

  Future<void> pumpApp(WidgetTester tester, {bool tv = false}) async {
    await tester.pumpWidget(TvScope(
      isTv: tv,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ));
  }

  Future<void> jank(WidgetTester tester) async {
    LiteMode.noteSustainedJank();
    await tester.pumpAndSettle();
  }

  testWidgets('des saccades ouvrent la question, l’interface reste complète',
      (tester) async {
    await pumpApp(tester);
    await jank(tester);

    expect(find.text(tr('L’interface saccade sur cet appareil')),
        findsOneWidget);
    expect(LiteMode.isLite, isFalse);

    // Une seule question à la fois : celle-ci se ferme avant le test suivant.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('« Passer en mode léger » l’active', (tester) async {
    await pumpApp(tester);
    await jank(tester);

    await tester.tap(find.text(tr('Passer en mode léger')));
    await tester.pumpAndSettle();

    expect(LiteMode.isLite, isTrue);
    expect(LiteMode.preference, LiteModePreference.on);
  });

  testWidgets('« Garder l’interface complète » ne redemande plus',
      (tester) async {
    await pumpApp(tester);
    await jank(tester);

    await tester.tap(find.text(tr('Garder l’interface complète')));
    await tester.pumpAndSettle();
    expect(LiteMode.isLite, isFalse);

    await jank(tester);
    expect(find.text(tr('L’interface saccade sur cet appareil')),
        findsNothing);
  });

  testWidgets('à la télécommande, OK accepte : le focus est sur le mode léger',
      (tester) async {
    await pumpApp(tester, tv: true);
    await jank(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(LiteMode.isLite, isTrue);
  });

  testWidgets('Retour ferme sans rien changer ni rien garder',
      (tester) async {
    await pumpApp(tester);
    await jank(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text(tr('L’interface saccade sur cet appareil')),
        findsNothing);
    expect(LiteMode.isLite, isFalse);
    expect(LiteMode.suggestion.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('lite_mode_suggestion_declined'), isFalse);
  });
}
