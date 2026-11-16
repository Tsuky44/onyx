import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/watch_list.dart';
import 'package:onyx/providers/watch_lists_provider.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/adaptive_panel.dart';
import 'package:onyx/widgets/global/add_to_list_sheet.dart';
import 'package:onyx/widgets/global/onyx_panel_surface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_doubles.dart';

/// Les feuilles du bas deviennent des panneaux sur grand écran (ADR-0131) :
/// une feuille sur téléphone et sur TV, un panneau collé au bouton au PC.

ResponseBody _json(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, Object?> _list(int id, String name, {int? contains}) => {
      'id': id,
      'kind': 'custom',
      'name': name,
      'description': '',
      'is_shared': false,
      'is_mine': true,
      'owner': {'id': 1, 'username': 'alice'},
      'item_count': 0,
      'posters': <String>[],
      'updated_at': '2026-10-19T20:00:00Z',
      if (contains != null) 'contains_item_id': contains,
    };

/// « Mes recos » a déjà le titre ; « Classiques » non.
ApiClient _server(List<String> requests) {
  final dio = Dio()
    ..httpClientAdapter = Adapter((options) {
      requests.add('${options.method} ${options.uri.path}');
      return switch ((options.method, options.uri.path)) {
        ('GET', '/api/ping') => _json({
            'status': 'ok',
            'capabilities': ['watch_lists'],
          }),
        ('GET', '/api/lists') => _json({
            'mine': [
              _list(1, 'Mes recos', contains: 7),
              _list(2, 'Classiques', contains: 0),
            ],
            'shared': <Object>[],
          }),
        ('POST', '/api/lists/2/items') => _json({
            'id': 41,
            'media_type': 'movie',
            'tmdb_id': 603,
            'title': 'The Matrix',
            'poster_url': '',
            'release_date': '1999-03-31',
            'added_at': '2026-10-19T20:00:00Z',
            'media_id': 0,
          }),
        _ => _json({'error': 'unexpected'}),
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

/// Un bouton en bas à gauche d'un écran de [size], qui lance [open].
Future<void> _mount(
  WidgetTester tester, {
  required Size size,
  required Future<void> Function(BuildContext button) open,
  bool tv = false,
  WatchListsProvider? lists,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  Widget app = TvScope(
    isTv: tv,
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Builder(
            builder: (button) => ElevatedButton(
              onPressed: () => open(button),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  if (lists != null) {
    app = ChangeNotifierProvider.value(value: lists, child: app);
  }
  await tester.pumpWidget(app);
}

/// Les coches visibles : les lignes d'un menu de choix réservent toutes la
/// place d'une coche, transparente tant que la ligne n'est pas cochée.
int _checks(WidgetTester tester) => tester
    .widgetList<Icon>(find.byIcon(AppIcons.check))
    .where((i) => i.color != Colors.transparent)
    .length;

Widget _content(BuildContext _) =>
    const SizedBox(height: 80, child: Text('Contenu'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('showAdaptivePanel', () {
    testWidgets('au téléphone, c’est une feuille du bas', (tester) async {
      await _mount(
        tester,
        size: const Size(400, 800),
        open: (b) => showAdaptivePanel<void>(b, builder: _content),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(OnyxPanelSurface), findsNothing);
      expect(find.text('Contenu'), findsOneWidget);
    });

    testWidgets('au PC, c’est un panneau collé sous le bouton', (tester) async {
      await _mount(
        tester,
        size: const Size(1000, 700),
        open: (b) => showAdaptivePanel<void>(b, builder: _content),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Contenu'), findsOneWidget);
      final button = tester.getRect(find.byType(ElevatedButton));
      final panel = tester.getRect(find.byType(OnyxPanelSurface));
      expect(panel.top, greaterThanOrEqualTo(button.bottom));
      // Le panneau reste à 12 px du bord de l'écran, même sous un bouton collé
      // à gauche.
      expect(panel.left, OnyxMenuPlacement.margin);
      expect(panel.width, 280);
    });

    testWidgets('centré, le panneau ne dépend pas du bouton', (tester) async {
      await _mount(
        tester,
        size: const Size(1000, 700),
        open: (b) => showAdaptivePanel<void>(b,
            centered: true, width: 600, builder: _content),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getCenter(find.byType(OnyxPanelSurface)).dx, 500);
    });

    testWidgets('sur TV, la feuille reste, même en grande largeur',
        (tester) async {
      await _mount(
        tester,
        size: const Size(1920, 1080),
        tv: true,
        open: (b) => showAdaptivePanel<void>(b, builder: _content),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(OnyxPanelSurface), findsNothing);
    });
  });

  group('« Ajouter à une liste » en panneau', () {
    testWidgets(
        'coche les listes qui ont le titre, et un choix part au serveur',
        (tester) async {
      final requests = <String>[];
      final provider = WatchListsProvider(_server(requests));
      addTearDown(provider.dispose);
      await _mount(
        tester,
        size: const Size(1000, 700),
        lists: provider,
        open: (b) => showAddToListSheet(b, ListableTitle.catalog(_matrix)),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('AJOUTER À UNE LISTE'), findsOneWidget);
      expect(find.text('Mes recos'), findsOneWidget);
      expect(find.text('Classiques'), findsOneWidget);
      expect(find.text('Nouvelle liste'), findsOneWidget);
      // Seule la liste qui contient déjà le titre est cochée.
      expect(_checks(tester), 1);

      await tester.tap(find.text('Classiques'));
      await tester.pumpAndSettle();
      expect(requests, contains('POST /api/lists/2/items'));
      expect(_checks(tester), 2);
    });
  });
}
