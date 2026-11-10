import 'package:dpad/dpad.dart';
import 'package:flutter/widgets.dart';

import '../tv_focus_entry.dart';
import 'tv_dpad_focusable.dart';
import 'tv_focusable.dart';

/// Coordonne un ensemble de sections verticales ([TvSection]) sur une page.
///
/// La navigation directionnelle ordinaire devine sa cible d'après la géométrie :
/// elle privilégie les cibles dans le faisceau (« in beam »). Sur une fiche
/// de média où le bouton « Reprendre » est décalé à droite de l'affiche et où
/// les bulles de saison sont calées à gauche, Bas depuis « Reprendre » sautait
/// toute la rangée des saisons pour tomber sur le premier épisode, car
/// l'épisode, pleine largeur, est dans le faisceau alors que les saisons ne le
/// sont pas.
///
/// Ici, l'ordre entre sections est explicite :
/// - Tant qu'il y a un élément dans la direction demandée à l'intérieur de la
///   section, la navigation y reste.
/// - Quand on est au plus bas de la section et qu'on descend, le focus passe
///   au plus haut de la section suivante dans l'ordre de l'écran.
/// - Quand on est au plus haut de la section et qu'on monte, le focus passe
///   au plus bas (ou à l'élément mémorisé) de la section précédente.
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
}

class TvSectionsState extends State<TvSections> {
  final List<TvSectionState> _sections = <TvSectionState>[];
  late final TvSectionsPolicy _policy = TvSectionsPolicy(this);

  void _register(TvSectionState section) {
    if (!_sections.contains(section)) _sections.add(section);
  }

  void _unregister(TvSectionState section) {
    _sections.remove(section);
  }

  /// La section voisine de [current] dans la direction [step] (1 = bas, -1 = haut),
  /// parmi celles qui possèdent au moins un élément focalisable à l'écran.
  TvSectionState? neighbour(
    TvSectionState current,
    int step,
    FocusScopeNode scope,
  ) {
    final placed = <(TvSectionState, Rect, List<FocusNode>)>[];
    for (final section in _sections) {
      if (!section.mounted) continue;
      final c = section.candidates(scope);
      if (c.isEmpty && !identical(section, current)) continue;
      final r = section.rect(scope);
      if (r != null) {
        placed.add((section, r, c));
      }
    }
    placed.sort((a, b) => a.$2.top.compareTo(b.$2.top));

    final index = placed.indexWhere((entry) => identical(entry.$1, current));
    if (index < 0) return null;

    final targetIndex = index + step;
    if (targetIndex < 0 || targetIndex >= placed.length) return null;

    return placed[targetIndex].$1;
  }

  @override
  Widget build(BuildContext context) {
    return _TvSectionsScope(
      state: this,
      child: FocusTraversalGroup(
        policy: _policy,
        child: widget.child,
      ),
    );
  }
}

class _TvSectionsScope extends InheritedWidget {
  const _TvSectionsScope({required this.state, required super.child});

  final TvSectionsState state;

  @override
  bool updateShouldNotify(_TvSectionsScope oldWidget) =>
      !identical(oldWidget.state, state);
}

/// Une section verticale sous un [TvSections].
class TvSection extends StatefulWidget {
  const TvSection({
    super.key,
    this.id,
    this.preferredFocus,
    this.entersAtTop = true,
    required this.child,
  });

  final String? id;
  final FocusNode? preferredFocus;
  final bool entersAtTop;
  final Widget child;

  @override
  State<TvSection> createState() => TvSectionState();
}

class TvSectionState extends State<TvSection> {
  TvSectionsState? _sections;
  FocusNode? _lastFocused;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sections =
        context.getInheritedWidgetOfExactType<_TvSectionsScope>()?.state;
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

  void noteFocus(FocusNode node) {
    _lastFocused = node;
  }

  static bool _placed(FocusNode node) =>
      node.context != null && !node.rect.isEmpty && node.canRequestFocus;

  static bool _isEntry(FocusNode node) {
    final context = node.context;
    if (context == null) return false;
    final focusable = context.findAncestorWidgetOfExactType<TvFocusable>();
    if (focusable?.entry ?? false) return true;
    final dpadFocusable =
        context.findAncestorWidgetOfExactType<TvDpadFocusable>();
    if (dpadFocusable?.entry ?? false) return true;
    return false;
  }

  /// Tous les nœuds focalisables appartenant à cette section.
  List<FocusNode> candidates(FocusScopeNode scope) {
    return [
      for (final node in scope.traversalDescendants)
        if (_placed(node) && identical(TvSections.sectionOf(node), this)) node,
    ];
  }

