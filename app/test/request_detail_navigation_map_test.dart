import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/my_request.dart';
import 'package:onyx/models/request_progress.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/requests/request_detail_screen.dart';
import 'package:onyx/screens/requests/widgets/request_season_panel.dart';
import 'package:onyx/services/api_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onyx/tv/nav/tv_nav_engine.dart';

import 'support/tv_nav_harness.dart';

/// La carte de navigation de la fiche d'une demande, à la télécommande : le
/// vrai `RequestDetailScreen`, sur les deux systèmes de navigation tant que
/// le drapeau `ONYX_TV_NAV` existe.
///
/// La fiche attend le réseau avant d'avoir ses actions : le focus tombait sur
/// le bouton retour, d'où Bas sautait « Demander » ; et dans une saison
/// ouverte, Bas sautait sa pastille « Demander » et tous ses épisodes pour le
/// bas de la fiche (vu sur Apple TV).

class _Api extends ApiClient {
  _Api(this.details);
  final RequestMediaDetails details;

  @override
  Future<RequestMediaDetails> getRequestMediaDetails(
          int id, RequestMediaType type) async =>
      details;

  @override
  Future<RequestAccess> getRequestAccess() async => RequestAccess.basic;

  @override
  Future<RequestProgress?> getRequestProgress(
          int tmdbId, RequestMediaType type) async =>
      null;

  @override
  Future<List<RequestEpisode>> getRequestSeasonEpisodes(
          int tmdbId, int seasonNumber) async =>
      [
        for (var n = 1; n <= 6; n++)
          RequestEpisode(
            id: seasonNumber * 100 + n,
            number: n,
            name: 'Épisode $n',
            overview: 'Résumé',
            stillPath: null,
            airDate: null,
            runtime: 40,
            rating: 0,
          ),
      ];
}

RequestMediaItem _item(int id, String title) => RequestMediaItem(
      id: id,
      mediaType: RequestMediaType.tv,
      title: title,
      overview: '',
      posterPath: null,
      backdropPath: null,
      releaseDate: null,
      rating: 0,
      status: RequestMediaStatus.unknown,
    );

RequestMediaDetails _show({
  RequestMediaStatus status = RequestMediaStatus.unknown,
}) =>
    RequestMediaDetails(
      id: 1,
      mediaType: RequestMediaType.tv,
      title: 'Série',
      overview: 'Synopsis',
      posterPath: null,
      backdropPath: null,
      releaseDate: '2021-01-01',
      rating: 7,
      status: status,
      runtime: null,
      genres: const ['Drame'],
      trailerKey: 'abc',
      seasons: [
        for (var n = 1; n <= 3; n++)
          RequestSeason(
            number: n,
            name: 'Saison $n',
            episodeCount: 6,
            posterPath: null,
            status: status,
          ),
      ],
      recommendations: [for (var i = 0; i < 5; i++) _item(10 + i, 'Reco $i')],
    );

/// Ce que la télécommande désigne : « Demander » (l'en-tête), « Demander la
/// saison » (la pastille du panneau), « Saison 2 » pour une bulle, « E3 » pour
/// un épisode.
String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (node == null || context == null) return null;
  final bubble =
      context.findAncestorWidgetOfExactType<Semantics>()?.properties.label;
  if (bubble != null && bubble.startsWith('Saison')) {
    return bubble.split(',').first;
  }
  final label = focusedLabelOf(node);
  if (label == 'Demander' &&
      context.findAncestorWidgetOfExactType<RequestSeasonPanel>() != null) {
    return 'Demander la saison';
  }
  return label;
}

const _up = TraversalDirection.up;
const _down = TraversalDirection.down;
const _left = TraversalDirection.left;
const _right = TraversalDirection.right;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  TvNavHarness.forEachEngine((engine) {
    Future<TvNavHarness> pump(
      WidgetTester tester,
      RequestMediaDetails details,
    ) async {
      final api = _Api(details);
      final nav = await TvNavHarness.pump(
        tester,
        RequestDetailScreen(item: _item(1, 'Série')),
        around: (app) => MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider(create: (_) => MediaRequestsProvider(api)),
            ChangeNotifierProvider(create: (_) => WatchListsProvider(api)),
          ],
          child: app,
        ),
        engine: engine,
      );
      await tester.pumpAndSettle();
      return nav;
    }

    Future<void> press(
      WidgetTester tester,
      TvNavHarness nav,
      TraversalDirection direction,
    ) async {
      await nav.press(direction);
      await tester.pumpAndSettle();
    }

    testWidgets('à l’ouverture, le focus est sur « Demander »', (tester) async {
      await pump(tester, _show());
      expect(_focused(), 'Demander');
    });

    testWidgets(
        'une demande en cours n’a pas d’action : le focus s’ouvre sur la '
        'bande-annonce, pas sur le bouton retour', (tester) async {
      await pump(tester, _show(status: RequestMediaStatus.processing));
      expect(_focused(), 'Bande-annonce');
    });

    testWidgets('les actions se parcourent de gauche à droite', (tester) async {
      final nav = await pump(tester, _show());
      await press(tester, nav, _right);
      expect(_focused(), 'Bande-annonce');
      await press(tester, nav, _left);
      expect(_focused(), 'Demander');
    });

    testWidgets(
        'Bas depuis « Demander » entre dans les saisons, Haut y revient',
        (tester) async {
      final nav = await pump(tester, _show());
      await press(tester, nav, _down);
      expect(_focused(), startsWith('Saison'));
      await press(tester, nav, _up);
      expect(_focused(), 'Demander');
    });

    testWidgets(
        'une saison ouverte se parcourt : ses épisodes sont des pas de la '
        'télécommande, et Haut depuis le premier mène à sa pastille '
        '« Demander »', (tester) async {
      final nav = await pump(tester, _show());
      await press(tester, nav, _down);
      await nav.select();
      await tester.pumpAndSettle();
      expect(_focused(), startsWith('Saison'), reason: 'OK ouvre le panneau');

      // L'ancien système passe par la pastille ; dpad, qui ne connaît pas les
      // sections, va droit au premier épisode sous la bulle.
      await press(tester, nav, _down);
      if (engine == TvNavEngine.legacy) {
        expect(_focused(), 'Demander la saison');
        await press(tester, nav, _down);
      }
      expect(_focused(), 'E1');
      await press(tester, nav, _down);
      expect(_focused(), 'E2');
      await press(tester, nav, _up);
      expect(_focused(), 'E1');
      await press(tester, nav, _up);
      expect(_focused(), 'Demander la saison');
    });
  });
}
