import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/request_service.dart';
import 'package:onyx/providers/media_requests_provider.dart';
import 'package:onyx/screens/settings/pages/integrations_page.dart';
import 'package:onyx/services/api_client.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_doubles.dart';

/// Le service de demandes se choisit dans Paramètres → Services : MediaHub,
/// Overseerr ou Jellyseerr (ADR-0136). Le choix part au serveur avec l'adresse
/// et la clé ; un serveur d'avant ne le reçoit pas.

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Un serveur réduit à ses réglages. [puts] et [tests] gardent les corps
/// reçus sur `PUT /api/settings` et `POST /api/settings/mediahub/test`.
class _Server {
  _Server({
    this.canChoose = true,
    this.service = 'mediahub',
    this.keySet = false,
  });

  final bool canChoose;
  String service;
  bool keySet;
  final List<Map<String, dynamic>> puts = [];
  final List<Map<String, dynamic>> tests = [];

  Map<String, dynamic> get _settings => {
        'mediahub_url': 'http://hub.test',
        'mediahub_api_key_set': keySet,
        'mediahub_api_key_hint': '••••1234',
        if (canChoose) 'request_service': service,
        'tmdb_api_key_set': true,
        'tmdb_language': 'fr-FR',
        'playback_logs_enabled': true,
        'playback_stats_enabled': true,
        'otp_policy': 'optional',
      };

  ApiClient get api {
    final dio = Dio()
      ..httpClientAdapter = Adapter((options) {
        final body = options.data is Map
            ? Map<String, dynamic>.from(options.data as Map)
            : <String, dynamic>{};
        switch ('${options.method} ${options.uri.path}') {
          case 'GET /api/ping':
            return _json({
              'status': 'ok',
              'capabilities': [
                'mediahub_link_test',
                'mediahub_requests',
                if (canChoose) 'request_services',
              ],
            });
          case 'GET /api/settings':
            return _json(_settings);
          case 'PUT /api/settings':
            puts.add(body);
            service = body['request_service'] as String? ?? service;
            keySet = keySet || body['mediahub_api_key'] != null;
            return _json(_settings);
          case 'POST /api/settings/mediahub/test':
            tests.add(body);
            return _json({
              'ok': true,
              'message': 'Le service répond.',
              'notes': ['Aucun compte ne porte ce nom.'],
            });
          default:
            return _json({'service': service, 'linked': true, 'can': {}});
        }
      });
    return ApiClient(httpClient: dio);
  }
}

Future<void> _open(WidgetTester tester, _Server server) async {
  // Assez haut pour les trois groupes : aucun bouton à faire défiler.
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = server.api;
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider(create: (_) => MediaRequestsProvider(api)),
    ],
    child: const MaterialApp(home: Scaffold(body: IntegrationsPage())),
  ));
  await tester.pumpAndSettle();
}

Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);

