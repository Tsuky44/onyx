import '../../../models/storage_admin.dart';

/// Le tri et les filtres du gestionnaire de stockage. Le serveur rend tout
/// en une fois (ADR-0114) : l'écran trie et filtre lui-même, sans aller-retour.

enum StorageKind { all, movies, shows }

enum StorageSort { size, idle, added, title }

/// « Pas regardé depuis » : la question qu'on se pose pour faire de la place.
enum StorageIdle { any, months3, months6, year, never }

class StorageQuery {
  const StorageQuery({
    this.kind = StorageKind.all,
    this.sort = StorageSort.size,
    this.idle = StorageIdle.any,
  });

  final StorageKind kind;
  final StorageSort sort;
  final StorageIdle idle;

  StorageQuery copyWith({StorageKind? kind, StorageSort? sort, StorageIdle? idle}) =>
      StorageQuery(
        kind: kind ?? this.kind,
        sort: sort ?? this.sort,
        idle: idle ?? this.idle,
      );

  List<StorageItem> apply(List<StorageItem> items, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final kept = items.where((item) => _keeps(item, reference)).toList();
    kept.sort(_compare);
    return kept;
  }

  bool _keeps(StorageItem item, DateTime now) {
    if (kind == StorageKind.movies && item.isShow) return false;
    if (kind == StorageKind.shows && !item.isShow) return false;
    final months = switch (idle) {
      StorageIdle.any => 0,
      StorageIdle.never => 0,
      StorageIdle.months3 => 3,
      StorageIdle.months6 => 6,
      StorageIdle.year => 12,
    };
    if (idle == StorageIdle.never) return item.lastPlayedAt == null;
    if (months == 0) return true;
    final since = item.idleSince;
    if (since == null) return true;
    return since.isBefore(DateTime(now.year, now.month - months, now.day));
  }

  int _compare(StorageItem a, StorageItem b) {
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    switch (sort) {
      case StorageSort.size:
        final bySize = b.size.compareTo(a.size);
        return bySize != 0 ? bySize : byTitle;
      case StorageSort.idle:
        // Le plus longtemps oublié d'abord ; sans date, il passe devant.
        final ai = a.idleSince, bi = b.idleSince;
        if (ai == null && bi == null) return byTitle;
        if (ai == null) return -1;
        if (bi == null) return 1;
        final byIdle = ai.compareTo(bi);
        return byIdle != 0 ? byIdle : byTitle;
      case StorageSort.added:
        final aa = a.addedAt, ba = b.addedAt;
        if (aa == null || ba == null) {
          return aa == ba ? byTitle : (aa == null ? 1 : -1);
        }
        final byAdded = ba.compareTo(aa);
        return byAdded != 0 ? byAdded : byTitle;
      case StorageSort.title:
        return byTitle;
    }
  }
}
