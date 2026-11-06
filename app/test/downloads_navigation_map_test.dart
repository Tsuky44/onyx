import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/downloads/downloads_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/download_manager.dart';
import 'package:onyx/services/server_reachability.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'support/tv_nav_harness.dart';

/// Les cartes de navigation de l'écran des téléchargements (plan de refonte
/// §6.3) : « depuis X, telle flèche amène en Y », pour les deux systèmes de
/// navigation tant que le drapeau `ONYX_TV_NAV` existe.
///
/// L'écran est monté en entier, sur le vrai [DownloadManager] : son
/// constructeur est privé, on ne peut pas le doubler, alors on lui fait relire
/// un manifeste jetable (comme `download_manager_test.dart`). Trois films
/// terminés, donc trois lignes jouables, chacune avec son menu (`_RowActions`,
/// un `PopupMenuButton`).

/// Un client pointé sur le serveur d'où viennent les médias du manifeste : la
/// liste des téléchargements est celle du serveur actif.
class _ApiAtNas extends ApiClient {
  @override
  String get baseUrl => 'http://nas:8080';
}

/// Pointe le stockage applicatif vers un dossier jetable.
class _TempSupportDirectory extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempSupportDirectory(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Map<String, dynamic> _movie(int id, String title) => {
      'media_id': id,
      'type': 'movie',
      'title': title,
      'file_name': 'video.mkv',
      // Du plus récent au plus ancien : c'est l'ordre de l'écran.
      'added_at': '2026-09-0${10 - id}T12:00:00.000Z',
      'server_url': 'http://nas:8080',
      'duration': 6000,
      'status': 'completed',
      'bytes_received': 1000,
      'bytes_total': 1000,
      'needs_sync': false,
    };

/// Ce que la télécommande désigne : une ligne par son titre, son menu par
/// « menu » et son rang.
String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? null : _labelOf(node);
}

String? _labelOf(FocusNode node) {
  final context = node.context;
  if (context == null) return null;
  final menu = context.findAncestorWidgetOfExactType<PopupMenuButton<String>>();
  if (menu != null) {
    final menus = find
        .byType(PopupMenuButton<String>)
        .evaluate()
        .map((e) => e.widget)
        .toList();
    return 'menu ${menus.indexOf(menu)}';
  }
  return focusedLabelOf(node);
}

