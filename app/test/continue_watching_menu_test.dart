import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/tv/touchpad_motion.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/tv/tv_touchpad.dart';
import 'package:onyx/widgets/global/continue_watching_card.dart';
import 'package:provider/provider.dart';

/// Le menu d'une carte « Reprendre », tel qu'on l'ouvre à la télécommande en
/// gardant OK enfoncé : il doit rester ouvert et mener à la fiche du média.
void main() {
  Widget card(HomeMediaItem item, {required VoidCallback onPlay}) =>
      Provider<ApiClient>.value(
        value: ApiClient(),
        child: TvScope(
          isTv: true,
          child: MaterialApp(
            shortcuts: <ShortcutActivator, Intent>{
              ...WidgetsApp.defaultShortcuts,
              ...tvSelectShortcuts,
            },
            home: Scaffold(
              body: Center(
                child: ContinueWatchingCard(
                  item: item,
                  onTap: (_) => onPlay(),
                  onTitleTap: (_) {},
                  onMarkAsWatched: (_) async {},
                  onRemoveFromRow: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );

  final item = HomeMediaItem.fromJson({
    'id': 42,
    'type': 'movie',
    'title': 'Le film',
    'duration': 6000,
    'current_position_seconds': 600,
    'is_finished': false,
    'created_at': '2026-09-30T10:00:00Z',
  });

  testWidgets(
      "holding OK opens a menu that stays open and leads to the media's page",
      (tester) async {
    var plays = 0;
    var detailsOpened = 0;
    var watched = 0;

    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: ApiClient(),
        child: TvScope(
          isTv: true,
          child: MaterialApp(
            shortcuts: <ShortcutActivator, Intent>{
              ...WidgetsApp.defaultShortcuts,
              ...tvSelectShortcuts,
            },
            home: Scaffold(
              body: Center(
                child: ContinueWatchingCard(
                  item: item,
                  onTap: (_) => plays++,
                  onTitleTap: (_) => detailsOpened++,
                  onMarkAsWatched: (_) async => watched++,
                  onRemoveFromRow: (_) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Focus.of(tester.element(find.text('Le film'))).requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.text("Aller à l'affiche"), findsOneWidget,
        reason: 'the rest of the long press must not close the menu');
    expect(find.text('Marquer comme vu'), findsOneWidget);
    expect(find.text('Supprimer de Reprendre'), findsOneWidget);
    expect(watched, 0);
    expect(plays, 0);

    await tester.tap(find.text("Aller à l'affiche"));
    await tester.pumpAndSettle();

    expect(detailsOpened, 1);
    expect(plays, 0);
    expect(find.text("Aller à l'affiche"), findsNothing);
  });

  testWidgets(
      'holding OK opens the menu on a remote that never repeats the key',
      (tester) async {
    var plays = 0;
    await tester.pumpWidget(card(item, onPlay: () => plays++));
    Focus.of(tester.element(find.text('Le film'))).requestFocus();
    await tester.pump();

    // La Siri Remote, un navigateur de téléviseur : un appui, un relâchement,
    // aucune répétition entre les deux.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.text("Aller à l'affiche"), findsOneWidget);
    expect(plays, 0);
  });

  testWidgets('a short press on OK still plays', (tester) async {
    var plays = 0;
    await tester.pumpWidget(card(item, onPlay: () => plays++));
    Focus.of(tester.element(find.text('Le film'))).requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));

    expect(plays, 1);
    expect(find.text("Aller à l'affiche"), findsNothing);
  });

  testWidgets(
      "a held click that the Apple TV simulator's remote breaks into bounces "
      'still opens the menu', (tester) async {
    var plays = 0;
    await tester.pumpWidget(card(item, onPlay: () => plays++));
    Focus.of(tester.element(find.text('Le film'))).requestFocus();
    await tester.pump();

    // Ce que la télécommande du simulateur envoie pour un clic tenu : un
    // relâchement 8 ms après l'appui, un nouvel appui aussitôt, et un frôlement
    // du pavé à gauche puis à droite.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 8));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text("Aller à l'affiche"), findsOneWidget);
    expect(plays, 0);
  });

  testWidgets('a single bounce-short press still plays', (tester) async {
    var plays = 0;
    await tester.pumpWidget(card(item, onPlay: () => plays++));
    Focus.of(tester.element(find.text('Le film'))).requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));

    expect(plays, 1);
    expect(find.text("Aller à l'affiche"), findsNothing);
  });

  // Après un menu fermé par Retour, le simulateur Apple TV envoie l'appui long
  // suivant sur la même carte en « enfoncé, relâché 1 ms après », puis plus
  // rien tant que le doigt reste appuyé. Le clic physique du pavé, lui, reste
  // enfoncé : c'est lui qui dit si l'appui dure.
  testWidgets(
      'a press the remote cuts short while the touchpad is still clicked '
      'opens the menu', (tester) async {
    addTearDown(TvTouchpad.debugReset);
    var plays = 0;
    await tester.pumpWidget(card(item, onPlay: () => plays++));
    Focus.of(tester.element(find.text('Le film'))).requestFocus();
    await tester.pump();

    TvTouchpad.handleTouch(TouchpadPhase.clickDown, 0, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    TvTouchpad.handleTouch(TouchpadPhase.clickUp, 0, 0);
    await tester.pumpAndSettle();

    expect(find.text("Aller à l'affiche"), findsOneWidget);
    expect(plays, 0);
  });

  testWidgets(
      'the same cut-short press plays once the touchpad is released early',
      (tester) async {
    addTearDown(TvTouchpad.debugReset);
    var plays = 0;
    await tester.pumpWidget(card(item, onPlay: () => plays++));
    Focus.of(tester.element(find.text('Le film'))).requestFocus();
    await tester.pump();

    TvTouchpad.handleTouch(TouchpadPhase.clickDown, 0, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 150));
    expect(plays, 0, reason: 'the touchpad is still clicked');
    TvTouchpad.handleTouch(TouchpadPhase.clickUp, 0, 0);
    await tester.pump(const Duration(seconds: 1));

    expect(plays, 1);
    expect(find.text("Aller à l'affiche"), findsNothing);
  });
}
