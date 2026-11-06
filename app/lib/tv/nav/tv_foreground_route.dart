import 'package:flutter/widgets.dart';

/// Si un élément focalisé vit dans la route affichée, et sinon comment y
/// revenir.
///
/// Sert la parade N1 d'`OnyxDpad` (ADR-0110) : à la reprise de l'app, dpad
/// rend le focus au dernier élément encore monté sans regarder si sa route
/// est toujours au premier plan. Une route poussée pendant la pause (lien
/// profond, reprise de lecture, `PlaybackHandoffWatch`) laisse alors le focus
/// sous elle, et les flèches naviguent dans un écran que personne ne voit.
abstract final class TvForegroundRoute {
  /// La route la plus extérieure qui contient [node] sans être au premier
  /// plan de son navigateur, ou nul quand [node] est bien dans ce qui est
  /// affiché.
  ///
  /// La plus extérieure, parce que les navigateurs s'emboîtent : un onglet
  /// garde sa propre pile, et l'onglet entier peut être recouvert par une
  /// fiche poussée sur le navigateur racine.
  static ModalRoute<Object?>? coveredRouteOf(FocusNode node) {
    ModalRoute<Object?>? covered;
    BuildContext? context = node.context;
    while (context != null && context.mounted) {
      final route = ModalRoute.of(context);
      if (route == null) break;
      if (!route.isCurrent) covered = route;
      context = route.navigator?.context;
    }
    return covered;
  }

  /// Rend le focus à la route au premier plan du navigateur de [covered].
  ///
  /// Le focus va à la *portée* de la route, pas à un élément choisi ici : la
  /// portée sans enfant focalisé, dpad y pose lui-même son élément d'entrée
  /// (`entry`, sinon le premier candidat), comme après un `push` ordinaire.
  /// Un seul endroit décide donc de l'élément d'entrée. Vrai quand une route
  /// a été trouvée.
  static bool refocus(ModalRoute<Object?> covered) {
    final navigator = covered.navigator;
    if (navigator == null) return false;
    Route<Object?>? top;
    // Le navigateur ne publie pas sa route du dessus. `popUntil` la donne
    // la première à son prédicat ; répondre vrai l'arrête sans rien dépiler.
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    final foreground = top;
    if (foreground is! ModalRoute<Object?> || identical(foreground, covered)) {
      return false;
    }
    // La portée de la route n'est pas publique ; celle qui englobe son
    // contenu, si.
    final content = foreground.subtreeContext;
    if (content == null || !content.mounted) return false;
    FocusScope.of(content).requestFocus();
    return true;
  }
}
