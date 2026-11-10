import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/onyx_dpad.dart';
import 'package:onyx/tv/nav/tv_dpad_focusable.dart';
import 'package:onyx/tv/nav/tv_region.dart';
import 'package:onyx/tv/tv_mode.dart';

import 'support/tv_nav_harness.dart';

/// Une rangée de [count] cartes, `<prefix>0` à `<prefix>N`, dans une zone.
Widget _rail(String id, String prefix, int count, {int? autofocusAt}) {
  return TvRegion.rail(
    entersAtStart: false,
    id: id,
    child: Row(
      children: [
        for (var i = 0; i < count; i++)
          TvDpadFocusable(
            autofocus: i == autofocusAt,
            onSelect: () {},
            child: TvTestTile('$prefix$i'),
          ),
      ],
    ),
  );
}

/// Une page de deux rangées, sous laquelle on peut pousser une autre route.
Widget _page(String title, {int? autofocusAt = 0}) {
  return Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        _rail('$title/r0', '$title r0 c', 5, autofocusAt: autofocusAt),
        _rail('$title/r1', '$title r1 c', 5),
      ],
    ),
  );
}

void main() {
  group('jeu de touches', () {
    test('hors téléviseur, aucune touche ne parle à dpad (C3)', () {
      final keys = OnyxDpad.keySetFor(isTv: false, isAndroid: false);
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.contextMenu,
      ]) {
        expect(keys.directionOf(key), isNull);
        expect(keys.isSelect(key), isFalse);
        expect(keys.isBack(key), isFalse);
        expect(keys.isMenu(key), isFalse);
      }
    });

    test('sur Android, goBack n’est pas une touche de dpad (C2)', () {
      final keys = OnyxDpad.keySetFor(isTv: true, isAndroid: true);
      expect(keys.isBack(LogicalKeyboardKey.goBack), isFalse);
      expect(keys.isBack(LogicalKeyboardKey.escape), isTrue);
      expect(keys.isBack(LogicalKeyboardKey.gameButtonB), isTrue);
    });

    test('ailleurs, goBack et le Retour du navigateur ramènent en arrière', () {
      final keys = OnyxDpad.keySetFor(isTv: true, isAndroid: false);
      expect(keys.isBack(LogicalKeyboardKey.goBack), isTrue);
      expect(keys.isBack(LogicalKeyboardKey.browserBack), isTrue);
      expect(keys.isMenu(LogicalKeyboardKey.gameButtonY), isTrue);
    });
  });

  testWidgets('un Retour Android ne défait qu’une couche : goBack + popRoute',
      (tester) async {
    final nav = await TvNavHarness.pump(tester, _page('A'), android: true);
    nav.navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => _page('B')));
    await TvNavHarness.settle(tester);
    nav.navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => _page('C')));
    await TvNavHarness.settle(tester);
    expect(nav.focusedLabel, 'C r0 c0');

    // Ce qu'Android 16 envoie pour un seul appui : la touche, puis popRoute.
    await TvNavHarness.sendKey(tester, LogicalKeyboardKey.goBack);
    await nav.popRoute();

    expect(find.text('C'), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  group('hors téléviseur (C3)', () {
    testWidgets('aucun focus posé au démarrage', (tester) async {
      final nav = await TvNavHarness.pump(tester, _page('A', autofocusAt: null),
          isTv: false);
      expect(nav.focusedLabel, isNull);
    });

    testWidgets('Tab et les flèches gardent le sens de Flutter',
        (tester) async {
      final nav = await TvNavHarness.pump(tester, _page('A', autofocusAt: null),
          isTv: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await TvNavHarness.settle(tester);
      expect(nav.focusedLabel, 'A r0 c0');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await TvNavHarness.settle(tester);
      expect(nav.focusedLabel, 'A r0 c1');
      await nav.press(TraversalDirection.right);
      expect(nav.focusedLabel, 'A r0 c2');
    });
  });

  testWidgets('basculer le mode TV ne reconstruit pas l’app', (tester) async {
    final nav = await TvNavHarness.pump(tester, const _Counter());
    final state = tester.state<_CounterState>(find.byType(_Counter));
    state.bump();

    TvMode.enabled.value = false;
    await TvNavHarness.settle(tester);
    TvMode.enabled.value = true;
    await TvNavHarness.settle(tester);

    expect(identical(tester.state(find.byType(_Counter)), state), isTrue);
    expect(state.count, 1);
    expect(nav.focusedLabel, isNotNull);
  });

  group('reprise (C14, N1)', () {
    testWidgets('le focus revient dans la route poussée pendant la pause',
        (tester) async {
      final nav = await TvNavHarness.pump(tester, _page('A'));
      await nav.press(TraversalDirection.right);
      await nav.press(TraversalDirection.right);
      expect(nav.focusedLabel, 'A r0 c2');

      await nav.pause(whilePaused: () async {
        nav.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
              builder: (_) => _page('B', autofocusAt: null)),
        );
        await tester.pump();
      });
      await nav.resume();

      expect(nav.focusedLabel, startsWith('B '));
    });

    testWidgets('l’élément d’entrée de la route gagne', (tester) async {
      final nav = await TvNavHarness.pump(tester, _page('A'));
      await nav.pause(whilePaused: () async {
        nav.navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const _EntryPage()),
        );
        await tester.pump();
      });
      await nav.resume();

      expect(nav.focusedLabel, 'entrée');
    });

    testWidgets('sans route poussée, le focus reste où il était',
        (tester) async {
      final nav = await TvNavHarness.pump(tester, _page('A'));
      await nav.press(TraversalDirection.down);
      expect(nav.focusedLabel, 'A r1 c0');

      await nav.pause();
      await nav.resume();

      expect(nav.focusedLabel, 'A r1 c0');
    });
  });

  group('mémoire des zones (C7)', () {
    testWidgets('la clé est rangée sous le profil', (tester) async {
      await TvNavHarness.pump(tester, _page('A'), profileKey: 'srv:alice');
      final region = tester.widget<DpadRegion>(find.byType(DpadRegion).first);
      expect(region.memoryKey, 'srv:alice/A/r0');
    });

    testWidgets('changer de profil vide la mémoire', (tester) async {
      final key = GlobalKey<NavigatorState>();
      Widget app(String profile, {required bool withPage}) => TvNavHarnessApp(
            navigatorKey: key,
            profileKey: profile,
            home: withPage ? const _MemoryPage() : const _Blank(),
          );
      final nav = await TvNavHarness.pump(tester, const _MemoryPage(),
          profileKey: 'srv:alice');
      await nav.press(TraversalDirection.down);
      for (var i = 0; i < 3; i++) {
        await nav.press(TraversalDirection.right);
      }
      expect(nav.focusedLabel, 'c3');

      // L'écran part puis revient pour le même profil : la mémoire de dpad
      // survit à la destruction de la zone, et Bas depuis l'en-tête rend c3.
      await tester.pumpWidget(app('srv:alice', withPage: false));
      await TvNavHarness.settle(tester);
      await tester.pumpWidget(app('srv:alice', withPage: true));
      await TvNavHarness.settle(tester);
      expect(nav.focusedLabel, 'en-tête');
      await nav.press(TraversalDirection.down);
      expect(nav.focusedLabel, 'c3');

      // Un autre profil ouvre le même écran : rien de ce qu'Alice a laissé.
      await tester.pumpWidget(app('srv:alice', withPage: false));
      await TvNavHarness.settle(tester);
      await tester.pumpWidget(app('srv:bob', withPage: false));
      await TvNavHarness.settle(tester);
      await tester.pumpWidget(app('srv:bob', withPage: true));
      await TvNavHarness.settle(tester);
      await nav.press(TraversalDirection.down);
      expect(nav.focusedLabel, 'c0');
    });

    testWidgets('le vidage atteint la table statique de dpad', (tester) async {
      // Une clé qui ne dépend pas du profil : seul le vidage peut alors
      // empêcher la mémoire d'Alice de servir à Bob.
      final key = GlobalKey<NavigatorState>();
      Widget app(String profile, {required bool withPage}) => TvNavHarnessApp(
            navigatorKey: key,
            profileKey: profile,
            home: withPage
                ? const _MemoryPage(rawKey: 'partagée')
                : const _Blank(),
          );
      final nav = await TvNavHarness.pump(
          tester, const _MemoryPage(rawKey: 'partagée'),
          profileKey: 'srv:alice');
      await nav.press(TraversalDirection.down);
      for (var i = 0; i < 3; i++) {
        await nav.press(TraversalDirection.right);
      }
      await tester.pumpWidget(app('srv:alice', withPage: false));
      await TvNavHarness.settle(tester);
      await tester.pumpWidget(app('srv:alice', withPage: true));
      await TvNavHarness.settle(tester);
      await nav.press(TraversalDirection.down);
      expect(nav.focusedLabel, 'c3', reason: 'même profil : la mémoire reste');

      await tester.pumpWidget(app('srv:alice', withPage: false));
      await TvNavHarness.settle(tester);
      await tester.pumpWidget(app('srv:bob', withPage: false));
      await TvNavHarness.settle(tester);
      await tester.pumpWidget(app('srv:bob', withPage: true));
      await TvNavHarness.settle(tester);
      await nav.press(TraversalDirection.down);
      expect(nav.focusedLabel, 'c0');
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) =>
      _rail('counter', 'compte $count c', 2, autofocusAt: 0);
}

class _EntryPage extends StatelessWidget {
  const _EntryPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          TvDpadFocusable(onSelect: () {}, child: const TvTestTile('premier')),
          DpadFocusable(
            entry: true,
            onSelect: () {},
            child: const TvTestTile('entrée'),
          ),
        ],
      ),
    );
  }
}

/// Un en-tête focalisé à l'ouverture, au-dessus d'une rangée : l'entrée dans
/// la rangée se fait toujours depuis l'extérieur, donc par sa mémoire.
class _MemoryPage extends StatelessWidget {
  const _MemoryPage({this.rawKey});

  /// Une clé de mémoire posée telle quelle sur une `DpadRegion`, sans le
  /// préfixe de profil de `TvRegion`.
  final String? rawKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvDpadFocusable(
            autofocus: true,
            onSelect: () {},
            child: const TvTestTile('en-tête'),
          ),
          if (rawKey == null)
            _rail('home/r0', 'c', 6)
          else
            DpadRegion(
              memoryKey: rawKey,
              horizontalEdge: DpadEdgeBehavior.stop,
              child: Row(
                children: [
                  for (var i = 0; i < 6; i++)
                    TvDpadFocusable(
                      onSelect: () {},
                      child: TvTestTile('c$i'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Blank extends StatelessWidget {
  const _Blank();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}
