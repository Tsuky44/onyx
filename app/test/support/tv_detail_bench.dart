import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/watch_list.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/library/movie_detail_screen.dart';
import 'package:onyx/screens/library/show_detail_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/services/media_details_cache.dart';
import 'package:onyx/services/media_tracks_cache.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/nav/tv_sections.dart';
import 'package:onyx/tv/tv_ui_scale.dart';
import 'package:onyx/widgets/global/episode_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tv_nav_harness.dart';

/// Le banc des fiches à la télécommande (ADR-0128) : les vrais écrans de la
/// bibliothèque (`MovieDetailScreen`, `ShowDetailScreen`) sur une API de
/// doublure, montés comme sur un téléviseur.
///
/// À l'échelle d'un téléviseur ([TvUiScale]) : une Apple TV annonce
/// 1920 × 1080 points et l'app s'y met en page sur 1280 de large. Les
/// rectangles du focus sont donc ceux de l'écran, une fois et demie plus
/// grands que la mise en page, comme sur l'appareil.
abstract final class TvDetailBench {
  /// L'identifiant de la série du banc ; tout autre est un film.
  static const int showId = 2;

  static const int episodeCount = 8;

  /// Le rapport entre l'écran du banc et la mise en page ([TvUiScale]).
  static const double scale = 1920 / TvUiScale.designWidth;

  static Media get movie => Media(
        id: 1,
        type: MediaType.movie,
        title: 'Film',
        duration: 7200,
        createdAt: DateTime(2026),
      );

  static Media get show => Media(
        id: showId,
        type: MediaType.show,
        title: 'Série',
        duration: 0,
        createdAt: DateTime(2026),
      );

  /// À appeler dans le `setUp` : préférences vides, coffre-fort muet et
  /// caches de fiches vidés d'un test à l'autre.
  static void setUp() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    MediaDetailsCache.clear();
    MediaTracksCache.clear();
  }

  static Future<TvNavHarness> pumpMovie(
    WidgetTester tester, {
    required TvNavEngine engine,
    TvDetailApi? api,
    bool isTv = true,
  }) =>
      pump(
        tester,
        MovieDetailScreen(movie: movie),
        engine: engine,
        api: api,
        isTv: isTv,
      );

  static Future<TvNavHarness> pumpShow(
    WidgetTester tester, {
    required TvNavEngine engine,
    TvDetailApi? api,
  }) =>
      pump(tester, ShowDetailScreen(show: show), engine: engine, api: api);

  /// Monte [screen] avec les fournisseurs que les fiches lisent, et laisse
  /// ses chargements se poser.
  static Future<TvNavHarness> pump(
    WidgetTester tester,
    Widget screen, {
    required TvNavEngine engine,
    TvDetailApi? api,
    bool isTv = true,
  }) async {
    final client = api ?? TvDetailApi();
    final auth = _Auth(client);
    addTearDown(auth.dispose);
    final lists = WatchListsProvider(client)..debugMarkSupported();
    addTearDown(lists.dispose);
    final nav = await TvNavHarness.pump(
      tester,
      isTv ? TvUiScale(child: screen) : screen,
      engine: engine,
      isTv: isTv,
      around: (app) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<ApiClient>.value(value: client),
          ChangeNotifierProvider<WatchListsProvider>.value(value: lists),
          ChangeNotifierProvider<DownloadManager>.value(
              value: DownloadManager.instance),
          ChangeNotifierProvider(create: (_) => LibraryProvider(client)),
          ChangeNotifierProvider(create: (_) => HomeProvider(client)),
        ],
        child: app,
      ),
    );
    await tester.pumpAndSettle();
    return nav;
  }

  /// Une flèche, puis le temps que la page se pose.
  static Future<void> press(
    WidgetTester tester,
    TvNavHarness nav,
    TraversalDirection direction,
  ) async {
    await nav.press(direction);
    await tester.pumpAndSettle();
  }

  /// Ce que la télécommande désigne : « Reprendre », « Retour », « Saison 2 »,
  /// « Épisode 3 », « A0 » pour la première carte de la distribution,
  /// « Similaire 1 ».
  static String? focused() {
    final node = FocusManager.instance.primaryFocus;
    return node == null ? null : labelOf(node);
  }

  static String? labelOf(FocusNode node) {
    final context = node.context;
    if (context == null) return node.debugLabel;
    final tile = context.findAncestorWidgetOfExactType<EpisodeTile>();
    if (tile != null) return tile.episode.media.title;
    String? named;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Semantics) {
        final label = widget.properties.label;
        if (label != null && label.startsWith('Saison')) named = label;
      } else if (widget is Tooltip) {
        named = widget.message;
      } else if (widget is IconButton) {
        named = widget.tooltip;
      }
      // Jamais au-delà de la section : le titre d'une autre zone n'est pas
      // le nom de cette cible.
      return named == null && widget is! TvSection;
    });
    return named ?? focusedLabelOf(node);
  }

  /// La section de la cible focalisée (`hero`, `seasons`, `episodes`, `info`…).
  static String? focusedSection() {
    final node = FocusManager.instance.primaryFocus;
    return node == null ? null : TvSections.sectionOf(node)?.widget.id;
  }

  /// La position de défilement de la fiche, en pixels de mise en page.
  static double offset(WidgetTester tester) => position(tester).pixels;

  static ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first)
      .position;

  /// Le rectangle de la cible focalisée, en pixels de mise en page, dans
  /// l'écran : `top` vaut 0 en haut de l'écran.
  static Rect focusedRect() {
    final rect = FocusManager.instance.primaryFocus!.rect;
    return Rect.fromLTRB(
      rect.left / scale,
      rect.top / scale,
      rect.right / scale,
      rect.bottom / scale,
    );
  }

  /// La hauteur de l'écran, en pixels de mise en page.
  static double screenHeight(WidgetTester tester) =>
      position(tester).viewportDimension;

  /// Le haut de la section [id] dans l'écran, en pixels de mise en page.
  /// Pour une section en boîte seulement (pas la liste des épisodes).
  static double sectionTop(WidgetTester tester, String id) =>
      tester
          .getTopLeft(find.byWidgetPredicate(
            (widget) => widget is TvSection && widget.id == id,
            // Une section défilée hors de l'écran garde sa place.
            skipOffstage: false,
          ))
          .dy /
      scale;

  /// Pose le focus sur la cible nommée [label], comme s'il y était arrivé.
  static Future<void> focusOn(WidgetTester tester, String label) async {
    final node =
        FocusManager.instance.rootScope.traversalDescendants.firstWhere(
      (node) =>
          node is! FocusScopeNode &&
          node.context != null &&
          labelOf(node) == label,
      orElse: () => throw StateError('rien ne se nomme « $label »'),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(focused(), label, reason: 'point de départ');
  }
}

