import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onyx/models/models.dart';
import 'package:onyx/models/server_account.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/widgets/global/account_menu.dart';
import 'package:onyx/widgets/global/account_menu_panel.dart';

import 'support/tv_nav_harness.dart';

/// Le menu du compte, « profils en tête » : les personnes du serveur en
/// pastilles au-dessus des actions, pour changer de personne en un geste.

const _mathis = ServerAccount(
    id: 'm', url: 'http://maison.local', username: 'mathis', userId: 1);
const _lea =
    ServerAccount(id: 'l', url: 'http://maison.local', username: 'lea');
const _chalet =
    ServerAccount(id: 'c', url: 'http://chalet.local', username: 'mathis');

String _as(String user) => 'Regarder en tant que $user';

/// Un serveur qui rend le profil du compte actif, sans réseau.
class _FakeApiClient extends ApiClient {
  @override
  Future<User> getMe() async {
    final active = servers.active!;
    return User(
      id: active.userId ?? 1,
      username: active.username,
      permissions: const Permissions(requestMedia: true),
    );
  }

  @override
  Future<void> refreshAccountLinks() async {}
}

Widget _panel({
  ValueChanged<AccountMenuChoice>? onChoice,
  bool canLinkDevice = false,
  List<ServerAccount> otherServers = const [],
}) =>
    AccountMenuPanel(
      profiles: const [_mathis, _lea],
      current: _lea,
      serverLabel: 'maison · Membre',
      otherServers: otherServers,
      canAddProfile: true,
      canLinkDevice: canLinkDevice,
      onChoice: onChoice ?? (_) {},
    );

String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
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
  return label;
}

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

  group('le panneau', () {
    testWidgets('les personnes du serveur sont en tête, la sienne marquée',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: Center(child: _panel())));

      expect(find.bySemanticsLabel(_as('mathis')), findsOneWidget);
      expect(find.bySemanticsLabel('lea, en cours'), findsOneWidget);
      expect(find.bySemanticsLabel('Ajouter un profil'), findsOneWidget);
      expect(find.text('maison · Membre'), findsOneWidget);
      // La rangée est au-dessus des actions.
      expect(
        tester.getRect(find.bySemanticsLabel(_as('mathis'))).bottom,
        lessThan(tester.getRect(find.text('Gérer les profils')).top),
      );
    });

    testWidgets('chaque pastille et chaque ligne rend son choix',
        (tester) async {
      final picked = <AccountMenuChoice>[];
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: _panel(onChoice: picked.add, otherServers: const [_chalet]),
        ),
      ));

      await tester.tap(find.bySemanticsLabel(_as('mathis')));
      await tester.tap(find.bySemanticsLabel('Ajouter un profil'));
      await tester.tap(find.text('Passer sur chalet.local'));
      await tester.tap(find.text('Se déconnecter'));

      expect(picked, hasLength(4));
      expect((picked[0] as AccountMenuProfile).account.id, 'm');
      expect(picked[1], AccountMenuAction.addProfile);
      expect((picked[2] as AccountMenuServer).account.id, 'c');
      expect(picked[3], AccountMenuAction.signOut);
    });

    testWidgets('« Connecter un appareil » n’est que là où il y a une caméra',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: Center(child: _panel())));
      expect(find.text('Connecter un appareil'), findsNothing);

      await tester.pumpWidget(
          MaterialApp(home: Center(child: _panel(canLinkDevice: true))));
      expect(find.text('Connecter un appareil'), findsOneWidget);
    });
  });

  testWidgets(
      'le menu s’ouvre sous le bouton et une pastille change de personne',
      (tester) async {
    final api = _FakeApiClient();
    await tester.runAsync(() async {
      await api.initialize();
      for (final (id, user) in [(1, 'mathis'), (2, 'lea')]) {
        await api.rememberSession(
          serverUrl: 'http://maison.local',
          username: user,
          token: 'jeton-$user',
          userId: id,
        );
      }
    });
    final auth = AuthProvider(api, startupRetryPauses: const []);
    addTearDown(auth.dispose);
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && auth.isInitializing; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await auth.chooseUser(auth.usersOnActiveServer.last.id);
    });
    expect(auth.currentUser?.username, 'lea');

    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [AccountMenu(authProvider: auth)]),
        ),
      ),
    ));

    final button = tester.getRect(find.byType(AccountMenu));
    await tester.tap(find.byType(AccountMenu));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(AccountMenuPanel));
    expect(panel.top, greaterThan(button.bottom),
        reason: 'le menu tombe sous l’avatar');
    expect(panel.right, lessThanOrEqualTo(800 - 12));
    expect(panel.left, greaterThanOrEqualTo(12));

    await tester.tap(find.bySemanticsLabel(_as('mathis')));
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && auth.currentUser?.username != 'mathis'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();

    expect(find.byType(AccountMenuPanel), findsNothing);
    expect(auth.currentUser?.username, 'mathis',
        reason: 'un geste suffit, sans passer par « Qui regarde ? »');
  });

  TvNavHarness.forEachEngine((engine) {
    group('à la télécommande', () {
      Future<TvNavHarness> pump(WidgetTester tester) => TvNavHarness.pump(
            tester,
            Center(child: _panel()),
            engine: engine,
          );

      testWidgets('à l’ouverture, le focus est sur la personne en cours',
          (tester) async {
        await pump(tester);
        expect(_focused(), 'lea, en cours');
      });

      testWidgets('la rangée se parcourt, puis Bas descend aux actions',
          (tester) async {
        final nav = await pump(tester);
        final route = <(TraversalDirection, String)>[
          (TraversalDirection.left, _as('mathis')),
          (TraversalDirection.right, 'lea, en cours'),
          (TraversalDirection.right, 'Ajouter un profil'),
          (TraversalDirection.down, 'Gérer les profils'),
          (TraversalDirection.down, 'Rejoindre une séance'),
          (TraversalDirection.down, 'Paramètres'),
          (TraversalDirection.down, 'Se déconnecter'),
        ];
        for (final (direction, expected) in route) {
          await nav.press(direction);
          expect(_focused(), expected,
              reason: '${direction.name} → $expected');
        }
      });
    });
  });
}
