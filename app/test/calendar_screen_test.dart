import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/calendar_provider.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/screens/calendar/calendar_screen.dart';
import 'package:onyx/screens/home/home_calendar_row.dart';
import 'package:onyx/theme/app_theme.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/follow_show_button.dart';
import 'package:onyx/widgets/global/media_countdown.dart';
import 'package:provider/provider.dart';

/// Un serveur qui rend le calendrier de la maquette, sans réseau. Les dates
/// partent du 27 novembre 2026.
class _CalendarServer extends ApiClient {
  final follows = <int>[];
  final unfollows = <int>[];

  static Map<String, dynamic> _ep(String date, int tmdb, String title,
          String source, int season, int episode,
          {String type = '', bool ready = false, int mediaId = 0}) =>
      {
        'id': 'tv:$tmdb:s${season}e$episode',
        'kind': 'show',
        'source': source,
        'tmdb_id': tmdb,
        'media_id': mediaId,
        'episode_media_id': ready ? 9000 + episode : 0,
        'title': title,
        'air_date': date,
        'season_number': season,
        'episode_number': episode,
        'episode_name': '',
        'episode_type': type,
        'release_type': '',
        'poster_url': '',
        'still_url': '',
        'ready': ready,
      };

  static Map<String, dynamic> _movie(
          String date, int tmdb, String title, String source) =>
      {
        'id': 'movie:$tmdb',
        'kind': 'movie',
        'source': source,
        'tmdb_id': tmdb,
        'media_id': 0,
        'episode_media_id': 0,
        'title': title,
        'air_date': date,
        'season_number': 0,
        'episode_number': 0,
        'episode_name': '',
        'episode_type': '',
        'release_type': 'digital',
        'poster_url': '',
        'still_url': '',
        'ready': false,
      };

  static Map<String, dynamic> _show(int tmdb, String title, String source) => {
        'tmdb_id': tmdb,
        'media_id': 0,
        'title': title,
        'source': source,
        'poster_url': '',
        'next_air_date': '',
        'next_season': 0,
        'next_episode': 0,
        'next_entry_id': '',
      };

  @override
  Future<CalendarFeed?> getCalendar({
    required DateTime from,
    required DateTime to,
    required DateTime today,
  }) async {
    return CalendarFeed.fromJson({
      'from': '2026-10-01',
      'to': '2027-05-26',
      'today': '2026-11-27',
      'entries': [
        _ep('2026-11-27', 1, 'Les Veilleurs', 'watching', 2, 9, ready: true),
        _ep('2026-11-27', 2, 'Orbite basse', 'followed', 1, 4),
        _ep('2026-11-28', 3, 'Cendres', 'request', 3, 1, type: 'premiere'),
        _movie('2026-11-30', 10, 'Le Dernier Phare', 'request'),
        _ep('2026-12-01', 4, 'Nord Sombre', 'watching', 1, 7),
        _ep('2026-12-02', 5, 'Halcyon', 'followed', 4, 10, type: 'finale'),
        _ep('2026-12-03', 1, 'Les Veilleurs', 'watching', 2, 10),
        _ep('2026-12-04', 6, 'La Ligue', 'server', 5, 2),
        _ep('2026-12-05', 3, 'Cendres', 'request', 3, 2),
        _ep('2026-12-11', 6, 'La Ligue', 'server', 5, 3),
      ],
      'followed': [
        _show(1, 'Les Veilleurs', 'watching'),
        _show(2, 'Orbite basse', 'followed'),
        _show(3, 'Cendres', 'request'),
        _show(6, 'La Ligue', 'server'),
        // Comme le vrai serveur : une série suivie revient dans la réponse.
        for (final id in follows) _show(id, 'Série $id', 'followed'),
      ],
    });
  }

  @override
  Future<void> followCalendarShow(int tmdbId) async => follows.add(tmdbId);

  @override
  Future<void> unfollowCalendarShow(int tmdbId) async => unfollows.add(tmdbId);
}

Future<CalendarProvider> _loadedProvider({_CalendarServer? server}) async {
  final provider = CalendarProvider(server ?? _CalendarServer(),
      clock: DateTime(2026, 11, 27));
  await provider.load();
  return provider;
}

