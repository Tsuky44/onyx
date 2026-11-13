import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

import '../tv_focus_entry.dart';
import '../tv_mode.dart';
import '../tv_page.dart';
import '../tv_touchpad_pace.dart';
import 'onyx_dpad.dart';
import 'tv_dpad_focusable.dart';
import 'tv_focusable.dart';
import 'tv_rows.dart';
import 'tv_sections_scroll.dart';

/// Une fiche de téléviseur : des sections empilées ([TvSection]), parcourues
/// dans l'ordre de l'écran et posées chacune à sa place (ADR-0128).
///
/// Le parcours directionnel ordinaire devine sa cible d'après la géométrie
/// de tout l'écran, et chaque cible se ramenait à l'écran à sa façon. Sur une
/// fiche, cela donnait : Bas depuis le bouton retour qui saute « Lecture » et
/// la distribution pour une section plus bas, Haut qui ramène au bouton
/// retour et jamais à « Lecture », et une page qui monte puis redescend d'un
/// pas à l'autre.
///
/// Ici, deux règles tiennent toute la fiche :
///
/// - **Haut et Bas suivent les lignes.** Dans une section, ils passent à la
///   ligne voisine ([TvRows]) ; au bout de la section, à la première ou à la
///   dernière ligne de la section voisine. Aucune ligne ne se saute, où
///   qu'elle soit à l'horizontale. On entre dans une ligne par son entrée
///   ([_isEntry] : « Lecture », la saison affichée), sinon par la cible à la
///   verticale de celle qu'on quitte, sinon par son début ; les rangées
///   gardent leur propre règle (ADR-0113).
/// - **Chaque ligne a sa place.** La page se pose de la même façon d'où
///   qu'on vienne ([TvSectionsScroll]) : la section en haut de l'écran,
///   l'en-tête tout en haut, et une liste longue qui défile ligne à ligne.
///
/// Gauche et droite gardent leur parcours ordinaire, qui reste sur la ligne.
/// Le pavé de l'Apple TV, lui, s'arrête à chaque section ([TvTouchpadStop]).
class TvSections extends StatefulWidget {
  const TvSections({super.key, required this.child});

  final Widget child;

  @override
  State<TvSections> createState() => TvSectionsState();

  /// La section qui contient [node], si elle existe.
  static TvSectionState? sectionOf(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return null;
    return context.getInheritedWidgetOfExactType<_TvSectionScope>()?.state;
  }

  /// La fiche au-dessus de [context], s'il y en a une.
  static TvSectionsState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_TvSectionsScope>()?.state;
}

class TvSectionsState extends State<TvSections> implements TvPage {
  final List<TvSectionState> _sections = <TvSectionState>[];
  late final TvSectionsPolicy _policy = TvSectionsPolicy(this);

  void _register(TvSectionState section) {
    if (!_sections.contains(section)) _sections.add(section);
  }

  void _unregister(TvSectionState section) {
    _sections.remove(section);
  }

  /// Vrai sous dpad (`ONYX_TV_NAV=dpad`), faux avec l'ancien système.
  bool get _dpad => TvNavScope.isActive(context);

  /// Les cibles de la fiche rangées par section, celles qui sont posées à
  /// l'écran et peuvent prendre le focus. Une section sans cible n'y est pas.
  Map<TvSectionState, List<FocusNode>> _census(FocusScopeNode scope) {
    final census = <TvSectionState, List<FocusNode>>{};
    for (final node in scope.traversalDescendants) {
      if (node.context == null || node.rect.isEmpty || !node.canRequestFocus) {
        continue;
      }
      final section = TvSections.sectionOf(node);
      if (section == null || !identical(section._sections, this)) continue;
      (census[section] ??= <FocusNode>[]).add(node);
    }
    return census;
  }

  /// Les cibles de la section de [node], [node] compris.
  List<FocusNode> _sectionMates(FocusNode node) {
    final scope = node.nearestScope;
    final section = TvSections.sectionOf(node);
    if (scope == null || section == null) return <FocusNode>[node];
    return _census(scope)[section] ?? <FocusNode>[node];
  }

