import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onyx/models/device_pairing.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/screens/auth/login_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/tv_deferred_keyboard.dart';

import 'support/tv_nav_harness.dart';

/// Records the sign-in attempt and keeps the screen off the network.
class _FakeApiClient extends ApiClient {
  final List<String> logins = [];

  @override
  Future<({bool required, bool codeRequired})> getSetupState() async =>
      (required: false, codeRequired: false);

  /// The QR sign-in beside the form opens a pairing; refused here, it shows its
  /// failure state and stays off the network.
  @override
  Future<DevicePairing> startDevicePairing(
          {required String deviceName}) async =>
      throw Exception('offline');

  @override
  Future<User> login(String username, String password) async {
    logins.add(username);
    throw Exception('refused');
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

  /// Mounts the form as a television does, under either navigation system:
  /// the fields are deferred (their keyboard opens on OK), which is the
  /// path the action key and the sign-in have to survive.
  Future<_FakeApiClient> pumpLogin(
    WidgetTester tester,
    TvNavEngine engine,
    bool tv,
  ) async {
    final apiClient = _FakeApiClient();
    await TvNavHarness.pump(
      tester,
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
          ChangeNotifierProvider(create: (_) => AuthProvider(apiClient)),
        ],
        child: const LoginScreen(),
      ),
      engine: engine,
      isTv: tv,
    );
    return apiClient;
  }

  /// OK on a field's frame: opens its keyboard, the field takes the focus.
  Future<void> open(WidgetTester tester, int index, bool tv) async {
    if (!tv) {
      await tester.tap(find.byType(TextFormField).at(index));
      await tester.pump();
      return;
    }
    tester
        .stateList<TvDeferredKeyboardState>(find.byType(TvDeferredKeyboard))
        .elementAt(index)
        .requestKeyboard();
    await tester.pumpAndSettle();
  }

  /// Types into a field as the keyboard would: opened first, since a closed
  /// field cannot take the focus on a television.
  Future<void> type(
      WidgetTester tester, int index, String text, bool tv) async {
    await open(tester, index, tv);
    await tester.enterText(find.byType(TextFormField).at(index), text);
    await tester.pump();
  }

  /// A frame, or the frames the field needs on a television. A phone's
  /// focused field blinks its caret for ever: it never settles.
  Future<void> step(WidgetTester tester, bool tv) =>
      tv ? tester.pumpAndSettle() : tester.pump();

  /// Fields in the order they are laid out: server, username, password.
  bool hasFocus(WidgetTester tester, int index) => tester
      .widget<EditableText>(find.byType(EditableText).at(index))
      .focusNode
      .hasFocus;

  TvNavHarness.forEachEngine((engine) {
    for (final tv in [false, true]) {
      group(tv ? 'on a television' : 'on a phone', () {
        // Constat de la phase 4 : avec l'ancien système, sur téléviseur, passer
        // d'un champ au suivant rend le focus au cadre du champ quitté
        // (`TvDeferredKeyboard._onFieldFocusChanged`). Sous dpad, il reste au
        // champ suivant. On ne touche pas à l'ancien système.
        final String? chained = engine == TvNavEngine.legacy && tv
            ? 'ancien système : le focus revient au champ quitté'
            : null;
        // The television has no pointer, and its keyboard covers the form. If the
        // action key does not move the focus, the fields below the server address are
        // unreachable — which is what the address field's `onEditingComplete` did by
        // replacing Flutter's own handling of that key.
        testWidgets('the keyboard action key walks down the form',
            skip: chained != null, (tester) async {
          await pumpLogin(tester, engine, tv);

          await open(tester, 0, tv);
          expect(hasFocus(tester, 0), isTrue);

          await tester.testTextInput.receiveAction(TextInputAction.next);
          await step(tester, tv);
          expect(hasFocus(tester, 1), isTrue, reason: 'server → username');

          await tester.testTextInput.receiveAction(TextInputAction.next);
          await step(tester, tv);
          expect(hasFocus(tester, 2), isTrue, reason: 'username → password');
        });

        testWidgets('the last field signs in without reaching for the button',
            skip: chained != null, (tester) async {
          final apiClient = await pumpLogin(tester, engine, tv);

          await type(tester, 0, 'http://192.168.1.50:8080', tv);
          await type(tester, 1, 'mathis', tv);
          await type(tester, 2, 'motdepasse', tv);

          await tester.testTextInput.receiveAction(TextInputAction.done);
          await step(tester, tv);

          expect(apiClient.logins, ['mathis']);
          // The keyboard is full screen on a television: it has to go, or the error
          // the sign-in produced is behind it.
          expect(hasFocus(tester, 2), isFalse);
        });

        // Au clavier physique (Windows, web), Entrée dans le mot de passe ne
        // soumettait rien : il fallait aller cliquer sur « Se connecter ».
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter
        ]) {
          testWidgets('a hardware ${key.keyLabel} in the password signs in',
              skip: chained != null, (tester) async {
            final apiClient = await pumpLogin(tester, engine, tv);

            await type(tester, 0, 'http://192.168.1.50:8080', tv);
            await type(tester, 1, 'mathis', tv);
            await type(tester, 2, 'motdepasse', tv);

            await tester.sendKeyEvent(key);
            await step(tester, tv);

            expect(apiClient.logins, ['mathis']);
          });
        }

        // 1Password remplissait le mot de passe et laissait l'identifiant vide : aucun
        // champ ne disait ce qu'il était, et l'adresse du serveur passait devant.
        testWidgets('a password manager is told which field is the username',
            (tester) async {
          await pumpLogin(tester, engine, tv);

          Iterable<String>? hints(int index) => tester
              .widget<EditableText>(find.byType(EditableText).at(index))
              .autofillHints;

          expect(hints(0), isNull, reason: 'the server address is not a login');
          expect(hints(1), [AutofillHints.username]);
          expect(hints(2), [AutofillHints.password]);
          expect(
            find.ancestor(
              of: find.byType(EditableText).at(1),
              matching: find.byType(AutofillGroup),
            ),
            findsOneWidget,
          );
        });

        testWidgets('the eye reveals the password and hides it again',
            (tester) async {
          await pumpLogin(tester, engine, tv);

          bool obscured() => tester
              .widget<EditableText>(find.byType(EditableText).at(2))
              .obscureText;

          expect(obscured(), isTrue);
          await tester.tap(find.byTooltip('Afficher le mot de passe'));
          await tester.pump();
          expect(obscured(), isFalse);
          await tester.tap(find.byTooltip('Masquer le mot de passe'));
          await tester.pump();
          expect(obscured(), isTrue);
        });
      });
    }
  });
}
