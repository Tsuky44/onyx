// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:onyx/models/models.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/hero_series_preview.dart';
import 'package:onyx/services/media_details_cache.dart';
import 'package:onyx/utils/hero_slides.dart';
import 'package:onyx/widgets/global/hero/hero_living_backdrop.dart';
import 'package:onyx/widgets/global/hero/hero_next_episode_card.dart';
import 'package:onyx/widgets/global/hero_banner.dart';
import 'package:onyx/widgets/global/hero_carousel.dart';
import 'package:onyx/widgets/global/media_logo_display.dart';

/// Le bandeau d'accueil d'une série (ADR-0154) : il lance l'épisode qu'il
/// annonce, fait défiler les images des épisodes déjà passés, et ne dévoile
/// rien de la suite.

const _showId = 50;

final _show = Media(
  id: _showId,
  type: MediaType.show,
  title: 'Les Veilleurs',
  duration: 0,
  releaseDate: '2022-03-01',
  createdAt: DateTime(2026),
);

HomeMediaItem _episode(
  int number, {
  int season = 2,
  int position = 0,
  String? still,
  bool newEpisode = false,
}) =>
    HomeMediaItem(
      media: Media(
        id: 1000 + season * 100 + number,
        type: MediaType.episode,
        title: 'Épisode $number',
        duration: 3000,
        seasonNumber: season,
        episodeNumber: number,
        posterUrl:
            still ?? 'https://image.tmdb.org/t/p/w300/s$season-e$number.jpg',
        createdAt: DateTime(2026),
      ),
      currentPositionSeconds: position,
      duration: 3000,
      isFinished: false,
      showId: _showId,
      episodeTitle: 'Titre $number',
      hasNewEpisode: newEpisode,
    );

class _SeriesApi extends ApiClient {
  _SeriesApi({this.next, this.season = const []});

  final HomeMediaItem? next;
  final List<HomeMediaItem> season;
  int resumeCalls = 0;
  int seasonCalls = 0;

  @override
  Future<ShowResumeResponse> getShowResumeEpisode(int showId) async {
    resumeCalls++;
    return ShowResumeResponse(hasEpisode: next != null, episode: next);
  }

  @override
  Future<List<HomeMediaItem>> getShowSeasonEpisodes(
      int showId, int seasonNumber) async {
    seasonCalls++;
    return season;
  }

  @override
  Future<MediaDetails> getMediaDetails(int mediaId) async => MediaDetails(
        id: mediaId,
        type: MediaType.show,
        title: 'Les Veilleurs',
        backdropUrl: 'https://image.tmdb.org/t/p/w1280/fond.jpg',
        numberOfSeasons: 3,
        genres: const ['Drame', 'Thriller'],
        voteAverage: 8.1,
      );
}

/// Une série commencée : S2 E4 à mi-parcours, et toute la saison 2 sur le
/// serveur, images comprises.
_SeriesApi _inProgress() => _SeriesApi(
      next: _episode(4, position: 1800),
      season: [for (var n = 1; n <= 8; n++) _episode(n)],
    );