/// Le groupe du service de demandes est le dernier de la page.
Future<void> _press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _typeKey(WidgetTester tester, String label, String key) async {
  await tester.enterText(find.widgetWithText(TextField, label), key);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('une valeur inconnue ou absente se lit MediaHub', () {
    expect(RequestService.parse('jellyseerr'), RequestService.jellyseerr);
    expect(RequestService.parse('overseerr'), RequestService.overseerr);
    // Un serveur d'avant le choix n'envoie rien ; « onyxhub » est un dialecte
    // de MediaHub, pas un service à choisir.
    expect(RequestService.parse(null), RequestService.mediaHub);
    expect(RequestService.parse('onyxhub'), RequestService.mediaHub);
    expect(RequestService.parse('ombi'), RequestService.mediaHub);

    expect(RequestService.mediaHub.isSeerr, isFalse);
    expect(RequestService.overseerr.isSeerr, isTrue);
    expect(RequestService.jellyseerr.isSeerr, isTrue);
  });

  test('les réglages du serveur portent le service choisi', () {
    final settings = ServerSettings.fromJson(const {
      'mediahub_url': 'http://seerr:5055',
      'mediahub_api_key_set': true,
      'request_service': 'overseerr',
    });
    expect(settings.requestService, RequestService.overseerr);
    expect(ServerSettings.fromJson(const {}).requestService,
        RequestService.mediaHub);
  });

  testWidgets('un serveur qui sait les brancher propose les trois services',
      (tester) async {
    await _open(tester, _Server(service: 'overseerr', keySet: true));

    for (final service in RequestService.values) {
      expect(_chip(service.label), findsOneWidget);
    }
    // Le service enregistré est celui qui est choisi, et le formulaire parle
    // de lui.
    expect(tester.widget<ChoiceChip>(_chip('Overseerr')).selected, isTrue);
    expect(find.text('Adresse de Overseerr'), findsOneWidget);
    expect(find.text('Clé API Overseerr'), findsOneWidget);
  });

  testWidgets('choisir Jellyseerr l’enregistre avec son adresse et sa clé',
      (tester) async {
    final server = _Server();
    await _open(tester, server);

    await tester.tap(_chip('Jellyseerr'));
    await tester.pumpAndSettle();
    expect(find.text('Adresse de Jellyseerr'), findsOneWidget);
    expect(find.text('Clé d’intégration MediaHub'), findsNothing);

    await _typeKey(tester, 'Clé API Jellyseerr', 'cle-jellyseerr');
    await _press(tester, 'Enregistrer');

    expect(server.puts.single, {
      'mediahub_url': 'http://hub.test',
      'mediahub_api_key': 'cle-jellyseerr',
      'request_service': 'jellyseerr',
    });
    expect(find.text('Jellyseerr enregistré.'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(_chip('Jellyseerr')).selected, isTrue);
  });

  testWidgets('changer de service sans sa clé ne garde pas celle de l’ancien',
      (tester) async {
    final server = _Server(keySet: true);
    await _open(tester, server);

    await tester.tap(_chip('Overseerr'));
    await tester.pumpAndSettle();
    await _press(tester, 'Enregistrer');

    // La clé de MediaHub, gardée, aurait été refusée par Overseerr à la
    // première demande : rien ne part, et l'écran dit quoi coller.
    expect(server.puts, isEmpty);
    expect(
        find.text('Collez la clé de Overseerr : celle de MediaHub ne lui '
            'sert pas.'),
        findsOneWidget);
  });

  testWidgets('le test de liaison porte le service du formulaire',
      (tester) async {
    final server = _Server();
    await _open(tester, server);

    await tester.tap(_chip('Jellyseerr'));
    await tester.pumpAndSettle();
    await _typeKey(tester, 'Clé API Jellyseerr', 'cle-jellyseerr');
    await _press(tester, 'Tester');

    expect(server.tests.single, {
      'mediahub_url': 'http://hub.test',
      'mediahub_api_key': 'cle-jellyseerr',
      'request_service': 'jellyseerr',
    });
    expect(server.puts, isEmpty);
    expect(find.text('Aucun compte ne porte ce nom.'), findsOneWidget);

    // La réserve parlait de Jellyseerr : elle ne reste pas sous MediaHub.
    await tester.tap(_chip('MediaHub'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun compte ne porte ce nom.'), findsNothing);
  });

  testWidgets('un serveur d’avant le choix ne règle que MediaHub',
      (tester) async {
    final server = _Server(canChoose: false);
    await _open(tester, server);

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Adresse de MediaHub'), findsOneWidget);

    await _typeKey(tester, 'Clé d’intégration MediaHub', 'cle-mediahub');
    await _press(tester, 'Tester');
    await _press(tester, 'Enregistrer');

    // Un réglage qu'il ne lit pas ne lui est pas envoyé.
    expect(server.tests.single.containsKey('request_service'), isFalse);
    expect(server.puts.single.containsKey('request_service'), isFalse);
  });
}
