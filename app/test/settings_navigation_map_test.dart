import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/server_activity.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/screens/settings/settings_screen.dart';
import 'package:onyx/screens/settings/widgets/settings_ui.dart';
import 'package:onyx/services/api_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// La carte de navigation des réglages en grand écran (plan de refonte §6.3) :
/// « depuis X, telle flèche amène en Y », pour les deux systèmes de navigation
/// tant que le drapeau `ONYX_TV_NAV` existe.
///
/// Le banc monte le vrai [SettingsScreen] : une barre de catégories à gauche,
/// la page à droite, chacune dans un `TvRegion.pane`. Ce que la carte attrape :
/// droite depuis une catégorie doit entrer dans la page par son premier
/// réglage, pas par celui qui se trouve à la même hauteur que la catégorie, et
/// gauche doit ramener à la catégorie qu'on a quittée, quelle que soit la
/// hauteur du réglage d'où l'on part.
///
/// Un compte membre, sans droit d'administration : la barre porte « Mon
/// compte », « Lecture », « Cet appareil », « Téléchargements et stockage » et
/// « Serveurs ». La carte reste sur « Lecture » et « Cet appareil » : « Mon
/// compte » relance un sondage qui garde un minuteur après le test, et
/// « Téléchargements et stockage » veut le gestionnaire de téléchargements.
/// Parcourir la barre à la télécommande ouvre ce qu'on survole.

class _FakeApi extends ApiClient {
  @override
  String get baseUrl => 'http://maison.local';

  @override
  Future<User> getMe() async => throw Exception('hors ligne');

  @override
  Future<PlaybackStats> getMyPlaybackStats({int days = 30}) async =>
      PlaybackStats.fromJson({
        'days': 30,
        'totals': {
          'plays': 0,
          'watched_seconds': 0,
          'active_users': 1,
          'movies': 0,
          'episodes': 0,
        },
        'daily': const [],
        'hour_of_day': List.filled(24, 0),
        'top_users': const [],
        'top_media': const [],
        'clients': const [],
        'play_methods': const [],
      });

  @override
  Future<List<ConnectedDevice>> getMyDevices() async => const [];
}

class _FakeAuth extends AuthProvider {
  _FakeAuth(super.api);

  @override
  User? get currentUser =>
      User(id: 1, username: 'mathis', permissions: const Permissions());

  @override
  Permissions get permissions => const Permissions();
}

const _up = TraversalDirection.up;
const _down = TraversalDirection.down;
const _left = TraversalDirection.left;
const _right = TraversalDirection.right;

/// Ce que la télécommande désigne : le titre du réglage qui porte le focus
/// (son menu ou son interrupteur en sont l'intérieur), à défaut le libellé de
/// ce qui le porte, celui d'une catégorie par exemple.
String? _labelOf(FocusNode? node) {
  final context = node?.context;
  if (node == null || context == null || node is FocusScopeNode) return null;
  String? title;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is SettingsTile) {
      title = widget.title;
    } else if (widget is SettingsSwitchTile) {
      title = widget.title;
    } else if (widget.runtimeType.toString().startsWith('SettingsChoiceTile')) {
      title = (widget as dynamic).title as String;
    }
    return title == null;
  });
  return title ?? focusedLabelOf(node);
}

String? _focused() => _labelOf(FocusManager.instance.primaryFocus);

/// Les nœuds qui portent [label] et prennent le focus.
Iterable<FocusNode> _nodesLabelled(String label) =>
    FocusManager.instance.rootScope.traversalDescendants.where(
      (node) =>
          node.context != null &&
          node.canRequestFocus &&
          _labelOf(node) == label,
    );

/// Pose le focus sur [label], comme si la télécommande y était arrivée.
Future<void> _focusOn(WidgetTester tester, String label) async {
  // Un interrupteur a son propre nœud dans la ligne : le point de départ est
  // la ligne entière, la plus large, pas l'interrupteur à son bord.
  final candidates = _nodesLabelled(label).toList()
    ..sort((a, b) => b.rect.width.compareTo(a.rect.width));
  candidates.first.requestFocus();
  await TvNavHarness.settle(tester);
  expect(_focused(), label, reason: 'point de départ');
}

