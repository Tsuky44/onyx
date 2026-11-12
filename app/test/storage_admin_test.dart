import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/storage_admin.dart';
import 'package:onyx/screens/settings/pages/storage_details_screen.dart';
import 'package:onyx/screens/settings/pages/storage_query.dart';

// Le gestionnaire de stockage de l'administration (ADR-0115).

StorageItem _item(
  String title, {
  bool show = false,
  int size = 0,
  DateTime? played,
  DateTime? added,
}) =>
    StorageItem(
      id: title.hashCode,
      isShow: show,
      title: title,
      size: size,
      lastPlayedAt: played,
      addedAt: added,
    );

void main() {
  test('la liste du serveur se lit avec ses demandes', () {
    final list = StorageList.fromJson({
      'requests_available': true,
      'items': [
        {
          'id': 4,
          'type': 'show',
          'title': 'Dark',
          'size': 3000,
          'episode_count': 2,
          'poster_url': '/p.jpg',
          'added_at': '2026-01-01T10:00:00Z',
          'requests': [
            {'requester': 'max', 'status': 'partial', 'seasons': [1, 2]},
          ],
        },
      ],
    });
    final dark = list.items.single;
    expect(list.requestsAvailable, isTrue);
    expect(dark.isShow, isTrue);
    expect(dark.lastPlayedAt, isNull);
    expect(dark.idleSince, isNotNull, reason: 'jamais lancé : depuis son ajout');
    expect(dark.requests.single.seasons, [1, 2]);
  });

  final now = DateTime(2026, 11, 12);
  final items = [
    _item('Heat', size: 8000, played: DateTime(2026, 11, 1)),
    _item('Alien', size: 2000, played: DateTime(2025, 1, 1)),
    _item('Dark', show: true, size: 9000, added: DateTime(2026, 2, 1)),
  ];

  test('« pas regardé depuis 6 mois » garde l’oublié et le jamais lancé', () {
    final kept = const StorageQuery(idle: StorageIdle.months6, sort: StorageSort.title)
        .apply(items, now: now);
    expect(kept.map((i) => i.title), ['Alien', 'Dark']);
  });

  test('« jamais lancé » ne garde que ce que personne n’a lu', () {
    final kept = const StorageQuery(idle: StorageIdle.never).apply(items, now: now);
    expect(kept.map((i) => i.title), ['Dark']);
  });

  test('le tri par taille met le plus gros d’abord, le tri par oubli le plus ancien', () {
    expect(const StorageQuery().apply(items, now: now).map((i) => i.title),
        ['Dark', 'Heat', 'Alien']);
    expect(
        const StorageQuery(sort: StorageSort.idle)
            .apply(items, now: now)
            .map((i) => i.title),
        ['Alien', 'Dark', 'Heat']);
    expect(
        const StorageQuery(kind: StorageKind.movies)
            .apply(items, now: now)
            .map((i) => i.title),
        ['Heat', 'Alien']);
  });

  test('un compte sur une série dit à quel épisode il en est', () {
    final viewer = StorageViewer.fromJson({
      'user_id': 2,
      'username': 'lea',
      'finished': false,
      'watched_episodes': 7,
      'total_episodes': 20,
      'current_episode': {
        'season': 2,
        'episode': 4,
        'position_seconds': 720,
        'duration_seconds': 3000,
        'finished': false,
      },
    });
    expect(storageViewerText(viewer, show: true),
        'S2 · E4 à 12 min sur 50 min · 7/20 épisodes vus');
  });
}
