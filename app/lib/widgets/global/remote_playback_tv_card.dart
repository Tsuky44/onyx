import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/remote_playback.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_focus.dart';
import '../../utils/format.dart';
import '../../utils/responsive.dart';
import 'app_network_image.dart';

/// « Lecture en cours sur un autre appareil », dans la page d'accueil d'un
/// téléviseur : ce qui se lit ailleurs, et un bouton pour le reprendre ici.
///
/// Le bouton est ce qui s'allume sous la télécommande, mais le focus lui-même
/// est tenu par toute la largeur de la page. Vers le haut, le parcours de
/// Flutter ne retient que ce qui chevauche la position de départ : un bouton
/// posé à droite du bandeau n'était atteignable que depuis ce qui se trouvait
/// exactement au-dessus de lui, et les boutons du carrousel, à gauche,
/// l'emportaient. Une zone pleine largeur chevauche tout ; le bouton, lui, ne
/// fait que montrer qu'il a le focus.
class RemotePlaybackTvCard extends StatefulWidget {
  final RemotePlayback play;
  final String? posterUrl;

  /// Faux quand la reprise est déjà lancée : le bouton ne se valide plus.
  final bool enabled;
  final VoidCallback onResume;

  const RemotePlaybackTvCard({
    super.key,
    required this.play,
    required this.posterUrl,
    required this.enabled,
    required this.onResume,
  });

  @override
  State<RemotePlaybackTvCard> createState() => _RemotePlaybackTvCardState();
}

class _RemotePlaybackTvCardState extends State<RemotePlaybackTvCard> {
  static const _maxWidth = 1040.0;

  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final pad = AppLayout.pagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 20),
      child: TvFocusable(
        onSelect: widget.enabled ? widget.onResume : null,
        onFocusChange: (focused) => setState(() => _focused = focused),
        focusScale: 1,
        showRing: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: _card(context),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final s = widget.play.session;
    final device =
        s.deviceName.isNotEmpty ? s.deviceName : tr('un autre appareil');
    final remaining = formatRemaining(s.durationSeconds - s.positionSeconds);
    final poster = widget.posterUrl;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 76,
                height: 114,
                child: poster == null
                    ? const ColoredBox(color: AppColors.surfaceHover)
                    : AppNetworkImage(
                        url: poster,
                        width: 76,
                        height: 114,
                        errorWidget:
                            const ColoredBox(color: AppColors.surfaceHover),
                      ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(AppIcons.series,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tr('Lecture en cours sur {0}', [device]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: AppType.callout,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.title2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (s.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      s.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppType.callout,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: s.progress,
                      minHeight: 5,
                      color: AppColors.progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  if (remaining != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      remaining,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: AppType.footnote,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 32),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _button(context),
                const SizedBox(height: 10),
                Text(
                  tr('ou lecture/pause sur la télécommande'),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: AppType.footnote,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Plein bleu au repos ; blanc, agrandi et cerclé quand il a le focus.
  Widget _button(BuildContext context) {
    final focused = _focused && widget.enabled;
    final foreground = focused ? Colors.black : AppColors.onAccent;
    return AnimatedScale(
      scale: focused ? 1.08 : 1,
      duration: AppMotion.move(context, AppMotion.focus),
      curve: AppMotion.curve,
      child: AnimatedContainer(
        duration: AppMotion.fade(context, AppMotion.focus),
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: focused ? Colors.white : AppColors.primary,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: focused ? AppColors.accent : Colors.transparent,
            width: 3,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    blurRadius: 22,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.play, size: 26, color: foreground),
            const SizedBox(width: 10),
            Text(
              tr('Reprendre'),
              style: TextStyle(
                color: foreground,
                fontSize: AppType.headline,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