/// Une case de la carte : depuis [from], [direction] amène en [to].
typedef _Step = ({String from, TraversalDirection direction, String to});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  TvNavHarness.forEachEngine((engine) {
    Future<TvNavHarness> pump(WidgetTester tester,
        {String section = SettingsSections.playback}) async {
      final api = _FakeApi();
      await api.initialize();
      final nav = await TvNavHarness.pump(
        tester,
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth(api)),
          ],
          child: SettingsScreen(initialSection: section),
        ),
        engine: engine,
      );
      await tester.pumpAndSettle();
      return nav;
    }

    // Une case à la fois, chacune depuis un écran neuf : aucune mémoire ne
    // décide à la place de la géométrie et des entrées de zone.
    const steps = <_Step>[
      // Haut et bas dans la barre passent de catégorie en catégorie.
      (from: 'Lecture', direction: _down, to: 'Cet appareil'),
      (from: 'Cet appareil', direction: _up, to: 'Lecture'),
      // Droite entre dans la page par son premier réglage, pas par celui qui
      // est à la hauteur de la catégorie.
      (from: 'Lecture', direction: _right, to: 'Langue audio par défaut'),
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

    /// Entre dans la page depuis « Lecture », puis se pose sur [setting],
    /// comme après quelques pas dans la page : on n'arrive jamais dans une
    /// page autrement que par sa catégorie.
    Future<TvNavHarness> fromLecture(
        WidgetTester tester, String setting) async {
      final nav = await pump(tester);
      await _focusOn(tester, 'Lecture');
      await nav.press(_right);
      await _focusOn(tester, setting);
      return nav;
    }

    // Gauche depuis la page rend la catégorie quittée, quelle que soit la
    // hauteur du réglage : pas le champ de recherche en haut de la barre, ni
    // la catégorie à la même hauteur.
    for (final setting in [
      'Langue audio par défaut',
      'Passer le récap automatiquement',
    ]) {
      testWidgets('depuis « $setting », left → « Lecture »', (tester) async {
        final nav = await fromLecture(tester, setting);
        await nav.press(_left);
        expect(_focused(), 'Lecture');
      });
    }

    testWidgets(
        'un aller-retour par la droite ramène au réglage qu’on regardait',
        (tester) async {
      final nav = await fromLecture(tester, 'Passer le récap automatiquement');

      await nav.press(_left);
      expect(_focused(), 'Lecture');
      await nav.press(_right);
      expect(_focused(), 'Passer le récap automatiquement',
          reason: 'la page rend le réglage où l’on était, pas son premier');
    });

    // Haut et bas ne quittent jamais un volet. Le parcours de Flutter cherche
    // dans tout l'écran : en bas d'une page courte, Bas tombait sur une
    // catégorie de la liste, plus bas à gauche, qui s'ouvrait aussitôt. On
    // descendait dans un menu et l'on se retrouvait dans un autre. À la
    // taille d'une page de téléviseur, où la liste descend plus bas que la
    // page.
    Future<TvNavHarness> onTvPage(WidgetTester tester) async {
      final nav = await pump(tester);
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      return nav;
    }

    bool inPage() =>
        (FocusManager.instance.primaryFocus?.rect.left ?? 0) > 260;

    testWidgets('en bas d’une page, bas reste dans la page', (tester) async {
      final nav = await onTvPage(tester);
      await _focusOn(tester, 'Serveurs');
      await nav.press(_right);
      expect(inPage(), isTrue, reason: 'point de départ');

      String? last;
      for (var i = 0; i < 6; i++) {
        await nav.press(_down);
        expect(inPage(), isTrue,
            reason: 'bas n° ${i + 1} a quitté la page pour « ${_focused()} »');
        last = _focused();
      }
      expect(last, 'Ajouter un serveur');
    });

    testWidgets('en haut d’une page, haut reste dans la page', (tester) async {
      final nav = await onTvPage(tester);
      await _focusOn(tester, 'Cet appareil');
      await nav.press(_right);
      final first = _focused();

      for (var i = 0; i < 3; i++) {
        await nav.press(_up);
        expect(inPage(), isTrue);
      }
      expect(_focused(), first);
    });

    testWidgets('au bout de la liste, bas reste sur la dernière catégorie',
        (tester) async {
      final nav = await onTvPage(tester);
      await _focusOn(tester, 'Serveurs');

      for (var i = 0; i < 3; i++) {
        await nav.press(_down);
      }
      expect(inPage(), isFalse);
      expect(_focused(), 'Serveurs');
    });

    // Les mêmes flèches enchaînées : c'est la mémoire des deux zones qui
    // décide, et la page affichée suit la catégorie survolée.
    testWidgets('on change de catégorie, on entre dans sa page, on en revient',
        (tester) async {
      final nav = await pump(tester);
      await _focusOn(tester, 'Lecture');
      final route = <(TraversalDirection, String)>[
        (_down, 'Cet appareil'),
        (_right, 'Mode télécommande'),
        (_left, 'Cet appareil'),
        (_up, 'Lecture'),
        (_right, 'Langue audio par défaut'),
        (_left, 'Lecture'),
      ];
      for (final (direction, expected) in route) {
        await nav.press(direction);
        expect(_focused(), expected, reason: '${direction.name} → $expected');
      }
    });
  });
}
