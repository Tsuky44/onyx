import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/watch_list.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/lists/list_detail_screen.dart';
import 'package:onyx/screens/lists/list_detail_view.dart';
import 'package:onyx/screens/lists/widgets/list_detail_actions.dart';
import 'package:onyx/screens/lists/widgets/list_item_card.dart';
import 'package:onyx/screens/lists/widgets/list_selection_bar.dart';
import 'package:onyx/services/api_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_doubles.dart';

/// Le détail d'une liste : des titres rangés par onglet et par tri, déplacés,
/// copiés ou retirés en lot (ADR-0160). « Vu » est celui du serveur.

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, Object?> _item(
  int id,
  String title, {
  String date = '2000-01-01',
  int mediaId = 0,
  bool watched = false,
  String type = 'movie',
}) =>
    {
      'id': id,
      'media_type': type,
      'tmdb_id': 100 + id,
      'title': title,
      'poster_url': '',
      'release_date': date,
      'added_at': '2026-10-19T20:00:00Z',
      'media_id': mediaId,
      'watched': watched,
      if (mediaId > 0)
        'media': {
          'id': mediaId,
          'type': type,
          'title': title,
          'file_path': '/m/$mediaId.mkv',
          'versions': <Object>[],
        },
    };

Map<String, Object?> _list(int id, String kind, String name,
        {int count = 0, bool canEdit = true, bool mine = true}) =>
    {
      'id': id,
      'kind': kind,
      'name': name,
      'description': '',
      'is_shared': false,
      'is_mine': mine,
      'can_edit': canEdit,
      'owner': {'id': 1, 'username': 'alice'},
      'item_count': count,
      'posters': <String>[],
      'updated_at': '2026-10-19T20:00:00Z',
      'watched_count': 1,
      'on_server_count': 2,
    };

/// Les titres, du plus récent ajout au plus ancien, comme le serveur les rend.
WatchListItem _parsed(Map<String, Object?> json) =>
    WatchListItem.fromJson(json);

final _items = [
  _parsed(_item(1, 'Heat', date: '1995-12-15', mediaId: 70, watched: true)),
  _parsed(_item(2, 'Alien', date: '1979-05-25', mediaId: 71)),
  _parsed(_item(3, 'Dune', date: '2021-10-22')),
  _parsed(_item(4, 'Brazil', date: '1985-02-20', mediaId: 72)),
];

/// Un serveur à deux listes : la 2 (`items`) et la 1 (« À regarder plus
/// tard », vide). [requests] garde ce qui lui a été demandé ; [failCopy] fait
/// refuser l'ajout de ces titres à la liste 1.
ApiClient _server(
  List<String> requests, {
  List<Map<String, Object?>>? items,
  Set<int> failCopy = const {},
}) {
  final source = [...?items];
  final dio = Dio()
    ..httpClientAdapter = Adapter((options) {
      final path = options.uri.path;
      requests.add('${options.method} $path');
      if (options.method == 'POST' && path == '/api/lists/1/items') {
        final body = options.data;
        requests.add('body ${jsonEncode(body)}');
        final mediaId = body is Map ? body['media_id'] as int? : null;
        if (mediaId != null && failCopy.contains(mediaId)) {
          return _json({'error': 'non'}, 500);
        }
        return _json(_item(90, 'x', mediaId: mediaId ?? 0));
      }
      if (options.method == 'DELETE' &&
          path.startsWith('/api/lists/2/items/')) {
        final id = int.parse(path.split('/').last);
        source.removeWhere((i) => i['id'] == id);
        return _json({'status': 'ok'});
      }
      return switch (path) {
        '/api/ping' => _json({
            'status': 'ok',
            'capabilities': ['watch_lists', 'watch_list_members'],
          }),
        '/api/lists' => _json({
            'mine': [
              _list(1, 'watch_later', 'À regarder plus tard'),
              _list(2, 'custom', 'Films de Noël', count: source.length),
            ],
            'shared': <Object>[],
          }),
        '/api/lists/2' => _json({
            ..._list(2, 'custom', 'Films de Noël', count: source.length),
            'items': source,
            'members': <Object>[],
          }),
        _ => _json({'error': 'unexpected'}, 404),
      };
    });
  return ApiClient(httpClient: dio);
}

