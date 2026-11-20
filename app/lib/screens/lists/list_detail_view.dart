import '../../l10n/tr.dart';
import '../../models/watch_list.dart';

/// L'onglet du détail d'une liste : ce qu'on y montre des titres.
///
/// « Vu » vient du serveur (`WatchListItem.watched`, ADR-0159) ; l'app ne le
/// recalcule pas, elle range seulement.
enum WatchListFilter {
  all,

  /// Sur le serveur et pas encore vus : ce qu'on peut lancer.
  toWatch,
  watched,

  /// Ce que le serveur n'a pas : ce qu'on peut demander.
  toRequest;

  String get label => switch (this) {
        all => tr('Tous'),
        toWatch => tr('À voir'),
        watched => tr('Vus'),
        toRequest => tr('À demander'),
      };

  bool accepts(WatchListItem item) => switch (this) {
        all => true,
        toWatch => item.isOnServer && !item.watched,
        watched => item.watched,
        toRequest => !item.isOnServer,
      };
}

/// L'ordre des titres d'une liste. Le serveur les renvoie du plus récent
/// ajout au plus ancien : c'est l'ordre par défaut.
enum WatchListSort {
  recent,
  oldest,
  title,
  year;

  String get label => switch (this) {
        recent => tr('Ajoutés récemment'),
        oldest => tr('Ajoutés en premier'),
        title => tr('Titre'),
        year => tr('Année'),
      };
}

/// Ce que le détail d'une liste montre : les titres de [items] retenus par
/// [filter], dans l'ordre de [sort].
List<WatchListItem> arrangeListItems(
  List<WatchListItem> items, {
  WatchListFilter filter = WatchListFilter.all,
  WatchListSort sort = WatchListSort.recent,
}) {
  final kept = [
    for (final item in items)
      if (filter.accepts(item)) item
  ];
  switch (sort) {
    case WatchListSort.recent:
      return kept;
    case WatchListSort.oldest:
      return kept.reversed.toList();
    case WatchListSort.title:
      kept.sort((a, b) => _titleKey(a).compareTo(_titleKey(b)));
      return kept;
    case WatchListSort.year:
      // Du plus récent au plus ancien ; sans date, en fin de liste. Le tri de
      // Dart est stable : à année égale, l'ordre d'ajout reste.
      kept.sort((a, b) => _yearOf(b).compareTo(_yearOf(a)));
      return kept;
  }
}

/// Combien de titres chaque onglet montre, pour les afficher à côté de son nom.
Map<WatchListFilter, int> countListItems(List<WatchListItem> items) => {
      for (final filter in WatchListFilter.values)
        filter: items.where(filter.accepts).length,
    };

String _titleKey(WatchListItem item) => item.title.toLowerCase();

int _yearOf(WatchListItem item) => int.tryParse(item.year ?? '') ?? -1;
