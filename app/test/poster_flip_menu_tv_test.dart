import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/tv_ui_scale.dart';
import 'package:onyx/widgets/global/continue_watching_card.dart';
import 'package:onyx/widgets/global/media_poster.dart';
import 'package:onyx/widgets/global/poster_flip/poster_flip_back.dart';
import 'package:provider/provider.dart';

import 'support/tv_nav_harness.dart';

/// Le menu d'une carte « Reprendre » à la télécommande : l'affiche se retourne
/// et porte au dos le titre, l'avancement et les actions. La télécommande
/// arrive dans le menu sans rien faire, le parcourt aux flèches, et Retour
/// rend l'affiche — et le focus — là où ils étaient.
void main() {
  const down = TraversalDirection.down;

  final item = HomeMediaItem.fromJson({
    'id': 42,
    'type': 'movie',
    'title': 'Le film',
    'duration': 6000,
    'current_position_seconds': 600,
    'is_finished': false,
    'created_at': '2026-09-30T10:00:00Z',
  });

  Future<TvNavHarness> pumpCard(
    WidgetTester tester,
    TvNavEngine engine, {
    void Function()? onPlay,
    void Function()? onWatched,
  }) =>
      TvNavHarness.pump(
        tester,
        // Comme chaque page sur un téléviseur : dessinée à 1280 de large, puis
        // agrandie à l'écran de 1920 du banc.
        TvUiScale(
          child: Scaffold(
            body: Center(
              child: ContinueWatchingCard(
                item: item,
                autofocus: true,
                onTap: (_) => onPlay?.call(),
                onTitleTap: (_) {},
                onMarkAsWatched: (_) async => onWatched?.call(),
                onRemoveFromRow: (_) async {},
              ),
            ),
          ),
        ),
        engine: engine,
        around: (app) => Provider<ApiClient>.value(
          value: ApiClient(),
          child: app,
        ),
      );

  Future<void> openMenu(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await TvNavHarness.settle(tester);
  }

  bool cardHasFocus() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ContinueWatchingCard>() !=
      null;

  TvNavHarness.forEachEngine((engine) {
    testWidgets("l'affiche retournée montre le titre et les actions",
        (tester) async {
      await pumpCard(tester, engine);
      await openMenu(tester);

      // Le titre apparaît deux fois : sous l'affiche, et au dos.
      expect(find.text('Le film'), findsNWidgets(2));
      expect(find.text('Reprendre'), findsOneWidget);
      expect(find.text("Aller à l'affiche"), findsOneWidget);
      expect(find.text('Marquer comme vu'), findsOneWidget);
      expect(find.text('Supprimer de Reprendre'), findsOneWidget);
      expect(cardHasFocus(), isFalse,
          reason: 'la télécommande doit être dans le menu, pas sous lui');
    });

    testWidgets("le dos recouvre l'affiche, même mise à l'échelle",
        (tester) async {
      await pumpCard(tester, engine);
      // Le zoom du focus fini : c'est l'affiche agrandie qui se retourne.
      await tester.pump(const Duration(seconds: 1));
      final poster = tester.getRect(find.descendant(
        of: find.byType(ContinueWatchingCard),
        matching: find.byType(MediaPoster),
      ));
      await openMenu(tester);

      // Mesuré en coordonnées d'écran, le dos tombait plus petit que
      // l'affiche et décalé en haut à gauche (vu sur Apple TV).
      final back =
          tester.getRect(find.byWidgetPredicate((w) => w is PosterFlipBack));
      expect(back.width, closeTo(poster.width * 1.18, 2));
      expect(back.height, closeTo(poster.height * 1.18, 2));
      expect((back.center - poster.center).distance, lessThan(2));
    });

    testWidgets('les flèches parcourent le dos et OK lance l’action',
        (tester) async {
      var watched = 0;
      var plays = 0;
      final nav = await pumpCard(
        tester,
        engine,
        onWatched: () => watched++,
        onPlay: () => plays++,
      );
      await openMenu(tester);

      // Reprendre → Aller à l'affiche → Marquer comme vu.
      await nav.press(down);
      await nav.press(down);
      await nav.select();
      await tester.pump(const Duration(milliseconds: 500));
      await TvNavHarness.settle(tester);

      expect(watched, 1);
      expect(plays, 0);
      expect(find.text('Marquer comme vu'), findsNothing);
    });

    Future<void> holdOk(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 500));
      await TvNavHarness.settle(tester);
    }

    testWidgets('OK tenu rouvre le menu après Retour, sur la même affiche',
        (tester) async {
      final nav = await pumpCard(tester, engine);
      await tester.pump(const Duration(seconds: 1));

      await holdOk(tester);
      expect(find.text('Supprimer de Reprendre'), findsOneWidget);

      // Menu de la Siri Remote : le moteur l'envoie en « popRoute ».
      await nav.popRoute();
      await tester.pump(const Duration(milliseconds: 500));
      await TvNavHarness.settle(tester);
      expect(find.text('Supprimer de Reprendre'), findsNothing);

      await holdOk(tester);
      expect(find.text('Supprimer de Reprendre'), findsOneWidget,
          reason: 'sans changer d’affiche, le second appui long doit '
              'retourner la carte comme le premier');
    });

    testWidgets('Retour retourne l’affiche et rend le focus à la carte',
        (tester) async {
      final nav = await pumpCard(tester, engine);
      await openMenu(tester);

      await nav.back();
      await tester.pump(const Duration(milliseconds: 500));
      await TvNavHarness.settle(tester);

      expect(find.text('Supprimer de Reprendre'), findsNothing);
      expect(cardHasFocus(), isTrue);
    });
  });
}
