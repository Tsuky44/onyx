import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/watch_list.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_mode.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/global/app_network_image.dart';
import '../../../widgets/global/glass_chrome.dart';
import '../../../widgets/global/onyx_menu.dart';
import '../../player/widgets/onyx/onyx_capsule_button.dart';
import 'list_detail_actions.dart';
import 'list_member_avatars.dart';
import 'list_progress.dart';

/// L'en-tête d'une liste : son éventail d'affiches, à qui elle est, son nom,
/// qui la remplit, où elle en est, et ses actions (ADR-0070, ADR-0127,
/// ADR-0159, ADR-0161).
///
/// Une seule action principale, lancer le prochain titre, en capsule blanche ;
/// « Partager » en capsule de verre avec les visages des invités ; le reste
/// (modifier, sélectionner, supprimer…) dans le menu « ⋯ ».
class ListDetailHeader extends StatelessWidget {
  const ListDetailHeader({
    super.key,
    required this.list,
    required this.members,
    required this.posters,
    required this.menuItems,
    required this.onMenu,
    this.onPlayNext,
    this.onShare,
  });

  final WatchList list;
  final List<WatchListMember> members;

  /// Les affiches de l'éventail, déjà résolues en adresses.
  final List<String?> posters;
  final List<OnyxMenuItem<ListAction>> menuItems;
  final ValueChanged<ListAction> onMenu;

  /// Lance le prochain titre à voir ; null quand il n'y en a pas.
  final VoidCallback? onPlayNext;

  /// Ouvre le partage, collé au bouton dont il reçoit le contexte ; null
  /// quand le compte ne peut pas partager.
  final ValueChanged<BuildContext>? onShare;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final info = _Info(list: list, members: members);
    final actions = _Actions(
      next: list.nextItem,
      members: members,
      onPlayNext: onPlayNext,
      onShare: onShare,
      menuItems: menuItems,
      onMenu: onMenu,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [info, const SizedBox(height: 18), actions],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        WatchListPosterFan(urls: posters, posterWidth: 104),
        const SizedBox(width: 32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [info, const SizedBox(height: 20), actions],
          ),
        ),
      ],
    );
  }
}

/// La lueur de la liste derrière son en-tête : la dernière affiche ajoutée,
/// floutée jusqu'à n'être plus qu'une couleur, qui se fond dans le fond de la
/// page. Le mode léger et le téléviseur s'en passent : le flou d'une grande
/// image est ce qu'ils paient le plus cher (ADR-0025).
class ListHeaderGlow extends StatelessWidget {
  const ListHeaderGlow({super.key, required this.url, this.height = 460});

  final String? url;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || TvMode.isTv || !glassBlurs(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 0.32,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                  child: AppNetworkImage(
                    url: url,
                    fit: BoxFit.cover,
                    // Floutée à ce point, une image de 200 px suffit : la
                    // décoder à la taille de la page coûterait sans rien voir.
                    decodeWidth: 200,
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.gradientTop, AppColors.background],
                    stops: [0.0, 0.92],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La ligne au-dessus du nom : à qui est la liste et qui peut la voir.
({IconData icon, String label}) _eyebrow(WatchList list) {
  if (!list.isMine) {
    return (
      icon: AppIcons.sharedList,
      label: tr('Liste de {0}', [list.owner.username]),
    );
  }
  return list.isShared
      ? (icon: AppIcons.sharedList, label: tr('Visible par tout le serveur'))
      : (icon: AppIcons.privateList, label: tr('Liste privée'));
}

class _Info extends StatelessWidget {
  const _Info({required this.list, required this.members});

  final WatchList list;
  final List<WatchListMember> members;

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final eyebrow = _eyebrow(list);
    String names(WatchListRole role) =>
        members.where((m) => m.role == role).map((m) => m.username).join(', ');
    final editors = names(WatchListRole.editor);
    final viewers = names(WatchListRole.viewer);
    final count = list.itemCount == 1
        ? tr('1 titre')
        : tr('{0} titres', [list.itemCount]);
    final who = [
      if (editors.isNotEmpty) tr('Remplie avec {0}', [editors]),
      if (viewers.isNotEmpty) tr('Visible par {0}', [viewers]),
      count,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(eyebrow.icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                eyebrow.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          list.displayName,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: compact ? AppType.display : AppType.hero,
                height: 1.08,
                letterSpacing: -0.4,
              ),
        ),
        if (list.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              list.description,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.callout,
                height: 1.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (members.isNotEmpty) ...[
              ListMemberAvatars(
                names: [for (final m in members) m.username],
                ring: AppColors.background,
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                who,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: AppType.body),
              ),
            ),
          ],
        ),
        if (list.hasProgress && list.itemCount > 0) ...[
          const SizedBox(height: 12),
          _Progress(list: list),
        ],
      ],
    );
  }
}

/// La barre d'avancement et sa ligne : « 5 vus sur 8 · 2 à demander », ce
/// qui reste à demander en orange, comme son onglet.
class _Progress extends StatelessWidget {
  const _Progress({required this.list});

  final WatchList list;

  @override
  Widget build(BuildContext context) {
    final toRequest = list.toRequestCount;
    const style =
        TextStyle(color: AppColors.textSecondary, fontSize: AppType.body);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: AppLayout.isCompact(context) ? 140 : 240,
          child: WatchListProgressBar(value: list.watchedFraction),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(
                    text: watchedOfText(list.watchedCount!, list.itemCount)),
                if (toRequest > 0) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: toRequestText(toRequest),
                    style: const TextStyle(color: AppColors.warning),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.next,
    required this.members,
    required this.onPlayNext,
    required this.onShare,
    required this.menuItems,
    required this.onMenu,
  });

  final WatchListNext? next;
  final List<WatchListMember> members;
  final VoidCallback? onPlayNext;
  final ValueChanged<BuildContext>? onShare;
  final List<OnyxMenuItem<ListAction>> menuItems;
  final ValueChanged<ListAction> onMenu;

  @override
  Widget build(BuildContext context) {
    final share = onShare;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (next != null && onPlayNext != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: OnyxCapsuleButton(
              label: tr('Lire {0}', [next!.title]),
              icon: AppIcons.play,
              primary: true,
              large: true,
              onPressed: onPlayNext,
            ),
          ),
        if (share != null)
          Builder(
            builder: (buttonContext) => OnyxCapsuleButton(
              label: tr('Partager'),
              large: true,
              icon: members.isEmpty ? AppIcons.sharedList : null,
              leading: members.isEmpty
                  ? null
                  : ListMemberAvatars(
                      names: [for (final m in members) m.username],
                      ring: AppColors.surfaceElevated,
                      size: 30,
                    ),
              onPressed: () => share(buttonContext),
            ),
          ),
        if (menuItems.isNotEmpty)
          OnyxMenuButton<ListAction>(
            tooltip: tr('Plus d’actions'),
            items: menuItems,
            onSelected: onMenu,
            child: const IgnorePointer(
              child: GlassIconButton(
                size: 44,
                child: Icon(AppIcons.more,
                    size: 20, color: AppColors.textPrimary),
              ),
            ),
          ),
      ],
    );
  }
}
