import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/screens/settings/user_admin_sections.dart';
import 'package:onyx/services/api_client.dart';

class _Api extends ApiClient {
  _Api(this.users);

  List<User> users;
  final deleted = <int>[];

  @override
  Future<List<User>> getUsers() async => users;

  @override
  Future<void> deleteUser(int userId) async {
    deleted.add(userId);
    users = users.where((u) => u.id != userId).toList();
  }
}

class _Auth extends AuthProvider {
  _Auth(super.api, this._me);

  final User _me;

  @override
  User? get currentUser => _me;

  @override
  bool get isOwner => _me.isOwner;

  @override
  Permissions get permissions => _me.permissions;
}

final _owner = User(
    id: 1, username: 'mathis', isOwner: true, permissions: Permissions.all);
final _admin = User(
    id: 2,
    username: 'paul',
    permissions: Permissions.all,
    otpEnabled: true);
final _member = User(
    id: 3, username: 'lea', permissions: const Permissions(requestMedia: true));

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

  Future<_Api> pump(WidgetTester tester, {required User me}) async {
    final api = _Api([_owner, _admin, _member]);
    final auth = _Auth(api, me);
    addTearDown(auth.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: UsersSection())),
      ),
    ));
    await tester.pumpAndSettle();
    return api;
  }

  Future<void> openMenu(WidgetTester tester, String username) async {
    await tester.tap(find.byTooltip('Actions pour $username'));
    await tester.pumpAndSettle();
  }

  testWidgets('le groupe compte les comptes et marque le propriétaire',
      (tester) async {
    await pump(tester, me: _owner);

    expect(find.text('Comptes · 3'), findsOneWidget);
    expect(find.text('Propriétaire'), findsOneWidget);
    expect(find.text('Vous'), findsOneWidget);
  });

  testWidgets('chaque compte a son menu, avec les actions qu’on lui doit',
      (tester) async {
    await pump(tester, me: _owner);

    await openMenu(tester, 'paul');
    expect(find.text('Modifier les droits'), findsOneWidget);
    expect(find.text('Réinitialiser le mot de passe'), findsOneWidget);
    expect(find.text('Réinitialiser la validation en deux étapes'),
        findsOneWidget,
        reason: 'paul a une double authentification');
    expect(find.text('Transférer la propriété'), findsOneWidget);
    expect(find.text('Supprimer le compte'), findsOneWidget);
  });

  testWidgets('seul le propriétaire touche au propriétaire', (tester) async {
    await pump(tester, me: _admin);

    // L'administrateur n'a aucune action sur le propriétaire : pas de menu.
    expect(find.byTooltip('Actions pour mathis'), findsNothing);
    // Sur un compte ordinaire, il peut tout sauf transférer la propriété.
    await openMenu(tester, 'lea');
    expect(find.text('Modifier les droits'), findsOneWidget);
    expect(find.text('Transférer la propriété'), findsNothing);
    expect(find.text('Supprimer le compte'), findsOneWidget);
  });

  testWidgets('on ne se supprime pas soi-même, ni le propriétaire',
      (tester) async {
    await pump(tester, me: _owner);

    await openMenu(tester, 'mathis');
    expect(find.text('Modifier les droits'), findsOneWidget);
    expect(find.text('Supprimer le compte'), findsNothing);
    expect(find.text('Transférer la propriété'), findsNothing);
  });

  testWidgets('supprimer un compte demande une confirmation destructive',
      (tester) async {
    final api = await pump(tester, me: _owner);

    await openMenu(tester, 'lea');
    await tester.tap(find.text('Supprimer le compte'));
    await tester.pumpAndSettle();

    expect(find.text('Supprimer lea ?'), findsOneWidget);
    // Annuler ne supprime rien.
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(api.deleted, isEmpty);

    await openMenu(tester, 'lea');
    await tester.tap(find.text('Supprimer le compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(api.deleted, [3]);
    expect(find.text('Comptes · 2'), findsOneWidget);
  });
}
