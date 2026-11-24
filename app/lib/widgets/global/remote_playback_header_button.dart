import 'package:material_ui/material_ui.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../tv/nav/tv_focusable.dart';
import 'remote_playback_slot.dart';

/// « Reprendre ici » dans la barre du haut d'un téléviseur, à côté du compte,
/// au même niveau que les onglets (ADR-0136).
///
/// Il n'existe que tant que l'accueil annonce une lecture sur un autre
/// appareil ([RemotePlaybackSlot]), et hors Apple TV : la Siri Remote reprend
/// en maintenant lecture/pause. Haut depuis l'accueil mène à la barre, Droite
/// jusqu'à lui, OK reprend. La notification juste dessous s'éclaire quand il a
/// le focus et dit « OK pour reprendre ici » : c'est elle qui dit quoi.
class RemotePlaybackHeaderButton extends StatefulWidget {
  const RemotePlaybackHeaderButton({super.key});

  /// Le diamètre du disque : celui du compte, pour que la barre reste d'une
  /// seule hauteur.
  static const double size = 34;

  @override
  State<RemotePlaybackHeaderButton> createState() =>
      _RemotePlaybackHeaderButtonState();
}

class _RemotePlaybackHeaderButtonState
    extends State<RemotePlaybackHeaderButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final slot = RemotePlaybackSlotScope.maybeOf(context);
    if (slot == null || slot.play == null) return const SizedBox.shrink();
    const size = RemotePlaybackHeaderButton.size;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: tr('Reprendre ici'),
        child: TvFocusable(
          focusNode: slot.focus,
          onSelect: slot.onResume,
          onFocusChange: (focused) => setState(() => _focused = focused),
          showRing: false,
          focusScale: 1,
          borderRadius: const BorderRadius.all(Radius.circular(size / 2)),
          child: AnimatedScale(
            scale: _focused ? 1.12 : 1.0,
            duration: AppMotion.move(context, AppMotion.micro),
            curve: AppMotion.curve,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              // Le disque de verre du compte (`GlassIconButton`), avec son
              // anneau de focus.
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: _focused ? 0.18 : 0.08),
                border: Border.all(
                  color: _focused
                      ? AppColors.focus
                      : Colors.white.withValues(alpha: 0.12),
                  width: _focused ? 2 : 1,
                ),
              ),
              child: const Icon(AppIcons.play,
                  size: size * 0.5, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
