import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/shell/shell_header_zone.dart';
import 'package:onyx/screens/shell/shell_tab_stack.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/nav/tv_focusable.dart';
import 'package:onyx/widgets/global/glass_chrome.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:onyx/widgets/global/media_row.dart';
import 'package:provider/provider.dart';

import 'support/tv_nav_harness.dart';

/// Les cartes de navigation de l'accueil et de l'en-tête (plan de refonte
/// §6.3) : « depuis X, telle flèche amène en Y », pour les deux systèmes de
/// navigation tant que le drapeau `ONYX_TV_NAV` existe.
///
/// C'est ce qui attrape les régressions de focus que personne ne remarque au
/// toucher. Le banc assemble les vrais morceaux du shell : la zone de
/// l'en-tête ([ShellHeaderZone]) et ses onglets ([GlassNavTab]), la pile des
/// onglets ([ShellTabStack]) et deux rangées de l'accueil ([MediaRow]). Le
/// Retour du shell (`ShellTvBack`) a sa table à lui, `tv_back_rules_test`.

const _tabs = <String, String>{
  'home': 'Accueil',
  'library:1': 'Films',
  'library:2': 'Séries',
};

Media _movie(int id, String title) => Media(
      id: id,
      type: MediaType.movie,
      title: title,
      duration: 6000,
      createdAt: DateTime(2026),
    );

