import 'package:flutter/widgets.dart';

import '../tv_mode.dart';
import 'tv_sections.dart';

/// Rend le focus à l'entrée d'une rangée d'actions arrivée après l'ouverture
/// de sa page : « Lecture », « Demander ».
///
/// `autofocus` ne vaut qu'à l'ouverture d'une route encore sans focus. Une
/// fiche qui attend le réseau (une demande, l'épisode à reprendre d'une
/// série) a déjà le sien quand son action principale arrive : le garde-fou
/// (`TvFocusGuard`), devant une route sans cible, l'a donné au premier
/// élément de l'écran, le bouton retour. La télécommande s'ouvrait alors en
/// haut à gauche, à trois pas de « Lecture ».
///
/// Sur un téléviseur seulement.
abstract final class TvEntryFocus {
  /// Demande le focus pour [entry] à la fin de l'image, s'il est resté là où
  /// la page l'a posé faute de mieux : nulle part, ou dans la section
  /// d'[entry] (le bouton retour, une action voisine). Quelqu'un qui est
  /// déjà parti plus bas dans la page, ou dans un dialogue, garde sa place.
  static void claim(FocusNode entry) {
    if (!TvMode.isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (entry.context == null || !entry.canRequestFocus) return;
      if (entry.hasPrimaryFocus) return;
      // La route de l'entrée doit tenir le focus : sous un dialogue ou une
      // autre page, il n'y a rien à reprendre.
      if (!(entry.enclosingScope?.hasFocus ?? false)) return;
      final focus = FocusManager.instance.primaryFocus;
      final stranded = focus == null || focus is FocusScopeNode;
      if (!stranded) {
        final section = TvSections.sectionOf(entry);
        if (section == null ||
            !identical(section, TvSections.sectionOf(focus))) {
          return;
        }
      }
      entry.requestFocus();
    });
  }
}
