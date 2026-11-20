import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/watch_list.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/lists/lists_screen.dart';
import 'package:onyx/screens/lists/widgets/list_progress.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_doubles.dart';

/// La vue d'ensemble des listes en grande fenêtre (ADR-0159) : la progression
/// vient du serveur, la vue large la montre, le téléphone garde ses vignettes.

ResponseBody _json(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, Object?> _list(
  int id,
  String kind,
  String name, {
  int count = 0,
  int? watched,
  int? onServer,
  Map<String, Object?>? next,
  bool mine = true,
  bool shared = false,
}) =>
    {
      'id': id,
      'kind': kind,
      'name': name,
      'description': '',
      'is_shared': shared,
      'is_mine': mine,
      'owner': {'id': mine ? 1 : 2, 'username': mine ? 'alice' : 'bob'},
      'item_count': count,
      'posters': <String>[],
      'updated_at': '2026-10-19T20:00:00Z',
      if (watched != null) 'watched_count': watched,
      if (onServer != null) 'on_server_count': onServer,
      if (next != null) 'next_item': next,
    };

const _next = {
  'id': 7,
  'media_id': 70,
  'media_type': 'movie',
  'title': 'Heat',
  'poster_url': '',
  'release_date': '1995-12-15',
};

ApiClient _server({bool withShared = true}) => ApiClient(
      httpClient: Dio()
        ..httpClientAdapter = Adapter((options) {
          return switch (options.uri.path) {
            '/api/ping' => _json({
                'status': 'ok',
                'capabilities': ['watch_lists'],
              }),
            '/api/lists' => _json({
                'mine': [
                  _list(1, 'watch_later', 'À regarder plus tard',
                      count: 5, watched: 2, onServer: 4, next: _next),
                  _list(2, 'custom', 'Films de Noël',
                      count: 4,
                      watched: 1,
                      onServer: 4,
                      next: {
                        ..._next,
                        'title': 'Maman, j’ai raté l’avion',
                      }),
                  _list(3, 'custom', 'À commander',
                      count: 3, watched: 0, onServer: 0, shared: true),
                  _list(4, 'custom', 'Pas commencée',
                      count: 6, watched: 0, onServer: 6, next: _next),
                ],
                'shared': [
                  if (withShared)
                    _list(21, 'custom', 'Les classiques',
                        count: 3,
                        watched: 1,
                        onServer: 3,
                        mine: false,
                        shared: true),
                ],
              }),
            _ => _json({'error': 'unexpected'}),
          };
        }),
    );

Future<void> _pumpScreen(WidgetTester tester,
    {required Size size, bool withShared = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _server(withShared: withShared);
  final lists = WatchListsProvider(api);
  addTearDown(lists.dispose);
  await tester.runAsync(lists.load);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<WatchListsProvider>.value(value: lists),
    ],
    child: const MaterialApp(home: ListsScreen()),
  ));
  await tester.pump();
}

