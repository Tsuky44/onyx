import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/lite_mode.dart';
import '../tv_focus_ring.dart';
import '../tv_mode.dart';
import '../tv_page.dart';
import 'tv_card_directions.dart';
import 'tv_contained_steps.dart';
import 'tv_nav_theme.dart';
import 'tv_wide_card.dart';

/// `TvFocusable` posé sur dpad : même API, même anneau, mais c'est dpad qui
/// décide où va le focus, quand la page défile et ce que vaut OK.
///
/// Les écrans ne l'emploient pas directement : `TvFocusable`
/// (`tv/nav/tv_focusable.dart`) le monte sous `OnyxDpad` (ADR-0110).
///
/// Ce qui change pour qui l'emploie :
///
/// - **l'action passe par [onSelect]** (constat N4). dpad rend l'enfant non
///   focalisable : un bouton Material enveloppé ne reçoit plus OK, son
///   `onPressed` n'est jamais appelé par la télécommande ;
/// - **un appui sur OK, un [onSelect]** (constat C9) : tvOS envoie Select en
///   `enter`, que dpad et l'`ActivateIntent` de Flutter reconnaissent tous
///   deux, et dpad ne le compte qu'une fois ;
/// - **le toucher ne passe pas par ici** : `tapToSelect` est coupé, l'enfant
///   garde ses propres gestes, comme avec l'ancien `TvFocusable` ;
/// - l'appui long (menu de la carte) se mesure entre l'appui et le relâchement
///   ([TvNavTheme.longSelectDuration]), plus aux répétitions.
class TvDpadFocusable extends StatefulWidget {
  const TvDpadFocusable({
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
    this.wide = false,
    this.editable = false,
  });

  final Widget child;

  /// OK, Entrée, A d'une manette. Le seul chemin de la télécommande vers
  /// l'action : voir N4 plus haut.
  final VoidCallback? onSelect;

  /// L'appui long sur OK, la touche menu ou Y d'une manette.
  final VoidCallback? onContextMenu;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Faux pour une carte présente mais inactive : visible et inatteignable.
  final bool enabled;

  /// L'entrée de sa zone quand elle n'a rien en mémoire (constat C8).
  final bool entry;

  /// Suit l'arrondi de l'enfant, pour que l'anneau épouse l'affiche.
  final BorderRadius borderRadius;

  /// L'agrandissement au focus, sur téléviseur seulement. 1.0 l'éteint.
  final double focusScale;

  /// 0,5 centre la cible dans ce qui défile ; toute autre valeur la ramène
  /// juste assez (voir [TvNavTheme.alignmentFor]).
  final double scrollAlignment;

  /// Faux quand l'enfant dessine son propre focus (l'affiche s'éclaire).
  final bool showRing;

  final ValueChanged<bool>? onFocusChange;

  /// Voir `TvFocusable.onDirection`.
  final bool Function(TraversalDirection direction)? onDirection;

  /// Voir `TvFocusable.childFocus` : l'enfant n'est pas exclu du focus. Sans
  /// [onDirection], droite entre dans ses boutons et gauche en ressort
  /// ([TvContainedSteps]).
  final bool childFocus;

  /// Voir `TvFocusable.wide` ([TvWideCard]).
  final bool wide;

  /// Voir `TvFocusable.editable` : le champ enveloppé garde le focus, et
  /// aucune flèche n'est prise avant dpad (`excludeChildFocus: false`, le
  /// montage que dpad prévoit pour un champ de saisie).
  final bool editable;

  static final Expando<VoidCallback> _contextMenus = Expando<VoidCallback>(
    'tv-context-menu',
  );

  /// Le menu de la carte focalisée, pour la touche menu que dpad remonte à
  /// la racine (`OnyxDpad`). Le nœud focalisé peut être celui de la carte ou
  /// l'un de ses descendants.
  static VoidCallback? contextMenuFor(FocusNode? node) {
    for (FocusNode? current = node; current != null; current = current.parent) {
      final menu = _contextMenus[current];
      if (menu != null) return menu;
    }
    return null;
  }

  @override
  State<TvDpadFocusable> createState() => _TvDpadFocusableState();
}

class _TvDpadFocusableState extends State<TvDpadFocusable> {
  /// Créé quand l'appelant n'en fournit pas : le menu de la carte s'y
  /// attache, et dpad a besoin d'un nœud stable pour s'en souvenir.
  FocusNode? _ownedNode;

  FocusNode get _node =>
      widget.focusNode ??
      (_ownedNode ??= FocusNode(debugLabel: 'tv-dpad-focusable'));

  @override
  void initState() {
    super.initState();
    _registerMenu(null);
  }

  @override
  void didUpdateWidget(TvDpadFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _registerMenu(oldWidget.focusNode ?? _ownedNode);
  }

  @override
  void dispose() {
    TvDpadFocusable._contextMenus[_node] = null;
    _ownedNode?.dispose();
    super.dispose();
  }

