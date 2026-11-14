import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/services/unavailable_titles_search.dart';

import 'support/search_catalog_fakes.dart';

/// La recherche des titres que le serveur n'a pas (ADR-0129) : quand le
/// catalogue de demandes est interrogé, et ce que l'écran en montre en
/// attendant sa réponse.
void main() {
  const pause = Duration(milliseconds: 350);

  late SearchCatalogApi api;
  late UnavailableTitlesSearch search;
  late int answers;

  setUp(() {
    api = SearchCatalogApi(catalog: {
      'du': [catalogTitle(1, 'Dune'), catalogTitle(2, 'Dumbo')],
      'dun': [catalogTitle(1, 'Dune'), catalogTitle(3, 'Dunkerque')],
    });
    search = UnavailableTitlesSearch(api, debounce: pause);
    answers = 0;
    search.addListener(() => answers++);
  });
  tearDown(() => search.dispose());

  List<String> shown(String query) =>
      [for (final item in search.resultsFor(query)) item.title];

  testWidgets('une lettre seule n’interroge pas le catalogue', (tester) async {
    search.search('d', enabled: true);
    await tester.pump(pause * 2);

    expect(api.asked, isEmpty);
    expect(shown('d'), isEmpty);
  });

  testWidgets(
      'la requête part à la pause : une seule pour toute une rafale de '
      'frappes', (tester) async {
    search.search('du', enabled: true);
    await tester.pump(pause ~/ 2);
    search.search('dun', enabled: true);
    await tester.pump(pause ~/ 2);
    expect(api.asked, isEmpty, reason: 'la frappe n’a pas encore marqué de pause');

    await tester.pump(pause);
    expect(api.asked, ['dun']);
    expect(shown('dun'), ['Dune', 'Dunkerque']);
    expect(answers, 1);
  });

  testWidgets(
      'la réponse à une recherche déjà quittée est jetée', (tester) async {
    api.gate = Completer<void>();
    search.search('du', enabled: true);
    await tester.pump(pause);
    expect(api.asked, ['du']);

    // On a tapé une lettre de plus pendant que le catalogue répondait.
    search.search('dun', enabled: true);
    api.gate!.complete();
    api.gate = null;
    await tester.pump();
    expect(answers, 0);
    expect(shown('dun'), isEmpty);

    await tester.pump(pause);
    expect(shown('dun'), ['Dune', 'Dunkerque']);
    expect(answers, 1);
  });

  testWidgets(
      'entre deux réponses, la dernière reste, réduite aux titres qui '
      'correspondent encore', (tester) async {
    search.search('du', enabled: true);
    await tester.pump(pause);
    expect(shown('du'), ['Dune', 'Dumbo']);

    // « Dumbo » ne correspond plus ; « Dune » reste en attendant la réponse.
    search.search('dun', enabled: true);
    expect(shown('dun'), ['Dune']);

    await tester.pump(pause);
    expect(shown('dun'), ['Dune', 'Dunkerque']);
  });

  testWidgets('revenir à une recherche déjà répondue ne la redemande pas',
      (tester) async {
    search.search('du', enabled: true);
    await tester.pump(pause);
    search.search('dun', enabled: true);
    search.search('du', enabled: true);
    await tester.pump(pause * 2);

    expect(api.asked, ['du']);
    expect(shown('du'), ['Dune', 'Dumbo']);
  });

  testWidgets(
      'un compte qui ne peut rien demander n’interroge pas le catalogue',
      (tester) async {
    search.search('dun', enabled: false);
    await tester.pump(pause * 2);

    expect(api.asked, isEmpty);
    expect(shown('dun'), isEmpty);
  });

  testWidgets(
      'au retour d’une fiche de demande, la recherche se redemande sans '
      'attendre : le statut a pu changer', (tester) async {
    search.search('dun', enabled: true);
    await tester.pump(pause);
    api.catalog['dun'] = [
      catalogTitle(3, 'Dunkerque', status: RequestMediaStatus.pending),
    ];

    search.refresh();
    await tester.pump();
    expect(api.asked, ['dun', 'dun']);
    expect(
      search.resultsFor('dun').single.status,
      RequestMediaStatus.pending,
    );
  });

  testWidgets('un catalogue en panne laisse la recherche telle quelle',
      (tester) async {
    search.search('du', enabled: true);
    await tester.pump(pause);
    api.broken = true;

    search.search('dun', enabled: true);
    await tester.pump(pause);
    expect(answers, 1, reason: 'la panne ne prévient personne');
    expect(shown('dun'), ['Dune']);
  });
}
