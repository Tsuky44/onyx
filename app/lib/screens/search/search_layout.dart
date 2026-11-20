import '../../models/media_request.dart';
import '../../models/models.dart';
import 'search_shelves.dart';

/// Les pastilles d'une recherche (bureau, téléphone) : ce que les résultats
/// gardent.
enum SearchFilter { all, movies, shows, unavailable }

/// Un titre des résultats : de la bibliothèque, ou absent du serveur.
sealed class SearchHit {
  const SearchHit();

  /// Un titre qui reste le même d'une frappe à l'autre : l'aperçu ne
  /// rejoue son fondu que lorsqu'il change.
  Object get identity;
}

final class LibraryHit extends SearchHit {
  const LibraryHit(this.media);

  final Media media;

  @override
  Object get identity => ('library', media.type, media.id);
}

final class UnavailableHit extends SearchHit {
  const UnavailableHit(this.item);

  final RequestMediaItem item;

  @override
  Object get identity => ('catalog', item.mediaType, item.id);
}

/// Ce que montre une recherche pour une pastille : les titres
/// de la bibliothèque, puis les titres absents (ADR-0129).
class SearchLayout {
  const SearchLayout._({
    required this.library,
    required this.unavailable,
    required this.movieCount,
    required this.showCount,
    required this.unavailableCount,
  });

  /// Les titres de la bibliothèque que la pastille garde.
  final List<Media> library;

  /// Les titres absents que la pastille garde.
  final List<RequestMediaItem> unavailable;

  /// Les décomptes des pastilles, sur toute la recherche : changer de
  /// pastille ne les change pas.
  final int movieCount;
  final int showCount;
  final int unavailableCount;

  int get total => movieCount + showCount + unavailableCount;

  /// Les longueurs des grilles empilées, dans l'ordre de l'écran.
  List<int> get sections => [library.length, unavailable.length];

  /// Tous les titres affichés, dans l'ordre de la sélection au clavier.
  List<SearchHit> get hits => [
        for (final media in library) LibraryHit(media),
        for (final item in unavailable) UnavailableHit(item),
      ];

  factory SearchLayout.of(
    SearchShelves shelves,
    SearchFilter filter,
  ) {
    final movies = shelves.movies;
    final shows = shelves.shows;
    return SearchLayout._(
      library: switch (filter) {
        SearchFilter.all => shelves.library,
        SearchFilter.movies => movies,
        SearchFilter.shows => shows,
        SearchFilter.unavailable => const [],
      },
      unavailable: switch (filter) {
        SearchFilter.all || SearchFilter.unavailable => shelves.unavailable,
        _ => const [],
      },
      movieCount: movies.length,
      showCount: shows.length,
      unavailableCount: shelves.unavailable.length,
    );
  }

  /// La grille des derniers ajouts, quand rien n'est tapé.
  factory SearchLayout.recent(List<Media> recent) => SearchLayout._(
        library: recent,
        unavailable: const [],
        movieCount: 0,
        showCount: 0,
        unavailableCount: 0,
      );
}
