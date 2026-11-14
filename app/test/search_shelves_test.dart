import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_request.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/providers/library_provider.dart';
import 'package:onyx/screens/search/search_shelves.dart';

import 'support/search_catalog_fakes.dart';

/// Le rangement d'une recherche (ADR-0129) : la bibliothèque d'abord, puis
/// les titres que le catalogue connaît et que le serveur n'a pas.
void main() {
  late LibraryProvider library;

  setUp(() async {
    final api = SearchCatalogApi(
      movies: [
        libraryMovie(1, 'Dune', tmdbId: 438631, day: 3),
        libraryMovie(2, 'Le Voyage de Chihiro', tmdbId: 129, day: 1),
      ],
      shows: [
        libraryMedia(11, 'Dune : Prophétie',
            type: MediaType.show, tmdbId: 90228, day: 2),
      ],
    );
    library = LibraryProvider(api);
    await library.ensureCatalogLoaded();
  });

  List<String> titles(Iterable<Media> medias) =>
      [for (final media in medias) media.title];

  test('sans catalogue, la recherche est celle de la bibliothèque', () {
    final shelves = SearchShelves.of(library, 'dune');

    expect(titles(shelves.movies), ['Dune']);
    expect(titles(shelves.shows), ['Dune : Prophétie']);
    expect(shelves.unavailable, isEmpty);
  });

  test(
      'un titre du catalogue que le serveur n’a pas forme le rayon des '
      'absents, demandé ou non', () {
    final shelves = SearchShelves.of(library, 'dune', catalog: [
      catalogTitle(693134, 'Dune : Deuxième partie'),
      catalogTitle(841, 'Dune (1984)', status: RequestMediaStatus.pending),
    ]);

    expect(titles(shelves.library), ['Dune', 'Dune : Prophétie']);
    expect(
      [for (final item in shelves.unavailable) item.title],
      ['Dune : Deuxième partie', 'Dune (1984)'],
    );
  });

  test(
      'un titre déjà trouvé dans la bibliothèque ne revient pas parmi les '
      'absents', () {
    final shelves = SearchShelves.of(library, 'dune', catalog: [
      catalogTitle(438631, 'Dune', status: RequestMediaStatus.available),
      catalogTitle(90228, 'Dune : Prophétie',
          type: RequestMediaType.tv, status: RequestMediaStatus.partial),
    ]);

    expect(titles(shelves.library), ['Dune', 'Dune : Prophétie']);
    expect(shelves.unavailable, isEmpty);
  });

  test(
      'un titre que seul le catalogue reconnaît (titre original) rejoint les '
      'rayons de la bibliothèque', () {
    // « Spirited Away » ne correspond à aucun titre local ; le catalogue,
    // lui, sait que c'est « Le Voyage de Chihiro », que le serveur détient.
    final shelves = SearchShelves.of(library, 'spirited away', catalog: [
      catalogTitle(129, 'Le Voyage de Chihiro',
          status: RequestMediaStatus.available),
    ]);

    expect(titles(shelves.movies), ['Le Voyage de Chihiro']);
    expect(shelves.unavailable, isEmpty);
  });

  test('un film et une série de même numéro TMDB ne se confondent pas', () {
    final shelves = SearchShelves.of(library, 'dune', catalog: [
      catalogTitle(438631, 'Dune, la série', type: RequestMediaType.tv),
    ]);

    expect(
      [for (final item in shelves.unavailable) item.title],
      ['Dune, la série'],
    );
  });

  test(
      'un titre que le serveur dit détenir mais que ce compte ne voit pas '
      'n’est montré nulle part', () {
    final shelves = SearchShelves.of(library, 'alien', catalog: [
      catalogTitle(348, 'Alien', status: RequestMediaStatus.available),
    ]);

    expect(shelves.isEmpty, isTrue);
  });

  test('le catalogue qui répète un titre ne le montre qu’une fois', () {
    final shelves = SearchShelves.of(library, 'arrival', catalog: [
      catalogTitle(329865, 'Premier Contact'),
      catalogTitle(329865, 'Premier Contact'),
    ]);

    expect(shelves.unavailable, hasLength(1));
  });

  test('rien de tapé : aucun rayon, et les derniers ajouts en proposition',
      () {
    expect(SearchShelves.of(library, '  ').isEmpty, isTrue);
    expect(
      titles(SearchShelves.recentlyAdded(library, 2)),
      ['Dune', 'Dune : Prophétie'],
    );
  });
}
