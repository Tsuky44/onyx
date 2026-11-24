import 'dart:convert';

import 'package:dio/dio.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/models/request_service.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/setup_provider.dart';
import 'package:onyx/screens/auth/widgets/setup_code_hint.dart';
import 'package:onyx/screens/home/home_empty_view.dart';
import 'package:onyx/screens/setup/setup_launcher.dart';
import 'package:onyx/screens/setup/setup_wizard_screen.dart';
import 'package:onyx/screens/setup/widgets/setup_home_card.dart';
import 'package:onyx/screens/setup/widgets/setup_tmdb_step.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_doubles.dart';

/// L'assistant de première installation (ADR-0165) contre un faux serveur :
/// le verrou de l'étape Demandes, le lien TMDB, le test de la clé, la reprise
/// par la checklist de l'accueil, et le repli sur un serveur plus ancien.

SetupState _state({
  bool completed = false,
  int libraries = 0,
  bool tmdb = false,
  bool requests = false,
  bool? available,
}) =>
    SetupState(
      completed: completed,
      libraryCount: libraries,
      librariesDone: libraries > 0,
      tmdbDone: tmdb,
      requestsDone: requests,
      requestsAvailable: available ?? tmdb,
    );

ServerSettings _settings({bool tmdbKey = false}) => ServerSettings(
      mediaHubUrl: '',
      mediaHubApiKeySet: false,
      tmdbApiKeySet: tmdbKey,
      tmdbLanguage: 'fr-FR',
      playbackLogsEnabled: true,
      playbackStatsEnabled: true,
    );

/// Un serveur réduit à ce que l'assistant demande.
class _FakeApi extends ApiClient {
  SetupState? guide;
  ServerSettings settings = _settings();
  final List<TmdbTest?> tmdbAnswers = [];
  final List<String?> tmdbTested = [];
  LibraryFolders folders = LibraryFolders.none;
  List<MediaLibrary> libraries = [];
  final List<String> created = [];
  int completes = 0;
  int guideReads = 0;

  @override
  Future<SetupState?> getSetupGuide() async {
    guideReads++;
    return guide;
  }

  @override
  Future<void> completeSetup() async {
    completes++;
    guide = guide?.copyWith(completed: true);
  }

  @override
  Future<ServerSettings> getServerSettings() async => settings;

  @override
  Future<bool> supportsRequestServices() async => true;

  @override
  Future<TmdbTest?> testTmdbKey({String? apiKey}) async {
    tmdbTested.add(apiKey);
    return tmdbAnswers.isEmpty ? null : tmdbAnswers.removeAt(0);
  }

  @override
  Future<LibraryFolders> getLibraryFolders() async => folders;

  @override
  Future<List<MediaLibrary>> getLibraries() async => libraries;

  @override
  Future<MediaLibrary> createLibrary({
    required String name,
    required LibraryKind kind,
    required String path,
  }) async {
    created.add('$name ${kind.wire} $path');
    final library =
        MediaLibrary(id: libraries.length + 1, name: name, kind: kind, path: path);
    libraries = [...libraries, library];
    guide = guide?.copyWith(
        libraryCount: libraries.length, librariesDone: true);
    return library;
  }

  @override
  Future<bool> getScanStatus() async => false;

  @override
  Future<List<HomeMediaItem>> getMovies() async => [];

  @override
  Future<List<Media>> getShows() async => [];
}

