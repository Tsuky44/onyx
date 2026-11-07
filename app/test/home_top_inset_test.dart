import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/desktop_window.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/auth_provider.dart';
import 'package:onyx/providers/home_provider.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/providers/search_provider.dart';
import 'package:onyx/screens/home/home_screen.dart';
import 'package:onyx/services/api_client.dart';
import 'package:provider/provider.dart';

class _MockApi extends ApiClient {
  @override
  Future<HomeResponse> getHome() async => HomeResponse.fromJson({
        'continue_watching': [],
        'recent_movies': [],
        'recent_shows': [],
        'discovery_movies': [],
        'discovery_shows': [],
      });

  @override
  Future<List<HomeMediaItem>> getMovies() async => [];

  @override
  Future<List<Media>> getShows() async => [];

  @override
  Future<IndexerStatus> getIndexerStatus() async => IndexerStatus.fromJson({});

  @override
  Future<List<MediaLibrary>> getLibraries() async => [];
}

void main() {
  testWidgets('l’accueil commence sous l’en-tête de verre sur grand écran',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockApi();
    late double expectedInset;

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api)),
        ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: MaterialApp(
        home: Builder(builder: (context) {
          expectedInset = shellHeaderHeight(context);
          return const HomeScreen(embedded: true);
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // Le premier sliver est un SizedBox qui ménage la place sous l'en-tête
    final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
    final matchingBox = sizedBoxes.where((box) => box.height == expectedInset);
    expect(matchingBox, isNotEmpty);
  });

  testWidgets('l’accueil commence sous la barre du haut sur téléphone',
      (tester) async {
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockApi();
    const expectedInset = 56.0; // padding top est 0 dans le test de base

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => HomeProvider(api)),
        ChangeNotifierProvider(create: (_) => LibraryProvider(api)),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: const MaterialApp(
        home: HomeScreen(embedded: false),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
    final matchingBox = sizedBoxes.where((box) => box.height == expectedInset);
    expect(matchingBox, isNotEmpty);
  });
}