  /// Vrai quand [node] est une cible de cette fiche.
  bool holds(FocusNode node) =>
      identical(TvSections.sectionOf(node)?._sections, this);

  /// Où Haut ou Bas mène depuis [current] : la ligne voisine de sa section,
  /// sinon la ligne d'entrée de la section voisine. Nul au bout de la fiche.
  @override
  FocusNode? targetFor(FocusNode current, TraversalDirection direction) {
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down) {
      return null;
    }
    final down = direction == TraversalDirection.down;
    final scope = current.nearestScope;
    final section = TvSections.sectionOf(current);
    if (scope == null || section == null) return null;
    final census = _census(scope);

    var row = TvRows.next(
      current,
      census[section] ?? const <FocusNode>[],
      down: down,
    );
    var target = section;
    if (row.isEmpty) {
      final neighbour = _neighbour(census, section, current, down: down);
      if (neighbour == null) return null;
      target = neighbour;
      row = TvRows.edge(census[neighbour]!, top: down);
    }
    if (row.isEmpty) return null;

    final preferred = target.widget.preferredFocus;
    if (preferred != null && row.contains(preferred)) return preferred;
    for (final node in row) {
      if (_isEntry(node)) return node;
    }
    return TvRows.enter(row, current.rect);
  }

  /// La section qui suit [section] dans l'ordre de l'écran, parmi celles qui
  /// ont une cible. Une section se place par le haut de ses cibles ; celle de
  /// [current], qui peut n'en avoir plus d'autre, par [current] lui-même.
  TvSectionState? _neighbour(
    Map<TvSectionState, List<FocusNode>> census,
    TvSectionState section,
    FocusNode current, {
    required bool down,
  }) {
    double topOf(TvSectionState other) {
      final nodes = census[other];
      if (nodes == null || nodes.isEmpty) return current.rect.top;
      return nodes
          .map((node) => node.rect.top)
          .reduce((a, b) => a < b ? a : b);
    }

    final ordered = <TvSectionState>{...census.keys, section}.toList()
      ..sort((a, b) => topOf(a).compareTo(topOf(b)));
    final index = ordered.indexOf(section) + (down ? 1 : -1);
    if (index < 0 || index >= ordered.length) return null;
    return ordered[index];
  }

  @override
  bool step(FocusNode from, TraversalDirection direction) {
    final current = from;
    final target = targetFor(current, direction);
    if (target == null) return false;
    final context = target.context;
    final dpad = context == null ? null : Dpad.maybeOf(context);
    if (dpad == null) {
      // L'ancien système : les zones choisissent l'entrée (première carte
      // d'une rangée, bulle quittée), puis un seul défilement, le nôtre. La
      // politique d'alignement ne sert qu'hors téléviseur, au clavier d'un
      // bureau : la cible y est montrée au plus près, comme Flutter le fait.
      TvFocusEntries.requestFocus(
        target,
        alignmentPolicy: direction == TraversalDirection.down
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      return true;
    }
    final entered = _enterRegion(target, from: current);
    if (!dpad.requestFocus(entered)) return false;
    // dpad ne fait défiler que ses propres cibles : une pastille ordinaire
    // (« Lecture ») attendrait sinon hors de l'écran. Hors téléviseur, le
    // clavier d'un bureau garde le défilement de Flutter.
    if (TvMode.isTv) _revealAfterFrame(entered);
    return true;
  }

  /// Sous dpad, l'entrée que choisit la zone de [target] quand on y arrive
  /// d'ailleurs : sa mémoire, sa première carte (ADR-0113).
  FocusNode _enterRegion(FocusNode target, {required FocusNode from}) {
    final region = DpadRegion.ofNode(target);
    if (region == null || identical(region, DpadRegion.ofNode(from))) {
      return target;
    }
    final scope = target.nearestScope;
    if (scope == null) return target;
    final mates = <FocusNode>[
      for (final node in scope.traversalDescendants)
        if (identical(DpadRegion.ofNode(node), region)) node,
    ];
    // `resolveEnter` est `@internal` dans dpad 3.3.0 : `TvRailRegion` et
    // `TvPaneRegion` s'y appuient déjà, à relire à chaque montée de version.
    // ignore: invalid_use_of_internal_member
    return region.resolveEnter(target, mates);
  }

  void _revealAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.hasFocus) reveal(node);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void reveal(FocusNode node, {double? alignment}) {
    if (!mounted) return;
    final section = TvSections.sectionOf(node);
    TvSectionsScroll.reveal(
      page: context,
      node: node,
      row: TvRows.of(node, _sectionMates(node)),
      section: section?.context,
      alignment: alignment,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _TvSectionsScope(
      state: this,
      child: TvPageScope(
        page: this,
        child: FocusTraversalGroup(
          policy: _policy,
          child: widget.child,
        ),
      ),
    );
  }

  /// Vrai pour la cible par où l'on entre dans sa ligne : celle qu'un
  /// `TvFocusable` marque `entry` (la saison affichée), ou celle que la page
  /// focalise à l'ouverture (`autofocus` : « Lecture », « Demander »).
  static bool _isEntry(FocusNode node) {
    final context = node.context;
    if (context == null) return false;
    final widget = context.widget;
    if (widget is Focus && widget.autofocus) return true;
    final focusable = context.findAncestorWidgetOfExactType<TvFocusable>();
    if (focusable != null && (focusable.entry || focusable.autofocus)) {
      return true;
    }
    final dpadFocusable =
        context.findAncestorWidgetOfExactType<TvDpadFocusable>();
    return dpadFocusable?.entry ?? false;
  }
}

