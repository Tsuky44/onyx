import '../../models/media_request.dart';
import '../../models/models.dart';
import '../../providers/library_provider.dart';

/// Ce qu'une recherche montre : les titres de la bibliothèque d'abord, puis
/// ceux que le catalogue connaît sans que le serveur les ait (ADR-0129).
///
/// Le même rangement pour toutes les recherches de l'app : la grille du
/// téléphone et du bureau, le mur d'un téléviseur et l'écran du système de
/// l'Apple TV.
class SearchShelves {
  const SearchShelves._({required this.library, required this.unavailable});

  /// Les titres de la bibliothèque, les plus pertinents d'abord.
  final List<Media> library;

  /// Les titres que le serveur n'a pas, dans l'ordre du catalogue.
  final List<RequestMediaItem> unavailable;

  List<Media> get movies => _of(MediaType.movie);
  List<Media> get shows => _of(MediaType.show);

  bool get isEmpty => library.isEmpty && unavailable.isEmpty;

  List<Media> _of(MediaType type) => [
        for (final media in library)
          if (media.type == type) media,
      ];

  /// Les [count] derniers titres ajoutés à [library] : ce qu'une recherche
  /// propose tant que rien n'est tapé.
  static List<Media> recentlyAdded(LibraryProvider library, int count) {
    final recent = <Media>[
      for (final item in library.movies) item.media,
      ...library.shows,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return recent.take(count).toList();
  }

  /// Range [query] : ce que [library] trouve par le titre, puis [catalog], la
  /// réponse du catalogue de demandes à la même recherche.
  ///
  /// Un titre du catalogue que la bibliothèque détient rejoint ses rayons,
  /// même si son titre ne correspondait pas : le catalogue connaît le titre
  /// original et les fautes de frappe, pas la recherche locale. Les autres
  /// forment le rayon des titres absents.
  factory SearchShelves.of(
    LibraryProvider library,
    String query, {
    List<RequestMediaItem> catalog = const [],
  }) {
    if (query.trim().isEmpty) {
      return const SearchShelves._(library: [], unavailable: []);
    }
    final held = library.searchCatalog(query);
    // Par type et identifiant TMDB : un film et une série peuvent partager le
    // même numéro.
    final shown = <(MediaType, int)>{
      for (final media in held)
        if ((media.tmdbId ?? 0) > 0) (media.type, media.tmdbId!),
    };
    final unavailable = <RequestMediaItem>[];
    for (final item in catalog) {
      final type = item.mediaType == RequestMediaType.tv
          ? MediaType.show
          : MediaType.movie;
      if (!shown.add((type, item.id))) continue;
      final owned = library.mediaForTmdb(type, item.id);
      if (owned != null) {
        held.add(owned);
        continue;
      }
      // Le serveur dit le détenir, mais ce compte ne le voit pas (une
      // bibliothèque qui ne lui est pas ouverte) : ni à lire, ni à demander.
      if (item.status == RequestMediaStatus.available ||
          item.status == RequestMediaStatus.partial) {
        continue;
      }
      unavailable.add(item);
    }
    return SearchShelves._(library: held, unavailable: unavailable);
  }
}