Future<SetupProvider> _pumpWizard(
  WidgetTester tester,
  _FakeApi api, {
  SetupStep? step,
  bool tv = false,
  List<String>? opened,
  bool opensBrowser = true,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final setup = SetupProvider(api);
  addTearDown(setup.dispose);
  await setup.load();
  final library = LibraryProvider(api);
  addTearDown(library.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<SetupProvider>.value(value: setup),
      ChangeNotifierProvider<LibraryProvider>.value(value: library),
    ],
    // Le TvScope est au-dessus du navigateur, comme dans l'app : la page
    // poussée le voit.
    child: TvScope(
      isTv: tv,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SetupWizardScreen(
                      initialStep: step,
                      openUrl: (url) async {
                        opened?.add(url);
                        return opensBrowser;
                      },
                    ),
                  ),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return setup;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppLanguage.notifier.value = AppLanguage.french);

  group('contrat : ce que le serveur répond', () {
    test('GET /api/setup/state', () {
      final state = SetupState.fromJson(jsonDecode('''
{"completed":false,"libraries":{"count":2,"done":true},
 "tmdb":{"done":true},"requests":{"done":false,"available":true}}''')
          as Map<String, dynamic>);
      expect(state.completed, isFalse);
      expect(state.libraryCount, 2);
      expect(state.doneSteps, 2);
      expect(state.requestsAvailable, isTrue);
    });

    test('POST /api/settings/tmdb/test : les trois causes', () {
      TmdbTest parse(String reason) => TmdbTest.fromJson(
          {'ok': reason == 'ok', 'reason': reason, 'message': 'm'});
      expect(parse('ok').reason, TmdbTestReason.ok);
      expect(parse('invalid_key').reason, TmdbTestReason.invalidKey);
      expect(parse('unreachable').reason, TmdbTestReason.unreachable);
      expect(parse('no_key').reason, TmdbTestReason.noKey);
      // Une cause ajoutée par un serveur plus récent garde sa phrase.
      expect(parse('quota').reason, TmdbTestReason.unknown);
    });
  });

  group('un serveur plus ancien répond 404 : l’app se comporte comme avant',
      () {
    ResponseBody notFound() => ResponseBody.fromString(
        jsonEncode({'error': 'not found'}), 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

    ApiClient old() => ApiClient(
        httpClient: Dio()..httpClientAdapter = Adapter((_) => notFound()));

    test('ni état, ni test de clé, ni explorateur', () async {
      final api = old();
      expect(await api.getSetupGuide(), isNull);
      expect(await api.testTmdbKey(apiKey: 'abc'), isNull);
      expect(await api.browseFolders(), isNull);
      // Terminer ne casse rien non plus.
      await api.completeSetup();
    });

    test('l’assistant ne s’ouvre pas et la checklist n’existe pas', () async {
      final api = _FakeApi();
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);
      expect(
          await shouldOpenSetupWizard(setup, manageSettings: true), isFalse);
      expect(setup.needsSetup, isFalse);
    });

    testWidgets('l’accueil n’a pas de checklist', (tester) async {
      final api = _FakeApi();
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);
      await setup.load();
      await tester.pumpWidget(ChangeNotifierProvider<SetupProvider>.value(
        value: setup,
        child: const MaterialApp(home: Scaffold(body: SetupHomeCard(canManage: true))),
      ));
      expect(find.textContaining('Finir l’installation'), findsNothing);
    });
  });

  group('l’ouverture automatique', () {
    test('une fois par appareil, pour qui administre', () async {
      final api = _FakeApi()..guide = _state();
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);

      expect(
          await shouldOpenSetupWizard(setup, manageSettings: true), isTrue);
      expect(
          await shouldOpenSetupWizard(setup, manageSettings: true), isFalse,
          reason: 'quitté, l’assistant ne revient pas : la checklist reprend');
    });

    test('un compte sans manage_settings ne voit rien et ne demande rien',
        () async {
      final api = _FakeApi()..guide = _state();
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);

      expect(
          await shouldOpenSetupWizard(setup, manageSettings: false), isFalse);
      expect(api.guideReads, 0);
    });

    test('une installation terminée ne rouvre rien', () async {
      final api = _FakeApi()..guide = _state(completed: true);
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);
      expect(
          await shouldOpenSetupWizard(setup, manageSettings: true), isFalse);
    });
  });

  group('étape 2 : la clé TMDB', () {
    testWidgets('le lien ouvre themoviedb.org/settings/api', (tester) async {
      final opened = <String>[];
      await _pumpWizard(tester, _FakeApi()..guide = _state(libraries: 1),
          step: SetupStep.tmdb, opened: opened);

      await tester.tap(find.text('Ouvrir themoviedb.org/settings/api'));
      await tester.pumpAndSettle();

      expect(opened, [kTmdbApiSettingsUrl]);
      expect(kTmdbApiSettingsUrl, 'https://www.themoviedb.org/settings/api');
    });

    testWidgets('sans navigateur, l’adresse est dite au lieu de rester muette',
        (tester) async {
      // Le presse-papiers est un canal de la plateforme : sans doublure, il
      // ne répond jamais dans un test.
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pumpWizard(tester, _FakeApi()..guide = _state(libraries: 1),
          step: SetupStep.tmdb, opensBrowser: false);

      await tester.tap(find.text('Ouvrir themoviedb.org/settings/api'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Adresse : themoviedb.org/settings/api'),
          findsOneWidget);
      expect(copied, [kTmdbApiSettingsUrl]);
    });

    testWidgets(
        'sur TV, l’adresse est écrite en clair, sans bouton, et l’étape se passe',
        (tester) async {
      await _pumpWizard(tester, _FakeApi()..guide = _state(libraries: 1),
          step: SetupStep.tmdb, tv: true);

      expect(find.text('Ouvrir themoviedb.org/settings/api'), findsNothing);
      expect(find.text('themoviedb.org/settings/api'), findsOneWidget);
      expect(find.textContaining('télécommande est pénible'), findsOneWidget);
      expect(find.text('Passer'), findsOneWidget);
    });

    testWidgets('elle dit à quoi sert la clé et qu’elle est gratuite',
        (tester) async {
      await _pumpWizard(tester, _FakeApi()..guide = _state(libraries: 1),
          step: SetupStep.tmdb);

      expect(find.textContaining('affiches, les résumés, les logos'),
          findsOneWidget);
      expect(find.textContaining('gratuite pour un usage non commercial'),
          findsOneWidget);
      expect(find.textContaining('licence auprès de TMDB'), findsOneWidget);
      expect(find.textContaining('pas le jeton d’accès'), findsWidgets);
    });

    testWidgets('sans clé, l’étape se passe avec un avertissement',
        (tester) async {
      await _pumpWizard(tester, _FakeApi()..guide = _state(libraries: 1),
          step: SetupStep.tmdb);

      expect(find.textContaining('Sans clé, pas d’affiches ni de métadonnées'),
          findsWidgets);
      expect(find.text('Passer'), findsOneWidget);
    });

    testWidgets('avec une clé enregistrée, le bouton dit Continuer',
        (tester) async {
      final api = _FakeApi()
        ..guide = _state(libraries: 1, tmdb: true)
        ..settings = _settings(tmdbKey: true);
      await _pumpWizard(tester, api, step: SetupStep.tmdb);

      expect(find.text('Continuer'), findsOneWidget);
      expect(find.text('Passer'), findsNothing);
    });

    testWidgets('la langue des titres suit la langue de l’app', (tester) async {
      AppLanguage.notifier.value = AppLanguage.english;
      await _pumpWizard(tester, _FakeApi()..guide = _state(libraries: 1),
          step: SetupStep.tmdb);

      final menu = tester.widget<DropdownMenu<String>>(
          find.byType(DropdownMenu<String>));
      expect(menu.initialSelection, 'en-US');
    });

    testWidgets('Tester : une clé refusée n’est pas un TMDB injoignable',
        (tester) async {
      final api = _FakeApi()
        ..guide = _state(libraries: 1)
        ..tmdbAnswers.addAll([
          const TmdbTest(ok: false, reason: TmdbTestReason.invalidKey),
          const TmdbTest(ok: false, reason: TmdbTestReason.unreachable),
          const TmdbTest(ok: true, reason: TmdbTestReason.ok),
        ]);
      await _pumpWizard(tester, api, step: SetupStep.tmdb);
      await tester.enterText(find.byType(TextField).first, 'ma-cle');

      await tester.tap(find.text('Tester'));
      await tester.pumpAndSettle();
      expect(find.textContaining('TMDB refuse cette clé'), findsOneWidget);

      await tester.tap(find.text('Tester'));
      await tester.pumpAndSettle();
      expect(find.textContaining('n’arrive pas à joindre TMDB'),
          findsOneWidget);
      expect(find.textContaining('La clé n’est pas en cause'), findsOneWidget);
      expect(find.textContaining('TMDB refuse cette clé'), findsNothing);

      await tester.tap(find.text('Tester'));
      await tester.pumpAndSettle();
      expect(find.text('La clé est acceptée par TMDB.'), findsOneWidget);
      expect(api.tmdbTested, ['ma-cle', 'ma-cle', 'ma-cle']);
    });
  });

  testWidgets(
      'à la télécommande, le bouton principal a le focus et OK passe à la suite',
      (tester) async {
    await _pumpWizard(tester, _FakeApi()..guide = _state(libraries: 1),
        step: SetupStep.tmdb, tv: true);

    // « Passer » est l'entrée de l'écran : OK, sans autre geste, passe à l'étape
    // des demandes (la clé se tape mal à la télécommande).
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Les demandes'), findsOneWidget);
  });

  group('étape 3 : les demandes', () {
    testWidgets('grisée tant qu’il n’y a pas de TMDB, avec le chemin du retour',
        (tester) async {
      final api = _FakeApi()..guide = _state(libraries: 1, available: false);
      await _pumpWizard(tester, api, step: SetupStep.requests);

      expect(find.textContaining('Configurez d’abord TMDB'), findsOneWidget);
      // Le formulaire est là mais hors de portée.
      expect(find.byType(IgnorePointer), findsWidgets);

      await tester.tap(find.text('Configurer TMDB'));
      await tester.pumpAndSettle();
      expect(find.text('La clé TMDB'), findsOneWidget,
          reason: 'le bouton ramène à l’étape 2');
    });

    testWidgets('libre quand TMDB est réglé', (tester) async {
      final api = _FakeApi()
        ..guide = _state(libraries: 1, tmdb: true)
        ..settings = _settings(tmdbKey: true);
      await _pumpWizard(tester, api, step: SetupStep.requests);

      expect(find.textContaining('Configurez d’abord TMDB'), findsNothing);
      expect(find.text('Tester'), findsOneWidget);
      expect(find.text('Overseerr'), findsWidgets);
    });

    testWidgets('l’état se relit : TMDB réglé à l’étape d’avant déverrouille',
        (tester) async {
      final api = _FakeApi()..guide = _state(libraries: 1, available: false);
      final setup = await _pumpWizard(tester, api, step: SetupStep.requests);
      expect(find.textContaining('Configurez d’abord TMDB'), findsOneWidget);

      api.guide = _state(libraries: 1, tmdb: true);
      await setup.load();
      await tester.pumpAndSettle();
      expect(find.textContaining('Configurez d’abord TMDB'), findsNothing);
    });
  });

  group('étape 1 : les bibliothèques', () {
    testWidgets('« Ajouter tous les dossiers trouvés » les crée une par une',
        (tester) async {
      final api = _FakeApi()
        ..guide = _state()
        ..folders = const LibraryFolders(root: '/media', folders: [
          LibraryFolder(
              path: '/media/Films', name: 'Films', kind: LibraryKind.movies),
          LibraryFolder(
              path: '/media/Séries', name: 'Séries', kind: LibraryKind.shows),
        ]);
      await _pumpWizard(tester, api, step: SetupStep.libraries);

      expect(find.textContaining('Une bibliothèque, c’est un dossier'),
          findsOneWidget);
      await tester.tap(find.textContaining('Ajouter tous les dossiers trouvés'));
      await tester.pumpAndSettle();

      expect(api.created,
          ['Films movies /media/Films', 'Séries shows /media/Séries']);
      // La création lance l'analyse côté serveur : l'étape se continue.
      expect(find.text('Continuer'), findsOneWidget);
    });

    testWidgets('Précédent revient à l’étape d’avant', (tester) async {
      final api = _FakeApi()..guide = _state(libraries: 1, tmdb: true);
      await _pumpWizard(tester, api, step: SetupStep.tmdb);

      await tester.tap(find.text('Précédent'));
      await tester.pumpAndSettle();
      expect(find.text('Vos bibliothèques'), findsOneWidget);
      expect(find.text('Précédent'), findsNothing,
          reason: 'la première étape n’a rien avant elle');
    });
  });

  group('étape 4 et checklist', () {
    testWidgets('Terminer clôt l’installation et ferme l’assistant',
        (tester) async {
      final api = _FakeApi()..guide = _state(libraries: 1, tmdb: true);
      await _pumpWizard(tester, api, step: SetupStep.finish);

      await tester.tap(find.text('Terminer'));
      await tester.pumpAndSettle();

      expect(api.completes, 1);
      expect(find.byType(SetupWizardScreen), findsNothing);
    });

    testWidgets(
        'la checklist de l’accueil reprend l’étape où l’on s’était arrêté',
        (tester) async {
      final api = _FakeApi()
        ..guide = _state(libraries: 1, tmdb: false)
        ..settings = _settings();
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);
      await setup.load();
      final library = LibraryProvider(api);
      addTearDown(library.dispose);
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<SetupProvider>.value(value: setup),
          ChangeNotifierProvider<LibraryProvider>.value(value: library),
        ],
        child: const MaterialApp(
            home: Scaffold(body: SetupHomeCard(canManage: true))),
      ));

      expect(find.text('Finir l’installation : 1/3'), findsOneWidget);

      await tester.tap(find.text('Ajouter la clé TMDB'));
      await tester.pumpAndSettle();
      expect(find.text('La clé TMDB'), findsOneWidget,
          reason: 'la ligne rouvre l’étape TMDB, pas la première');
    });

    testWidgets('Ignorer ferme l’installation et fait disparaître la checklist',
        (tester) async {
      final api = _FakeApi()..guide = _state(libraries: 1);
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);
      await setup.load();
      await tester.pumpWidget(ChangeNotifierProvider<SetupProvider>.value(
        value: setup,
        child: const MaterialApp(
            home: Scaffold(body: SetupHomeCard(canManage: true))),
      ));

      await tester.tap(find.text('Ignorer'));
      await tester.pumpAndSettle();

      expect(api.completes, 1);
      expect(find.textContaining('Finir l’installation'), findsNothing);
    });

    testWidgets('un compte sans manage_settings ne voit pas la checklist',
        (tester) async {
      final api = _FakeApi()..guide = _state(libraries: 1);
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);
      await setup.load();
      await tester.pumpWidget(ChangeNotifierProvider<SetupProvider>.value(
        value: setup,
        child: const MaterialApp(
            home: Scaffold(body: SetupHomeCard(canManage: false))),
      ));
      expect(find.textContaining('Finir l’installation'), findsNothing);
    });

    testWidgets(
        'sans bibliothèque, l’accueil montre la checklist à la place du simple '
        '« Aucune bibliothèque »', (tester) async {
      final api = _FakeApi()..guide = _state();
      final setup = SetupProvider(api);
      addTearDown(setup.dispose);
      await setup.load();
      final home = HomeProvider(api);
      addTearDown(home.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<SetupProvider>.value(
        value: setup,
        child: MaterialApp(
          home: Scaffold(
            body: HomeEmptyView(
              libraries: const [],
              permissions: Permissions.all,
              homeProvider: home,
            ),
          ),
        ),
      ));

      expect(find.text('Finir l’installation : 0/3'), findsOneWidget);
      expect(find.text('Aucune bibliothèque'), findsNothing);
    });
  });

  testWidgets('l’inscription du propriétaire dit où lire le code d’installation',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SetupCodeHint())));
    expect(find.text('docker logs onyx-server'), findsOneWidget);
    expect(RequestService.values, isNotEmpty);
  });
}