/// Pose le focus sur ce que [label] désigne, comme s'il y était arrivé.
///
/// Sous dpad, le menu d'une ligne n'est pas dans le parcours directionnel (il
/// ne s'atteint que par Droite, `TvFocusable.childFocus`) : on le cherche
/// parmi tous les nœuds focalisables.
Future<void> _focusOn(WidgetTester tester, String label) async {
  bool named(FocusNode node) =>
      node is! FocusScopeNode &&
      node.canRequestFocus &&
      node.context != null &&
      _labelOf(node) == label;
  final scope = FocusManager.instance.rootScope;
  // Ce que le parcours voit d'abord (la carte, pas l'`InkWell` qu'elle
  // contient), puis le reste.
  final node = scope.traversalDescendants.where(named).firstOrNull ??
      scope.descendants.where(named).firstOrNull;
  if (node == null) throw StateError('rien ne se nomme « $label »');
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

/// Les cases que l'ancien système ne tient pas : son parcours s'arrête sur le
/// menu de la ligne suivante. C'est le comportement de `main`, que la refonte
/// ne change pas tant que le drapeau `ONYX_TV_NAV` vaut `legacy` ; sous dpad,
/// les menus sont hors du parcours (`TvFocusable.childFocus`).
const _skips = <TvNavEngine, Map<String, String>>{
  TvNavEngine.legacy: {
    'Film A|down': 'legacy, comme sur main : bas depuis une ligne tombe sur le menu de la '
        'ligne suivante (« menu 1 »), pas sur la ligne',
    'Film B|down': 'legacy, comme sur main : bas depuis une ligne tombe sur le menu de la '
        'ligne suivante (« menu 2 »), pas sur la ligne',
    'menu 1|down': 'legacy, comme sur main : bas depuis un menu va au menu de la ligne '
        'suivante (« menu 2 »), pas à la ligne',
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('onyx_downloads_nav_test');
    PathProviderPlatform.instance = _TempSupportDirectory(root.path);
    final store = Directory('${root.path}/onyx_offline')
      ..createSync(recursive: true);
    File('${store.path}/manifest.json').writeAsStringSync(jsonEncode({
      'version': 1,
      'items': [
        _movie(1, 'Film A'),
        _movie(2, 'Film B'),
        _movie(3, 'Film C'),
      ],
    }));
    await DownloadManager.instance.initialize(_ApiAtNas());
  });

  tearDownAll(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // Laissé au système : c'est un dossier temporaire.
    }
  });

  TvNavHarness.forEachEngine((engine) {
    Future<TvNavHarness> pump(WidgetTester tester) {
      final api = _ApiAtNas();
      final reachability = ServerReachability(api);
      addTearDown(reachability.dispose);
      return TvNavHarness.pump(
        tester,
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<DownloadManager>.value(
                value: DownloadManager.instance),
            ChangeNotifierProvider<ServerReachability>.value(
                value: reachability),
          ],
          child: const DownloadsScreen(),
        ),
        engine: engine,
      );
    }

    // Une case à la fois, chacune depuis un écran neuf.
    const steps = <_Step>[
      // Les lignes se parcourent de haut en bas.
      (from: 'Film A', direction: _down, to: 'Film B'),
      (from: 'Film B', direction: _down, to: 'Film C'),
      (from: 'Film C', direction: _up, to: 'Film B'),
      (from: 'Film C', direction: _down, to: 'Film C'),
      // Droite entre dans le menu de la ligne, gauche en ressort.
      (from: 'Film A', direction: _right, to: 'menu 0'),
      (from: 'Film B', direction: _right, to: 'menu 1'),
      (from: 'menu 1', direction: _left, to: 'Film B'),
      // Le menu s'arrête au bord de la ligne.
      (from: 'menu 1', direction: _right, to: 'menu 1'),
      // Haut et bas depuis un menu passent à la ligne voisine.
      (from: 'menu 1', direction: _down, to: 'Film C'),
      (from: 'menu 1', direction: _up, to: 'Film A'),
    ];

    for (final step in steps) {
      // `testWidgets` n'accepte qu'un booléen : le constat de la phase 3 passe
      // dans le nom de la case.
      final skip = _skips[engine]?['${step.from}|${step.direction.name}'];
      testWidgets(
          'depuis « ${step.from} », ${step.direction.name} → « ${step.to} »'
          '${skip == null ? '' : ' [$skip]'}',
          skip: skip != null, (tester) async {
        final nav = await pump(tester);
        await _focusOn(tester, step.from);
        await nav.press(step.direction);
        expect(_focused(), step.to);
      });
    }

    testWidgets('l’écran compte trois lignes jouables et trois menus',
        (tester) async {
      await pump(tester);
      expect(find.byType(PopupMenuButton<String>), findsNWidgets(3));
      expect(find.text('Film A'), findsOneWidget);
    });

    // Les mêmes flèches enchaînées.
    testWidgets(
        'on descend les lignes, entre dans un menu et on en ressort'
        '${engine == TvNavEngine.legacy ? ' [legacy : bute sur les cases sautées ci-dessus]' : ''}',
        skip: engine == TvNavEngine.legacy, (tester) async {
      final nav = await pump(tester);
      await _focusOn(tester, 'Film A');
      final route = <(TraversalDirection, String)>[
        (_down, 'Film B'),
        (_right, 'menu 1'),
        (_left, 'Film B'),
        (_down, 'Film C'),
        (_up, 'Film B'),
        (_up, 'Film A'),
      ];
      for (final (direction, expected) in route) {
        await nav.press(direction);
        expect(_focused(), expected, reason: '${direction.name} → $expected');
      }
    });
  });
}
