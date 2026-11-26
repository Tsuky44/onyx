import 'package:flutter/widgets.dart';

import '../../../models/retro.dart';
import '../../../theme/retro_palette.dart';
import '../widgets/retro_ambient.dart';
import '../widgets/retro_confetti.dart';
import '../widgets/retro_entrance.dart';
import '../widgets/retro_slide_layout.dart';

export '../widgets/retro_ambient.dart'
    show RetroAmbient, RetroBands, RetroDots, RetroOrbs, RetroRays, RetroRings;

/// Ce que chaque écran du Rétro reçoit.
class RetroStoryData {
  const RetroStoryData({
    required this.report,
    required this.name,
    required this.serverBaseUrl,
  });

  final RetroReport report;

  /// Le nom du compte, pour l'ouverture.
  final String name;

  /// Pour résoudre les affiches servies par le serveur.
  final String? serverBaseUrl;
}

/// Un écran de la story : ses couleurs, son texte, son visuel, et ce qu'un
/// lecteur d'écran en dit. La mise en page (portrait ou paysage) est commune,
/// dans [RetroSlideLayout].
abstract class RetroSlide {
  const RetroSlide();

  RetroColors colors(RetroStoryData data);

  /// Le texte porte l'écran : il prend la hauteur en portrait.
  bool get centered => false;

  Widget text(BuildContext context, RetroStoryData data);

  Widget? visual(BuildContext context, RetroStoryData data) => null;

  /// L'écran en une phrase, pour un lecteur d'écran (ADR-0054).
  String summary(RetroStoryData data);

  /// Le fond animé de l'écran, s'il en a un.
  RetroAmbient? ambient(RetroStoryData data) => null;

  /// Une gerbe de confettis : la carte de fin seulement.
  bool get confetti => false;

  /// Le texte et le visuel se construisent sous la mise en page : c'est elle
  /// qui pose l'unité de mesure (`RetroUnits`) qu'ils lisent.
  ///
  /// L'écran porte sa propre horloge d'entrée ([RetroEntrance]) : chaque
  /// ouverture rejoue l'arrivée des mots, des chiffres et des barres.
  Widget build(BuildContext context, RetroStoryData data) {
    final palette = colors(data);
    final ambient = this.ambient(data);
    return Semantics(
      container: true,
      label: summary(data),
      child: ExcludeSemantics(
        child: RetroEntrance(
          child: RetroSlideLayout(
            colors: palette,
            centered: centered,
            background: ambient == null && !confetti
                ? null
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (ambient != null)
                        RetroAmbientLayer(ambient: ambient, ink: palette.ink),
                      if (confetti)
                        RetroConfetti(colors: [
                          palette.ink,
                          palette.accent,
                          ...RetroPalette.confetti,
                        ]),
                    ],
                  ),
            text: Builder(builder: (context) => text(context, data)),
            visual: Builder(
              builder: (context) =>
                  visual(context, data) ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
