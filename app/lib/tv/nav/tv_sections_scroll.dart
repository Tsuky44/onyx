import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';
import '../tv_focus_scroll.dart';

/// Où une fiche de téléviseur se pose quand le focus change de ligne, et à
/// quelle allure elle y va (ADR-0128).
///
/// Avant, chaque cible décidait : une affiche se centrait, une pastille se
/// collait en bas de l'écran, une ligne d'épisode se posait au tiers. De
/// « Télécharger la saison » à « Marquer la saison vue » puis à une bulle de
/// saison, la page remontait tout en haut, redescendait d'un tiers d'écran et
/// remontait encore. Et ces trajets, souvent plus d'un demi-écran, se
/// faisaient en 200 ms.
///
/// Ici la place ne dépend que de la ligne focalisée :
///
/// 1. **la section se cale en haut de l'écran**, à [topMargin] du bord, titre
///    compris. Toutes les lignes qu'elle montre alors partagent cette place :
///    passer de l'une à l'autre ne fait rien défiler. L'en-tête, première
///    section, pose donc la page tout en haut ;
/// 2. **une ligne trop basse pour cette place** (le cinquième épisode) fait
///    monter la page juste assez pour se tenir à [focusBottom] de la hauteur :
///    une liste longue défile alors ligne à ligne, la suivante déjà visible.
///
/// L'allure suit la distance ([durationFor]) : un pas dans une liste garde
/// celle d'un pas, un changement de section prend le temps de se lire.
abstract final class TvSectionsScroll {
  /// L'écart, en pixels de page, entre le haut de l'écran et le début de la
  /// section focalisée. La marge sûre d'un téléviseur (5 % de 720) : le
  /// padding de la section porte le reste.
  static const double topMargin = 36;

  /// La part de la hauteur de l'écran sous laquelle la ligne focalisée ne
  /// descend pas. À 0,72, la ligne suivante d'une liste d'épisodes (135 px)
  /// tient entière dessous.
  static const double focusBottom = 0.72;

  /// Ce qu'une ligne garde au-dessus d'elle quand elle est plus haute que
  /// l'écran ne le permet : la place de son anneau de focus.
  static const double ringMargin = 16;

  /// La part de la hauteur de l'écran à partir de laquelle un trajet prend
  /// la durée d'un changement de section ([AppMotion.section]).
  static const double fullTravel = 0.6;

  /// En deçà, la page est déjà à sa place : un éventail qui redresse une
  /// carte déplace sa ligne de quelques pixels, pas la page.
  static const double _settled = 6;

  /// Pose la page pour [node], dont [row] est la ligne et [section] la
  /// section. [page] est le contexte de la fiche : seul ce qui défile dessous
  /// est concerné. [alignment] vaut pour les rangées horizontales que [node]
  /// traverse (0,5 centre une affiche) ; nul, la cible y est juste montrée.
  static void reveal({
    required BuildContext page,
    required FocusNode node,
    required List<FocusNode> row,
    required BuildContext? section,
    double? alignment,
  }) {
    final context = node.context;
    if (context == null || !context.mounted) return;
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) return;

    // Ce qui défile entre la cible et la fiche, du plus proche au plus
    // lointain. La fiche elle-même est le plus lointain des défilements
    // verticaux ; le reste (une rangée d'affiches) suit sa règle ordinaire.
    final chain = <ScrollableState>[];
    for (var scrollable = Scrollable.maybeOf(context);
        scrollable != null && _isWithin(scrollable.context, page);
        scrollable = Scrollable.maybeOf(scrollable.context)) {
      chain.add(scrollable);
    }
    final pageIndex = chain.lastIndexWhere(
      (scrollable) =>
          axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical,
    );
    final duration = TvFocusScroll.durationFor(context);
    for (var i = 0; i < chain.length; i++) {
      if (i == pageIndex) continue;
      _revealInRail(chain[i].position, object, alignment, duration);
    }
    if (pageIndex < 0) return;

