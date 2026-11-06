import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/screens/lists/lists_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';
import 'test_doubles.dart';

/// Les cartes de navigation de l'onglet des listes (plan de refonte §6.3) :
/// « depuis X, telle flèche amène en Y », pour les deux systèmes de navigation
/// tant que le drapeau `ONYX_TV_NAV` existe.
///
/// L'écran est monté en entier : un serveur réduit aux listes (la même
/// doublure que `watch_lists_test.dart`) lui donne neuf listes à soi, qui
/// font deux rangées de la grille, et deux listes partagées.

ResponseBody _json(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, Object?> _list(int id, String name, {bool mine = true}) => {
      'id': id,
      'kind': 'custom',
      'name': name,
      'description': '',
      'is_shared': !mine,
      'is_mine': mine,
      'owner': {'id': mine ? 1 : 2, 'username': mine ? 'alice' : 'bob'},
      'item_count': 0,
      'posters': <String>[],
      'updated_at': '2026-10-19T20:00:00Z',
    };

ApiClient _server() => ApiClient(
      httpClient: Dio()
        ..httpClientAdapter = Adapter((options) {
          return switch (options.uri.path) {
            '/api/ping' => _json({
                'status': 'ok',
                'capabilities': ['watch_lists'],
              }),
            '/api/lists' => _json({
                'mine': [for (var i = 1; i <= 9; i++) _list(i, 'Liste $i')],
                'shared': [
                  _list(21, 'Partage 1', mine: false),
                  _list(22, 'Partage 2', mine: false),
                ],
              }),
            _ => _json({'error': 'unexpected'}),
          };
        }),
    );

const _create = 'Nouvelle liste';

/// Ce que la télécommande désigne : la liste par son nom, le bouton par son
/// texte.
String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? null : focusedLabelOf(node);
}

/// Pose le focus sur ce que [label] désigne, comme s'il y était arrivé.
Future<void> _focusOn(WidgetTester tester, String label) async {
  final node = FocusManager.instance.rootScope.traversalDescendants.firstWhere(
    (node) =>
        node is! FocusScopeNode &&
        node.context != null &&
        focusedLabelOf(node) == label,
    orElse: () => throw StateError('rien ne se nomme « $label »'),
  );
  node.requestFocus();
  await TvNavHarness.settle(tester);
  expect(_focused(), label, reason: 'point de départ');
}

const _up = TraversalDirection.up;
const _down = TraversalDirection.down;
const _left = TraversalDirection.left;
const _right = TraversalDirection.right;

/// Une case de la carte : depuis [from], [direction] amène en [to].
typedef _Step = ({String from, TraversalDirection direction, String to});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  TvNavHarness.forEachEngine((engine) {
    late WatchListsProvider lists;

    Future<TvNavHarness> pump(WidgetTester tester) async {
      final api = _server();
      lists = WatchListsProvider(api);
      addTearDown(lists.dispose);
      await tester.runAsync(lists.load);
      return TvNavHarness.pump(
        tester,
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<WatchListsProvider>.value(value: lists),
          ],
          child: const ListsScreen(),
        ),
        engine: engine,
      );
    }

    testWidgets('à l’ouverture, le focus est sur la première liste',
        (tester) async {
      await pump(tester);
      expect(_focused(), 'Liste 1');
    });

    // Une case à la fois, chacune depuis un écran neuf.
    const steps = <_Step>[
      // La grille se parcourt tuile à tuile, et s'arrête à son bord gauche.
      (from: 'Liste 1', direction: _right, to: 'Liste 2'),
      (from: 'Liste 2', direction: _left, to: 'Liste 1'),
      (from: 'Liste 1', direction: _left, to: 'Liste 1'),
      // Haut depuis la première rangée monte au bouton de l'en-tête.
      (from: 'Liste 1', direction: _up, to: _create),
    ];

    for (final step in steps) {
      testWidgets(
          'depuis « ${step.from} », ${step.direction.name} → « ${step.to} »',
          (tester) async {
        final nav = await pump(tester);
        await _focusOn(tester, step.from);
        await nav.press(step.direction);
        expect(_focused(), step.to);
      });
    }

    // La première rangée tient autant de tuiles que la largeur le permet :
    // les cases de la deuxième rangée se calculent depuis elle.
    testWidgets(
        'bas passe à la rangée du dessous, haut remonte à la tuile '
        'd’où l’on vient', (tester) async {
      final nav = await pump(tester);
      final first = tester.getTopLeft(find.text('Liste 1')).dy;
      final columns = [
        for (var i = 1; i <= 9; i++)
          if (tester.getTopLeft(find.text('Liste $i')).dy == first) i,
      ].length;
      expect(columns, inInclusiveRange(2, 8),
          reason: 'la grille a deux rangées');

      final below = 'Liste ${columns + 1}';
      await nav.press(_down);
      expect(_focused(), below);
      await nav.press(_up);
      expect(_focused(), 'Liste 1');
    });

    // Le bouton est à droite de l'écran, la première tuile à gauche : c'est la
    // mémoire de la grille qui ramène sur la tuile quittée.
    // `testWidgets` n'accepte qu'un booléen : le constat passe dans le nom de
    // la case. Sous dpad, la grille n'est pas une zone (une `TvRegion` ne
    // s'enveloppe pas autour d'un sliver : son `Focus` y pose un nœud de
    // sémantique) ; sans mémoire, Bas depuis le bouton va à la tuile la plus
    // proche de lui. Reste à faire, comme pour les grilles des bibliothèques.
    final lostMemory = engine == TvNavEngine.dpad;
    testWidgets(
        'la tuile quittée par le haut se retrouve en redescendant'
        '${lostMemory ? ' [dpad : bas depuis le bouton tombe sur « Liste 6 », '
            'la tuile la plus proche, pas sur « Liste 1 » quittée]' : ''}',
        skip: lostMemory, (tester) async {
      final nav = await pump(tester);
      await nav.press(_up);
      expect(_focused(), _create);
      await nav.press(_down);
      expect(_focused(), 'Liste 1');
    });

    testWidgets('on parcourt la grille jusqu’aux listes partagées',
        (tester) async {
      final nav = await pump(tester);
      // Descendre jusqu'au bout : la dernière rangée de « Mes listes », puis
      // les listes partagées, sans jamais perdre le focus.
      var steps = 0;
      while (!(_focused() ?? '').startsWith('Partage') && steps < 6) {
        await nav.press(_down);
        expect(_focused(), isNotNull, reason: 'bas n’a pas perdu le focus');
        steps++;
      }
      expect(_focused(), startsWith('Partage'));
      // Et la télécommande revient par le haut, jusqu'au bouton.
      for (var i = 0; i < 6 && _focused() != _create; i++) {
        await nav.press(_up);
      }
      expect(_focused(), _create);
    });
  });
}
