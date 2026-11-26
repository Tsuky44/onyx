import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/retro.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_type.dart';
import '../../../theme/retro_palette.dart';
import '../../../tv/nav/tv_focusable.dart';
import '../../../tv/tv_mode.dart';
import '../services/retro_share_action.dart';
import 'retro_home_text.dart';
import 'retro_poster_fan.dart';

/// La carte du Rétro sur l'accueil, au-dessus de « Reprendre la lecture »,
/// une fois la story vue ou la diapo rangée (« Plus tard ») : pour revoir
/// l'année et partager l'image, jusqu'à la fin de la saison.
class RetroHomeCard extends StatelessWidget {
  const RetroHomeCard({
    super.key,
    required this.status,
    required this.report,
    required this.name,
    required this.serverBaseUrl,
    required this.onOpen,
  });

  final RetroStatus status;
  final RetroReport? report;
  final String name;
  final String? serverBaseUrl;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isTv = TvScope.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final report = this.report;
    final palette =
        RetroPalette.forArchetype(report?.archetype ?? RetroArchetype.marathon);
    final title = status.seen ? tr('Revoir ton année') : tr('Voir ton année');
    final profile = RetroHomeText.profile(report);
    final radius = BorderRadius.circular(18);

    return Padding(
      padding:
          EdgeInsets.fromLTRB(isCompact ? 16 : 48, 8, isCompact ? 16 : 48, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Semantics(
            button: true,
            label: [title, if (profile != null) profile].join('. '),
            child: TvFocusable(
              onSelect: onOpen,
              borderRadius: radius,
              focusScale: 1.02,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpen,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: radius,
                      border: Border.all(
                          color: palette.ink.withValues(alpha: 0.18)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                      child: Row(
                        children: [
                          if (report != null && report.top.isNotEmpty) ...[
                            RetroPosterFan(
                              titles: report.top.take(3).toList(),
                              serverBaseUrl: serverBaseUrl,
                              posterWidth: 34,
                              spread: 0.26,
                            ),
                            const SizedBox(width: 16),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  RetroHomeText.kicker(status).toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.ink.withValues(alpha: 0.75),
                                    fontSize: AppType.caption,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontSize: AppType.headline,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (profile != null)
                                  Text(
                                    profile,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.ink.withValues(alpha: 0.8),
                                      fontSize: AppType.footnote,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Partager sans rouvrir la story. Pas au
                          // téléviseur, qui ne partage rien.
                          if (!isTv && report != null) ...[
                            const SizedBox(width: 10),
                            Builder(
                              builder: (button) => _ShareButton(
                                compact: isCompact,
                                ink: palette.ink,
                                background: palette.background,
                                onPressed: () => shareRetroImage(
                                  button,
                                  report: report,
                                  name: name,
                                  origin: _rectOf(button),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// « Partager » : une pastille pleine d'encre ; sur un téléphone, son icône
/// seule, pour laisser la place au titre.
class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.compact,
    required this.ink,
    required this.background,
    required this.onPressed,
  });

  final bool compact;
  final Color ink;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = tr('Partager');
    if (compact) {
      return IconButton(
        onPressed: onPressed,
        tooltip: label,
        style: IconButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: background,
          minimumSize: const Size(44, 44),
        ),
        icon: const Icon(AppIcons.share, size: 20),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: background,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: AppType.footnote,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: const Icon(AppIcons.share, size: 16),
      label: Text(label),
    );
  }
}

/// Où est le bouton à l'écran : la feuille de partage d'un iPad s'y accroche.
Rect _rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}
