import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/shell/shell_tv_back.dart';
import 'package:onyx/tv/nav/tv_back.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';

import 'support/tv_nav_harness.dart';

/// « État → effet du Retour », par plateforme et par voie (ADR-0110, phase 5).
///
/// Sous dpad, [TvBack] décide seul, dans cet ordre : ce qui est ouvert se
/// ferme, ce qui est poussé se dépile, le contenu d'un onglet remonte à
/// l'en-tête, et l'en-tête rend Retour au système, **quel que soit
/// l'onglet**. On ne retient jamais Menu à la racine (App Review tvOS).
///
/// Les voies : `popRoute` (Menu/‹ de l'Apple TV, Retour d'Android TV), la
/// touche (Échap d'un clavier ou d'un téléviseur LG, Menu de l'Apple TV s'il
/// arrive en touche, `goBack` d'Android), et les deux pour le même appui :
/// l'Apple TV n'a jamais été essayée sur machine réelle, et [TvBack] doit
/// tenir que Menu arrive d'une façon, de l'autre, ou des deux.

/// Les quatre cibles d'un Retour.
enum _Platform { tvos, android, webos, desktop }

/// Les voies par lesquelles un Retour arrive.
enum _Way {
  popRoute,
  key,

  /// La touche, puis `popRoute`, 20 ms plus tard.
  keyThenPopRoute,

  /// `popRoute`, puis la touche, 20 ms plus tard.
  popRouteThenKey,
}

/// Là où est la télécommande quand Retour arrive.
enum _State {
  /// Un dialogue ouvert sur une fiche.
  dialog,

  /// Une fiche poussée par-dessus la coquille.
  page,

  /// Une carte du contenu de l'onglet d'accueil.
  content,

  /// L'onglet d'accueil, dans l'en-tête.
  headerHome,

  /// Un autre onglet (Films), affiché, dans l'en-tête.
  headerOther,
}

/// Ce que Retour a fait.
enum _Effect {
  /// Le dialogue est fermé, le focus est revenu au bouton qui l'a ouvert.
  closesDialog,

  /// La fiche est dépilée, le focus est revenu à la carte qui l'a ouverte.
  popsPage,

  /// Le focus est sur l'onglet affiché, dans l'en-tête.
  toHeader,

  /// Rendu au système : `SystemNavigator.pop` (voie `popRoute`), touche non
  /// consommée ; rien n'a bougé dans l'app.
  toSystem,

  /// Rien : la touche n'est pas un Retour pour l'app (le `goBack` d'Android,
  /// que le système rejoue en `popRoute`).
  nothing,

  /// Bureau, Échap : le dialogue se ferme (son sens de bureau), une page ne
  /// se dépile pas.
  desktopEscape,
}

const _tabs = <String>['Accueil', 'Films'];

/// Une coquille réduite : un en-tête d'onglets et une rangée de cartes, sous
/// le vrai [ShellTvBack] de `MainShell`.
class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final FocusNode header = FocusNode(
    debugLabel: 'shell-header',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final Map<String, FocusNode> tabs = {
    for (final tab in _tabs) tab: FocusNode(debugLabel: 'tab-$tab'),
  };
  String selected = 'Accueil';

  void select(String tab) => setState(() => selected = tab);

  @override
  void dispose() {
    header.dispose();
    for (final node in tabs.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellTvBack(
      headerNode: header,
      selectedTab: selected,
      homeTab: 'Accueil',
      focusTab: (tab) => tabs[tab]!.requestFocus(),
      selectTab: select,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Focus(
              focusNode: header,
              child: Row(
                children: [
                  for (final tab in _tabs)
                    TvFocusable(
                      focusNode: tabs[tab],
                      onSelect: () => select(tab),
                      child: TvTestTile(tab),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 200),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  TvFocusable(
                    autofocus: i == 0,
                    onSelect: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const _Page()),
                    ),
                    child: TvTestTile('Carte $i'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Fiche'),
          TvFocusable(
            autofocus: true,
            onSelect: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                content: TvFocusable(
                  autofocus: true,
                  onSelect: () {},
                  child: const TvTestTile('Dans le dialogue'),
                ),
              ),
            ),
            child: const TvTestTile('Ouvrir le dialogue'),
          ),
        ],
      ),
    );
  }
}

