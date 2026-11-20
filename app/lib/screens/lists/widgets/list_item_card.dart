import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/watch_list.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/poster_url.dart';
import '../../../widgets/global/poster_card.dart';
import '../../../widgets/global/poster_card_details.dart';
import '../../../widgets/global/progress_pill.dart';
import '../../../widgets/global/unavailable_badge.dart';

/// Une affiche du détail d'une liste, avec ce qu'on veut y lire d'un coup
/// d'œil : vu, en cours, pas sur le serveur, et sa case en mode sélection.
///
/// Le clic droit et l'appui long demandent le menu de l'affiche : la carte
/// rend à [onMenu] la clé de son ancre, que le menu de l'écran vise.
class ListItemCard extends StatefulWidget {
  const ListItemCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onMenu,
    this.selecting = false,
    this.selected = false,
    this.autofocus = false,
  });

  final WatchListItem item;

  /// Ouvrir la fiche, ou cocher la case quand [selecting].
  final void Function(BuildContext cardContext) onTap;
  final void Function(GlobalKey anchor) onMenu;

  /// La liste est en sélection : chaque affiche porte une case.
  final bool selecting;
  final bool selected;
  final bool autofocus;

  @override
  State<ListItemCard> createState() => _ListItemCardState();
}

class _ListItemCardState extends State<ListItemCard> {
  final GlobalKey _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final baseUrl = context.read<ApiClient>().baseUrl;
    final isShow = item.mediaType == WatchListMediaType.show;
    final progress = item.media?.percentWatched ?? 0;
    final inProgress = !isShow && progress > 0 && progress < 0.99;
    // Une série n'a pas de position de lecture : sa barre compte les épisodes
    // terminés, que le serveur donne (ADR-0162).
    final showInProgress = item.isShowInProgress;
    final nextCode = item.nextEpisodeCode;
    final episodesLine = showInProgress
        ? tr('{0}/{1} épisodes vus', [item.episodesWatched, item.episodesTotal])
        : null;
    final facts = item.isOnServer
        ? [
            if (item.year != null) item.year!,
            if (episodesLine != null) episodesLine,
            if (showInProgress && nextCode != null)
              tr('Prochain : {0}', [nextCode]),
          ].join(' · ')
        : [
            if (item.year != null) item.year!,
            tr('Pas sur le serveur'),
          ].join(' · ');
    final label = widget.selecting
        ? (widget.selected
            ? tr('Désélectionner {0}', [item.title])
            : tr('Sélectionner {0}', [item.title]))
        : null;
    return GestureDetector(
      key: _anchor,
      behavior: HitTestBehavior.deferToChild,
      // Le menu de l'affiche n'a pas à s'annoncer : un lecteur d'écran passe
      // par le menu « ⋯ » et la sélection. Sans cela, l'action d'appui long se
      // fond dans le bouton de l'affiche et lui prend son nom.
      excludeFromSemantics: true,
      onSecondaryTapDown: (_) => widget.onMenu(_anchor),
      onLongPressStart: (_) => widget.onMenu(_anchor),
      child: Semantics(
        label: label,
        child: PosterCard(
          posterUrl: cardPosterUrl(item.posterUrl, serverBaseUrl: baseUrl),
          title: item.title,
          showMeta: false,
          hoverDetails: PosterCardDetails(
            title: item.title,
            typeLabel: isShow ? tr('Série') : tr('Film'),
            facts: facts.isEmpty ? null : facts,
          ),
          dimmed: !item.isOnServer,
          autofocus: widget.autofocus,
          placeholderIcon: isShow ? AppIcons.series : AppIcons.movie,
          onTap: () => widget.onTap(context),
          overlays: [
            // Le contour blanc d'une affiche cochée : la sélection se lit de
            // loin, pas seulement à la pastille du coin.
            if (widget.selecting && widget.selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(PosterCard.radius),
                      border: Border.all(color: AppColors.focus, width: 3),
                    ),
                  ),
                ),
              ),
            if (widget.selecting || item.watched)
              Positioned(
                top: PosterCard.overlayInset,
                right: PosterCard.overlayInset,
                child: _Mark(selecting: widget.selecting, on: widget.selected),
              ),
            if (!item.isOnServer)
              const Positioned(
                left: PosterCard.overlayInset,
                bottom: PosterCard.overlayInset,
                child: UnavailableBadge(),
              ),
            if (showInProgress && nextCode != null)
              Positioned(
                top: PosterCard.overlayInset,
                left: PosterCard.overlayInset,
                child: _NextEpisodeChip(code: nextCode),
              ),
          ],
          footerOverlay: inProgress
              ? ProgressPill(value: progress)
              : showInProgress
                  ? ProgressPill(value: item.episodesFraction)
                  : null,
        ),
      ),
    );
  }
}

/// L'épisode où reprendre une série commencée, en pastille de verre comme
/// « Indispo » : « S2 E5 ». Elle se lit avec la barre du bas, qui dit combien
/// d'épisodes sont derrière.
class _NextEpisodeChip extends StatelessWidget {
  const _NextEpisodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Prochain : {0}', [code]),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          code,
          style: const TextStyle(
            fontSize: AppType.micro,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// La pastille du coin de l'affiche : la case de la sélection, ou la coche
/// d'un titre vu. Cochée, la case est blanche à l'encre noire, comme le
/// choix en cours partout ailleurs (ADR-0161) : le bleu reste aux barres de
/// lecture.
class _Mark extends StatelessWidget {
  const _Mark({required this.selecting, required this.on});

  final bool selecting;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final lit = selecting && on;
    final filled = selecting ? on : true;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? AppColors.focus : Colors.black.withValues(alpha: 0.55),
        border: Border.all(
          color: lit ? AppColors.focus : Colors.white.withValues(alpha: 0.75),
          width: lit ? 1.5 : 2,
        ),
      ),
      child: filled
          ? Icon(AppIcons.check,
              size: 14, color: lit ? AppColors.background : AppColors.focus)
          : null,
    );
  }
}
