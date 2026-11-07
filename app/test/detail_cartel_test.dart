import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/widgets/global/detail_info_table.dart';

void main() {
  testWidgets('DetailInfoTable.forDetails affiche le cartel complet d’un film',
      (tester) async {
    final details = MediaDetails(
      id: 42,
      type: MediaType.movie,
      title: 'Dune : Deuxième Partie',
      originalTitle: 'Dune: Part Two',
      director: 'Denis Villeneuve',
      writers: ['Denis Villeneuve', 'Jon Spaihts'],
      releaseDate: '2024-03-01',
      runtime: 166,
      voteAverage: 8.3,
      originalLanguage: 'en',
      countries: ['US'],
      studios: ['Legendary Pictures', 'Warner Bros.'],
      genres: ['Science-Fiction', 'Aventure'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DetailInfoTable.forDetails(
              details,
              keywords: ['désert', 'prophétie', 'épice'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nature, langue et pays
    expect(find.text('FILM · ANGLAIS · ÉTATS-UNIS'), findsOneWidget);

    // Titre et réalisation
    expect(find.text('Dune : Deuxième Partie'), findsOneWidget);
    expect(find.text('Réalisé par Denis Villeneuve'), findsOneWidget);

    // Faits clés
    expect(find.text('Sortie'), findsOneWidget);
    expect(find.text('1 mars 2024'), findsOneWidget);
    expect(find.text('Durée'), findsOneWidget);
    expect(find.text('2h 46min'), findsOneWidget);
    expect(find.text('Note TMDB'), findsOneWidget);
    expect(find.text('83%'), findsOneWidget);

    // Lignes détaillées
    expect(find.text('Titre original'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('Scénario'), findsOneWidget);
    expect(find.text('Denis Villeneuve, Jon Spaihts'), findsOneWidget);
    expect(find.text('Studios'), findsOneWidget);
    expect(find.text('Legendary Pictures, Warner Bros.'), findsOneWidget);

    // Mots-clés
    expect(find.text('désert'), findsOneWidget);
    expect(find.text('prophétie'), findsOneWidget);
    expect(find.text('épice'), findsOneWidget);
  });

  testWidgets('DetailInfoTable.forDetails affiche le cartel d’une série',
      (tester) async {
    final details = MediaDetails(
      id: 99,
      type: MediaType.show,
      title: 'Breaking Bad',
      director: 'Vince Gilligan',
      releaseDate: '2008-01-20',
      numberOfSeasons: 5,
      numberOfEpisodes: 62,
      voteAverage: 8.9,
      originalLanguage: 'en',
      countries: ['US'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DetailInfoTable.forDetails(details),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SÉRIE TÉLÉVISÉE · ANGLAIS · ÉTATS-UNIS'), findsOneWidget);
    expect(find.text('Breaking Bad'), findsOneWidget);
    expect(find.text('Créée par Vince Gilligan'), findsOneWidget);
    expect(find.text('Première diffusion'), findsOneWidget);
    expect(find.text('5 saisons, 62 épisodes'), findsOneWidget);
    expect(find.text('89%'), findsOneWidget);
  });
}
