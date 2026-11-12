import 'package:flutter/widgets.dart';

import 'tv_focus_panes.dart';
import 'tv_focus_scroll.dart';
import 'tv_mode.dart';

/// Ce qu'une zone répond quand le focus s'apprête à y entrer.
///
/// [landed] est l'élément que le parcours directionnel a choisi dans la zone,
/// [from] celui que la télécommande quitte (nul s'il n'y en a pas). La réponse
/// est l'élément qui doit recevoir le focus à la place, ou nul pour garder
/// [landed]. Une zone ne se prononce que pour une *entrée* : quand [from] est
/// déjà dans la zone, elle répond nul.
typedef TvFocusEntry = FocusNode? Function(FocusNode landed, FocusNode? from);

/// Les zones qui choisissent où le focus entre, consultées *avant* qu'il ne se
/// pose.
///
/// Rediriger après coup — réagir à `onFocusChange` par un second `requestFocus`
/// — coûtait deux pas par flèche : le focus se posait sur l'élément géométrique,
/// la zone le déplaçait à la frame suivante, et le défilement, déjà lancé vers
/// le premier, repartait vers le second. Ici, la politique de parcours demande
/// la réponse des zones qui entourent l'élément trouvé, puis ne pose le focus
/// qu'une fois, sur le bon. Voir ADR-0109.
///
/// Les zones s'inscrivent sur leur propre nœud de focus ([register]) et
/// s'emboîtent : l'ancêtre le plus extérieur parle d'abord, un onglet avant sa
/// rangée.
abstract final class TvFocusEntries {
  static final Expando<TvFocusEntry> _zones = Expando<TvFocusEntry>(
    'tv-focus-entry',
  );

  /// Inscrit [entry] pour tout ce qui vit sous [zone]. Chaque appel est rendu
  /// par un [unregister], au `dispose` de la zone.
  static void register(FocusNode zone, TvFocusEntry entry) {
    _zones[zone] = entry;
  }

  static void unregister(FocusNode zone) {
    _zones[zone] = null;
  }

  /// Où le focus doit réellement entrer quand le parcours a trouvé [landed].
  ///
  /// Hors téléviseur, [landed] : les zones ne redirigent jamais rien.
  static FocusNode resolve(FocusNode landed, {FocusNode? from}) {
    if (!TvMode.isTv) return landed;
    // `ancestors` va du plus proche au plus lointain : on veut l'inverse.
    final zones = [
      for (final ancestor in landed.ancestors)
        if (_zones[ancestor] != null) ancestor,
    ].reversed;
    for (final zone in zones) {
      final entry = _zones[zone]!(landed, from);
      if (entry != null && !identical(entry, landed)) return entry;
    }
    return landed;
  }

  /// Le [TraversalRequestFocusCallback] des politiques de l'app : demande le
  /// focus sur l'élément que les zones désignent, et le ramène à l'écran d'un
  /// seul défilement. Voir [TvFocusScroll.requestFocus].
  static void requestFocus(
    FocusNode node, {
    ScrollPositionAlignmentPolicy? alignmentPolicy,
    double? alignment,
    Duration? duration,
    Curve? curve,
  }) {
    final target = resolve(node, from: FocusManager.instance.primaryFocus);
    // Haut ou bas qui sortirait d'un volet : le focus reste où il est.
    if (!TvFocusPanes.admits(target)) return;
    TvFocusScroll.requestFocus(
      target,
      alignmentPolicy: alignmentPolicy,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }
}

/// La politique de parcours de l'app, dans l'ordre de lecture : les zones
/// ([TvFocusEntries]) choisissent l'entrée, [TvFocusScroll] fait défiler.
///
/// Une zone qui veut son propre ordre pose un `FocusTraversalGroup` avec
/// [TvWidgetOrderTraversalPolicy] ; les deux passent par les mêmes entrées.
class TvTraversalPolicy extends ReadingOrderTraversalPolicy {
  TvTraversalPolicy()
      : super(requestFocusCallback: TvFocusEntries.requestFocus);
}

/// La même politique, dans l'ordre des widgets : celle d'une zone dont l'ordre
/// de déclaration est l'ordre voulu (l'en-tête du shell).
class TvWidgetOrderTraversalPolicy extends WidgetOrderTraversalPolicy {
  TvWidgetOrderTraversalPolicy()
      : super(requestFocusCallback: TvFocusEntries.requestFocus);
}