    // Le viewport de la fiche : un par défilement traversé.
    RenderAbstractViewport? viewport = RenderAbstractViewport.maybeOf(object);
    for (var i = 0; i < pageIndex && viewport != null; i++) {
      viewport = RenderAbstractViewport.maybeOf(viewport.parent);
    }
    if (viewport == null) return;
    if (section == null || !section.mounted) {
      // Une cible hors de toute section n'a pas de place à elle : elle est
      // juste montrée.
      _revealInRail(chain[pageIndex].position, object, null, duration);
      return;
    }
    _rest(
      context: context,
      position: chain[pageIndex].position,
      viewport: viewport,
      row: row,
      section: section,
    );
  }

  static bool _isWithin(BuildContext context, BuildContext page) {
    var within = false;
    context.visitAncestorElements((element) {
      within = identical(element, page);
      return !within;
    });
    return within;
  }

  static void _revealInRail(
    ScrollPosition position,
    RenderBox object,
    double? alignment,
    Duration duration,
  ) {
    if (alignment != null) {
      position.ensureVisible(
        object,
        alignment: alignment,
        duration: duration,
        curve: AppMotion.curve,
      );
      return;
    }
    // Sans place demandée, la cible est montrée au plus près, d'un bord puis
    // de l'autre : l'appel ne fait rien quand elle est déjà de ce côté-là.
    for (final policy in const <ScrollPositionAlignmentPolicy>[
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      position.ensureVisible(
        object,
        alignmentPolicy: policy,
        duration: duration,
        curve: AppMotion.curve,
      );
    }
  }

  static void _rest({
    required BuildContext context,
    required ScrollPosition position,
    required RenderAbstractViewport viewport,
    required List<FocusNode> row,
    required BuildContext section,
  }) {
    if (!position.hasPixels || !position.hasContentDimensions) return;
    final target = restOffset(
      viewport: viewport,
      viewportExtent: position.viewportDimension,
      row: <RenderObject>[
        for (final node in row)
          if (node.context?.findRenderObject() case final RenderObject object
              when object.attached)
            object,
      ],
      section: section.findRenderObject(),
      minExtent: position.minScrollExtent,
    );
    if (target == null) return;
    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final distance = (clamped - position.pixels).abs();
    if (distance < _settled) return;
    final duration = durationFor(
      context,
      distance: distance,
      viewportExtent: position.viewportDimension,
    );
    if (duration == Duration.zero) {
      position.jumpTo(clamped);
    } else {
      position.animateTo(
        clamped,
        duration: duration,
        curve:
            TvFocusScroll.isTracking ? AppMotion.curve : AppMotion.sectionCurve,
      );
    }
  }

  /// La position de défilement où [row] se pose dans [viewport] : voir la
  /// règle en tête de classe. Nulle quand la ligne n'y est pas. [minExtent]
  /// est le début de la page.
  ///
  /// Par les positions de défilement du viewport, et non par les rectangles à
  /// l'écran : une section encore sous l'écran n'a pas de place fiable tant
  /// qu'elle n'est pas dessinée, alors que sa position de défilement est
  /// exacte.
  @visibleForTesting
  static double? restOffset({
    required RenderAbstractViewport viewport,
    required double viewportExtent,
    required List<RenderObject> row,
    required RenderObject? section,
    double minExtent = 0,
  }) {
    double? rowTop;
    double? rowBottom;
    for (final object in row) {
      if (!_isUnder(object, viewport)) continue;
      // La position où la cible touche le haut de l'écran, puis le bas.
      final top = viewport.getOffsetToReveal(object, 0).offset;
      final bottom = viewport.getOffsetToReveal(object, 1).offset;
      rowTop = rowTop == null ? top : math.min(rowTop, top);
      rowBottom = rowBottom == null ? bottom : math.max(rowBottom, bottom);
    }
    if (rowTop == null || rowBottom == null) return null;

    // 2. La ligne à [focusBottom] de la hauteur, pas plus bas : c'est la
    // position où son bas touche le bas de l'écran, plus ce qu'il faut pour
    // la remonter jusque-là.
    var target = rowBottom + viewportExtent * (1 - focusBottom);
    // 1. La section calée en haut, tant que la ligne y tient : la page ne
    // remonte jamais au-dessus du début de sa section.
    if (section != null && section.attached && _isUnder(section, viewport)) {
      final anchor = viewport.getOffsetToReveal(section, 0).offset - topMargin;
      // La première section de la page, l'en-tête : tout en haut tant que
      // la ligne s'y voit en entier, même plus bas que [focusBottom]. Une
      // fiche dont les actions descendent un peu bas ne doit pas glisser de
      // quelques pixels chaque fois qu'on revient sur « Lecture ».
      if (anchor <= minExtent && rowBottom + ringMargin <= minExtent) {
        return minExtent;
      }
      target = math.max(target, anchor);
    }
    // Une ligne plus haute que sa place garde son haut à l'écran.
    return math.min(target, rowTop - ringMargin);
  }

  static bool _isUnder(RenderObject object, RenderAbstractViewport viewport) {
    for (RenderObject? ancestor = object.parent;
        ancestor != null;
        ancestor = ancestor.parent) {
      if (identical(ancestor, viewport)) return true;
    }
    return false;
  }

  /// La durée d'un trajet de [distance] pixels dans un écran haut de
  /// [viewportExtent].
  ///
  /// Un pas dans une liste (135 px) reste proche d'[AppMotion.standard] ; un
  /// changement de section, qui parcourt plus d'un demi-écran, prend
  /// [AppMotion.section]. Entre les deux, la durée suit la distance : la
  /// page garde à peu près la même vitesse, au lieu de traverser l'écran dans
  /// le temps d'un pas. Flèche maintenue ou rangée qui file : la durée la
  /// plus courte, les pas se suivent ([TvFocusScroll.isTracking]).
  static Duration durationFor(
    BuildContext context, {
    required double distance,
    required double viewportExtent,
  }) {
    if (TvFocusScroll.isTracking) return TvFocusScroll.durationFor(context);
    final travel = viewportExtent <= 0
        ? 1.0
        : (distance / (viewportExtent * fullTravel)).clamp(0.0, 1.0);
    final milliseconds = lerpDouble(
      AppMotion.standard.inMilliseconds,
      AppMotion.section.inMilliseconds,
      travel,
    )!;
    return AppMotion.move(
        context, Duration(milliseconds: milliseconds.round()));
  }
}