/// L'API des fiches du banc : un film et une série complets (distribution,
/// saga, titres similaires, trois saisons de huit épisodes).
class TvDetailApi extends ApiClient {
  TvDetailApi({this.overview = 'Un résumé.', this.resumeDelay});

  /// Court par défaut : il tient en entier et n'est pas une cible. Long, il
  /// est coupé et s'ouvre en dialogue : une ligne de plus dans l'en-tête.
  final String overview;

  /// Ce que le serveur met à dire quel épisode reprendre : la pastille de
  /// lecture d'une série n'existe pas avant.
  final Duration? resumeDelay;

  @override
  Future<MediaDetails> getMediaDetails(int mediaId) async {
    final isShow = mediaId == TvDetailBench.showId;
    return MediaDetails.fromJson({
      'id': mediaId,
      'type': isShow ? 'show' : 'movie',
      'title': isShow ? 'Série' : 'Film',
      'overview': overview,
      'vote_average': 8.3,
      'runtime': 120,
      'release_date': '2021-01-01',
      'director': 'Une réalisatrice',
      'genres': ['Drame'],
      'number_of_seasons': 3,
      'cast': [
        for (var i = 0; i < 10; i++)
          {'tmdb_id': 100 + i, 'name': 'Acteur $i', 'character': 'Rôle $i'},
      ],
      if (!isShow) 'collection': {'id': 9, 'name': 'La saga'},
      'similar_titles': [
        for (var i = 0; i < 8; i++)
          {'tmdb_id': 200 + i, 'local_id': 50 + i, 'title': 'Similaire $i'},
      ],
    });
  }

  @override
  Future<MediaTracks> getMediaTracks(int mediaId) async =>
      MediaTracks.fromJson({});

  @override
  Future<Map<String, dynamic>> getProgress(int mediaId) async =>
      {'current_position_seconds': 2700, 'is_finished': false};

  /// Pas de suivi de la progression des autres appareils : l'échec est
  /// immédiat, sans requête, et la fiche garde ce qu'elle montre.
  @override
  Future<String> getProgressRevision({
    String? since,
    CancelToken? cancelToken,
  }) async =>
      throw StateError('le banc n’a pas de serveur');

  @override
  Future<WatchListsOverview> getWatchLists({ListableTitle? containing}) async =>
      WatchListsOverview.empty;

  @override
  Future<List<Media>> getShowSeasons(int showId) async => [
        for (var number = 1; number <= 3; number++)
          Media.fromJson({
            'id': 10 + number,
            'type': 'season',
            'title': 'Saison $number',
            'season_number': number,
            'duration': 0,
            'is_available': true,
            'created_at': '2026-01-01T00:00:00Z',
          }),
      ];

  @override
  Future<ShowResumeResponse> getShowResumeEpisode(int showId) async {
    final delay = resumeDelay;
    if (delay != null) await Future<void>.delayed(delay);
    return ShowResumeResponse(hasEpisode: false);
  }

  @override
  Future<List<HomeMediaItem>> getSeasonEpisodes(
    int seasonId, {
    bool includeMissing = false,
  }) async =>
      [
        for (var number = 1; number <= TvDetailBench.episodeCount; number++)
          HomeMediaItem(
            media: Media(
              id: seasonId * 100 + number,
              type: MediaType.episode,
              title: 'Épisode $number',
              duration: 2400,
              episodeNumber: number,
              seasonNumber: seasonId - 10,
              createdAt: DateTime(2026),
            ),
            currentPositionSeconds: 0,
            isFinished: false,
            duration: 2400,
          ),
      ];
}

class _Auth extends AuthProvider {
  _Auth(super.api);

  @override
  User? get currentUser =>
      User(id: 1, username: 'mathis', permissions: Permissions.all);

  @override
  Permissions get permissions => Permissions.all;
}