class _TvSectionsScope extends InheritedWidget {
  const _TvSectionsScope({required this.state, required super.child});

  final TvSectionsState state;

  @override
  bool updateShouldNotify(_TvSectionsScope oldWidget) =>
      !identical(oldWidget.state, state);
}

/// Une section d'une fiche, sous un [TvSections] : l'en-tête, les saisons,
/// les épisodes, la distribution.
///
/// C'est l'unité de la fiche : Haut et Bas en sortent par ses bords, la page
/// se cale sur son début, et un glissé du pavé de l'Apple TV ne la franchit
/// qu'une fois.
class TvSection extends StatefulWidget {
  const TvSection({
    super.key,
    this.id,
    this.preferredFocus,
    required this.child,
  });

  final String? id;

  /// La cible par où l'on entre dans sa ligne, quand la ligne ne la marque
  /// pas elle-même (voir [TvSectionsState.targetFor]).
  final FocusNode? preferredFocus;

  final Widget child;

  @override
  State<TvSection> createState() => TvSectionState();
}

class TvSectionState extends State<TvSection> {
  TvSectionsState? _sections;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sections = TvSections.maybeOf(context);
    if (identical(sections, _sections)) return;
    _sections?._unregister(this);
    _sections = sections;
    _sections?._register(this);
  }

  @override
  void dispose() {
    _sections?._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _TvSectionScope(
      state: this,
      child: TvTouchpadStop(zone: this, child: widget.child),
    );
  }
}

class _TvSectionScope extends InheritedWidget {
  const _TvSectionScope({required this.state, required super.child});

  final TvSectionState state;

  @override
  bool updateShouldNotify(_TvSectionScope oldWidget) =>
      !identical(oldWidget.state, state);
}

/// La politique de parcours d'une fiche : Haut et Bas par les lignes de
/// [TvSectionsState.step], le reste par le parcours ordinaire.
// ignore: must_be_immutable
class TvSectionsPolicy extends DpadTraversalPolicy {
  TvSectionsPolicy(this._state);

  final TvSectionsState _state;

  /// Avec l'ancien système, tout focus demandé par cette politique (Tab, le
  /// garde-fou `TvFocusGuard`) passe par les zones et le défilement de la
  /// fiche, comme une flèche. Sous dpad, c'est lui qui pose et fait défiler.
  @override
  TraversalRequestFocusCallback get requestFocusCallback =>
      _state.mounted && !_state._dpad
          ? TvFocusEntries.requestFocus
          : super.requestFocusCallback;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.left ||
        direction == TraversalDirection.right ||
        !_state.mounted ||
        !_state.holds(currentNode)) {
      return super.inDirection(currentNode, direction);
    }
    return _state.step(currentNode, direction);
  }
}