Future<void> _pumpBanner(
  WidgetTester tester,
  ApiClient api, {
  Size size = const Size(1400, 900),
  bool reducedMotion = false,
  ValueChanged<int>? onFrameCount,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(Provider<ApiClient>.value(
    value: api,
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: Scaffold(
            body: HeroBanner(
              media: _show,
              onPlay: () {},
              onInfo: () {},
              onFrameCount: onFrameCount,
            ),
          ),
        ),
      ),
    ),
  ));
  // La fiche, puis l'épisode à reprendre, puis la liste de sa saison.
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  setUp(() {
    HeroSeriesPreviewCache.reset();
    MediaDetailsCache.clear();
  });

  group('les images du fond', () {
    test('aucun épisode d’après celui à lancer ne passe au fond', () {
      final season = [for (var n = 1; n <= 8; n++) _episode(n)];
      final stills = pickHeroStills(season, _episode(4));
      final numbers =
          stills.map((e) => e.media.effectiveEpisodeNumber).toList();
      expect(numbers.every((n) => n! <= 4), isTrue,
          reason: 'le fond défile sous les yeux de qui n’a pas vu la suite');
      expect(numbers, hasLength(3));
      expect(numbers.last, 4, reason: 'l’épisode à lancer vient en dernier');
    });

    test('elles viennent de la saison de l’épisode à lancer, avec une image',
        () {
      final episodes = [
        _episode(1, season: 1),
        _episode(2, season: 1),
        _episode(1),
        _episode(2, still: ''),
        _episode(3),
      ];
      final stills = pickHeroStills(episodes, _episode(3));
      expect(
        stills.map((e) =>
            (e.media.effectiveSeasonNumber, e.media.effectiveEpisodeNumber)),
        [(2, 1), (2, 3)],
      );
    });

    test('un premier épisode n’a que sa propre image', () {
      final stills = pickHeroStills(
          [for (var n = 1; n <= 6; n++) _episode(n, season: 1)],
          _episode(1, season: 1));
      expect(stills.single.media.effectiveEpisodeNumber, 1);
    });
  });

  group('la mémoire des aperçus', () {
    test('une série de la découverte demande où la reprendre, une reprise non',
        () async {
      final api = _inProgress();
      final preview = await HeroSeriesPreviewCache.load(api, _showId);
      expect(preview.next?.media.effectiveEpisodeNumber, 4);
      expect(api.resumeCalls, 1);

      await HeroSeriesPreviewCache.load(api, _showId, known: _episode(6));
      expect(api.resumeCalls, 1,
          reason: 'l’épisode de « Reprendre » est déjà celui à lancer');
      expect(api.seasonCalls, 2);
    });

    test('deux bandeaux qui la demandent ensemble partagent la requête',
        () async {
      final api = _inProgress();
      await Future.wait([
        HeroSeriesPreviewCache.load(api, _showId),
        HeroSeriesPreviewCache.load(api, _showId),
      ]);
      expect(api.resumeCalls, 1);
    });

    test('au retour du lecteur, l’épisode à suivre est redemandé', () async {
      final api = _inProgress();
      await HeroSeriesPreviewCache.load(api, _showId);
      expect(HeroSeriesPreviewCache.peek(_showId), isNotNull);
      HeroSeriesPreviewCache.clear();
      expect(HeroSeriesPreviewCache.peek(_showId), isNull);
    });
  });

  group('le bandeau d’une série', () {
    testWidgets('son bouton dit l’épisode qu’il lance', (tester) async {
      await _pumpBanner(tester, _inProgress());
      expect(find.text('Reprendre S2 E4'), findsOneWidget);
      expect(find.text('SÉRIE  ·  3 SAISONS'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('la carte « À suivre » est sur grand écran, pas au téléphone',
        (tester) async {
      await _pumpBanner(tester, _inProgress());
      expect(find.byType(HeroNextEpisodeCard), findsOneWidget);
      expect(find.text('S2 E4 · Titre 4'), findsOneWidget);
      await _unmount(tester);

      HeroSeriesPreviewCache.reset();
      await _pumpBanner(tester, _inProgress(), size: const Size(390, 844));
      expect(find.byType(HeroNextEpisodeCard), findsNothing,
          reason: 'sous le texte et les boutons, elle chargeait le téléphone');
      expect(find.text('Reprendre S2 E4'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('le fond fait passer les épisodes déjà vus, et le dit',
        (tester) async {
      final counts = <int>[];
      await _pumpBanner(tester, _inProgress(), onFrameCount: counts.add);
      expect(counts.last, 4, reason: 'l’image de la série et trois épisodes');
      expect(find.byType(HeroBackdropCaption), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('sous « réduire les animations », le fond reste immobile',
        (tester) async {
      final counts = <int>[];
      await _pumpBanner(tester, _inProgress(),
          reducedMotion: true, onFrameCount: counts.add);
      expect(counts.last, 1);
      expect(find.byType(HeroBackdropCaption), findsNothing);
      await _unmount(tester);
    });

    testWidgets('une série jamais commencée propose son premier épisode',
        (tester) async {
      await _pumpBanner(
        tester,
        _SeriesApi(next: _episode(1, season: 1)),
      );
      expect(find.text('Lecture S1 E1'), findsOneWidget);
      expect(find.text('PREMIER ÉPISODE'), findsOneWidget);
      await _unmount(tester);
    });
  });

  testWidgets('une série au fond vivant reste le temps de montrer ses images',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final film = Media(
      id: 7,
      type: MediaType.movie,
      title: 'Un film',
      duration: 6000,
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(Provider<ApiClient>.value(
      value: _inProgress(),
      child: MaterialApp(
        home: Scaffold(
          body: HeroCarousel(
            slides: [
              HeroSlide(media: _show, title: _show.title),
              HeroSlide(media: film, title: film.title),
            ],
            onPlay: (_) {},
            onInfo: (_) {},
          ),
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    PageController controller() =>
        tester.widget<PageView>(find.byType(PageView)).controller!;

    // Sept secondes suffisent à un film ; quatre images en demandent seize.
    await tester.pump(const Duration(seconds: 8));
    expect(controller().page, 0);

    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 1));
    expect(controller().page, 1);
    await _unmount(tester);
  });

  testWidgets('le logo n’ombre pas sa boîte', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaLogoDisplay(
        title: 'Les Veilleurs',
        logoUrl: 'https://image.tmdb.org/t/p/w500/logo.png',
        maxHeight: 128,
        maxWidth: 560,
      ),
    ));
    final shadowed = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(MediaLogoDisplay),
          matching: find.byType(DecoratedBox),
        ))
        .where((box) =>
            box.decoration is BoxDecoration &&
            ((box.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false));
    expect(shadowed, isEmpty,
        reason: 'l’ombre d’une boîte de 560 px dessinait un rectangle sombre '
            'derrière le logo');
  });
}