List<Map<String, Object?>> _seed() => [
      _item(1, 'Heat', date: '1995-12-15', mediaId: 70, watched: true),
      _item(2, 'Alien', date: '1979-05-25', mediaId: 71),
      _item(3, 'Dune', date: '2021-10-22'),
      _item(4, 'Brazil', date: '1985-02-20', mediaId: 72),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('les onglets et le tri', () {
    test('« À voir » est ce que le serveur a et que le compte n’a pas vu', () {
      final shown = arrangeListItems(_items, filter: WatchListFilter.toWatch);
      expect(shown.map((i) => i.title), ['Alien', 'Brazil']);
    });

    test('« Vus » suit le drapeau du serveur, « À demander » ce qui lui manque',
        () {
      expect(
          arrangeListItems(_items, filter: WatchListFilter.watched)
              .map((i) => i.title),
          ['Heat']);
      expect(
          arrangeListItems(_items, filter: WatchListFilter.toRequest)
              .map((i) => i.title),
          ['Dune']);
    });

    test('les compteurs des onglets sont ceux des titres retenus', () {
      final counts = countListItems(_items);
      expect(counts[WatchListFilter.all], 4);
      expect(counts[WatchListFilter.toWatch], 2);
      expect(counts[WatchListFilter.watched], 1);
      expect(counts[WatchListFilter.toRequest], 1);
    });

    test('le tri par défaut garde l’ordre du serveur, « en premier » l’inverse',
        () {
      expect(arrangeListItems(_items).map((i) => i.title),
          ['Heat', 'Alien', 'Dune', 'Brazil']);
      expect(
          arrangeListItems(_items, sort: WatchListSort.oldest)
              .map((i) => i.title),
          ['Brazil', 'Dune', 'Alien', 'Heat']);
    });

    test('le tri par titre ignore la casse, celui par année va du plus récent',
        () {
      expect(
          arrangeListItems(_items, sort: WatchListSort.title)
              .map((i) => i.title),
          ['Alien', 'Brazil', 'Dune', 'Heat']);
      expect(
          arrangeListItems(_items, sort: WatchListSort.year)
              .map((i) => i.title),
          ['Dune', 'Heat', 'Brazil', 'Alien']);
    });

    test('un serveur d’avant l’ADR-0159 ne marque rien comme vu', () {
      final item = WatchListItem.fromJson({
        'id': 1,
        'media_type': 'movie',
        'title': 'Heat',
      });
      expect(item.watched, isFalse);
    });
  });

  group('déplacer, copier, retirer', () {
    test('copier un titre du serveur ne renvoie que son identifiant', () {
      final title = ListableTitle.fromItem(_items.first);
      expect(title.toJson(), {'media_id': 70});
    });

    test('copier un titre absent du serveur garde son identité TMDB', () {
      final title = ListableTitle.fromItem(WatchListItem.fromJson({
        ..._item(3, 'Dune', date: '2021-10-22'),
        'poster_url': 'https://image.tmdb.org/t/p/w500/dune.jpg',
      }));
      expect(title.toJson(), containsPair('tmdb_id', 103));
      expect(title.toJson(), containsPair('poster_path', '/dune.jpg'));
    });

    test('déplacer copie d’abord, retire ensuite de la liste d’origine',
        () async {
      final requests = <String>[];
      final provider = WatchListsProvider(_server(requests, items: _seed()));
      addTearDown(provider.dispose);
      await provider.load();
      await provider.loadDetail(2);
      requests.clear();

      final result = await provider.moveItems(2, 1, [_items[0], _items[1]]);

      expect(result.isComplete, isTrue);
      expect(result.done.map((i) => i.title), ['Heat', 'Alien']);
      final writes = requests
          .where((r) => r.startsWith('POST') || r.startsWith('DELETE'))
          .toList();
      expect(writes, [
        'POST /api/lists/1/items',
        'POST /api/lists/1/items',
        'DELETE /api/lists/2/items/1',
        'DELETE /api/lists/2/items/2',
      ]);
      expect(provider.detail(2)!.items.map((i) => i.title), ['Dune', 'Brazil']);
    });

    test('un titre qui n’a pas pu être copié reste dans la liste d’origine',
        () async {
      final requests = <String>[];
      final provider =
          WatchListsProvider(_server(requests, items: _seed(), failCopy: {70}));
      addTearDown(provider.dispose);
      await provider.load();
      await provider.loadDetail(2);
      requests.clear();

      final result = await provider.moveItems(2, 1, [_items[0], _items[1]]);

      expect(result.failed, 1);
      expect(result.done.map((i) => i.title), ['Alien']);
      expect(requests, isNot(contains('DELETE /api/lists/2/items/1')));
      await provider.loadDetail(2);
      expect(provider.detail(2)!.items.map((i) => i.title),
          containsAll(['Heat', 'Dune', 'Brazil']));
    });

    test('retirer plusieurs titres rend ceux qu’on peut remettre', () async {
      final provider = WatchListsProvider(_server([], items: _seed()));
      addTearDown(provider.dispose);
      await provider.load();
      await provider.loadDetail(2);

      final result = await provider.removeItems(2, [_items[1], _items[3]]);

      expect(result.done.map((i) => i.title), ['Alien', 'Brazil']);
      expect(provider.detail(2)!.items.map((i) => i.title), ['Heat', 'Dune']);
    });
  });

  group('le menu « ⋯ » (ADR-0161)', () {
    WatchList list({bool mine = true, int members = 0}) => WatchList(
          id: 2,
          kind: WatchListKind.custom,
          name: 'Soirées SF',
          description: '',
          isShared: false,
          isMine: mine,
          canEdit: true,
          isMember: !mine,
          memberCount: members,
          owner: const WatchListOwner(id: 1, username: 'alice'),
          itemCount: 4,
          posters: const [],
        );

    test('range la liste et ses titres en deux groupes titrés', () {
      final items = listMenuItems(list(members: 2),
          canInvite: true, hasItems: true, watchedCount: 3);
      expect(
          [for (final i in items) if (i.section != null) i.section],
          ['La liste', 'Les titres']);
      final share = items.firstWhere((i) => i.value == ListAction.share);
      expect(share.subtitle, '2 personnes invitées');
      final watched =
          items.firstWhere((i) => i.value == ListAction.removeWatched);
      expect(watched.subtitle, '3 titres · se défait',
          reason: 'on sait ce qu’on retire avant de le retirer');
    });

    test('un groupe seul ne se titre pas', () {
      final items = listMenuItems(list(mine: false),
          canInvite: true, hasItems: true, watchedCount: 0);
      expect(items.where((i) => i.section != null), isEmpty);
      expect(items.map((i) => i.value),
          [ListAction.select, ListAction.leave]);
    });
  });

  group('l’écran', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _server([], items: _seed());
      final lists = WatchListsProvider(api);
      addTearDown(lists.dispose);
      await tester.runAsync(() async {
        await lists.load();
        await lists.loadDetail(2);
      });
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<WatchListsProvider>.value(value: lists),
        ],
        child: const MaterialApp(home: ListDetailScreen(listId: 2)),
      ));
      await tester.pump();
      // La relecture silencieuse de l'ouverture part au premier tour : on
      // avance l'horloge pour que sa minuterie se déclenche.
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('les onglets montrent leur nombre et filtrent les affiches',
        (tester) async {
      await pump(tester);
      expect(find.text('Tous · 4'), findsOneWidget);
      expect(find.text('À voir · 2'), findsOneWidget);
      expect(find.text('Vus · 1'), findsOneWidget);
      expect(find.text('À demander · 1'), findsOneWidget);

      await tester.tap(find.text('Vus · 1'));
      await tester.pump();
      expect(find.byType(ListItemCard), findsOneWidget);
    });

    testWidgets('la sélection fait flotter ses actions sous la grille',
        (tester) async {
      await pump(tester);
      expect(find.text('Tout sélectionner'), findsNothing);

      await tester.tap(find.byTooltip('Plus d’actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sélectionner des titres'));
      await tester.pumpAndSettle();

      expect(find.text('Tout sélectionner'), findsOneWidget);
      expect(find.text('Déplacer vers…'), findsOneWidget);
      expect(find.text('Copier vers…'), findsOneWidget);
      expect(find.byType(ListSelectionBar), findsOneWidget);
      // Les onglets restent : on choisit dans l'onglet ouvert.
      expect(find.text('Tous · 4'), findsOneWidget);
    });
  });
}