/// Un cas de la table.
typedef _Case = ({_State state, _Platform platform, _Way way, _Effect effect});

/// La règle sous dpad, sur téléviseur : même effet par toutes les voies.
_Effect _tvRule(_State state) => switch (state) {
      _State.dialog => _Effect.closesDialog,
      _State.page => _Effect.popsPage,
      _State.content => _Effect.toHeader,
      _State.headerHome || _State.headerOther => _Effect.toSystem,
    };

List<_Case> _table() => [
      for (final state in _State.values) ...[
        // tvOS : Menu en popRoute, en touche, ou les deux, dans les deux
        // ordres. Un appui, un effet.
        for (final way in _Way.values)
          (state: state, platform: _Platform.tvos, way: way, effect: _tvRule(state)),
        // Android : Retour arrive en popRoute ; goBack seul ne fait rien
        // (C2), et goBack suivi de popRoute ne défait qu'une couche.
        (state: state, platform: _Platform.android, way: _Way.popRoute, effect: _tvRule(state)),
        (state: state, platform: _Platform.android, way: _Way.key, effect: _Effect.nothing),
        (state: state, platform: _Platform.android, way: _Way.keyThenPopRoute, effect: _tvRule(state)),
        // webOS : le Retour LG est réécrit en Échap, jamais de popRoute.
        (state: state, platform: _Platform.webos, way: _Way.key, effect: _tvRule(state)),
      ],
      // Bureau : TvBack ne décide de rien, Flutter garde son Retour.
      (state: _State.dialog, platform: _Platform.desktop, way: _Way.key, effect: _Effect.desktopEscape),
      (state: _State.page, platform: _Platform.desktop, way: _Way.key, effect: _Effect.desktopEscape),
      (state: _State.page, platform: _Platform.desktop, way: _Way.popRoute, effect: _Effect.popsPage),
    ];

class _Bench {
  _Bench(this.nav, this.platform, this.tester);

  final TvNavHarness nav;
  final _Platform platform;
  final WidgetTester tester;
  int systemPops = 0;

  _ShellState get shell => tester.state<_ShellState>(find.byType(_Shell));

  Future<void> reach(_State state) async {
    if (platform == _Platform.desktop) return _reachByCode(state);
    switch (state) {
      case _State.dialog:
        await reach(_State.page);
        await nav.select();
        await TvNavHarness.settle(tester);
        expect(find.text('Dans le dialogue'), findsOneWidget);
      case _State.page:
        await reach(_State.content);
        await nav.select();
        await tester.pumpAndSettle();
        expect(nav.focusedLabel, 'Ouvrir le dialogue');
      case _State.content:
        await nav.press(TraversalDirection.right);
        expect(nav.focusedLabel, 'Carte 1');
      case _State.headerHome:
        shell.tabs['Accueil']!.requestFocus();
        await TvNavHarness.settle(tester);
      case _State.headerOther:
        shell.select('Films');
        shell.tabs['Films']!.requestFocus();
        await TvNavHarness.settle(tester);
    }
  }

  /// Hors téléviseur, les flèches ne naviguent pas (jeu de touches vide,
  /// constat C3) : la fiche et le dialogue s'ouvrent par le code.
  Future<void> _reachByCode(_State state) async {
    nav.navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const _Page()));
    await tester.pumpAndSettle();
    if (state != _State.dialog) return;
    showDialog<void>(
      context: tester.element(find.text('Fiche')),
      builder: (_) => const AlertDialog(content: Text('Dans le dialogue')),
    );
    await tester.pumpAndSettle();
  }

  LogicalKeyboardKey get _key => switch (platform) {
        _Platform.android => LogicalKeyboardKey.goBack,
        _ => LogicalKeyboardKey.escape,
      };

  /// Envoie le Retour ; rend vrai si la touche a été consommée (nul sans
  /// touche).
  Future<bool?> back(_Way way, void Function(Duration) advance) async {
    bool? keyHandled;
    Future<void> key() async {
      keyHandled = await TvNavHarness.sendKey(tester, _key);
      await TvNavHarness.settle(tester);
    }

    switch (way) {
      case _Way.popRoute:
        await nav.popRoute();
      case _Way.key:
        await key();
      case _Way.keyThenPopRoute:
        await key();
        advance(const Duration(milliseconds: 20));
        await nav.popRoute();
      case _Way.popRouteThenKey:
        await nav.popRoute();
        advance(const Duration(milliseconds: 20));
        await key();
    }
    await tester.pumpAndSettle();
    return keyHandled;
  }
}

