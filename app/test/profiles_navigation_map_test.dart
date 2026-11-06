import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/server_account.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/screens/auth/avatar_picker_screen.dart';
import 'package:onyx/screens/auth/user_choice_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/tv_nav_harness.dart';

/// Les cartes de navigation du choix du profil et du sélecteur d'avatar (plan
/// de refonte §6.3) : « depuis X, telle flèche amène en Y », pour les deux
/// systèmes de navigation tant que le drapeau `ONYX_TV_NAV` existe.
///
/// Les deux écrans sont montés en entier. Le choix du profil lit un
/// [AuthProvider] dont le carnet de comptes porte quatre personnes sur un même
/// serveur (c'est ce qui fait demander « Qui regarde ? » au lancement) ; le
/// sélecteur d'avatar ne lit rien d'autre que l'[ApiClient] pour enregistrer.
///
/// Ce que la télécommande désigne est lu sur la `Semantics` de la tuile
/// (« Regarder en tant que lea », « Avatar 3 ») : c'est le nom que lui donne
/// un lecteur d'écran, et il ne dépend pas de la mise en page.

const _users = ['alice', 'bob', 'carole', 'dave'];
const _add = 'Ajouter un utilisateur';
const _manage = 'Gérer les profils';

String _as(String user) => 'Regarder en tant que $user';

/// Le libellé de la plus proche `Semantics` nommée au-dessus de [node], ou son
/// texte à défaut (le bouton « Gérer les profils »).
String? _labelOf(FocusNode node) {
  final context = node.context;
  if (context == null) return null;
  String? label;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Semantics && widget.properties.label != null) {
      label = widget.properties.label;
      return false;
    }
    return true;
  });
  return label ?? focusedLabelOf(node);
}

String? _focused() {
  final node = FocusManager.instance.primaryFocus;
  return node == null ? null : _labelOf(node);
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  TvNavHarness.forEachEngine((engine) {
    group('choix du profil', () {
      Future<TvNavHarness> pump(WidgetTester tester) async {
        final api = ApiClient();
        await tester.runAsync(() async {
          await api.initialize();
          for (final user in _users) {
            await api.rememberSession(
              serverUrl: 'http://maison.local',
              username: user,
              token: 'jeton-$user',
              userId: _users.indexOf(user) + 1,
            );
          }
        });
        final auth = AuthProvider(api, startupRetryPauses: const []);
        addTearDown(auth.dispose);
        await tester.runAsync(() async {
          for (var i = 0; i < 200 && auth.isInitializing; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        });
        return TvNavHarness.pump(
          tester,
          ChangeNotifierProvider<AuthProvider>.value(
            value: auth,
            child: const UserChoiceScreen(atStartup: true),
          ),
          engine: engine,
        );
      }

      testWidgets('à l’ouverture, le focus est sur la première personne',
          (tester) async {
        await pump(tester);
        expect(_focused(), _as('alice'));
      });

      // Une case à la fois, chacune depuis un écran neuf.
      final steps = <_Step>[
        // La rangée se parcourt de profil en profil, jusqu'au « + ».
        (from: _as('alice'), direction: _right, to: _as('bob')),
        (from: _as('bob'), direction: _left, to: _as('alice')),
        (from: _as('dave'), direction: _right, to: _add),
        (from: _add, direction: _left, to: _as('dave')),
        // Elle s'arrête à ses bords.
        (from: _as('alice'), direction: _left, to: _as('alice')),
        (from: _add, direction: _right, to: _add),
        // Bas descend au bouton qui gère les profils (haut en revient par la
        // mémoire de la rangée, voir le parcours enchaîné).
        (from: _as('alice'), direction: _down, to: _manage),
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

      testWidgets('on parcourt la rangée puis on gère les profils',
          (tester) async {
        final nav = await pump(tester);
        final route = <(TraversalDirection, String)>[
          (_right, _as('bob')),
          (_right, _as('carole')),
          (_down, _manage),
          // Haut rend la personne d'où l'on venait.
          (_up, _as('carole')),
          (_right, _as('dave')),
          (_right, _add),
        ];
        for (final (direction, expected) in route) {
          await nav.press(direction);
          expect(_focused(), expected, reason: '${direction.name} → $expected');
        }
      });
    });

    group('sélecteur d’avatar', () {
      Future<TvNavHarness> pump(WidgetTester tester) {
        final api = ApiClient();
        return TvNavHarness.pump(
          tester,
          Provider<ApiClient>.value(
            value: api,
            child: const AvatarPickerScreen(
              account: ServerAccount(
                id: 'a',
                url: 'http://maison.local',
                username: 'alice',
              ),
            ),
          ),
          engine: engine,
        );
      }

      testWidgets('à l’ouverture, le focus est sur le premier avatar',
          (tester) async {
        await pump(tester);
        expect(_focused(), 'Avatar 1');
      });

      // La galerie tient en rangées de largeur fixe (760) : on lit leur
      // longueur à l'écran plutôt que de la supposer.
      int perRow(WidgetTester tester) {
        final top = tester.getTopLeft(find.bySemanticsLabel('Avatar 1')).dy;
        var count = 0;
        while (tester
                .getTopLeft(find.bySemanticsLabel('Avatar ${count + 1}'))
                .dy ==
            top) {
          count++;
        }
        return count;
      }

      testWidgets(
          'droite et gauche parcourent une rangée, bas passe à la '
          'rangée du dessous', (tester) async {
        final nav = await pump(tester);
        final row = perRow(tester);
        expect(row, greaterThan(1), reason: 'plusieurs avatars par rangée');

        await nav.press(_right);
        expect(_focused(), 'Avatar 2');
        await nav.press(_left);
        expect(_focused(), 'Avatar 1');
        await nav.press(_down);
        expect(_focused(), 'Avatar ${row + 1}');
      });

      testWidgets('haut depuis la deuxième rangée remonte à la première',
          (tester) async {
        final nav = await pump(tester);
        final row = perRow(tester);
        await _focusOn(tester, 'Avatar ${row + 1}');
        await nav.press(_up);
        expect(_focused(), 'Avatar 1');
      });

      // Sous dpad, gauche partait sur « Retour », en haut à gauche : les
      // avatars sont une `TvRegion.rail`, dont le bord arrête la flèche.
      testWidgets('gauche s’arrête au bord de la rangée', (tester) async {
        final nav = await pump(tester);
        await nav.press(_left);
        expect(_focused(), 'Avatar 1');
      });

      testWidgets('droite s’arrête au bout de la rangée', (tester) async {
        final nav = await pump(tester);
        final row = perRow(tester);
        await _focusOn(tester, 'Avatar $row');
        await nav.press(_right);
        expect(_focused(), 'Avatar $row');
      });
    });
  });
}
