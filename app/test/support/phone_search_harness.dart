// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/navigation/shell_navigator.dart';
import 'package:onyx/screens/shell/phone_search.dart';

/// La recherche du téléphone telle que la coquille la monte, sans la barre
/// d'onglets : le navigateur des pages, et sous lui la bulle qui porte le
/// champ ([PhoneSearchField]). La barre d'onglets elle-même, son rond qui
/// s'étire et le focus donné au champ sont éprouvés par
/// `phone_tab_bar_test.dart`.
Widget phoneSearchHarness(PhoneSearchSession session) => Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Navigator(
              key: session.navigatorKey,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Center(child: Text('Accueil')),
              ),
            ),
          ),
          SizedBox(height: 56, child: PhoneSearchField(session: session)),
        ],
      ),
    );

/// Une session sur le navigateur des pages de la coquille, celui où
/// s'ouvrent les fiches.
PhoneSearchSession phoneSearchSession() {
  final session = PhoneSearchSession(navigatorKey: shellNavigatorKey);
  addTearDown(session.dispose);
  return session;
}

/// Le rond touché : la page de recherche s'ouvre, le champ prend le clavier.
Future<void> openPhoneSearchIn(
    WidgetTester tester, PhoneSearchSession session) async {
  session.open(reduced: true);
  await tester.pumpAndSettle();
  session.focusNode.requestFocus();
  await tester.pumpAndSettle();
}
