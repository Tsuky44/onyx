import 'package:flutter/material.dart';

import '../../../../l10n/tr.dart';
import '../../../../theme/app_type.dart';
import '../../../../tv/nav/tv_region.dart';
import 'onyx_chrome_buttons.dart';
import 'onyx_chrome_theme.dart';

/// Les onglets sous la barre de lecture d'un téléviseur, comme ceux du lecteur
/// d'Apple (ADR-0124) : « Infos », « Épisodes », « Regarder ensemble ».
///
/// « Infos » déplie le résumé sous les onglets, sans quitter le chrome. Les
/// deux autres ouvrent le panneau que le lecteur avait déjà : la liste des
/// épisodes, la séance à plusieurs. Un onglet sans rien à ouvrir n'est pas
/// dessiné (un film n'a pas d'épisodes, une lecture hors ligne pas de séance).
class OnyxTvTabs extends StatefulWidget {
  const OnyxTvTabs({
    super.key,
    required this.visible,
    this.overview,
    this.onOpenEpisodes,
    this.onOpenWatchParty,
    this.watchPartyActive = false,
  });

  /// Le chrome est à l'écran. Quand il se cache, le résumé se replie : le
  /// chrome revient toujours dans son état de repos.
  final bool visible;

  /// Le résumé du titre, ou nul quand il n'y en a pas.
  final String? overview;
  final VoidCallback? onOpenEpisodes;
  final VoidCallback? onOpenWatchParty;
  final bool watchPartyActive;

  static bool hasAny({
    String? overview,
    VoidCallback? onOpenEpisodes,
    VoidCallback? onOpenWatchParty,
  }) =>
      (overview ?? '').trim().isNotEmpty ||
      onOpenEpisodes != null ||
      onOpenWatchParty != null;

  @override
  State<OnyxTvTabs> createState() => _OnyxTvTabsState();
}

class _OnyxTvTabsState extends State<OnyxTvTabs> {
  bool _infoOpen = false;

  @override
  void didUpdateWidget(OnyxTvTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) _infoOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final overview = (widget.overview ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Le texte du premier onglet s'aligne sur le titre : sa capsule, elle,
        // déborde de son retrait intérieur.
        Transform.translate(
          offset: const Offset(-16, 0),
          child: TvRegion.controls(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (overview.isNotEmpty)
                  OnyxChromeTab(
                    key: const ValueKey('onyx-info'),
                    label: tr('Infos'),
                    active: _infoOpen,
                    onPressed: () => setState(() => _infoOpen = !_infoOpen),
                  ),
                if (widget.onOpenEpisodes != null)
                  OnyxChromeTab(
                    key: const ValueKey('onyx-episodes'),
                    label: tr('Épisodes'),
                    onPressed: widget.onOpenEpisodes!,
                  ),
                if (widget.onOpenWatchParty != null)
                  OnyxChromeTab(
                    key: const ValueKey('onyx-watch-party'),
                    label: widget.watchPartyActive
                        ? tr('Séance en cours')
                        : tr('Regarder ensemble'),
                    active: widget.watchPartyActive,
                    onPressed: widget.onOpenWatchParty!,
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: _infoOpen && overview.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 780),
                    child: Text(
                      overview,
                      key: const ValueKey('onyx-info-text'),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OnyxChromeTheme.title,
                        fontSize: AppType.headline,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