  /// L'emprise globale de tous les éléments focalisables de cette section.
  Rect? rect(FocusScopeNode scope) {
    final list = candidates(scope);
    if (list.isEmpty) return null;
    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;
    for (final node in list) {
      final r = node.rect;
      if (r.left < left) left = r.left;
      if (r.top < top) top = r.top;
      if (r.right > right) right = r.right;
      if (r.bottom > bottom) bottom = r.bottom;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Choisit où le focus entre dans cette section selon le sens d'arrivée
  /// ([step] = 1 depuis le haut, [step] = -1 depuis le bas).
  FocusNode? entryFor(int step, FocusScopeNode scope, {double? fromX}) {
    final list = candidates(scope);
    if (list.isEmpty) return null;

    final preferred = widget.preferredFocus;
    if (preferred != null &&
        preferred.canRequestFocus &&
        preferred.context != null &&
        list.contains(preferred)) {
      return preferred;
    }

    if (step == 1) {
      // Arrivée depuis le haut : « au plus haut de l'autre zone ».
      for (final node in list) {
        if (_isEntry(node)) return node;
      }

      double minTop = double.infinity;
      for (final node in list) {
        if (node.rect.top < minTop) minTop = node.rect.top;
      }
      final topmost =
          list.where((node) => (node.rect.top - minTop).abs() < 12.0).toList();

      if (topmost.length == 1) return topmost.first;
      if (fromX != null) {
        return topmost.reduce((best, node) =>
            (node.rect.center.dx - fromX).abs() <
                    (best.rect.center.dx - fromX).abs()
                ? node
                : best);
      }
      return topmost.first;
    } else {
      // Arrivée depuis le bas : « au plus bas de l'autre zone » ou mémoire.
      final last = _lastFocused;
      if (last != null &&
          last.context != null &&
          last.canRequestFocus &&
          list.contains(last)) {
        return last;
      }

      double maxBottom = double.negativeInfinity;
      for (final node in list) {
        if (node.rect.bottom > maxBottom) maxBottom = node.rect.bottom;
      }
      final bottommost = list
          .where((node) => (node.rect.bottom - maxBottom).abs() < 12.0)
          .toList();

      if (bottommost.length == 1) return bottommost.first;
      if (fromX != null) {
        return bottommost.reduce((best, node) =>
            (node.rect.center.dx - fromX).abs() <
                    (best.rect.center.dx - fromX).abs()
                ? node
                : best);
      }
      return bottommost.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _TvSectionScope(state: this, child: widget.child);
  }
}

class _TvSectionScope extends InheritedWidget {
  const _TvSectionScope({required this.state, required super.child});

  final TvSectionState state;

  @override
  bool updateShouldNotify(_TvSectionScope oldWidget) =>
      !identical(oldWidget.state, state);
}

/// Politique de parcours des sections : verticale par transition de zone quand
/// on atteint le bord, ordinaire à l'intérieur d'une section et à l'horizontale.
// ignore: must_be_immutable
class TvSectionsPolicy extends DpadTraversalPolicy {
  TvSectionsPolicy(this._state);

  final TvSectionsState _state;

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final step = switch (direction) {
      TraversalDirection.up => -1,
      TraversalDirection.down => 1,
      TraversalDirection.left || TraversalDirection.right => 0,
    };
    if (step == 0) {
      return super.inDirection(currentNode, direction);
    }

    final currentSection = TvSections.sectionOf(currentNode);
    if (currentSection == null) {
      return super.inDirection(currentNode, direction);
    }

    final scope = currentNode.nearestScope;
    if (scope == null) return false;

    final currentRect = currentNode.rect;

    // Y a-t-il d'autres candidats dans la direction demandée à l'intérieur de la même section ?
    final sectionCandidates = currentSection.candidates(scope)
      ..removeWhere((node) => identical(node, currentNode));

    final hasWithin = sectionCandidates.any((node) {
      final r = node.rect;
      if (step == 1) {
        return r.top >= currentRect.bottom - 4 && r.bottom > currentRect.bottom;
      } else {
        return r.bottom <= currentRect.top + 4 && r.top < currentRect.top;
      }
    });

    if (hasWithin) {
      return super.inDirection(currentNode, direction);
    }

    currentSection.noteFocus(currentNode);

    final nextSection = _state.neighbour(currentSection, step, scope);
    if (nextSection == null) {
      return false;
    }

    final target = nextSection.entryFor(
      step,
      scope,
      fromX: currentRect.center.dx,
    );
    if (target == null) return false;

    final context = target.context;
    final dpad = context == null ? null : Dpad.maybeOf(context);
    if (dpad != null) {
      return dpad.requestFocus(target);
    }
    TvFocusEntries.requestFocus(target);
    return true;
  }
}
