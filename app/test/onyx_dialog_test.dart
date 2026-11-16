import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/onyx_dialog.dart';

/// Un bouton qui pose la question et range la réponse dans [answer].
Widget _host({
  required ValueSetter<bool> answer,
  bool destructive = false,
  bool tv = false,
}) {
  return TvScope(
    isTv: tv,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer(await showOnyxConfirm(
              context,
              title: 'Supprimer ?',
              message: 'Ce sera effacé.',
              confirmLabel: 'Supprimer',
              destructive: destructive,
              icon: AppIcons.delete,
            )),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

/// La couleur de fond de la capsule portant [label].
Color? _capsuleColor(WidgetTester tester, String label) {
  final box = tester.widget<AnimatedContainer>(find
      .ancestor(of: find.text(label), matching: find.byType(AnimatedContainer))
      .first);
  return (box.decoration as ShapeDecoration).color;
}

void main() {
  testWidgets('confirmer rend vrai', (tester) async {
    bool? answer;
    await tester.pumpWidget(_host(answer: (v) => answer = v));
    await _open(tester);

    expect(find.text('Ce sera effacé.'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
    expect(find.byType(OnyxDialog), findsNothing);
  });

  testWidgets('annuler rend faux', (tester) async {
    bool? answer;
    await tester.pumpWidget(_host(answer: (v) => answer = v));
    await _open(tester);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('Échap annule', (tester) async {
    bool? answer;
    await tester.pumpWidget(_host(answer: (v) => answer = v));
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(answer, isFalse);
    expect(find.byType(OnyxDialog), findsNothing);
  });

  testWidgets('un clic hors de la fenêtre annule', (tester) async {
    bool? answer;
    await tester.pumpWidget(_host(answer: (v) => answer = v));
    await _open(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('une suppression a son action en rouge, une question en blanc',
      (tester) async {
    await tester.pumpWidget(_host(answer: (_) {}, destructive: true));
    await _open(tester);
    expect(_capsuleColor(tester, 'Supprimer'), AppColors.error);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(answer: (_) {}));
    await _open(tester);
    expect(_capsuleColor(tester, 'Supprimer'), AppColors.textPrimary);
  });

  testWidgets(
      'une suppression démarre sur « Annuler » : Entrée ne supprime pas',
      (tester) async {
    bool? answer;
    await tester.pumpWidget(_host(answer: (v) => answer = v, destructive: true));
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(answer, isFalse);
  });

  testWidgets('sur TV, le dialogue garde le rendu Material du thème',
      (tester) async {
    bool? answer;
    await tester.pumpWidget(_host(answer: (v) => answer = v, tv: true));
    await _open(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
