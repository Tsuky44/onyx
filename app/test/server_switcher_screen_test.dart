import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onyx/models/models.dart';
import 'package:onyx/models/server_account.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/screens/auth/server_switcher_screen.dart';
import 'package:onyx/screens/settings/add_server_screen.dart';
import 'package:onyx/services/api_client.dart';

class _FakeApiClient extends ApiClient {
  final Map<String, User> profiles = {};
  List<SuggestedPeerServer> suggested = const [];

  @override
  Future<User> getMe() async {
    final user = profiles[baseUrl];
    if (user == null) throw Exception('aucun profil pour $baseUrl');
    return user;
  }

  @override
  Future<void> refreshAccountLinks() async {}

  @override
  Future<List<SuggestedPeerServer>> getSuggestedPeerServers() async => suggested;
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

  Future<(_FakeApiClient, AuthProvider)> buildAuth(
    WidgetTester tester, {
    bool twoServers = true,
    List<SuggestedPeerServer> suggested = const [],
  }) async {
    final api = _FakeApiClient()..suggested = suggested;
    await tester.runAsync(() async {
      await api.initialize();
      api.profiles['http://maison.local'] = User(id: 1, username: 'mathis');
      api.profiles['http://paul.local'] = User(id: 7, username: 'lea');
      if (twoServers) {
        await api.rememberSession(
          serverUrl: 'http://paul.local',
          username: 'lea',
          token: 'b',
        );
      }
      await api.rememberSession(
        serverUrl: 'http://maison.local',
        username: 'mathis',
        token: 'a',
      );
    });
    final auth = AuthProvider(api, startupRetryPauses: const []);
    addTearDown(() => tester.runAsync(() async => auth.dispose()));
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && auth.isInitializing; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    return (api, auth);
  }

  Future<void> pumpSwitcher(WidgetTester tester, AuthProvider auth) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: auth.apiClient),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ServerSwitcherScreen()),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'affiche les serveurs en cartes comme les profils, avec un seul Ajouter',
      (tester) async {
    final (_, auth) = await buildAuth(tester, twoServers: false);
    await pumpSwitcher(tester, auth);

    expect(find.text('Quel serveur ?'), findsOneWidget);
    expect(find.bySemanticsLabel('Serveur maison.local'), findsOneWidget);
    expect(find.bySemanticsLabel('Ajouter un serveur'), findsOneWidget);
    expect(find.text('Gérer les serveurs'), findsOneWidget);
    expect(find.text('Configurer les serveurs'), findsNothing);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Serveur maison.local'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('toucher un autre serveur bascule dessus et ferme la page',
      (tester) async {
    final (_, auth) = await buildAuth(tester, twoServers: true);
    await pumpSwitcher(tester, auth);

    await tester.tap(find.bySemanticsLabel('Serveur paul.local'));
    await tester.pumpAndSettle();

    expect(auth.activeServer?.url, 'http://paul.local');
    expect(find.byType(ServerSwitcherScreen), findsNothing);
  });

  testWidgets(
      'Gérer les serveurs bascule en mode édition sur la même grille',
      (tester) async {
    final (_, auth) = await buildAuth(tester, twoServers: true);
    await pumpSwitcher(tester, auth);

    await tester.tap(find.text('Gérer les serveurs'));
    await tester.pumpAndSettle();

    expect(find.text('Gérer les serveurs'), findsOneWidget);
    expect(find.text('Terminé'), findsOneWidget);
    expect(find.bySemanticsLabel('Ajouter un serveur'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Gérer paul.local'));
    await tester.pumpAndSettle();

    expect(find.text('Démarrer sur ce serveur'), findsOneWidget);
    expect(find.text('Renommer'), findsOneWidget);
    expect(find.text('Retirer de cet appareil'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminé'));
    await tester.pumpAndSettle();

    expect(find.text('Quel serveur ?'), findsOneWidget);
    expect(find.bySemanticsLabel('Ajouter un serveur'), findsOneWidget);
  });

  testWidgets(
      'Ajouter propose les serveurs pairs mutuellement acceptés par les admins',
      (tester) async {
    final (_, auth) = await buildAuth(
      tester,
      twoServers: false,
      suggested: const [
        SuggestedPeerServer(
          serverId: 'peer-2',
          name: 'Chez Paul',
          url: 'https://paul.local',
        ),
      ],
    );
    await pumpSwitcher(tester, auth);

    await tester.tap(find.bySemanticsLabel('Ajouter un serveur'));
    await tester.pumpAndSettle();

    expect(find.byType(AddServerScreen), findsOneWidget);
    expect(find.text('Serveurs proposés'), findsOneWidget);
    expect(find.text('Chez Paul'), findsOneWidget);

    await tester.tap(find.text('Chez Paul'));
    await tester.pumpAndSettle();

    expect(find.text('https://paul.local'), findsOneWidget);
  });
}
