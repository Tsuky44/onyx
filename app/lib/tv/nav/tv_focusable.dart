import 'package:flutter/widgets.dart';

import '../tv_focus.dart' show TvLegacyFocusable;
import '../tv_mode.dart';
import 'onyx_dpad.dart';
import 'tv_card_directions.dart';
import 'tv_dpad_focusable.dart';

export '../tv_focus.dart' show TvFocusHalo, kTvBackKeys, kTvSelectKeys;

/// La cible de focus que les écrans emploient (ADR-0110).
///
/// Une façade : sous `OnyxDpad` (compilation `ONYX_TV_NAV=dpad`), c'est
/// [TvDpadFocusable], et dpad décide où va le focus et quand la page défile ;
/// ailleurs, c'est l'ancien `TvFocusable` ([TvLegacyFocusable]), à
/// l'identique. Les écrans ne voient ni l'un ni l'autre : passer d'un système à
/// l'autre ne leur fait pas changer une ligne.
///
/// Le choix suit ce qui est monté à la racine ([TvNavScope]), pas le drapeau
/// lui-même : le drapeau se lit une fois, dans `main.dart`, et un test monte
/// l'un ou l'autre système sans recompiler.
///
/// Sur dpad, l'action passe par [onSelect] seulement : l'enfant ne prend plus
/// le focus, et le `onPressed` d'un bouton enveloppé n'est plus appelé par la
/// télécommande (constat N4, gardé par `no_parallel_focus_system_test`).
class TvFocusable extends StatelessWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.onContextMenu,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.entry = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.focusScale = 1.05,
    this.scrollAlignment = 0.5,
    this.showRing = true,
    this.onFocusChange,
    this.onDirection,
    this.childFocus = false,
  });

  final Widget child;

  /// OK, Entrée, A d'une manette. D'ordinaire le même rappel que le `onTap`
  /// de l'enfant.
  final VoidCallback? onSelect;

  /// L'appui long sur OK, la touche menu ou Y d'une manette, quand la cible a
  /// un menu qui vaut d'être atteint.
  final VoidCallback? onContextMenu;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Faux pour une carte présente mais inactive : visible et inatteignable.
  final bool enabled;

  /// L'élément où le focus entre dans sa zone (`TvRegion`) quand elle n'a
  /// rien en mémoire : la première carte d'une rangée, l'onglet affiché de
  /// l'en-tête (constat C8). Un par zone. Sans effet hors dpad : l'ancien
  /// système choisit l'entrée par la zone (`TvFocusMemory.entersAtTop`).
  final bool entry;

  /// Suit l'arrondi de l'enfant, pour que l'anneau épouse l'affiche.
  final BorderRadius borderRadius;

  /// L'agrandissement au focus, sur téléviseur seulement. 1.0 l'éteint.
  final double focusScale;

  /// Où la cible se pose une fois ramenée à l'écran ; 0,5 la centre.
  final double scrollAlignment;

  /// Faux quand l'enfant dessine son propre focus (l'affiche s'éclaire).
  final bool showRing;

  final ValueChanged<bool>? onFocusChange;

  /// Une flèche que la carte garde pour elle avant que le parcours ne la
  /// voie : passer à ses icônes, tourner une page. Vrai : la flèche est prise,
  /// le focus ne bouge que si la carte l'a déplacé. Faux : la flèche continue
  /// vers le parcours. Sur téléviseur seulement.
  ///
  /// Appelé quand la carte a le focus ; avec [childFocus], aussi pour gauche
  /// et droite quand l'une de ses cibles internes l'a. C'est le
  /// `DpadFocusable.onDirection` de dpad, qui remplace le `Focus.onKeyEvent`
  /// d'un écran (ADR-0110).
  final bool Function(TraversalDirection direction)? onDirection;

  /// L'enfant garde ses propres cibles de focus (les icônes d'une ligne
  /// d'épisode). Sous dpad, elles restent focalisables au lieu d'être
  /// exclues ; c'est à l'écran de les retirer du parcours directionnel et de
  /// les atteindre par [onDirection]. Haut et bas depuis l'une d'elles
  /// repartent de la carte (voir `TvCardDirections`).
  final bool childFocus;

  @override
  Widget build(BuildContext context) {
    if (TvNavScope.isActive(context)) {
      return TvDpadFocusable(
        onSelect: onSelect,
        onContextMenu: onContextMenu,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        entry: entry,
        borderRadius: borderRadius,
        focusScale: focusScale,
        scrollAlignment: scrollAlignment,
        showRing: showRing,
        onFocusChange: onFocusChange,
        onDirection: onDirection,
        childFocus: childFocus,
        child: child,
      );
    }
    final directions = onDirection;
    if (directions != null && TvScope.of(context)) {
      return _LegacyCard(card: this, onDirection: directions);
    }
    return _legacy(focusNode);
  }

  Widget _legacy(FocusNode? focusNode) => TvLegacyFocusable(
        onSelect: onSelect,
        onContextMenu: onContextMenu,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        borderRadius: borderRadius,
        focusScale: focusScale,
        scrollAlignment: scrollAlignment,
        showRing: showRing,
        onFocusChange: onFocusChange,
        child: child,
      );
}

/// L'ancien `TvFocusable` avec [TvFocusable.onDirection] : l'écran posait
/// lui-même un `Focus(onKeyEvent:)` autour de la carte, il est ici, à
/// l'identique ([TvCardDirections.legacy]). Disparaît avec le drapeau
/// `ONYX_TV_NAV`.
class _LegacyCard extends StatefulWidget {
  const _LegacyCard({required this.card, required this.onDirection});

  final TvFocusable card;
  final bool Function(TraversalDirection direction) onDirection;

  @override
  State<_LegacyCard> createState() => _LegacyCardState();
}

class _LegacyCardState extends State<_LegacyCard> {
  /// Créé quand l'écran ne fournit pas le sien : il faut savoir si le focus
  /// est sur la carte ou sur l'une de ses icônes.
  FocusNode? _owned;

  FocusNode get _node =>
      widget.card.focusNode ?? (_owned ??= FocusNode(debugLabel: 'tv-card'));

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvCardDirections.legacy(
        card: _node,
        onDirection: widget.onDirection,
        child: widget.card._legacy(_node),
      );
}
