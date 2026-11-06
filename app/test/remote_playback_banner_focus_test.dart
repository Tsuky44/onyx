import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/remote_playback.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_focus.dart';
import 'package:onyx/widgets/global/remote_playback_banner.dart';
import 'package:provider/provider.dart';

import 'support/tv_nav_harness.dart';

/// Sur télévision, un bandeau posé par-dessus l'accueil n'entre dans aucune
/// rangée de la télécommande : « Reprendre » restait hors d'atteinte. Il est
/// donc dans la page, atteignable en bas depuis l'affiche, et la touche
/// lecture/pause de la télécommande le déclenche aussi.

class _Api extends ApiClient {
  /// Après la première lecture du sondage, la suivante ne répond jamais : le
  /// test s'arrête à « Reprendre vient d'être demandé », sans ouvrir le lecteur.
  bool holdNext = false;

  @override
  Future<List<RemotePlayback>> getMyRemotePlaybacks() async {
    if (holdNext) return Completer<List<RemotePlayback>>().future;
    return _playbacks;
  }

  List<RemotePlayback> get _playbacks => [
        RemotePlayback.tryParse({
          'session_id': 's1',
          'device_name': 'Salon',
          'media_id': 7,
          'title': 'Film',
          'media': {'id': 7, 'type': 'movie', 'title': 'Film'},
        })!,
      ];
}

class _Auth extends AuthProvider {
  _Auth(super.api);
}

Widget _app(_Api api, FocusNode poster, FocusNode card) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(api)),
      ChangeNotifierProvider(create: (_) => HomeProvider(api)),
    ],
    child: Scaffold(
      // Le carrousel au-dessus et une rangée en dessous, tous deux calés à
      // gauche : c'est ce qui laissait un bandeau étroit hors d'atteinte.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            focusNode: poster,
            autofocus: true,
            onPressed: () {},
            child: const Text('Lecture'),
          ),
          const RemotePlaybackBanner(inline: true),
          ElevatedButton(
            focusNode: card,
            onPressed: () {},
            child: const Text('Affiche'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  TvNavHarness.forEachEngine((engine) {
    testWidgets('le bandeau se rejoint depuis le haut comme depuis le bas', (
      tester,
    ) async {
      final poster = FocusNode();
      final card = FocusNode();
      addTearDown(poster.dispose);
      addTearDown(card.dispose);
      final nav = await TvNavHarness.pump(tester, _app(_Api(), poster, card),
          engine: engine);
      await tester.pumpAndSettle();
      expect(find.byType(TvFocusable), findsOneWidget);
      expect(poster.hasFocus, isTrue);

      bool onBanner() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<TvFocusable>() !=
          null;

      await nav.press(TraversalDirection.down);
      expect(onBanner(), isTrue,
          reason: 'bas depuis « Lecture » mène au bandeau');

      await nav.press(TraversalDirection.down);
      expect(card.hasFocus, isTrue);

      await nav.press(TraversalDirection.up);
      expect(onBanner(), isTrue,
          reason: 'haut depuis une affiche à gauche mène au bandeau, pas au '
              'carrousel');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lecture/pause de la télécommande reprend la lecture', (
      tester,
    ) async {
      final poster = FocusNode();
      final card = FocusNode();
      addTearDown(poster.dispose);
      addTearDown(card.dispose);
      final api = _Api();
      await TvNavHarness.pump(tester, _app(api, poster, card), engine: engine);
      await tester.pumpAndSettle();
      TvFocusable banner() => tester.widget(find.byType(TvFocusable));
      expect(banner().onSelect, isNotNull);

      api.holdNext = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();

      expect(banner().onSelect, isNull,
          reason: 'la reprise est lancée : le bandeau ne se valide plus');
      await tester.pumpWidget(const SizedBox());
    });
  });
}
