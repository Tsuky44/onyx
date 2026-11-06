import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/detail_actions.dart';
import 'package:onyx/widgets/global/episode_tile.dart';
import 'package:onyx/widgets/global/season_bubbles.dart';

import 'package:provider/provider.dart';

import 'package:onyx/tv/nav/tv_nav_engine.dart';

import 'support/tv_nav_harness.dart';

/// Les cartes de navigation de la fiche d'une série (plan de refonte §6.3) :
/// « depuis X, telle flèche amène en Y », pour les deux systèmes de navigation
/// tant que le drapeau `ONYX_TV_NAV` existe.
///
/// Le banc assemble les vrais morceaux que `ShowDetailScreen` pose sur un
/// téléviseur, dans la même colonne défilante : les actions ([DetailActions],
/// « Lecture » en `autofocusPlay`), les bulles de saisons ([SeasonBubbleRow],
/// ce que `SeasonTabs` enveloppe) et les épisodes ([EpisodeTile]). L'écran
/// entier demande un `LibraryProvider`, l'API et le réseau : il n'apporterait
/// rien de plus à la carte du focus. Les boutons secondaires de l'écran
/// (liste, partage, menu) sont remplacés par des `IconButton` de même forme,
/// car les vrais lisent des fournisseurs.

const _play = 'Lecture';

HomeMediaItem _episode(int n) => HomeMediaItem(
      media: Media(
        id: n,
        type: MediaType.episode,
        title: 'Épisode $n',
        duration: 2400,
        createdAt: DateTime(2026),
      ),
      currentPositionSeconds: 0,
      isFinished: false,
      duration: 2400,
    );

class _Detail extends StatefulWidget {
  const _Detail();

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  final _list = FocusNode(debugLabel: 'Liste');
  final _share = FocusNode(debugLabel: 'Partage');
  int _season = 1;

  @override
  void dispose() {
    _list.dispose();
    _share.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(48),
              child: DetailActions(
                playLabel: _play,
                onPlay: () {},
                autofocusPlay: TvMode.isTv,
                secondary: [
                  IconButton(
                    focusNode: _list,
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    focusNode: _share,
                    onPressed: () {},
                    icon: const Icon(Icons.share),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: SeasonBubbleRow(
                selected: _season,
                onTap: (id) => setState(() => _season = id),
                entries: [
                  for (var s = 1; s <= 3; s++)
                    SeasonBubbleEntry(
                      id: s,
                      code: 'S$s',
                      title: 'Saison $s',
                      detail: '8 épisodes',
                      semanticLabel: 'Saison $s',
                    ),
                ],
              ),
            ),
            for (var n = 1; n <= 4; n++)
              EpisodeTile(
                episode: _episode(n),
                episodeNumber: n,
                allowDownload: false,
                onTap: () {},
                onToggleWatched: (_) async {},
              ),
          ],
        ),
      ),
    );
  }
}

/// Ce que la télécommande désigne : « Lecture », « Saison 2 »,
/// « Épisode 3 » pour sa ligne, « Épisode 3 (icônes) » pour l'une de ses
/// icônes.
String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? null : _labelOf(node);
}

String? _labelOf(FocusNode node) {
  final context = node.context;
  if (context == null) return null;
  final tile = context.findAncestorWidgetOfExactType<EpisodeTile>();
  if (tile != null) {
    final title = tile.episode.media.title;
    return node.debugLabel == 'episode-row' ? title : '$title (icônes)';
  }
  final semantics = context.findAncestorWidgetOfExactType<Semantics>();
  final bubble = semantics?.properties.label;
  if (bubble != null && bubble.startsWith('Saison')) return bubble;
  return focusedLabelOf(node);
}

