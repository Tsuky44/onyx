import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onyx/models/server_activity.dart';
import 'package:onyx/screens/settings/pages/my_stats_page.dart';
import 'package:onyx/services/api_client.dart';

Map<String, Object?> _personal() => {
      'all_time': false,
      'first_play': '2025-03-02',
      'previous': {'plays': 20, 'watched_seconds': 3600},
      'streak': {'current': 5, 'best': 12},
      'weekday_hour': [
        for (var d = 0; d < 7; d++)
          [for (var h = 0; h < 24; h++) d == 6 && h == 21 ? 7200 : 0],
      ],
      'longest_play': {'title': 'Dune', 'watched_seconds': 9960},
      'marathon': {'title': 'Severance', 'date': '2026-09-14', 'episodes': 6},
      'shows_count': 2,
      'shows_finished': 1,
      'shows': [
        {
          'show_id': 4,
          'title': 'Severance',
          'watched_seconds': 51600,
          'episodes_seen': 19,
          'episodes_total': 19,
          'finished': true,
        },
        {
          'show_id': 5,
          'title': 'The Bear',
          'watched_seconds': 18300,
          'episodes_seen': 9,
          'episodes_total': 28,
          'finished': false,
        },
      ],
      'unfinished_movies': [
        {'media_id': 7, 'title': 'Tenet', 'percent': 54},
      ],
      'average_movie_seconds': 7020,
      'decades': [
        {'decade': 1990, 'titles': 2, 'watched_seconds': 14000},
        {'decade': 2020, 'titles': 6, 'watched_seconds': 90000},
      ],
      'genres': [
        {'genre_id': 878, 'titles': 3, 'watched_seconds': 60000},
        {'genre_id': 18, 'titles': 2, 'watched_seconds': 20000},
        {'genre_id': 424242, 'titles': 1, 'watched_seconds': 100},
      ],
      'devices': [
        {
          'key': 'Salon',
          'label': 'Salon',
          'secondary': 'Android TV 1.4.2',
          'plays': 30,
          'watched_seconds': 118800
        },
      ],
      'lifetime': {
        'plays': 400,
        'watched_seconds': 1483200,
        'most_rewatched': {'title': 'Interstellar', 'times': 4},
      },
    };

class _FakeApi extends ApiClient {
  _FakeApi({this.withPersonal = true});
  final bool withPersonal;
  final calls = <({int days, bool allTime})>[];

  @override
  String get baseUrl => 'http://maison.local';

  @override
  Future<PlaybackStats> getMyPlaybackStats(
      {int days = 30, bool allTime = false}) async {
    calls.add((days: days, allTime: allTime));
    return PlaybackStats.fromJson({
      'days': 30,
      'totals': {
        'plays': 37,
        'watched_seconds': 151800,
        'active_users': 1,
        'movies': 6,
        'episodes': 31,
      },
      'daily': [
        for (var i = 0; i < 30; i++)
          {
            'date': '2026-09-${(i + 1).toString().padLeft(2, '0')}',
            'plays': 1,
            'watched_seconds': i == 13 ? 17400 : 3600,
          },
      ],
      'hour_of_day': List.filled(24, 0),
      'top_media': [
        {
          'key': 'show:Severance',
          'label': 'Severance',
          'media_type': 'show',
          'plays': 18,
          'watched_seconds': 51600,
        },
      ],
      'clients': const [],
      'play_methods': const [],
      if (withPersonal) 'personal': _personal(),
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  Future<_FakeApi> pump(WidgetTester tester, _FakeApi api) async {
    tester.view.devicePixelRatio = 1;
    // Assez haut pour que toute la page soit construite d'un coup.
    tester.view.physicalSize = const Size(1100, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await api.initialize();
    await tester.pumpWidget(Provider<ApiClient>.value(
      value: api,
      child: const MaterialApp(home: Scaffold(body: MyStatsPage())),
    ));
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('la page raconte le visionnage du compte, bloc par bloc',
      (tester) async {
    final api = await pump(tester, _FakeApi());

    expect(api.calls, [(days: 30, allTime: false)]);
    expect(find.text('42 h 10'), findsOneWidget);
    expect(find.text('41 h 10 de plus que la période d’avant'), findsOneWidget);
    expect(find.text('Record : 12 jours'), findsOneWidget);
    expect(find.text('Dimanche, le soir'), findsOneWidget);
    expect(find.text('6 épisodes de Severance · lundi 14 septembre'),
        findsOneWidget);
    expect(find.text('Terminée'), findsOneWidget);
    expect(find.text('9 / 28 ép.'), findsOneWidget);
    expect(find.text('Tenet'), findsOneWidget);
    expect(find.text('Science-fiction'), findsOneWidget);
    expect(find.text('Drame'), findsOneWidget);
    expect(find.text('90s'), findsOneWidget);
    expect(find.text('2020s'), findsOneWidget);
    expect(find.text('Salon'), findsOneWidget);
    expect(find.text('Interstellar, vu 4 fois'), findsOneWidget);
    // Ce qui ne parle qu'au serveur n'a pas sa place ici.
    expect(find.text('Méthodes de lecture'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Depuis le début » demande tout l’historique', (tester) async {
    final api = await pump(tester, _FakeApi());

    await tester.tap(find.text('Depuis le début'));
    await tester.pumpAndSettle();

    expect(api.calls.last, (days: 30, allTime: true));
    expect(tester.takeException(), isNull);
  });

  // Les lignes qui ouvrent une fiche se lisent par leur texte : un lecteur
  // d'écran les nomme (ADR-0054).
  testWidgets('chaque cible de la page a un nom, sur un téléphone',
      (tester) async {
    final handle = tester.ensureSemantics();
    final api = _FakeApi();
    await api.initialize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 5000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Provider<ApiClient>.value(
      value: api,
      child: const MaterialApp(home: Scaffold(body: MyStatsPage())),
    ));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('un serveur plus ancien garde les chiffres communs',
      (tester) async {
    await pump(tester, _FakeApi(withPersonal: false));

    expect(find.text('42 h 10'), findsOneWidget);
    expect(find.text('Heures de visionnage'), findsOneWidget);
    expect(find.text('Mes titres les plus regardés'), findsOneWidget);
    expect(find.text('Mes genres'), findsNothing);
    expect(find.text('Jours d’affilée'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
