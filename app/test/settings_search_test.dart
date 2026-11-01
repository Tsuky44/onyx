import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/settings/settings_categories.dart';
import 'package:onyx/screens/settings/settings_search.dart';
import 'package:onyx/screens/settings/widgets/settings_search_field.dart';

List<SettingsSearchEntry> _indexFor(Permissions p) =>
    buildSettingsSearchIndex(settingsCategoriesFor(p), p);

void main() {
  test('un mot de passe se retrouve par « mdp », sans accent ni casse', () {
    final index = _indexFor(const Permissions());

    for (final query in ['mot de passe', 'MDP', 'Mot  de  PASSE']) {
      final titles = searchSettings(index, query).map((e) => e.title);
      expect(titles, contains('Changer mon mot de passe'), reason: query);
    }
  });

  test('tous les mots tapés doivent correspondre, dans n’importe quel ordre',
      () {
    final index = _indexFor(const Permissions());

    expect(searchSettings(index, 'audio langue').map((e) => e.title),
        contains('Langue audio par défaut'));
    expect(searchSettings(index, 'audio zzz'), isEmpty);
    expect(searchSettings(index, '   '), isEmpty);
  });

  test('les titres qui contiennent la recherche passent avant les mots-clés',
      () {
    final index = _indexFor(const Permissions());
    final hits = searchSettings(index, 'journal');

    expect(hits.first.title, 'Journal');
  });

  test('un compte sans droits ne trouve pas les réglages d’administration', () {
    final member = _indexFor(const Permissions());
    final admin = _indexFor(Permissions.all);

    expect(searchSettings(member, 'tmdb'), isEmpty);
    expect(searchSettings(member, 'sous-titres'), isEmpty);
    expect(searchSettings(admin, 'tmdb'), isNotEmpty);
    expect(searchSettings(admin, 'sous-titres'), isNotEmpty);
  });

  test('chaque entrée de l’index mène à une page qui existe', () {
    final categories = settingsCategoriesFor(Permissions.all);

    for (final entry in _indexFor(Permissions.all)) {
      expect(categories.any((c) => c.opens(entry.section)), isTrue,
          reason: '« ${entry.title} » vise ${entry.section}, absente des '
              'catégories : la recherche ouvrirait une page vide.');
    }
  });

  testWidgets('un résultat ouvre sa page, sans résultat le dit', (tester) async {
    final index = _indexFor(Permissions.all);
    String? opened;

    Widget host(String query) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsSearchResults(
                index: index,
                query: query,
                onSelect: (hit) => opened = hit.section,
              ),
            ),
          ),
        );

    await tester.pumpWidget(host('qualité automatique'));
    await tester.tap(find.text('Qualité automatique'));
    expect(opened, 'playback');

    await tester.pumpWidget(host('zzzz'));
    expect(find.textContaining('Aucun résultat'), findsOneWidget);
  });
}