void main() {
  var now = Duration.zero;
  setUp(() {
    now = Duration.zero;
    TvBack.debugClock = () => now;
  });
  tearDown(() => TvBack.debugClock = null);

  for (final c in _table()) {
    testWidgets(
        '${c.platform.name}, ${c.state.name}, ${c.way.name} → ${c.effect.name}',
        (tester) async {
      final nav = await TvNavHarness.pump(
        tester,
        const _Shell(),
        isTv: c.platform != _Platform.desktop,
        android: c.platform == _Platform.android,
        browser: c.platform == _Platform.webos,
      );
      final bench = _Bench(nav, c.platform, tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') bench.systemPops++;
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await bench.reach(c.state);
      final before = nav.focusedLabel;
      final keyHandled = await bench.back(c.way, (d) => now += d);

      switch (c.effect) {
        case _Effect.closesDialog:
          expect(find.text('Dans le dialogue'), findsNothing);
          expect(find.text('Fiche'), findsOneWidget);
          expect(nav.focusedLabel, 'Ouvrir le dialogue');
        case _Effect.popsPage:
          expect(find.text('Fiche'), findsNothing);
          if (c.platform != _Platform.desktop) {
            expect(nav.focusedLabel, 'Carte 1');
          }
        case _Effect.toHeader:
          expect(nav.focusedLabel, bench.shell.selected);
          expect(bench.systemPops, 0);
        case _Effect.toSystem:
          expect(nav.focusedLabel, before, reason: 'rien n’a bougé dans l’app');
          expect(find.byType(SnackBar), findsNothing,
              reason: 'pas de « appuyez de nouveau » : Menu n’est pas retenu');
          if (c.way != _Way.key) expect(bench.systemPops, 1);
          if (keyHandled != null) expect(keyHandled, isFalse);
        case _Effect.nothing:
          expect(nav.focusedLabel, before);
          expect(bench.systemPops, 0);
          expect(keyHandled, isFalse,
              reason: 'goBack n’est pas une touche de l’app sur Android (C2)');
          if (c.state == _State.page || c.state == _State.dialog) {
            expect(find.text('Fiche'), findsOneWidget);
          }
          if (c.state == _State.dialog) {
            expect(find.text('Dans le dialogue'), findsOneWidget);
          }
        case _Effect.desktopEscape:
          expect(find.text('Dans le dialogue'), findsNothing);
          expect(find.text('Fiche'), findsOneWidget);
      }
    });
  }

  group('ancien système (sans ONYX_TV_NAV), à l’identique', () {
    testWidgets('depuis le contenu, Retour remonte à l’onglet affiché',
        (tester) async {
      final nav = await TvNavHarness.pump(tester, const _Shell(),
          engine: TvNavEngine.legacy);
      await nav.press(TraversalDirection.right);
      await nav.back();
      expect(nav.focusedLabel, 'Accueil');
    });

    testWidgets('depuis un autre onglet, Retour revient à l’accueil',
        (tester) async {
      final nav = await TvNavHarness.pump(tester, const _Shell(),
          engine: TvNavEngine.legacy);
      final shell = tester.state<_ShellState>(find.byType(_Shell));
      shell.select('Films');
      shell.tabs['Films']!.requestFocus();
      await TvNavHarness.settle(tester);
      await nav.back();
      expect(shell.selected, 'Accueil');
      expect(nav.focusedLabel, 'Accueil');
    });

    testWidgets('sur l’accueil, Retour demande avant de quitter',
        (tester) async {
      final nav = await TvNavHarness.pump(tester, const _Shell(),
          engine: TvNavEngine.legacy);
      tester.state<_ShellState>(find.byType(_Shell)).tabs['Accueil']!
          .requestFocus();
      await TvNavHarness.settle(tester);
      await nav.back();
      expect(find.text('Appuyez de nouveau sur Retour pour quitter'),
          findsOneWidget);
    });
  });
}