  /// Le [TvFocusable.onDirection] d'une carte qui garde ses boutons
  /// ([TvFocusable.childFocus]) sans en donner un : droite y entre, gauche
  /// en ressort, et l'on s'arrête au bord de la carte.
  bool _containedStep(TraversalDirection direction) {
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return false;
    final onCard = identical(current, _node);
    switch (direction) {
      case TraversalDirection.right:
        final target = onCard
            ? TvContainedSteps.into(_node)
            : TvContainedSteps.beside(current, _node, direction);
        if (onCard && target == null) return false;
        target?.requestFocus();
        return true;
      case TraversalDirection.left:
        if (onCard) return false;
        (TvContainedSteps.beside(current, _node, direction) ?? _node)
            .requestFocus();
        return true;
      case TraversalDirection.up:
      case TraversalDirection.down:
        return false;
    }
  }

  /// Après l'image qui pose le focus, comme le défilement de dpad : la
  /// ligne d'arrivée peut encore se mettre en page.
  void _revealIn(TvPage page) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _node.hasFocus) {
        page.reveal(_node, alignment: widget.scrollAlignment);
      }
    });
  }

  void _registerMenu(FocusNode? previous) {
    if (previous != null && !identical(previous, _node)) {
      TvDpadFocusable._contextMenus[previous] = null;
    }
    TvDpadFocusable._contextMenus[_node] =
        widget.enabled ? widget.onContextMenu : null;
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvScope.of(context);
    // Dans une page qui tient son parcours (une fiche, [TvPage]), Haut et
    // Bas lui reviennent avant que la zone de la carte ne réponde : dpad
    // cherche d'abord dans la zone, et un éventail de cartes penchées y
    // trouvait toujours une voisine « plus bas ».
    final page = isTv ? TvPageScope.maybeOf(context) : null;
    final own =
        widget.onDirection ?? (widget.childFocus ? _containedStep : null);
    final onDirection = !isTv
        ? null
        : page == null
            ? own
            : (TraversalDirection direction) =>
                (own?.call(direction) ?? false) || page.step(_node, direction);
    final focusable = DpadFocusable(
      focusNode: _node,
      // Sur téléviseur seulement : prendre le focus sur un téléphone ouvre
      // le clavier et dessine un anneau que personne n'a demandé.
      autofocus: widget.autofocus && widget.enabled && isTv,
      enabled: widget.enabled,
      entry: widget.entry || widget.wide,
      onSelect: widget.onSelect,
      onLongSelect: isTv && widget.enabled ? widget.onContextMenu : null,
      onFocusChange: page == null
          ? widget.onFocusChange
          : (focused) {
              widget.onFocusChange?.call(focused);
              if (focused) _revealIn(page);
            },
      // La page pose son propre défilement : celui de dpad s'y ajouterait.
      autoScroll: page == null,
      scrollAlignment: TvNavTheme.alignmentFor(widget.scrollAlignment),
      tapToSelect: false,
      excludeChildFocus: !widget.childFocus && !widget.editable,
      onDirection: onDirection,
      builder: (context, state, child) => _TvFocusRing(
        // dpad ne lit pas le nœud qu'on lui donne : il attend un changement.
        // Le menu du lecteur passe un même nœud, déjà focalisé, d'une rangée
        // à l'autre ; sans cette lecture, la rangée qui l'hérite n'aurait pas
        // d'anneau (comme l'ancien `TvFocusable`, voir son `initState`).
        focused: state.focused || _node.hasFocus,
        isTv: isTv,
        borderRadius: widget.borderRadius,
        focusScale: widget.focusScale,
        showRing: widget.showRing,
        child: child,
      ),
      child: widget.childFocus
          // Les cibles de la carte ne se trouvent pas par le parcours : haut
          // et bas passent de carte en carte, sans s'arrêter sur le menu de
          // la ligne suivante ni sur l'`InkWell` qui double la carte ; droite
          // les atteint ([_containedStep], [TvCardDirections]).
          ? Focus(
              canRequestFocus: false,
              skipTraversal: true,
              descendantsAreTraversable: false,
              includeSemantics: false,
              child: widget.child,
            )
          : widget.child,
    );
    final card = onDirection == null || !widget.childFocus
        ? focusable
        : TvCardDirections.dpad(
            card: _node,
            onDirection: onDirection,
            child: focusable,
          );
    return widget.wide && isTv ? TvWideCard(card: _node, child: card) : card;
  }
}

/// L'anneau d'Onyx (ADR-0008), le même que celui de l'ancien `TvFocusable`.
class _TvFocusRing extends StatelessWidget {
  const _TvFocusRing({
    required this.focused,
    required this.isTv,
    required this.borderRadius,
    required this.focusScale,
    required this.showRing,
    required this.child,
  });

  final bool focused;
  final bool isTv;
  final BorderRadius borderRadius;
  final double focusScale;
  final bool showRing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lite = LiteScope.of(context);
    Widget content = TvFocusRing(
      visible: focused && showRing,
      borderRadius: borderRadius,
      child: child,
    );
    // L'agrandissement est un geste de téléviseur : sur téléphone ou bureau,
    // il se battrait avec le survol des cartes.
    if (isTv && focusScale != 1.0) {
      content = AnimatedScale(
        scale: focused ? focusScale : 1.0,
        duration: lite ? Duration.zero : AppMotion.focus,
        curve: Curves.easeOutCubic,
        child: content,
      );
    }
    return content;
  }
}
