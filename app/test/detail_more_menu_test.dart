import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/library/movie_detail_screen.dart';
import 'package:onyx/screens/library/show_hero_actions.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/services/download_preferences.dart';
import 'package:onyx/services/media_details_cache.dart';
import 'package:onyx/services/media_tracks_cache.dart';
import 'package:onyx/services/network_status.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/detail_hero.dart';
import 'package:onyx/widgets/global/onyx_menu.dart';

/// Le menu « Plus » de la fiche (ADR-0132) : hors TV, deux actions nommées
/// en vue et le reste rangé ; sur un téléviseur, la rangée d'avant.
class _Api extends ApiClient {
  @override
  Future<MediaDetails> getMediaDetails(int mediaId) async =>
      MediaDetails.fromJson({'id': mediaId, 'type': 'movie', 'title': 'Film'});

  @override
  Future<MediaTracks> getMediaTracks(int mediaId) async =>
      MediaTracks.fromJson({});

  @override
  Future<Map<String, dynamic>> getProgress(int mediaId) async =>
      {'current_position_seconds': 0, 'is_finished': false};
}

class _Auth extends AuthProvider {
  _Auth(super.api, this._permissions);

  final Permissions _permissions;

  @override
  User? get currentUser =>
      User(id: 1, username: 'mathis', permissions: _permissions);

  @override
  Permissions get permissions => _permissions;
}

const _member = Permissions(requestMedia: true, shareMedia: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    MediaDetailsCache.clear();
    MediaTracksCache.clear();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Permissions permissions = Permissions.all,
    bool tv = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(tester.view.reset);
    final api = _Api();
    final auth = _Auth(api, permissions);
    addTearDown(auth.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(
            create: (_) => WatchListsProvider(api)..debugMarkSupported()),
        ChangeNotifierProvider<DownloadManager>.value(
            value: DownloadManager.instance),
        ChangeNotifierProvider<DownloadPreferences>.value(
            value: DownloadPreferences.instance),
        ChangeNotifierProvider<NetworkStatus>(create: (_) => NetworkStatus()),
      ],
      child: TvScope(isTv: tv, child: MaterialApp(home: home)),
    ));
    await tester.pumpAndSettle();
  }

  Widget movie() => MovieDetailScreen(
        movie: Media(
          id: 1,
          type: MediaType.movie,
          title: 'Film',
          duration: 7200,
          createdAt: DateTime(2026),
        ),
      );

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(HeroPill, 'Plus'));
    await tester.pumpAndSettle();
  }

  group('fiche film hors TV', () {
    testWidgets('« Ma liste » et « Plus » sont des boutons nommés',
        (tester) async {
      await pump(tester, movie());

      expect(find.widgetWithText(HeroPill, 'Ma liste'), findsOneWidget);
      expect(find.widgetWithText(HeroPill, 'Plus'), findsOneWidget);
      // Les ronds sans libellé d'avant ont quitté la rangée.
      expect(find.byTooltip('Marquer vu'), findsNothing);
      expect(find.byTooltip('Corriger la fiche'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Plus » groupe vu, partage puis l’administration',
        (tester) async {
      await pump(tester, movie());
      await openMore(tester);

      expect(find.text('Marquer comme vu'), findsOneWidget);
      expect(find.text('Partager'), findsOneWidget);
      expect(find.text('ADMINISTRATION'), findsOneWidget);
      expect(find.text('Corriger la fiche…'), findsOneWidget);
      expect(find.text('Changer l’affiche…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans manage_library, pas de section Administration',
        (tester) async {
      await pump(tester, movie(), permissions: _member);
      await openMore(tester);

      expect(find.text('Marquer comme vu'), findsOneWidget);
      expect(find.text('ADMINISTRATION'), findsNothing);
      expect(find.text('Corriger la fiche…'), findsNothing);
      expect(find.text('Changer l’affiche…'), findsNothing);
    });
  });

  testWidgets('sur un téléviseur, la fiche film garde sa rangée de ronds',
      (tester) async {
    await pump(tester, movie(), tv: true);

    expect(find.widgetWithText(HeroPill, 'Plus'), findsNothing);
    expect(find.widgetWithText(HeroPill, 'Ma liste'), findsNothing);
    expect(find.byTooltip('Marquer vu'), findsOneWidget);
    expect(find.byTooltip('Corriger la fiche'), findsOneWidget);
  });

  group('fiche série', () {
    HomeMediaItem episode(int id, {bool watched = false}) => HomeMediaItem(
          media: Media(
            id: id,
            type: MediaType.episode,
            title: 'Épisode $id',
            duration: 2400,
            seasonNumber: 2,
            episodeNumber: id,
            isAvailable: true,
            createdAt: DateTime(2026),
          ),
          currentPositionSeconds: 0,
          duration: 2400,
          isFinished: watched,
          showId: 7,
          showTitle: 'Severance',
        );

    Widget actions() => Scaffold(
          body: ShowHeroActions(
            show: Media(
              id: 7,
              type: MediaType.show,
              title: 'Severance',
              duration: 0,
              createdAt: DateTime(2026),
            ),
            playLabel: 'Reprendre S2 E4',
            onPlay: () {},
            progress: null,
            progressLabel: null,
            episodes: [episode(101), episode(102, watched: true)],
            hasPlayableEpisode: true,
            seasonNumber: 2,
            seasonBusy: false,
            onSetSeasonWatched: (_, __) async {},
            onRedetect: () {},
            onPickOnTmdb: () {},
            onChangePoster: () {},
          ),
        );

    testWidgets('les libellés disent ce qui va se passer', (tester) async {
      await pump(tester, actions());
      expect(find.byTooltip('Métadonnées série'), findsNothing,
          reason: 'le crayon isolé a rejoint « Plus »');
      await openMore(tester);

      expect(find.text('Marquer la saison 2 comme vue'), findsOneWidget);
      expect(find.text('Télécharger les non vus de la saison 2'),
          findsOneWidget);
      expect(find.text('Partager la série'), findsOneWidget);
      expect(find.text('ADMINISTRATION'), findsOneWidget);
    });

    testWidgets('« Corriger la fiche… » propose détection auto et TMDB',
        (tester) async {
      await pump(tester, actions());
      await openMore(tester);
      await tester.tap(find.text('Corriger la fiche…'));
      await tester.pumpAndSettle();

      expect(find.text('Relancer la détection auto'), findsOneWidget);
      expect(find.text('Choisir sur TMDB'), findsOneWidget);
    });

    testWidgets('sans manage_library, pas de section Administration',
        (tester) async {
      await pump(tester, actions(), permissions: _member);
      await openMore(tester);

      expect(find.text('ADMINISTRATION'), findsNothing);
      expect(find.text('Corriger la fiche…'), findsNothing);
    });

    testWidgets('sur un téléviseur, le crayon et les ronds restent',
        (tester) async {
      await pump(tester, actions(), tv: true);

      expect(find.widgetWithText(HeroPill, 'Plus'), findsNothing);
      expect(find.byTooltip('Métadonnées série'), findsOneWidget);
    });
  });

  testWidgets('une ligne qui ouvre une section porte son titre',
      (tester) async {
    await pump(
      tester,
      Scaffold(
        body: Center(
          child: OnyxMenuButton<int>(
            tooltip: 'Menu',
            icon: AppIcons.more,
            onSelected: (_) {},
            items: const [
              OnyxMenuItem(value: 1, label: 'Partager'),
              OnyxMenuItem(value: 2, label: 'Corriger', section: 'Admin'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('Corriger'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
