import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/calendar_provider.dart';
import 'package:onyx/screens/calendar/calendar_entry_launch.dart';
import 'package:onyx/services/api_client.dart';

Map<String, dynamic> _episode(int tmdb, String date,
        {String source = 'watching',
        int season = 2,
        int episode = 9,
        String type = '',
        bool ready = false}) =>
    {
      'id': 'tv:$tmdb:s${season}e$episode',
      'kind': 'show',
      'source': source,
      'tmdb_id': tmdb,
      'media_id': 50 + tmdb,
      'episode_media_id': ready ? 777 : 0,
      'title': 'Série $tmdb',
      'air_date': date,
      'season_number': season,
      'episode_number': episode,
      'episode_type': type,
      'release_type': '',
      'poster_url': 'https://image.tmdb.org/t/p/w342/p$tmdb.jpg',
      'ready': ready,
    };

/// Un serveur de calendrier réglable, sans réseau.
class _Server extends ApiClient {
  _Server(this.feed);

  Map<String, dynamic>? feed;
  bool failChoices = false;
  final calls = <String>[];

  @override
  Future<CalendarFeed?> getCalendar({
    required DateTime from,
    required DateTime to,
    required DateTime today,
  }) async {
    calls.add('get');
    final f = feed;
    return f == null ? null : CalendarFeed.fromJson(f);
  }

  @override
  Future<void> followCalendarShow(int tmdbId) async {
    calls.add('follow $tmdbId');
    if (failChoices) throw StateError('hors ligne');
  }

  @override
  Future<void> unfollowCalendarShow(int tmdbId) async {
    calls.add('unfollow $tmdbId');
    if (failChoices) throw StateError('hors ligne');
  }
}

Media _show(int id, {int? tmdbId}) => Media(
      id: id,
      type: MediaType.show,
      title: 'Série',
      duration: 0,
      tmdbId: tmdbId,
      createdAt: DateTime(2026),
    );

void main() {
  final today = DateTime(2026, 11, 27);

  test('le flux du serveur devient les entrées des vues, libellés compris',
      () async {
    final server = _Server({
      'entries': [
        _episode(1, '2026-11-27', ready: true),
        _episode(2, '2026-12-02',
            source: 'followed', season: 4, episode: 10, type: 'finale'),
        _episode(3, '2026-11-28',
            source: 'request', season: 3, episode: 1, type: 'premiere'),
        {
          'id': 'movie:9',
          'kind': 'movie',
          'source': 'request',
          'tmdb_id': 9,
          'title': 'Brume',
          'air_date': '2026-12-16',
          'release_type': 'digital',
        },
      ],
      'followed': [
        {
          'tmdb_id': 1,
          'media_id': 51,
          'title': 'Série 1',
          'source': 'watching',
          'next_season': 2,
          'next_episode': 9
        },
      ],
    });
    final calendar = CalendarProvider(server, clock: today);
    await calendar.load();

    expect(calendar.available, isTrue);
    expect(calendar.entries.map((e) => e.subtitle), [
      'S2 · É9',
      'S4 · É10 · Finale',
      'S3 · É1 · Reprise',
      'Film · sortie numérique',
    ]);
    final first = calendar.entries.first;
    expect(first.ready && first.episodeMediaId == 777 && first.mediaId == 51,
        isTrue);
    expect(first.showId, 'tv:1');
    expect(calendar.hasAvailableToday, isTrue);
    expect(calendar.thisWeekEntries, hasLength(3),
        reason: 'le film du 16 décembre est hors semaine');
    expect(calendar.followedShows.single.nextSummary, 'S2 · É9');
    expect(calendar.followReasonFor(_show(51, tmdbId: 1)),
        'Suivie car vous la regardez');
  });

  test('un serveur sans calendrier laisse tout vide', () async {
    final calendar = CalendarProvider(_Server(null), clock: today);
    await calendar.load();
    expect(calendar.available, isFalse);
    expect(calendar.entries, isEmpty);
  });

  test('« Suivre » s’affiche tout de suite, part au serveur puis relit',
      () async {
    final server = _Server({'entries': [], 'followed': []});
    final calendar = CalendarProvider(server, clock: today);
    await calendar.load();
    server.calls.clear();

    final show = _show(7, tmdbId: 70);
    expect(
        calendar.toggleFollowShow(show,
            nextAirDate: '2026-12-01', nextCaption: 'S1 · É2'),
        isTrue);
    expect(calendar.isFollowingShow(show), isTrue);
    expect(calendar.entries.single.title, 'Série',
        reason: 'le prochain épisode connu de la fiche apparaît');

    // Le serveur rend désormais la série suivie.
    server.feed = {
      'entries': [
        _episode(70, '2026-12-01', source: 'followed', season: 1, episode: 2)
      ],
      'followed': [
        {'tmdb_id': 70, 'title': 'Série 70', 'source': 'followed'}
      ],
    };
    await pumpEventQueue();
    expect(server.calls, ['follow 70', 'get']);
    expect(calendar.entries.single.id, 'tv:70:s1e2',
        reason: 'l’entrée provisoire laisse la place à celle du serveur');
    expect(calendar.isFollowingShow(show), isTrue);
  });

  test(
      '« Ne plus suivre » masque la série avant la réponse, et un refus la remet',
      () async {
    final server = _Server({
      'entries': [_episode(1, '2026-11-28')],
      'followed': [
        {'tmdb_id': 1, 'media_id': 51, 'title': 'Série 1', 'source': 'watching'}
      ],
    })
      ..failChoices = true;
    final calendar = CalendarProvider(server, clock: today);
    await calendar.load();

    calendar.unfollowById('tv:1');
    expect(calendar.entries, isEmpty);
    expect(calendar.followedShows, isEmpty);

    await pumpEventQueue();
    expect(calendar.entries, hasLength(1),
        reason: 'le serveur a refusé : rien n’a changé');
    expect(calendar.followedShows, hasLength(1));
    expect(calendar.errorMessage, isNotNull);
  });

  test('une série sans identifiant TMDB ne peut pas être suivie', () async {
    final server = _Server({'entries': [], 'followed': []});
    final calendar = CalendarProvider(server, clock: today);
    await calendar.load();
    expect(calendar.toggleFollowShow(_show(8)), isFalse);
    expect(server.calls.where((c) => c.startsWith('follow')), isEmpty);
  });

  test('naviguer au-delà de la fenêtre chargée la fait élargir', () async {
    final server = _Server({'entries': [], 'followed': []});
    final calendar = CalendarProvider(server, clock: today);
    await calendar.load();
    server.calls.clear();
    calendar.shiftMonth(1);
    await pumpEventQueue();
    expect(server.calls, isEmpty, reason: 'décembre est déjà chargé');
    calendar.shiftMonth(8);
    await pumpEventQueue();
    expect(server.calls, ['get']);
  });

  test('le chemin TMDB d’une affiche, pour la fiche de demande', () {
    expect(
        tmdbImagePath('https://image.tmdb.org/t/p/w342/abc.jpg'), '/abc.jpg');
    expect(tmdbImagePath('/api/media/3/poster'), isNull);
    expect(tmdbImagePath(null), isNull);
  });
}
