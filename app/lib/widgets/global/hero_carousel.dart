import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import '../../models/models.dart';
import '../../theme/app_motion.dart';
import '../../theme/lite_mode.dart';
import '../../tv/nav/tv_region.dart';
import '../../tv/tv_mode.dart';
import '../../utils/hero_slides.dart';
import '../../utils/on_screen.dart';
import 'hero/hero_living_backdrop.dart';
import 'hero/hero_page_dashes.dart';
import 'hero_banner.dart';

class HeroCarousel extends StatefulWidget {
  final List<HeroSlide> slides;
  final void Function(HeroSlide slide) onPlay;
  final void Function(HeroSlide slide)? onInfo;

  /// Gives the visible slide's play button the first focus. Television only —
  /// see [HeroBanner.autofocusPlay].
  final bool autofocusPlay;

  /// Voir [HeroBanner.extendTop].
  final double extendTop;

  /// Une première page qui n'est pas un média : le Rétro de fin d'année
  /// (ADR 2026-11-26-tsuky-retro-annuel). Elle défile, se tourne et prend le
  /// focus comme les autres ; [autofocus] lui dit si son bouton doit le
  /// prendre d'office.
  final Widget Function(BuildContext context, bool autofocus)? leading;

  const HeroCarousel({
    super.key,
    required this.slides,
    required this.onPlay,
    this.onInfo,
    this.autofocusPlay = false,
    this.extendTop = 0,
    this.leading,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel>
    with OnScreenState, SingleTickerProviderStateMixin {
  /// Le temps d'une diapositive.
  static const _defaultDwell = Duration(seconds: 7);

  /// Le plus long qu'une diapositive au fond vivant reste à l'écran : quatre
  /// images de quatre secondes (ADR-0154).
  static const _maxDwell = Duration(seconds: 16);

  late final PageController _pageController;
  Timer? _autoTimer;

  /// Ce que chaque diapositive demande de temps, quand son fond fait défiler
  /// des images ; les autres prennent [_defaultDwell].
  final Map<int, Duration> _dwell = {};

  /// Le temps déjà passé sur la diapositive affichée : [_elapsedBefore] avant
  /// la dernière pause, [_clock] depuis. Le survol suspend le défilement sans
  /// le remettre à zéro.
  Duration _elapsedBefore = Duration.zero;
  final Stopwatch _clock = Stopwatch();

  /// Le remplissage du trait de la diapositive affichée ([HeroPageDashes]).
  late final AnimationController _fill =
      AnimationController(vsync: this, value: 1);
  int _currentIndex = 0;
  bool _hovered = false;

  /// Le focus est dans le bandeau. Au clavier, il suspend le défilement comme
  /// le survol d'une souris ; à la télécommande, non ([_heldByFocus]).
  bool _focused = false;

  /// Le focus retient le bandeau, hors téléviseur seulement.
  ///
  /// La télécommande a toujours le focus quelque part, et d'abord ici, sur
  /// « Reprendre » : retenu par lui, le bandeau d'un téléviseur ne défilait
  /// jamais, sous des traits figés, quand celui du bureau tourne seul. Le
  /// bouton de la diapositive qui arrive reprend le focus de celle qui part
  /// (voir [_advance]).
  bool get _heldByFocus => _focused && !TvScope.of(context);

  /// La page d'en tête, quand il y en a une.
  int get _lead => widget.leading == null ? 0 : 1;

  /// Toutes les pages : celle d'en tête, puis les médias.
  int get _count => widget.slides.length + _lead;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  /// Le carrousel n'avance que sous les yeux de quelqu'un : caché sous le
  /// lecteur, dans un autre onglet ou fenêtre réduite, chaque diapositive
  /// relançait une transition d'une seconde que personne ne voyait.
  @override
  void didChangeOnScreen(bool onScreen) => _scheduleAutoAdvance();

  @override
  void didUpdateWidget(covariant HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount =
        oldWidget.slides.length + (oldWidget.leading == null ? 0 : 1);
    if (oldCount != _count) {
      _currentIndex = 0;
      _dwell.clear();
      _restartClock();
      // L'accueil s'est rechargé sous la télécommande : le retour à la
      // première page ne doit pas lui faire perdre le focus.
      _refocusAfterPaging = _focused;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _scheduleAutoAdvance();
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _fill.dispose();
    _pageController.dispose();
    _observer.dispose();
    super.dispose();
  }

  /// Un doigt s'est posé sur le bandeau : il ne repart plus tout seul. Au
  /// tactile il n'y a pas de survol pour le suspendre, et le mouvement était
  /// inarrêtable.
  bool _touched = false;

  /// Rien n'arrête le défilement pour l'instant.
  bool get _advances =>
      _count > 1 &&
      !_hovered &&
      !_heldByFocus &&
      !_touched &&
      isOnScreen &&
      // « Réduire les animations » : un fond plein écran qui défile seul
      // est exactement ce que ce réglage demande d'éviter.
      !AppMotion.reduced(context);

  /// Plus rien ne fera défiler le bandeau tout seul : le trait reste plein
  /// au lieu de rester à moitié rempli.
  bool get _stopsForGood =>
      _count <= 1 || _touched || AppMotion.reduced(context);

  Duration get _elapsed => _elapsedBefore + _clock.elapsed;

  Duration _dwellOf(int index) => _dwell[index] ?? _defaultDwell;

  void _restartClock() {
    _elapsedBefore = Duration.zero;
    _clock.reset();
  }

  /// Arme la diapositive affichée pour ce qui lui reste de temps, ou la met
  /// en pause.
  ///
  /// Une minuterie par diapositive, et non plus une périodique : une série
  /// au fond vivant reste plus longtemps qu'un film (ADR-0154).
  void _scheduleAutoAdvance() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (!_advances) {
      _elapsedBefore = _elapsed;
      _clock
        ..stop()
        ..reset();
      _fill.stop();
      if (_stopsForGood) _fill.value = 1;
      return;
    }
    final dwell = _dwellOf(_currentIndex);
    final elapsed = _elapsed < dwell ? _elapsed : dwell;
    _elapsedBefore = elapsed;
    _clock
      ..reset()
      ..start();
    _autoTimer = Timer(dwell - elapsed, _advance);
    // Un téléviseur en mode léger garde ses traits immobiles : une animation
    // de plus en continu sous chaque bandeau, pour une petite box, n'en
    // valait pas le coût. Les autres remplissent leur trait comme le bureau.
    if (TvScope.of(context) && LiteScope.of(context)) {
      _fill.value = 1;
    } else {
      _fill.duration = dwell;
      _fill.forward(from: elapsed.inMicroseconds / dwell.inMicroseconds);
    }
  }

  void _advance() {
    _autoTimer = null;
    if (!mounted || !_advances) return;
    final next = (_currentIndex + 1) % _count;
    // Sous la télécommande, le bouton de la diapositive qui arrive prend le
    // focus de celle qui part : sinon il retombait sur l'en-tête.
    _refocusAfterPaging = _focused;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Le fond de la diapositive [index] fera défiler [frames] images : elle
  /// reste le temps de les montrer, sans dépasser [_maxDwell].
  void _onFrameCount(int index, int frames) {
    var dwell = HeroLivingBackdrop.frameDuration * frames;
    if (dwell < _defaultDwell) dwell = _defaultDwell;
    if (dwell > _maxDwell) dwell = _maxDwell;
    if (_dwellOf(index) == dwell) return;
    _dwell[index] = dwell;
    // La diapositive est déjà à l'écran : elle garde le temps passé.
    if (index == _currentIndex && _autoTimer != null) _scheduleAutoAdvance();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _restartClock();
    _scheduleAutoAdvance();
    if (!_refocusAfterPaging) return;
    _refocusAfterPaging = false;
    // Partie dans une rangée pendant que la page tournait, la télécommande y
    // reste.
    if (!_focused) return;
    // L'ancienne page vient de sortir du parcours (voir [build]) et son bouton
    // a perdu le focus : il passe au premier bouton de la nouvelle, au même
    // endroit de l'écran.
    //
    // Sans condition sur le focus actuel : à ce moment, le bouton exclu le
    // tient encore, et le retrait n'est appliqué qu'à la microtâche suivante —
    // vers le dernier élément focalisé de la page, l'onglet de l'en-tête. Le
    // focus demandé ici passe après et l'emporte.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targets = _observer.traversalDescendants;
      if (targets.isNotEmpty) targets.first.requestFocus();
    });
  }

  /// Observe le focus du bandeau, sans jamais le prendre.
  final FocusNode _observer = FocusNode(
    debugLabel: 'hero-carousel',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// Le bandeau entier à l'écran dès que la télécommande y entre.
  ///
  /// Remonter depuis la première rangée ne défilait que jusqu'au bouton, posé
  /// au ras du haut de l'écran : sous l'en-tête de verre, avec le titre et le
  /// logo hors de l'écran. Cette animation, demandée après celle du parcours,
  /// la remplace.
  void _revealWhole() {
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position == null || !position.hasContentDimensions) return;
    // Même déjà en haut : le défilement du parcours vient peut-être de partir
    // vers l'élément d'abord visé (« Voir tout », avant que la mémoire de
    // l'onglet ne rende le focus au bandeau), et c'est lui qu'il faut arrêter.
    final duration = AppMotion.move(context);
    if (duration == Duration.zero) {
      position.jumpTo(position.minScrollExtent);
    } else {
      position.animateTo(position.minScrollExtent,
          duration: duration, curve: AppMotion.curve);
    }
  }

  /// La page change sous la télécommande : son bouton doit suivre.
  bool _refocusAfterPaging = false;

  /// Gauche et droite au bord de la diapositive affichée la tournent (voir
  /// [TvRegion.slide]).
  ///
  /// Sans ça, la télécommande ne voyait que la diapositive affichée : droite
  /// depuis « Plus d'infos » sautait n'importe où à droite de l'écran (la
  /// recherche de l'en-tête), et les autres titres n'étaient atteignables
  /// qu'en attendant que le carrousel tourne.
  void _turn(TraversalDirection direction) {
    final step = direction == TraversalDirection.right ? 1 : -1;
    final count = _count;
    _refocusAfterPaging = true;
    _pageController.animateToPage(
      (_currentIndex + step + count) % count,
      duration: AppMotion.move(context, AppMotion.emphasis),
      curve: AppMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;
    final bannerHeight = HeroBanner.heightFor(context) + widget.extendTop;

    return Focus(
      // A pure observer: it reports that something below it holds the focus,
      // and never takes it itself.
      focusNode: _observer,
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        _focused = focused;
        _scheduleAutoAdvance();
        if (focused) _revealWhole();
      },
      child: Listener(
        onPointerDown: (event) {
          if (event.kind != PointerDeviceKind.touch || _touched) return;
          _touched = true;
          _scheduleAutoAdvance();
        },
        child: MouseRegion(
          onEnter: (_) {
            _hovered = true;
            _scheduleAutoAdvance();
          },
          onExit: (_) {
            _hovered = false;
            _scheduleAutoAdvance();
          },
          child: SizedBox(
            height: bannerHeight,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: _count,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    if (index < _lead) {
                      return ExcludeFocus(
                        excluding: index != _currentIndex,
                        child: TvRegion.slide(
                          onEdge: _count > 1 ? _turn : null,
                          child: widget.leading!(
                            context,
                            widget.autofocusPlay && index == 0,
                          ),
                        ),
                      );
                    }
                    final slide = widget.slides[index - _lead];
                    // Seule la page affichée se parcourt : le PageView garde
                    // ses voisines construites hors écran, et Bas depuis
                    // l'en-tête pouvait y poser le focus — invisible.
                    return ExcludeFocus(
                      excluding: index != _currentIndex,
                      child: TvRegion.slide(
                        onEdge: _count > 1 ? _turn : null,
                        child: HeroBanner(
                          media: slide.media,
                          titleOverride: slide.title,
                          subtitle: slide.subtitle,
                          backgroundUrlOverride: slide.backgroundUrl,
                          detailsMediaId: slide.media.type == MediaType.episode
                              ? slide.continueItem?.showId
                              : slide.media.id,
                          playLabel: slide.playLabel,
                          onPlay: () => widget.onPlay(slide),
                          onInfo: slide.showInfoButton && widget.onInfo != null
                              ? () => widget.onInfo!(slide)
                              : null,
                          // Only the slide on screen: an autofocus on a page the
                          // PageView has built ahead would pull the focus off-screen.
                          autofocusPlay: widget.autofocusPlay && index == 0,
                          extendTop: widget.extendTop,
                          continueItem: slide.continueItem,
                          active: index == _currentIndex,
                          onFrameCount: (frames) =>
                              _onFrameCount(index, frames),
                        ),
                      ),
                    );
                  },
                ),
                if (_count > 1)
                  Positioned(
                    // Alignés sur le texte du bandeau, pas centrés sous un
                    // contenu qui, lui, est calé à gauche.
                    left: isCompact ? 16 : 48,
                    bottom: isCompact ? 20 : 36,
                    child: HeroPageDashes(
                      count: _count,
                      current: _currentIndex,
                      progress: _fill,
                      onTap: (index) => _pageController.animateToPage(
                        index,
                        duration: AppMotion.move(context, AppMotion.emphasis),
                        curve: AppMotion.curve,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
