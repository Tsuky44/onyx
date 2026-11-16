import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/watch_list.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/widgets/global/add_to_list_sheet.dart';
import 'package:onyx/widgets/global/watch_list_members_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_doubles.dart';

/// Les listes du compte (ADR-0070) : « À regarder plus tard », les siennes,
/// et celles des autres. Le serveur tient tout ; l'app coche, décoche et relit.

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, Object?> _list(int id, String kind, String name,
        {int count = 0, int? contains}) =>
    {
      'id': id,
      'kind': kind,
      'name': name,
      'description': '',
      'is_shared': false,
      'is_mine': true,
      'owner': {'id': 1, 'username': 'alice'},
      'item_count': count,
      'posters': <String>[],
      'updated_at': '2026-10-19T20:00:00Z',
      if (contains != null) 'contains_item_id': contains,
    };

/// Un serveur réduit aux listes. [requests] garde ce qui lui a été demandé ;
/// le titre 603 n'est d'abord dans aucune liste.
ApiClient _server(List<String> requests,
    {bool lists = true, bool roles = false}) {
  var inLater = 0;
  // Le rôle de carol sur la liste 2, tel que le serveur le tient.
  String? carolRole;
  List<Object> members() => [
        if (carolRole != null)
          {
            'id': 3,
            'username': 'carol',
            'avatar': 'preset:fox',
            'role': carolRole
          },
      ];
  final dio = Dio()
    ..httpClientAdapter = Adapter((options) {
      final query = options.uri.hasQuery ? '?${options.uri.query}' : '';
      requests.add('${options.method} ${options.uri.path}$query');
      final probe = options.uri.queryParameters.isNotEmpty;
      return switch ((options.method, options.uri.path)) {
        ('GET', '/api/ping') => _json({
            'status': 'ok',
            'capabilities': [
              if (lists) 'watch_lists',
              if (lists) 'watch_list_members',
              if (lists && roles) 'watch_list_member_roles',
            ],
          }),
        ('GET', '/api/lists') => _json({
            'mine': [
              _list(1, 'watch_later', 'À regarder plus tard',
                  count: inLater > 0 ? 1 : 0, contains: probe ? inLater : null),
              _list(2, 'custom', 'Mes recos', contains: probe ? 0 : null),
            ],
            'shared': [
              {
                ..._list(3, 'custom', 'Noël'),
                'is_mine': false,
                'is_shared': true,
                'owner': {'id': 2, 'username': 'bob'},
              },
              {
                ..._list(4, 'custom', 'Soirée ciné',
                    contains: probe ? 0 : null),
                'is_mine': false,
                'can_edit': true,
                'owner': {'id': 2, 'username': 'bob'},
              },
            ],
          }),
        ('GET', '/api/lists/2') => _json({
            ..._list(2, 'custom', 'Mes recos'),
            'items': <Object>[],
            'members': members(),
          }),
        ('GET', '/api/list-people') => _json([
            {'id': 2, 'username': 'bob', 'avatar': ''},
            {'id': 3, 'username': 'carol', 'avatar': 'preset:fox'},
          ]),
        ('PUT', '/api/lists/2/members/3') => () {
            final body = options.data;
            requests.add('body ${body == null ? '-' : jsonEncode(body)}');
            carolRole = body is Map ? body['role'] as String : 'editor';
            return _json(members());
          }(),
        ('DELETE', '/api/lists/2/members/3') => () {
            carolRole = null;
            return _json({'status': 'ok'});
          }(),
        ('POST', '/api/lists/1/items') => () {
            inLater = 41;
            return _json({
              'id': 41,
              'media_type': 'movie',
              'tmdb_id': 603,
              'title': 'The Matrix',
              'poster_url': '',
              'release_date': '1999-03-31',
              'added_at': '2026-10-19T20:00:00Z',
              'media_id': 0,
            });
          }(),
        ('DELETE', '/api/lists/1/items/41') => () {
            inLater = 0;
            return _json({'status': 'ok'});
          }(),
        _ => _json({'error': 'unexpected'}, 404),
      };
    });
  return ApiClient(httpClient: dio);
}

