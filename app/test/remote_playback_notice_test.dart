import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/remote_playback.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/widgets/global/remote_playback_banner.dart';
import 'package:onyx/widgets/global/remote_playback_notice.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// « En lecture sur un autre appareil » (ADR-0127) : une notification en
/// haut à droite, et sa forme ramassée en bas de l'écran d'un téléphone.
///
/// Demande de l'utilisateur sur Apple TV : « pour lancer il faut qu'on reste
/// appuyé sur play », avec « un petit texte pour que ce soit facilement
/// compréhensible ». Maquette validée le 2026-11-13, puis : « mets-le sur
/// tout sauf téléphone ».
///
/// - Apple TV : elle ne prend pas le focus, on maintient lecture/pause ;
/// - un autre téléviseur : le même geste, et OK sur la notification pour les
///   télécommandes qui n'ont pas cette touche ;
/// - une souris : un clic reprend, la croix l'écarte ;
/// - un téléphone : la même, ramassée en bas de l'écran (maquette « 1 bis »).

class _Api extends ApiClient {
  /// Les lectures demandées au serveur : une au sondage, une de plus quand la
  /// reprise part (elle redemande la position).
  int fetches = 0;

  /// Posé avant la reprise : sa relecture ne répond jamais, et le test
  /// s'arrête à « la reprise vient d'être demandée », sans ouvrir le lecteur.
  bool holdNext = false;

  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Future<List<RemotePlayback>> getMyRemotePlaybacks() async {
    fetches++;
    if (holdNext) return Completer<List<RemotePlayback>>().future;
    return [
      RemotePlayback.tryParse({
        'session_id': 's1',
        'device_name': 'iPhone',
        'media_id': 7,
        'title': 'Le Gardien',
        'show_title': 'Phare Nord',
        'position_seconds': 1500,
        'duration_seconds': 2580,
        'media': {'id': 7, 'type': 'episode', 'title': 'Le Gardien'},
      })!,
    ];
  }
}

class _Auth extends AuthProvider {
  _Auth(super.api);
}

Widget _providers(_Api api, Widget child) => MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(api)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ],
      child: child,
    );

/// L'accueil d'un téléviseur qui n'est pas une Apple TV : le compte en haut à
/// droite de l'en-tête, la notification dessous, focalisable.
Widget _otherTv(_Api api, FocusNode account) => _providers(
      api,
      Scaffold(
        body: Stack(
          children: [
            Positioned(
              right: 48,
              top: 22,
              child: TvFocusable(
                focusNode: account,
                autofocus: true,
                onSelect: () {},
                child: const TvTestTile('Compte', width: 120, height: 40),
              ),
            ),
            const Positioned(
              top: 84,
              right: 48,
              child: RemotePlaybackBanner.notice(hold: true, selectable: true),
            ),
          ],
        ),
      ),
    );

