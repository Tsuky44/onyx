import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/screens/auth/server_choice_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/server_reachability.dart';
import 'package:onyx/tv/tv_mode.dart';

/// « Quel serveur ? » : le serveur principal ne répond pas au lancement.
/// Voir ADR-0013 pour le carnet de comptes.

/// « maison » (le principal) est éteint ; « paul » et « cabane » répondent.
class _FakeApiClient extends ApiClient {
  @override
  Future<User> getMe() async {
    if (baseUrl == 'http://maison.local') {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/api/auth/me'),
        reason: 'serveur injoignable',
      );
    }
    return User(
      id: 1,
      username: 'mathis',
      permissions: const Permissions(requestMedia: true),
    );
  }

  @override
  Future<void> refreshAccountLinks() async {}
}

Future<void> _settle(AuthProvider auth) async {
  for (var i = 0; i < 200 && auth.isInitializing; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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

  Future<AuthProvider> startWithDeadPrimary(WidgetTester tester) async {
    late AuthProvider auth;
    late _FakeApiClient api;
    await tester.runAsync(() async {
      api = _FakeApiClient();
      await api.initialize();
      for (final host in ['cabane', 'paul', 'maison']) {
        await api.rememberSession(
          serverUrl: 'http://$host.local',
          username: 'mathis',
          token: 'jeton-$host',
        );
      }
      await api.servers
          .setPrimary(api.servers.accountForUrl('http://maison.local')!.id);
      auth = AuthProvider(api, startupRetryPauses: const []);
      await _settle(auth);
    });
    expect(auth.needsServerChoice, isTrue);
    addTearDown(() => tester.runAsync(() async => auth.dispose()));
    return auth;
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    AuthProvider auth, {
    bool isTv = false,
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TvScope(
      isTv: isTv,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<ApiClient>.value(value: auth.apiClient),
          ChangeNotifierProvider(
              create: (_) => ServerReachability(auth.apiClient)),
        ],
        child: const MaterialApp(home: ServerChoiceScreen()),
      ),
    ));
    await tester.pump();
  }

  testWidgets(
      'le bouton nomme le serveur retenu, et choisir une carte le change',
      (tester) async {
    final auth = await startWithDeadPrimary(tester);
    await pumpScreen(tester, auth);

    expect(find.text('Quel serveur ?'), findsOneWidget);
    expect(find.text('Continuer sur cabane.local'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Serveur paul.local'));
    await tester.pump();

    expect(find.text('Continuer sur paul.local'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Serveur paul.local'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Serveur cabane.local'))
          .flagsCollection
          .isSelected,
      Tristate.isFalse,
    );
  });

  testWidgets('le principal muet n’est pas proposé, l’adresse est en infobulle',
      (tester) async {
    final auth = await startWithDeadPrimary(tester);
    await pumpScreen(tester, auth);

    expect(find.bySemanticsLabel('Serveur maison.local'), findsNothing);
    expect(find.text('1 profil'), findsNWidgets(2));
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('la carte Ajouter mène au chemin d’ajout de serveur',
      (tester) async {
    final auth = await startWithDeadPrimary(tester);
    await pumpScreen(tester, auth);

    await tester.tap(find.bySemanticsLabel('Ajouter un serveur'));
    await tester.pumpAndSettle();

    expect(find.text('Quel serveur ?'), findsNothing);
  });

  testWidgets('sur téléphone, les cartes tiennent sans débordement',
      (tester) async {
    final auth = await startWithDeadPrimary(tester);
    await pumpScreen(tester, auth, size: const Size(360, 740));

    expect(tester.takeException(), isNull);
    expect(find.text('Continuer sur cabane.local'), findsOneWidget);
  });

  testWidgets('sur TV, l’écran en liste reste tel quel', (tester) async {
    final auth = await startWithDeadPrimary(tester);
    await pumpScreen(tester, auth, isTv: true);

    expect(find.text('Serveur principal non disponible'), findsOneWidget);
    expect(find.text('Quel serveur ?'), findsNothing);
    expect(find.text('Continuer sur cabane.local'), findsNothing);
  });
}