WatchList _fromJson(Map<String, Object?> json) => WatchList.fromJson(json);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('la progression d’une liste', () {
    test('« vus » est ce que le serveur dit, sur le nombre de titres', () {
      final list = _fromJson(
          _list(2, 'custom', 'Noël', count: 8, watched: 2, onServer: 6));
      expect(list.hasProgress, isTrue);
      expect(list.watchedFraction, 0.25);
      expect(list.toRequestCount, 2);
    });

    test('un serveur d’avant l’ADR-0159 ne donne pas de progression', () {
      final list = _fromJson(_list(2, 'custom', 'Noël', count: 8));
      expect(list.hasProgress, isFalse);
      expect(list.watchedFraction, 0);
      expect(list.toRequestCount, 0);
      expect(list.nextItem, isNull);
    });

    test('une liste vide ne divise pas par zéro', () {
      final list = _fromJson(
          _list(2, 'custom', 'Vide', count: 0, watched: 0, onServer: 0));
      expect(list.watchedFraction, 0);
    });

    test('le prochain titre se lit tel que le serveur le donne', () {
      final list = _fromJson(_list(1, 'watch_later', 'x',
          count: 5, watched: 2, onServer: 4, next: _next));
      expect(list.nextItem!.mediaId, 70);
      expect(list.nextItem!.mediaType, WatchListMediaType.movie);
      expect(list.nextItem!.year, '1995');
    });

    test(
        'la ligne d’une carte dit le vu, le prochain, ou ce qu’il faut '
        'demander', () {
      ({String text, bool warn}) line(Map<String, Object?> json) =>
          watchListProgressLine(_fromJson(json));
      expect(
        line(_list(2, 'custom', 'a',
                count: 4, watched: 1, onServer: 4, next: _next))
            .text,
        '1 vu sur 4 · prochain : Heat',
      );
      expect(
        line(_list(2, 'custom', 'a', count: 3, watched: 0, onServer: 0)),
        (text: '3 à demander', warn: true),
      );
      expect(
        line(_list(2, 'custom', 'a',
            count: 6, watched: 0, onServer: 6, next: _next)),
        (text: 'Rien de vu sur 6', warn: false),
      );
      // Tout ce que le serveur a est vu, il reste à demander.
      expect(
        line(_list(2, 'custom', 'a', count: 5, watched: 3, onServer: 3)),
        (text: '3 vus sur 5 · 2 à demander', warn: true),
      );
      expect(
        line(_list(2, 'custom', 'a', count: 3, watched: 3, onServer: 3)),
        (text: '3 vus sur 3', warn: false),
      );
    });
  });

  group('la vue large', () {
    testWidgets(
        'l’encart « À regarder plus tard » dit où l’on en est et ce '
        'qui vient', (tester) async {
      await _pumpScreen(tester, size: const Size(1400, 1100));

      expect(find.text('Prochain à regarder'), findsOneWidget);
      expect(find.textContaining('2 vus sur 5'), findsOneWidget);
      expect(find.textContaining('4 sur le serveur'), findsOneWidget);
      expect(find.textContaining('1 à demander'), findsOneWidget);
      expect(find.text('Heat'), findsOneWidget);
      expect(find.text('1995 · Film'), findsOneWidget);
      expect(find.text('Lire'), findsOneWidget);
      expect(find.text('Ouvrir la liste'), findsOneWidget);

      // Ce qu'il reste à demander est en `warning`, le reste ne l'est pas.
      final rich = tester.widget<RichText>(find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText().contains('4 sur le serveur')));
      final warned = <String>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.style?.color == AppColors.warning) {
          warned.add(span.text ?? '');
        }
        return true;
      });
      expect(warned, [' · 1 à demander']);
    });

    testWidgets('« Mes listes » met chaque liste en carte, sans « plus tard »',
        (tester) async {
      await _pumpScreen(tester, size: const Size(1400, 1100));

      expect(find.text('Mes listes · 3'), findsOneWidget);
      expect(find.text('1 vu sur 4 · prochain : Maman, j’ai raté l’avion'),
          findsOneWidget);
      expect(find.text('3 à demander'), findsOneWidget);
      expect(find.text('Rien de vu sur 6'), findsOneWidget);
      // L'encart tient « plus tard » : pas de carte du même nom en plus.
      expect(find.text('À regarder plus tard'), findsOneWidget);
      // Trois colonnes : les trois cartes sont sur la même rangée.
      final tops = [
        for (final name in ['Films de Noël', 'À commander', 'Pas commencée'])
          tester.getTopLeft(find.text(name)).dy,
      ];
      expect(tops.toSet(), hasLength(1));
    });

    testWidgets(
        'une liste partagée montre son propriétaire et le nombre de '
        'titres', (tester) async {
      await _pumpScreen(tester, size: const Size(1400, 1100));

      expect(find.text('Partagées par les autres · 1'), findsOneWidget);
      expect(find.text('Les classiques'), findsOneWidget);
      expect(find.text('bob · 3 titres'), findsOneWidget);
    });

    testWidgets('sans liste partagée, un cadre dit où elles apparaîtront',
        (tester) async {
      await _pumpScreen(tester,
          size: const Size(1400, 1100), withShared: false);

      expect(find.text('Partagées par les autres · 0'), findsOneWidget);
      expect(find.text('Personne n’a encore partagé de liste sur ce serveur.'),
          findsOneWidget);
      expect(
          find.text('Quand un autre compte partagera une liste, elle '
              'apparaîtra ici.'),
          findsOneWidget);
    });

    testWidgets('le tri « Nom » range les cartes par ordre alphabétique',
        (tester) async {
      await _pumpScreen(tester, size: const Size(1400, 1100));

      await tester.tap(find.text('Récentes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nom').last);
      await tester.pumpAndSettle();

      final order = [
        for (final name in ['Films de Noël', 'À commander', 'Pas commencée'])
          (name, tester.getTopLeft(find.text(name)).dx),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      expect([for (final e in order) e.$1],
          ['À commander', 'Films de Noël', 'Pas commencée']);
    });
  });

  group('le téléphone', () {
    testWidgets('garde les vignettes d’avant : ni encart, ni barre',
        (tester) async {
      await _pumpScreen(tester, size: const Size(420, 900));

      expect(find.text('Prochain à regarder'), findsNothing);
      expect(find.text('Mes listes'), findsOneWidget);
      expect(find.text('Partagées par les autres'), findsOneWidget);
      expect(find.text('Films de Noël'), findsOneWidget);
      expect(find.text('Ouvrir la liste'), findsNothing);
    });
  });
}