/// L'accueil d'une Apple TV, réduit à ce qui compte : un bouton qui a le
/// focus, et la notification posée par-dessus, en haut à droite.
Widget _home(_Api api, FocusNode button) => MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(api)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api)),
      ],
      child: Scaffold(
        body: Stack(
          children: [
            Positioned(
              left: 48,
              top: 300,
              child: TvFocusable(
                focusNode: button,
                autofocus: true,
                onSelect: () {},
                child: const TvTestTile('Lecture'),
              ),
            ),
            const Positioned(
              top: 84,
              right: 48,
              child: RemotePlaybackBanner.notice(hold: true),
            ),
          ],
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('à la souris', () {
    Future<_Api> open(WidgetTester tester) async {
      final api = _Api();
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: _providers(
          api,
          const Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 84,
                  right: 48,
                  child: RemotePlaybackBanner.notice(),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(RemotePlaybackNotice), findsOneWidget);
      return api;
    }

    testWidgets('la dernière ligne dit « Reprendre ici », et un clic reprend',
        (tester) async {
      final api = await open(tester);

      expect(find.text('Reprendre ici'), findsOneWidget);
      expect(find.text('Maintenir pour reprendre ici'), findsNothing);
      // Rien à focaliser : ce n'est pas un téléviseur.
      expect(find.byType(TvFocusable), findsNothing);

      final polled = api.fetches;
      api.holdNext = true;
      await tester.tap(find.text('Phare Nord'));
      await tester.pump();
      expect(api.fetches, polled + 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("la croix l'écarte, sans reprendre", (tester) async {
      final api = await open(tester);
      final polled = api.fetches;

      await tester.tap(find.byTooltip('Ignorer'));
      await tester.pumpAndSettle();

      expect(find.byType(RemotePlaybackNotice), findsNothing);
      expect(api.fetches, polled);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('sur un téléphone', () {
    Future<_Api> open(WidgetTester tester) async {
      final api = _Api();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: _providers(
          api,
          const Scaffold(
            body: Stack(
              children: [
                // Là où l'accueil la pose : en bas, au-dessus des onglets.
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 14,
                  child: Center(child: RemotePlaybackBanner()),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(RemotePlaybackNotice), findsOneWidget);
      return api;
    }

    testWidgets(
        'une seule hauteur, à la largeur de l\'écran, sans ligne de texte '
        'dessous', (tester) async {
      await open(tester);

      expect(find.text('EN LECTURE SUR IPHONE'), findsOneWidget);
      expect(find.text('Phare Nord'), findsOneWidget);
      // Maquette « 1 bis » : le bouton lecture est à droite du titre, et la
      // ligne « … pour reprendre ici » a disparu.
      expect(find.textContaining('reprendre ici'), findsNothing);
      expect(find.textContaining('Reprendre ici'), findsNothing);
      final rect = tester.getRect(find.byType(RemotePlaybackNotice));
      expect(rect.left, 12);
      expect(rect.right, 390 - 12);
      expect(rect.bottom, 844 - 14);
      expect(rect.height, lessThan(104));
      // La croix est dans le coin, au-dessus du bouton lecture.
      final close = tester.getRect(find.byTooltip('Ignorer'));
      expect(close.top, greaterThanOrEqualTo(rect.top));
      expect(close.right, lessThanOrEqualTo(rect.right));
      expect(close.center.dx,
          greaterThan(tester.getRect(find.text('Phare Nord')).right));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('toucher la carte reprend', (tester) async {
      final api = await open(tester);
      final polled = api.fetches;
      api.holdNext = true;

      await tester.tap(find.text('Phare Nord'));
      await tester.pump();

      expect(api.fetches, polled + 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("la croix l'écarte, sans reprendre", (tester) async {
      final api = await open(tester);
      final polled = api.fetches;

      await tester.tap(find.byTooltip('Ignorer'));
      await tester.pumpAndSettle();

      expect(find.byType(RemotePlaybackNotice), findsNothing);
      expect(api.fetches, polled);
      await tester.pumpWidget(const SizedBox());
    });
  });

  TvNavHarness.forEachEngine((engine) {
    late _Api api;
    late FocusNode button;

    Future<TvNavHarness> open(WidgetTester tester) async {
      api = _Api();
      button = FocusNode();
      addTearDown(button.dispose);
      final nav =
          await TvNavHarness.pump(tester, _home(api, button), engine: engine);
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      expect(find.byType(RemotePlaybackNotice), findsOneWidget);
      return nav;
    }

    Future<void> down(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
    }

    Future<void> up(WidgetTester tester) async {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
    }

    /// Le temps passe image par image, comme à l'écran : une animation ne
    /// progresse qu'aux images qu'on lui donne.
    Future<void> wait(WidgetTester tester, Duration duration) async {
      const frame = Duration(milliseconds: 20);
      for (var spent = Duration.zero; spent < duration; spent += frame) {
        await tester.pump(frame);
      }
    }

    testWidgets(
        'la notification dit ce qui se lit, où, et quoi faire, en haut à '
        'droite', (tester) async {
      await open(tester);

      expect(find.text('EN LECTURE SUR IPHONE'), findsOneWidget);
      expect(find.text('Phare Nord'), findsOneWidget);
      expect(find.textContaining('Le Gardien'), findsOneWidget);
      expect(find.text('Maintenir pour reprendre ici'), findsOneWidget);
      final rect = tester.getRect(find.byType(RemotePlaybackNotice));
      expect(rect.width, RemotePlaybackNotice.width);
      expect(rect.right, 1280 - 48);
      expect(rect.top, 84);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('elle ne prend pas le focus : aucune flèche n\'y mène',
        (tester) async {
      final nav = await open(tester);

      for (final direction in [
        TraversalDirection.up,
        TraversalDirection.right,
        TraversalDirection.up,
      ]) {
        await nav.press(direction);
      }
      expect(button.hasFocus, isTrue);
      expect(
        find.descendant(
          of: find.byType(RemotePlaybackNotice),
          matching: find.byType(TvFocusable),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un appui court sur lecture/pause ne reprend rien',
        (tester) async {
      await open(tester);
      final polled = api.fetches;

      await down(tester);
      await wait(tester, const Duration(milliseconds: 250));
      // Le texte dit de ne pas lâcher.
      expect(find.text('Continuez d\'appuyer…'), findsOneWidget);
      await up(tester);
      await wait(tester, const Duration(seconds: 2));

      expect(api.fetches, polled, reason: 'aucune reprise demandée');
      expect(find.byType(RemotePlaybackNotice), findsOneWidget);
      expect(find.text('Maintenir pour reprendre ici'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('maintenir lecture/pause reprend la lecture', (tester) async {
      await open(tester);
      final polled = api.fetches;
      api.holdNext = true;

      await down(tester);
      // Pas encore : il reste un instant à tenir.
      await wait(
          tester,
          RemotePlaybackBanner.holdDuration -
              const Duration(milliseconds: 100));
      expect(api.fetches, polled);
      await wait(tester, const Duration(milliseconds: 150));

      expect(api.fetches, polled + 1,
          reason: 'la reprise redemande la position de l\'autre appareil');
      // Relâcher ensuite ne défait rien.
      await up(tester);
      await wait(tester, const Duration(milliseconds: 300));
      expect(api.fetches, polled + 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'un appui coupé par la télécommande (relâché, ré-enfoncé aussitôt) '
        'reste un seul appui', (tester) async {
      await open(tester);
      final polled = api.fetches;
      api.holdNext = true;

      await down(tester);
      await wait(tester, const Duration(milliseconds: 400));
      // Le simulateur Apple TV coupe un appui tenu : 8 ms entre les deux.
      await up(tester);
      await wait(tester, const Duration(milliseconds: 8));
      await down(tester);
      await wait(tester, const Duration(milliseconds: 600));

      expect(api.fetches, polled + 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'sur un autre téléviseur, la notification prend aussi le focus et '
        'OK reprend', (tester) async {
      api = _Api();
      final account = FocusNode();
      addTearDown(account.dispose);
      final nav = await TvNavHarness.pump(tester, _otherTv(api, account),
          engine: engine);
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      expect(account.hasFocus, isTrue);
      // Le geste d'abord : toutes les télécommandes n'ont pas la touche.
      expect(find.text('Maintenir pour reprendre ici'), findsOneWidget);

      await nav.press(TraversalDirection.down);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<RemotePlaybackNotice>(),
        isNotNull,
        reason: 'bas depuis le compte mène à la notification',
      );
      expect(find.text('OK pour reprendre ici'), findsOneWidget);

      final polled = api.fetches;
      api.holdNext = true;
      await nav.select();
      expect(api.fetches, polled + 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('relâcher puis reprendre l\'appui repart de zéro',
        (tester) async {
      await open(tester);
      final polled = api.fetches;
      api.holdNext = true;

      await down(tester);
      await wait(tester, const Duration(milliseconds: 600));
      await up(tester);
      await wait(tester, const Duration(milliseconds: 400));
      // 600 ms + 600 ms dépassent la durée, mais ce sont deux appuis.
      await down(tester);
      await wait(tester, const Duration(milliseconds: 600));
      expect(api.fetches, polled);

      await wait(tester, const Duration(milliseconds: 400));
      expect(api.fetches, polled + 1);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
