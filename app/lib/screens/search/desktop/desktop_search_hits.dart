import 'package:flutter/widgets.dart';

import '../../../models/media_request.dart';
import '../../../models/models.dart';
import '../search_shelves.dart';

/// Les pastilles de la recherche du bureau : ce que la grille garde.
enum DesktopSearchFilter { all, movies, shows, unavailable }

/// Un titre de la grille : de la bibliothèque, ou absent du serveur.
sealed class DesktopSearchHit {
  const DesktopSearchHit();

  /// Un titre qui reste le même d'une frappe à l'autre : l'aperçu ne
  /// rejoue son fondu que lorsqu'il change.
  Object get identity;
}

final class LibraryHit extends DesktopSearchHit {
  const LibraryHit(this.media);

  final Media media;

  @override
  Object get identity => ('library', media.type, media.id);
}

final class UnavailableHit extends DesktopSearchHit {
  const UnavailableHit(this.item);

  final RequestMediaItem item;

  @override
  Object get identity => ('catalog', item.mediaType, item.id);
}

/// Ce que la feuille montre pour une recherche et une pastille : la grille
/// de la bibliothèque, puis celle des titres absents (ADR-0129).
class DesktopSearchLayout {
  const DesktopSearchLayout._({
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
  List<DesktopSearchHit> get hits => [
        for (final media in library) LibraryHit(media),
        for (final item in unavailable) UnavailableHit(item),
      ];

  factory DesktopSearchLayout.of(
    SearchShelves shelves,
    DesktopSearchFilter filter,
  ) {
    final movies = shelves.movies;
    final shows = shelves.shows;
    return DesktopSearchLayout._(
      library: switch (filter) {
        DesktopSearchFilter.all => shelves.library,
        DesktopSearchFilter.movies => movies,
        DesktopSearchFilter.shows => shows,
        DesktopSearchFilter.unavailable => const [],
      },
      unavailable: switch (filter) {
        DesktopSearchFilter.all ||
        DesktopSearchFilter.unavailable =>
          shelves.unavailable,
        _ => const [],
      },
      movieCount: movies.length,
      showCount: shows.length,
      unavailableCount: shelves.unavailable.length,
    );
  }

  /// La grille des derniers ajouts, quand rien n'est tapé.
  factory DesktopSearchLayout.recent(List<Media> recent) =>
      DesktopSearchLayout._(
        library: recent,
        unavailable: const [],
        movieCount: 0,
        showCount: 0,
        unavailableCount: 0,
      );
}

/// Le titre où mène une flèche, dans des grilles empilées de [columns]
/// colonnes dont [sections] donne les longueurs.
///
/// Gauche et Droite suivent l'ordre de lecture et passent d'une grille à
/// l'autre ; Haut et Bas gardent la colonne, et tombent sur le dernier titre
/// d'une ligne incomplète plutôt que de ne rien faire. Null quand Haut part de
/// la première ligne : la sélection rend la main au champ.
int? stepSelection({
  required List<int> sections,
  required int columns,
  required int index,
  required TraversalDirection direction,
}) {
  final total = sections.fold<int>(0, (sum, length) => sum + length);
  if (total == 0) return null;
  final cols = columns < 1 ? 1 : columns;
  final current = index.clamp(0, total - 1);

  switch (direction) {
    case TraversalDirection.left:
      return current == 0 ? 0 : current - 1;
    case TraversalDirection.right:
      return current == total - 1 ? current : current + 1;
    case TraversalDirection.up:
    case TraversalDirection.down:
      break;
  }

  // La grille de [current], et sa place dans cette grille.
  var section = 0;
  var start = 0;
  while (current >= start + sections[section]) {
    start += sections[section];
    section++;
  }
  final local = current - start;
  final column = local % cols;
  final length = sections[section];

  if (direction == TraversalDirection.down) {
    if (local + cols < length) return current + cols;
    final lastRowStart = (length - 1) ~/ cols * cols;
    if (local < lastRowStart) return start + length - 1;
    var nextStart = start + length;
    for (var s = section + 1; s < sections.length; s++) {
      if (sections[s] > 0) {
        return nextStart + (column < sections[s] ? column : sections[s] - 1);
      }
      nextStart += sections[s];
    }
    return current;
  }

  if (local - cols >= 0) return current - cols;
  var previousEnd = start;
  for (var s = section - 1; s >= 0; s--) {
    final previousStart = previousEnd - sections[s];
    if (sections[s] > 0) {
      final lastRowStart = (sections[s] - 1) ~/ cols * cols;
      final target = lastRowStart + column;
      return previousStart +
          (target < sections[s] ? target : sections[s] - 1);
    }
    previousEnd = previousStart;
  }
  return null;
}