/// L'en-tête et l'accueil, comme `MainShell` les pose sur un téléviseur.
class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  final ApiClient _api = ApiClient();
  final FocusNode _header = FocusNode(
    debugLabel: 'shell-header',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final Map<String, FocusNode> _tabNodes = {
    for (final tab in _tabs.keys) tab: FocusNode(debugLabel: 'nav-tab-$tab'),
  };

  @override
  void dispose() {
    for (final node in _tabNodes.values) {
      node.dispose();
    }
    _header.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider<ApiClient>.value(
      value: _api,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShellHeaderZone(
              focusNode: _header,
              // Ce que fait `MainShell._headerEntry`.
              entryFor: (landed) =>
                  _tabNodes.values.contains(landed) ? _tabNodes['home'] : null,
              child: Row(
                children: [
                  const SizedBox(width: 28),
                  for (final MapEntry(key: tab, value: label) in _tabs.entries)
                    GlassNavTab(
                      label: label,
                      selected: tab == 'home',
                      focusNode: _tabNodes[tab],
                      onTap: () {},
                    ),
                  const Spacer(),
                  TvFocusable(
                    onSelect: () {},
                    child: const SizedBox(
                      width: 60,
                      height: 40,
                      child: Center(child: Text('Recherche')),
                    ),
                  ),
                  const SizedBox(width: 28),
                ],
              ),
            ),
            Expanded(
              child: ShellTabStack(
                selected: 'home',
                mounted: const {'home'},
                tabs: {
                  'home': SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Le bouton du bandeau, au-dessus des rangées.
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: ElevatedButton(
                            onPressed: () {},
                            child: const Text('Bandeau'),
                          ),
                        ),
                        MediaRow(
                          title: 'Reprendre',
                          items: [
                            for (var i = 0; i < 8; i++)
                              _movie(100 + i, 'Reprendre $i'),
                          ],
                          onItemTap: (_) {},
                        ),
                        MediaRow(
                          title: 'Ajouts',
                          onSeeAll: () {},
                          items: [
                            for (var i = 0; i < 8; i++)
                              _movie(200 + i, 'Ajouts $i'),
                          ],
                          onItemTap: (_) {},
                        ),
                      ],
                    ),
                  ),
                  for (final tab in _tabs.keys.skip(1))
                    tab: const SizedBox.shrink(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ce que la télécommande désigne : l'onglet par son nom, la carte par son
/// titre, la recherche par son texte.
String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (node == null || context == null) return null;
  final tab = context.findAncestorWidgetOfExactType<GlassNavTab>();
  if (tab != null) return tab.label;
  final card = context.findAncestorWidgetOfExactType<MediaCard>();
  if (card != null) return card.media.title;
  return focusedLabelOf(node);
}

/// Pose le focus sur ce que [label] désigne, comme s'il y était arrivé.
Future<void> _focusOn(WidgetTester tester, String label) async {
  final node = FocusManager.instance.rootScope.traversalDescendants.firstWhere(
    (node) => node.context != null && _labelOf(node) == label,
  );
  node.requestFocus();
  await TvNavHarness.settle(tester);
  expect(_focused(), label, reason: 'point de départ');
}

String? _labelOf(FocusNode node) {
  final context = node.context!;
  final tab = context.findAncestorWidgetOfExactType<GlassNavTab>();
  if (tab != null) return tab.label;
  final card = context.findAncestorWidgetOfExactType<MediaCard>();
  if (card != null) return card.media.title;
  return focusedLabelOf(node);
}

const _up = TraversalDirection.up;
const _down = TraversalDirection.down;
const _left = TraversalDirection.left;
const _right = TraversalDirection.right;

/// Une case de la carte : depuis [from], [direction] amène en [to].
typedef _Step = ({String from, TraversalDirection direction, String to});

void main() {
  TvNavHarness.forEachEngine((engine) {
    Future<TvNavHarness> pump(WidgetTester tester) =>
        TvNavHarness.pump(tester, const _Shell(), engine: engine);

    // Une case à la fois, chacune depuis un écran neuf : aucune mémoire ne
    // décide à la place de la géométrie et des entrées de zone.
    const steps = <_Step>[
      // L'en-tête : gauche et droite le parcourent sans en sortir.
      (from: 'Accueil', direction: _right, to: 'Films'),
      (from: 'Films', direction: _left, to: 'Accueil'),
      (from: 'Séries', direction: _right, to: 'Recherche'),
      (from: 'Accueil', direction: _left, to: 'Accueil'),
      // Bas depuis l'onglet affiché entre dans l'accueil par le bandeau.
      (from: 'Accueil', direction: _down, to: 'Bandeau'),
      // Puis dans la première rangée, pas sur « Tout voir » de la suivante :
      // vu au simulateur sous dpad, quand une zone entourait la page entière
      // (constat N6).
      (from: 'Bandeau', direction: _down, to: 'Reprendre 0'),
      (from: 'Reprendre 0', direction: _up, to: 'Bandeau'),
      // Une rangée se parcourt carte à carte, et s'arrête à son bord.
      (from: 'Reprendre 0', direction: _right, to: 'Reprendre 1'),
      (from: 'Reprendre 1', direction: _left, to: 'Reprendre 0'),
      (from: 'Reprendre 0', direction: _left, to: 'Reprendre 0'),
      // D'une rangée à l'autre, à la verticale.
      // Changer de rangée ramène à sa première carte (ADR-0113).
      (from: 'Reprendre 2', direction: _down, to: 'Ajouts 0'),
      (from: 'Ajouts 2', direction: _up, to: 'Reprendre 0'),
      // Haut depuis le bandeau monte sur l'onglet affiché (ADR-0109 pour
      // l'ancien système, entrée de `TvRegion.tabs` sous dpad).
      (from: 'Bandeau', direction: _up, to: 'Accueil'),
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

    // Les mêmes flèches enchaînées : c'est la mémoire des rangées qui décide.
    testWidgets('changer de rangée ramène toujours à sa première carte',
        (tester) async {
      final nav = await pump(tester);
      await _focusOn(tester, 'Bandeau');
      final route = <(TraversalDirection, String)>[
        (_down, 'Reprendre 0'),
        (_right, 'Reprendre 1'),
        (_right, 'Reprendre 2'),
        // La rangée du dessous s'entre par sa première carte, pas par celle
        // qui est juste en dessous (ADR-0113).
        (_down, 'Ajouts 0'),
        (_right, 'Ajouts 1'),
        (_right, 'Ajouts 2'),
        // Celle du dessus aussi, pas par la carte qu'on y avait quittée.
        (_up, 'Reprendre 0'),
        (_down, 'Ajouts 0'),
      ];
      for (final (direction, expected) in route) {
        await nav.press(direction);
        expect(_focused(), expected, reason: '${direction.name} → $expected');
      }
    });
  });
}
