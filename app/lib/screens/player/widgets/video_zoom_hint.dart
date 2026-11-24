import 'package:material_ui/material_ui.dart';

import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../video_display_mode.dart';
import 'onyx/onyx_chrome_theme.dart';
import 'onyx/onyx_glass_panel.dart';

/// Transient label naming the display mode a pinch just landed on.
///
/// The gesture changes the shape of the picture, sometimes by cropping its
/// edges away, and does it without touching the chrome — so it needs to say
/// what it did.
///
/// Une capsule fine du verre du lecteur ([OnyxGlassPanel]), comme « Passer
/// l'intro » et les boutons ronds. Elle était un pavé au fond et au flou à
/// elle, plus haut et plus gros que tout ce que le lecteur pose sur l'image :
/// l'utilisateur l'a trouvée trop grosse à côté du reste.
///
/// Placed above the middle rather than on it: the centre belongs to the
/// transport button, which may be up at the same time.
class VideoZoomHint extends StatelessWidget {
  /// The mode the picture has just been put into.
  final VideoDisplayMode mode;

  final bool visible;

  const VideoZoomHint({super.key, required this.mode, required this.visible});

  /// La hauteur de la capsule : celle d'une ligne de texte et de son icône,
  /// pas celle d'un bouton — on ne la touche pas.
  static const double height = 32;

  static const BorderRadius _capsule =
      BorderRadius.all(Radius.circular(height / 2));

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          // In fast, out slow: the answer has to be legible the instant the
          // fingers land, and must not linger over the film afterwards.
          duration: visible ? AppMotion.focus : AppMotion.emphasis,
          curve: AppMotion.curve,
          child: OnyxGlassPanel(
            radius: _capsule,
            // Une pastille d'une seconde : pas l'ombre portée d'un panneau.
            elevated: false,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(mode.icon, color: OnyxChromeTheme.title, size: 16),
                    const SizedBox(width: 7),
                    Text(
                      mode.label,
                      style: const TextStyle(
                        color: OnyxChromeTheme.title,
                        fontSize: AppType.subhead,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
