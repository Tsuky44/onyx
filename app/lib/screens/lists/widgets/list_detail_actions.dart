import '../../../l10n/tr.dart';
import '../../../models/watch_list.dart';
import '../../../theme/app_icons.dart';
import '../../../widgets/global/onyx_menu.dart';

/// Ce que le menu « ⋯ » d'une liste propose.
enum ListAction { edit, share, select, removeWatched, leave, delete }

/// Ce que le menu d'une affiche (clic droit, appui long) propose.
enum ItemAction { play, details, move, copy, remove }

/// Les lignes du menu « ⋯ » d'[list], selon ce que le compte peut en faire
/// (ADR-0070, ADR-0127) : un invité qui remplit la liste ne la renomme ni ne
/// la supprime, un lecteur n'y touche pas. Les lignes qui détruisent vont en
/// fin de menu, sous le filet que le panneau pose lui-même.
///
/// [canInvite] : le serveur sait inviter des comptes. [hasItems] et
/// [watchedCount] masquent ce qui n'aurait rien à faire ; le nombre de titres
/// vus se lit aussi sous « Retirer les titres vus », pour savoir ce qu'on
/// retire avant de le faire.
List<OnyxMenuItem<ListAction>> listMenuItems(
  WatchList list, {
  required bool canInvite,
  required bool hasItems,
  required int watchedCount,
}) {
  final canShare = list.isMine && (list.isWatchLater || canInvite);
  final canRename = list.isMine && !list.isWatchLater;
  // Les deux groupes ne se titrent que s'ils sont tous deux là : un titre
  // au-dessus d'une ligne seule ne range rien.
  final listGroup = canRename || canShare;
  final itemsGroup = list.canEdit && hasItems;
  final titled = listGroup && itemsGroup;
  return [
    if (canRename)
      OnyxMenuItem(
        value: ListAction.edit,
        icon: AppIcons.edit,
        label: tr('Modifier la liste'),
        section: titled ? tr('La liste') : null,
      ),
    if (canShare)
      OnyxMenuItem(
        value: ListAction.share,
        icon: AppIcons.sharedList,
        label: list.isWatchLater ? tr('Partage…') : tr('Partager…'),
        subtitle: list.memberCount > 0
            ? trPlural(list.memberCount, '{0} personne invitée',
                '{0} personnes invitées')
            : list.isShared
                ? tr('Visible par tout le serveur')
                : null,
        section: titled && !canRename ? tr('La liste') : null,
      ),
    if (itemsGroup)
      OnyxMenuItem(
        value: ListAction.select,
        icon: AppIcons.check,
        label: tr('Sélectionner des titres'),
        section: titled ? tr('Les titres') : null,
      ),
    if (itemsGroup && watchedCount > 0)
      OnyxMenuItem(
        value: ListAction.removeWatched,
        icon: AppIcons.watched,
        label: tr('Retirer les titres vus'),
        subtitle: trPlural(watchedCount, '{0} titre · se défait',
            '{0} titres · se défait'),
      ),
    if (list.isMember)
      OnyxMenuItem(
        value: ListAction.leave,
        icon: AppIcons.signOut,
        label: tr('Quitter la liste'),
        destructive: true,
      ),
    if (canRename)
      OnyxMenuItem(
        value: ListAction.delete,
        icon: AppIcons.delete,
        label: tr('Supprimer la liste…'),
        destructive: true,
      ),
  ];
}

/// Les lignes du menu d'une affiche. « Lire » et « Ouvrir la fiche » ne valent
/// que pour un titre que le serveur a ; ce qu'il n'a pas s'ouvre dans le
/// catalogue des demandes. Copier est ouvert à tous, déplacer et retirer
/// demandent de pouvoir modifier la liste.
List<OnyxMenuItem<ItemAction>> itemMenuItems(
  WatchListItem item, {
  required bool canEdit,
  required bool hasOtherLists,
}) {
  final rows = <OnyxMenuItem<ItemAction>>[
    if (item.isOnServer)
      OnyxMenuItem(
        value: ItemAction.play,
        icon: AppIcons.play,
        label: tr('Lire'),
      ),
    OnyxMenuItem(
      value: ItemAction.details,
      icon: AppIcons.info,
      label: item.isOnServer
          ? tr('Ouvrir la fiche')
          : tr('Voir dans le catalogue'),
    ),
    if (hasOtherLists && canEdit)
      OnyxMenuItem(
        value: ItemAction.move,
        icon: AppIcons.forward,
        label: tr('Déplacer vers…'),
      ),
    if (hasOtherLists)
      OnyxMenuItem(
        value: ItemAction.copy,
        icon: AppIcons.copy,
        label: tr('Copier vers…'),
      ),
    if (canEdit)
      OnyxMenuItem(
        value: ItemAction.remove,
        icon: AppIcons.close,
        label: tr('Retirer de la liste'),
        destructive: true,
      ),
  ];
  // Le titre en tête du menu : un clic droit dans une grille dit sur quelle
  // affiche il porte (ADR-0161).
  final first = rows.first;
  rows[0] = OnyxMenuItem(
    value: first.value,
    icon: first.icon,
    label: first.label,
    section: item.title,
  );
  return rows;
}