Widget _wrap({
  required CalendarProvider provider,
  required Widget child,
  Size size = const Size(390, 844),
  bool isTv = false,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: ChangeNotifierProvider<CalendarProvider>.value(
      value: provider,
      child: TvScope(
        isTv: isTv,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('mobile (< 700 px) affiche l’Agenda, filtre et gère les suivis',
      (tester) async {
    final provider = await _loadedProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(_wrap(
      provider: provider,
      size: const Size(390, 844),
      child: const CalendarScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('À venir'), findsOneWidget);
    expect(find.text('Les Veilleurs'), findsOneWidget);
    expect(find.text('Le Dernier Phare'), findsOneWidget);

    // Le filtre « Séries » masque les films.
    await tester.tap(find.text('Séries'));
    await tester.pumpAndSettle();
    expect(find.text('Le Dernier Phare'), findsNothing);
    expect(find.text('Les Veilleurs'), findsOneWidget);

    // Ouverture du panneau « Gérer les séries suivies » et retrait d'une série.
    await tester.tap(find.byTooltip('Gérer les séries suivies'));
    await tester.pumpAndSettle();
    expect(find.text('Séries suivies'), findsOneWidget);

    await tester.tap(find.text('Ne plus suivre').first);
    await tester.pumpAndSettle();
    expect(find.text('Retirée du calendrier'), findsOneWidget);
  });

  testWidgets('bureau (>= 700 px) affiche Semaine puis bascule vers Mois',
      (tester) async {
    final provider = await _loadedProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(_wrap(
      provider: provider,
      size: const Size(1280, 800),
      child: const CalendarScreen(embedded: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Les 7 prochains jours'), findsOneWidget);
    expect(find.text('Semaine'), findsOneWidget);
    expect(find.text('Mois'), findsOneWidget);

    await tester.tap(find.text('Mois'));
    await tester.pumpAndSettle();
    expect(find.text('Novembre 2026'), findsOneWidget);
    expect(find.text('LUN'), findsOneWidget);
  });

  testWidgets('TV affiche la vue Affiche (hero + rangées)', (tester) async {
    final provider = await _loadedProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(_wrap(
      provider: provider,
      size: const Size(1280, 720),
      isTv: true,
      child: const CalendarScreen(embedded: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cendres'), findsWidgets);
    expect(find.text('Cette semaine'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
    await tester.pump();
    expect(find.text('La semaine prochaine'), findsOneWidget);
  });

  testWidgets(
      'accueil « Cette semaine » et fiche « Suivre » + compte à rebours',
      (tester) async {
    final provider = await _loadedProvider();
    addTearDown(provider.dispose);
    final show = Media(
      id: 999,
      type: MediaType.show,
      title: 'Nouvelle Série',
      duration: 0,
      tmdbId: 42,
      createdAt: DateTime(2026, 11, 1),
    );
    var opened = 0;

    await tester.pumpWidget(_wrap(
      provider: provider,
      size: const Size(1280, 800),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const HomeCalendarRow(),
            FollowShowButton(show: show),
            MediaCountdown(
              now: DateTime(2026, 11, 27),
              model: const CountdownModel(
                kind: CountdownKind.next,
                label: 'Prochain épisode',
                target: '2026-12-03',
                caption: 'Saison 2 · Épisode 10',
              ),
              onOpenCalendar: () => opened++,
              calendarNote: 'Suivie car vous la regardez',
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Cette semaine'), findsOneWidget);
    expect(find.text('Tout voir'), findsOneWidget);

    await tester.tap(find.text('Suivre'));
    await tester.pump();
    expect(find.text('Suivie'), findsOneWidget);
    expect(find.text('Ajoutée au calendrier'), findsOneWidget);

    await tester.tap(find.text('Voir dans le calendrier'));
    await tester.pump();
    expect(opened, 1);

    await tester.tap(find.text('Tout voir'));
    await tester.pump();
    expect(provider.openTabVersion, 1);
  });
}