const _matrix = RequestMediaItem(
  id: 603,
  mediaType: RequestMediaType.movie,
  title: 'The Matrix',
  overview: '',
  posterPath: '/matrix.jpg',
  backdropPath: null,
  releaseDate: '1999-03-31',
  rating: 8.2,
  status: RequestMediaStatus.unknown,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ListableTitle', () {
    test('un titre du catalogue part avec son identité TMDB et son affiche',
        () {
      final title = ListableTitle.catalog(_matrix);
      expect(title.isOnServer, isFalse);
      expect(title.toJson(), {
        'tmdb_id': 603,
        'media_type': 'movie',
        'title': 'The Matrix',
        'poster_path': '/matrix.jpg',
        'release_date': '1999-03-31',
      });
      expect(title.probe, {'tmdb_id': 603, 'media_type': 'movie'});
    });

    test('une fiche du serveur ne part qu’avec son identifiant', () {
      final show = Media(
          id: 12,
          type: MediaType.show,
          title: 'Lioness',
          duration: 0,
          createdAt: DateTime(2026));
      final title = ListableTitle.server(show);
      expect(title.toJson(), {'media_id': 12});
      expect(title.probe, {'media_id': 12});
      expect(title.mediaType, WatchListMediaType.show);
    });
  });

  test('ce qui n’est pas sur le serveur s’ouvre dans le catalogue', () {
    final item = WatchListItem.fromJson({
      'id': 1,
      'media_type': 'show',
      'tmdb_id': 1399,
      'title': 'Game of Thrones',
      'poster_url': 'https://image.tmdb.org/t/p/w500/got.jpg',
      'release_date': '2011-04-17',
      'media_id': 0,
    });
    expect(item.isOnServer, isFalse);
    final request = item.toRequestItem();
    expect(request.id, 1399);
    expect(request.mediaType, RequestMediaType.tv);
    expect(request.posterPath, '/got.jpg');
    expect(item.year, '2011');
  });

  test('cocher et décocher compte un titre de plus, puis de moins', () {
    final list = WatchList.fromJson(_list(1, 'custom', 'Recos', count: 2));
    final added = list.withMembership(-1);
    expect(added.contains, isTrue);
    expect(added.itemCount, 3);
    final confirmed = added.withMembership(9);
    expect(confirmed.itemCount, 3, reason: 'déjà compté pendant l’ajout');
    expect(confirmed.withMembership(0).itemCount, 2);
  });

  test('« À regarder plus tard » suit la langue de l’app, pas le serveur', () {
    final later = WatchList.fromJson(_list(1, 'watch_later', 'Watch later'));
    expect(later.isWatchLater, isTrue);
    expect(later.displayName, 'À regarder plus tard');
  });

  group('WatchListsProvider', () {
    test('un serveur sans listes n’en reçoit aucune question', () async {
      final requests = <String>[];
      final provider = WatchListsProvider(_server(requests, lists: false));
      addTearDown(provider.dispose);
      await provider.load();
      expect(provider.isSupported, isFalse);
      expect(provider.hasLoaded, isTrue);
      expect(requests, ['GET /api/ping']);
    });

    test('les miennes d’abord, celles des autres à part', () async {
      final provider = WatchListsProvider(_server([]));
      addTearDown(provider.dispose);
      await provider.load();
      expect(provider.isSupported, isTrue);
      expect(provider.overview.mine.first.isWatchLater, isTrue);
      expect(provider.overview.shared.first.owner.username, 'bob');
      expect(provider.summary(3)?.isMine, isFalse);
    });

    test('la feuille « Ajouter » propose aussi les listes où l’on est invité',
        () async {
      final provider = WatchListsProvider(_server([]));
      addTearDown(provider.dispose);
      final lists = await provider.membership(ListableTitle.catalog(_matrix));
      expect(lists.map((l) => l.id), [1, 2, 4],
          reason:
              'la liste 3 est partagée en lecture seule : elle n’y est pas');
      expect(lists.last.canEdit, isTrue);
      expect(lists.last.isMine, isFalse);
    });

    test('inviter et retirer un compte passe par le serveur', () async {
      final requests = <String>[];
      final provider = WatchListsProvider(_server(requests));
      addTearDown(provider.dispose);
      await provider.load();
      expect(provider.supportsMembers, isTrue);
      expect(
          (await provider.people()).map((p) => p.username), ['bob', 'carol']);
      await provider.addMember(2, 3);
      await provider.removeMember(2, 3);
      expect(
          requests,
          containsAll([
            'PUT /api/lists/2/members/3',
            'DELETE /api/lists/2/members/3',
          ]));
    });

    test('changer de serveur oublie les listes du précédent', () async {
      final provider = WatchListsProvider(_server([]));
      addTearDown(provider.dispose);
      await provider.load();
      provider.reset();
      expect(provider.hasLoaded, isFalse);
      expect(provider.summary(1), isNull);
    });
  });

  testWidgets('la feuille coche la liste, puis la décoche, au serveur',
      (tester) async {
    final requests = <String>[];
    final provider = WatchListsProvider(_server(requests));
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: AddToListSheet(title: ListableTitle.catalog(_matrix)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(requests, contains('GET /api/lists?tmdb_id=603&media_type=movie'));
    expect(find.text('À regarder plus tard'), findsOneWidget);
    expect(find.byIcon(AppIcons.check), findsNothing);

    await tester.tap(find.text('À regarder plus tard'));
    await tester.pumpAndSettle();
    expect(requests, contains('POST /api/lists/1/items'));
    expect(find.byIcon(AppIcons.check), findsOneWidget);

    await tester.tap(find.text('À regarder plus tard'));
    await tester.pumpAndSettle();
    expect(requests, contains('DELETE /api/lists/1/items/41'));
    expect(find.byIcon(AppIcons.check), findsNothing);
  });

  testWidgets(
      'la feuille « Inviter » liste les autres comptes et invite au serveur',
      (tester) async {
    final requests = <String>[];
    final provider = WatchListsProvider(_server(requests));
    addTearDown(provider.dispose);
    final list = WatchList.fromJson(_list(2, 'custom', 'Mes recos'));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(body: WatchListMembersSheet(list: list)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
    expect(find.byIcon(AppIcons.check), findsNothing);

    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();
    expect(requests, contains('PUT /api/lists/2/members/3'));
    expect(find.byIcon(AppIcons.check), findsOneWidget,
        reason: 'carol est cochée avec les invités que le serveur renvoie');
  });
  testWidgets(
      'la feuille « Partager » invite à voir seulement, puis à ajouter, '
      'puis retire', (tester) async {
    final requests = <String>[];
    final provider = WatchListsProvider(_server(requests, roles: true));
    addTearDown(provider.dispose);
    // Dio répond hors du temps simulé du test : la lecture des capacités
    // passe par du vrai asynchrone.
    await tester.runAsync(provider.load);
    expect(provider.supportsMemberRoles, isTrue);
    final list = WatchList.fromJson(_list(2, 'custom', 'Mes recos'));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(body: WatchListMembersSheet(list: list)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aucun accès'), findsNWidgets(2));

    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peut voir'));
    await tester.pumpAndSettle();
    expect(requests, contains('body {"role":"viewer"}'));
    expect(provider.detail(2)!.members.single.role, WatchListRole.viewer);
    expect(find.text('Peut voir'), findsOneWidget,
        reason: 'la ligne de carol dit son accès, choix repliés');

    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peut ajouter des titres'));
    await tester.pumpAndSettle();
    expect(requests, contains('body {"role":"editor"}'));
    expect(provider.detail(2)!.members.single.role, WatchListRole.editor);

    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aucun accès').last);
    await tester.pumpAndSettle();
    expect(requests, contains('DELETE /api/lists/2/members/3'));
    expect(provider.detail(2)!.members, isEmpty);
  });

  test('un serveur d’avant les rôles reçoit une invitation sans corps',
      () async {
    final requests = <String>[];
    final provider = WatchListsProvider(_server(requests));
    addTearDown(provider.dispose);
    await provider.load();
    expect(provider.supportsMemberRoles, isFalse);
    await provider.addMember(2, 3, role: WatchListRole.viewer);
    expect(requests, contains('body -'),
        reason: 'un rôle ignoré donnerait le droit d’écrire à un invité '
            'qui ne devait que voir');
  });

  test('un invité à voir peut quitter la liste sans pouvoir la remplir', () {
    final list = WatchList.fromJson({
      ..._list(5, 'custom', 'Recos de bob'),
      'is_mine': false,
      'is_member': true,
    });
    expect(list.isMember, isTrue);
    expect(list.canEdit, isFalse);
    final legacy = WatchList.fromJson({
      ..._list(4, 'custom', 'Soirée ciné'),
      'is_mine': false,
      'can_edit': true,
    });
    expect(legacy.isMember, isTrue,
        reason: 'un serveur d’avant les rôles ne dit pas is_member');
  });
}
