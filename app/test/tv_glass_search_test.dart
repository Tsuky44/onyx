import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/screens/library/search_results_screen.dart';
import 'package:onyx/screens/search/tv_search_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/glass_catalog_search.dart';
import 'package:onyx/widgets/global/glass_chrome.dart';
import 'package:onyx/widgets/global/media_card.dart';
import 'package:provider/provider.dart';

import 'support/tv_nav_harness.dart';

class _FakeApiClient extends ApiClient {
  @override
  String get baseUrl => 'http://localhost:8080';

  @override
  Future<List<HomeMediaItem>> getMovies() async => [
        HomeMediaItem.fromJson({
          'id': 1,
          'type': 'movie',
          'title': 'Dune',
          'duration': 6000,
        }),
      ];

  @override
  Future<List<Media>> getShows() async => [];
}

void main() {
  group('GlassSearchInput sur téléviseur', () {
    testWidgets(
        'confirmer avec Select / OK sur la télécommande valide directement la recherche',
        (tester) async {
      TvMode.enabled.value = true;
      addTearDown(() => TvMode.enabled.value = false);

      String? submittedQuery;
      final controller = TextEditingController(text: 'Matrix');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassSearchInput(
              controller: controller,
              focusNode: focusNode,
              hint: 'Rechercher',
              onSubmitted: (query) => submittedQuery = query,
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      // Touche OK / Select de la télécommande TV
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(submittedQuery, 'Matrix');
    });

    testWidgets('confirmer avec Entrée valide directement la recherche',
        (tester) async {
      TvMode.enabled.value = true;
      addTearDown(() => TvMode.enabled.value = false);

      String? submittedQuery;
      final controller = TextEditingController(text: 'Inception');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassSearchInput(
              controller: controller,
              focusNode: focusNode,
              hint: 'Rechercher',
              onSubmitted: (query) => submittedQuery = query,
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submittedQuery, 'Inception');
    });

    testWidgets(
        'appui sur Select / OK avec texte vide réclame l’ouverture du clavier virtuel',
        (tester) async {
      TvMode.enabled.value = true;
      addTearDown(() => TvMode.enabled.value = false);

      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.textInput, null));

      final controller = TextEditingController(text: '');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassSearchInput(
              controller: controller,
              focusNode: focusNode,
              hint: 'Rechercher',
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(calls, contains('TextInput.show'));
    });
  });

  group('GlassCatalogSearch sur téléviseur', () {
    TvNavHarness.forEachEngine((engine) {
      testWidgets(
          'OK ouvre la page de recherche et le clavier du système '
          '(ADR-0126)', (tester) async {
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.textInput, null));

        final apiClient = _FakeApiClient();
        final libraryProvider = LibraryProvider(apiClient);
        final authProvider = AuthProvider(apiClient);
        final searchProvider = SearchProvider();

        await TvNavHarness.pump(
          tester,
          const Scaffold(
            body: GlassCatalogSearch(),
          ),
          around: (app) => MultiProvider(
            providers: [
              Provider<ApiClient>.value(value: apiClient),
              ChangeNotifierProvider.value(value: libraryProvider),
              ChangeNotifierProvider.value(value: authProvider),
              ChangeNotifierProvider.value(value: searchProvider),
            ],
            child: app,
          ),
          engine: engine,
          isTv: true,
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        // La page de recherche d'un téléviseur, et non la grille du bureau.
        // Un seul OK : le clavier du système s'ouvre avec elle. Son parcours
        // est épinglé par `tv_search_screen_test.dart`.
        expect(find.byType(TvSearchScreen), findsOneWidget);
        expect(find.byType(SearchResultsScreen), findsNothing);
        expect(calls, contains('TextInput.show'));
        // Le catalogue est déjà là : le film du serveur est proposé.
        expect(find.byType(MediaCard), findsOneWidget);
      });
    });
  });
}
