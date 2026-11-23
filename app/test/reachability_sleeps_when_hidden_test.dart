import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/services/server_reachability.dart';
import 'package:onyx/utils/on_screen.dart';

import 'test_doubles.dart';

// Une app cachée ne se réveille plus toutes les 45 s pour sonder le serveur ;
// elle sonde dès qu'elle revient (ADR-0166).
void main() {
  late int pings;
  late ServerReachability reachability;

  setUp(() {
    pings = 0;
    final probe = Dio()
      ..httpClientAdapter = Adapter((options) {
        pings++;
        return ResponseBody.fromString(jsonEncode({'ok': true}), 200);
      });
    reachability = ServerReachability(
      ApiClient(registry: Registry()),
      probe: probe,
    );
  });

  // Libérée dans le corps du test : sa minuterie doit être annulée avant la
  // vérification des minuteries en suspens, qui passe avant `tearDown`.
  tearDown(() => AppForeground.debugSetVisible(true));

  testWidgets('visible, l\'app sonde toutes les 45 s', (tester) async {
    reachability.start();
    await tester.pump(const Duration(milliseconds: 10));
    expect(pings, 1);

    await tester.pump(const Duration(seconds: 46));
    expect(pings, 2);
    reachability.dispose();
  });

  testWidgets('cachée, elle ne sonde plus ; au retour, elle sonde aussitôt',
      (tester) async {
    reachability.start();
    await tester.pump(const Duration(milliseconds: 10));
    expect(pings, 1);

    AppForeground.debugSetVisible(false);
    await tester.pump(const Duration(minutes: 10));
    expect(pings, 1);

    AppForeground.debugSetVisible(true);
    await tester.pump(const Duration(milliseconds: 10));
    expect(pings, 2);

    await tester.pump(const Duration(seconds: 46));
    expect(pings, 3);
    reachability.dispose();
  });
}
