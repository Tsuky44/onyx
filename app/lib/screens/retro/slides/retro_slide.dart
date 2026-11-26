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
    this.topLogoUrl,
  });

  final RetroReport report;

  /// Le nom du compte, pour l'ouverture.
  final String name;

  /// Pour résoudre les affiches servies par le serveur.
  final String? serverBaseUrl;

  /// Le logo du n°1 (TMDB), déjà résolu ; null quand il n'en a pas ou qu'il
  /// n'est pas arrivé à temps : l'écran du n°1 écrit alors le titre.
  final String? topLogoUrl;
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

  /// Ce qui se pose sous le fond animé, sur tout l'écran : le mur d'affiches
  /// de l'ouverture, la teinte de l'affiche du n°1. Lit [RetroUnits].
  Widget? backdrop(BuildContext context, RetroStoryData data) => null;

  /// Toute la scène, posée par l'écran lui-même, quand la mise en page
  /// commune (texte, puis visuel) ne lui va pas — en général en paysage, où
  /// l'écran large demande ses propres places. Lit [RetroUnits] ; null garde
  /// la mise en page commune.
  Widget? compose(BuildContext context, RetroStoryData data) => null;

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
            background: Builder(
              builder: (context) => Stack(
                fit: StackFit.expand,
                children: [
                  if (backdrop(context, data) case final backdrop?) backdrop,
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
            ),
            compose: (context) => compose(context, data),
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
