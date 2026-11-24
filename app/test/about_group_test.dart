import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/l10n/localized_asset.dart';
import 'package:onyx/screens/settings/legal_document_screen.dart';
import 'package:onyx/screens/settings/widgets/about_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AboutGroup())),
      ));

  // Ce que les magasins et les conditions de TMDB exigent de lire dans l'app.
  testWidgets(
      'À propos porte l’attribution TMDB et le rappel de responsabilité',
      (tester) async {
    await pump(tester);

    expect(find.textContaining(AboutGroup.tmdbAttribution), findsOneWidget);
    expect(find.textContaining(AboutGroup.responsibility), findsOneWidget);
    expect(find.text('Licences open source'), findsOneWidget);
  });

  testWidgets('la politique de confidentialité s’ouvre dans l’app',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text(LegalDocument.privacy.title));
    await tester.pumpAndSettle();

    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.textContaining('ne vend aucune donnée vous concernant'),
        findsOneWidget);
  });

  // Lu sur le disque : `rootBundle` ne répond pas hors d'un `testWidgets`.
  test('chaque document légal est un fichier du dossier embarqué', () {
    expect(
        File('pubspec.yaml').readAsStringSync(), contains('- assets/legal/'));
    for (final document in LegalDocument.values) {
      expect(File(document.asset).readAsStringSync().trim(), isNotEmpty,
          reason: document.asset);
    }
    expect(File('assets/legal/third_party.txt').readAsStringSync(),
        contains('LGPL'));
  });

  testWidgets('en anglais, l’écran légal lit la traduction anglaise', (
    tester,
  ) async {
    addTearDown(AppLanguage.resetForTest);
    AppLanguage.notifier.value = AppLanguage.english;
    await tester.pumpWidget(
      const MaterialApp(
        home: LegalDocumentScreen(document: LegalDocument.privacy),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('does not receive, store, share or sell'),
      findsOneWidget,
    );
    expect(
      find.textContaining('The French version is the authoritative'),
      findsOneWidget,
    );
  });

  testWidgets('en français, l’écran légal lit la version qui fait foi', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LegalDocumentScreen(document: LegalDocument.terms),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('régies par le droit français'), findsOneWidget);
  });

  test('une langue sans traduction retombe sur le français', () async {
    final bundle = _OnlyFrenchBundle();
    expect(
      await loadLocalizedAsset(
        'assets/legal/conditions.txt',
        bundle: bundle,
        language: AppLanguage.english,
      ),
      'fr',
    );
    expect(bundle.requested, [
      'assets/legal/conditions.en.txt',
      'assets/legal/conditions.txt',
    ]);
  });

  // Chaque texte légal a sa traduction pour chaque langue de l'interface, et
  // chaque traduction dit que le français fait foi.
  test('chaque document légal est traduit dans chaque langue', () {
    const sources = [
      'assets/legal/confidentialite.txt',
      'assets/legal/conditions.txt',
      'assets/legal/third_party.txt',
    ];
    expect(sources, containsAll(LegalDocument.values.map((d) => d.asset)));
    for (final source in sources) {
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.french) continue;
        final path = localizedAssetPath(source, language);
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    }
    expect(
      File('assets/legal/conditions.en.txt').readAsStringSync(),
      contains('French version is the authoritative text'),
    );
  });
}

class _OnlyFrenchBundle extends CachingAssetBundle {
  final List<String> requested = [];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    if (key.endsWith('.en.txt')) throw FlutterError('Unable to load asset');
    return ByteData.sublistView(Uint8List.fromList('fr'.codeUnits));
  }
}