/// Pose le focus sur ce que [label] désigne, comme s'il y était arrivé.
Future<void> _focusOn(WidgetTester tester, String label) async {
  final node = FocusManager.instance.rootScope.traversalDescendants.firstWhere(
    (node) =>
        node is! FocusScopeNode &&
        node.context != null &&
        _labelOf(node) == label,
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
  TvNavHarness.forEachEngine((engine) {
    // Les fournisseurs que les affiches et le bouton de partage des épisodes
    // lisent.
    Future<TvNavHarness> pump(WidgetTester tester) {
      final api = ApiClient();
      final auth = AuthProvider(api);
      addTearDown(auth.dispose);
      return TvNavHarness.pump(
        tester,
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: const _Detail(),
        ),
        engine: engine,
      );
    }

    testWidgets('à l’ouverture, le focus est sur « Lecture »', (tester) async {
      await pump(tester);
      expect(_focused(), _play);
    });

    // Une case à la fois, chacune depuis un écran neuf : aucune mémoire ne
    // décide à la place de la géométrie et des entrées de zone.
    const steps = <_Step>[
      // Les actions se parcourent de gauche à droite, et s'arrêtent au bord.
      (from: _play, direction: _right, to: 'Liste'),
      (from: 'Liste', direction: _right, to: 'Partage'),
      (from: 'Liste', direction: _left, to: _play),
      (from: _play, direction: _left, to: _play),
      (from: 'Partage', direction: _right, to: 'Partage'),
      // Bas depuis les actions entre dans les saisons.
      (from: _play, direction: _down, to: 'Saison 1'),
      // Les bulles se parcourent une à une, et s'arrêtent à leur bord.
      (from: 'Saison 1', direction: _right, to: 'Saison 2'),
      (from: 'Saison 2', direction: _left, to: 'Saison 1'),
      (from: 'Saison 1', direction: _left, to: 'Saison 1'),
      (from: 'Saison 3', direction: _right, to: 'Saison 3'),
      // Les saisons ouvrent la liste des épisodes par le premier.
      (from: 'Saison 1', direction: _down, to: 'Épisode 1'),
      // Les épisodes se parcourent de ligne en ligne, sans s'arrêter sur
      // leurs icônes.
      (from: 'Épisode 1', direction: _down, to: 'Épisode 2'),
      (from: 'Épisode 3', direction: _up, to: 'Épisode 2'),
      (from: 'Épisode 4', direction: _down, to: 'Épisode 4'),
      // Droite entre dans les icônes de la ligne, gauche en ressort.
      (from: 'Épisode 2', direction: _right, to: 'Épisode 2 (icônes)'),
      (from: 'Épisode 2 (icônes)', direction: _left, to: 'Épisode 2'),
      // Haut et bas depuis une icône passent à la ligne voisine.
      (from: 'Épisode 2 (icônes)', direction: _down, to: 'Épisode 3'),
    ];

    for (final step in steps) {
      testWidgets(
          'depuis « ${step.from} », ${step.direction.name} → « ${step.to} »',
          (tester) async {
        final nav = await pump(tester);
        const icons = ' (icônes)';
        if (step.from.endsWith(icons)) {
          // Les icônes sont hors du parcours directionnel : on n'y arrive que
          // par la droite depuis la ligne, comme à la télécommande.
          await _focusOn(
              tester, step.from.substring(0, step.from.length - icons.length));
          await nav.press(_right);
          expect(_focused(), step.from, reason: 'point de départ');
        } else {
          await _focusOn(tester, step.from);
        }
        await nav.press(step.direction);
        expect(_focused(), step.to);
      });
    }

    // Depuis une action plus à droite, on entre sur la saison affichée, pas
    // sur la bulle qui se trouve dessous (vu au simulateur : la saison 8 sous
    // « Ajouter à une liste »). Sous dpad seulement : la bulle choisie est
    // l'entrée de sa zone. L'ancien système, comme sur `main`, prend la plus
    // proche.
    if (engine == TvNavEngine.dpad) {
      testWidgets('depuis « Partage », down → la saison affichée',
          (tester) async {
        final nav = await pump(tester);
        await _focusOn(tester, 'Partage');
        await nav.press(_down);
        expect(_focused(), 'Saison 1');
      });
    }

    // Les mêmes flèches enchaînées : c'est la mémoire des saisons qui décide.
    testWidgets('les saisons quittées se retrouvent sur la bulle où l’on était',
        (tester) async {
      final nav = await pump(tester);
      final route = <(TraversalDirection, String)>[
        (_down, 'Saison 1'),
        (_right, 'Saison 2'),
        (_right, 'Saison 3'),
        (_down, 'Épisode 1'),
        (_down, 'Épisode 2'),
        (_up, 'Épisode 1'),
        // Les saisons rendent la bulle quittée, pas la plus proche.
        (_up, 'Saison 3'),
        // Redescendre mène au premier épisode.
        (_down, 'Épisode 1'),
      ];
      for (final (direction, expected) in route) {
        await nav.press(direction);
        expect(_focused(), expected, reason: '${direction.name} → $expected');
      }
    });
  });
}
