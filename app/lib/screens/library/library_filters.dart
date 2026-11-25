import 'package:material_ui/material_ui.dart';

import 'widgets/library_tv_view.dart';

/// L'ordre d'une grille de bibliothèque.
enum LibrarySort { recent, title, progress, release }

/// Où en est le compte avec un titre.
enum LibraryWatchFilter { all, unwatched, inProgress, watched }

/// Le tri et les filtres d'une bibliothèque. Tout se fait sur la liste déjà
/// chargée : le serveur envoie le catalogue entier d'une bibliothèque
/// (`getLibraryMovies`, `getLibraryShows`), il n'y a rien à redemander.
///
/// Les plages gardent la forme des Demandes (dates `AAAA-MM-JJ`, minutes),
/// pour partager leurs choix rapides (`filterPeriodPresets`,
/// `filterDurationPresets`).
@immutable
class LibraryFilters {
  const LibraryFilters({
    this.sort = LibrarySort.recent,
    this.watch = LibraryWatchFilter.all,
    this.from = '',
    this.to = '',
    this.minDuration = '',
    this.maxDuration = '',
  });

  static const defaults = LibraryFilters();

  final LibrarySort sort;
  final LibraryWatchFilter watch;
  final String from;
  final String to;

  /// En minutes, comme les choix rapides.
  final String minDuration;
  final String maxDuration;

  bool get hasPeriod => from.isNotEmpty || to.isNotEmpty;
  bool get hasDuration => minDuration.isNotEmpty || maxDuration.isNotEmpty;

  /// Le nombre de familles posées, le tri mis à part : c'est le compte du
  /// bouton « Filtres ».
  int get activeCount => [
        watch != LibraryWatchFilter.all,
        hasPeriod,
        hasDuration,
      ].where((set) => set).length;

  /// Tout retiré sauf le tri, qui a toujours une valeur.
  LibraryFilters cleared() => LibraryFilters(sort: sort);

  LibraryFilters copyWith({
    LibrarySort? sort,
    LibraryWatchFilter? watch,
    String? from,
    String? to,
    String? minDuration,
    String? maxDuration,
  }) =>
      LibraryFilters(
        sort: sort ?? this.sort,
        watch: watch ?? this.watch,
        from: from ?? this.from,
        to: to ?? this.to,
        minDuration: minDuration ?? this.minDuration,
        maxDuration: maxDuration ?? this.maxDuration,
      );

  /// Les titres de [entries] qui passent les filtres, dans l'ordre du tri.
  /// [titleKey] est la clé de tri alphabétique (sans article).
  List<LibraryEntry> apply(
    List<LibraryEntry> entries, {
    required String Function(String title) titleKey,
  }) {
    final kept = [
      for (final e in entries)
        if (_keeps(e)) e
    ];
    switch (sort) {
      case LibrarySort.title:
        kept.sort((a, b) =>
            titleKey(a.media.title).compareTo(titleKey(b.media.title)));
      case LibrarySort.recent:
        kept.sort((a, b) => b.media.createdAt.compareTo(a.media.createdAt));
      case LibrarySort.release:
        // Les dates inconnues en dernier, pas en tête d'un tri décroissant.
        kept.sort((a, b) =>
            (b.media.releaseDate ?? '').compareTo(a.media.releaseDate ?? ''));
      case LibrarySort.progress:
        double progress(LibraryEntry entry) {
          final movie = entry.movie;
          if (movie == null) return 0;
          return movie.isFinished ? -1.0 : movie.percentWatched;
        }
        kept.sort((a, b) => progress(b).compareTo(progress(a)));
    }
    return kept;
  }

  bool _keeps(LibraryEntry entry) {
    if (watch != LibraryWatchFilter.all && _watchOf(entry) != watch) {
      return false;
    }
    if (hasPeriod) {
      // Une date inconnue ne tombe dans aucune période.
      final date = entry.media.releaseDate ?? '';
      if (date.isEmpty) return false;
      if (from.isNotEmpty && date.compareTo(from) < 0) return false;
      if (to.isNotEmpty && date.compareTo(to) > 0) return false;
    }
    if (hasDuration) {
      final seconds = entry.movie?.duration ?? entry.media.duration;
      if (seconds <= 0) return false;
      final minutes = seconds / 60;
      final min = int.tryParse(minDuration);
      final max = int.tryParse(maxDuration);
      if (min != null && minutes < min) return false;
      if (max != null && minutes > max) return false;
    }
    return true;
  }

  static LibraryWatchFilter _watchOf(LibraryEntry entry) {
    final movie = entry.movie;
    if (movie != null) {
      if (movie.isFinished) return LibraryWatchFilter.watched;
      return movie.currentPositionSeconds > 0
          ? LibraryWatchFilter.inProgress
          : LibraryWatchFilter.unwatched;
    }
    final media = entry.media;
    if (media.isFullyWatched) return LibraryWatchFilter.watched;
    if (media.isPartiallyWatched) return LibraryWatchFilter.inProgress;
    return LibraryWatchFilter.unwatched;
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryFilters &&
      other.sort == sort &&
      other.watch == watch &&
      other.from == from &&
      other.to == to &&
      other.minDuration == minDuration &&
      other.maxDuration == maxDuration;

  @override
  int get hashCode =>
      Object.hash(sort, watch, from, to, minDuration, maxDuration);
}
