import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import 'theme/app_colors.dart';
import 'theme/app_motion.dart';
import 'tv/tv_mode.dart';
import 'utils/app_platform.dart';
import 'utils/responsive.dart';
import 'utils/window_controls.dart';
import 'widgets/global/window_caption_buttons.dart';

/// Custom caption bar is Windows-only; macOS keeps native traffic lights.
bool get useDesktopCaptionBar => AppPlatform.isWindows;

/// Hidden native title bar (custom bar on Windows, traffic lights on macOS).
bool get useHiddenNativeTitleBar =>
    AppPlatform.isWindows || AppPlatform.isMacOS;

/// Vertical space for macOS traffic lights — UI controls sit just below.
double get macOSWindowControlsTopInset => AppPlatform.isMacOS ? 40 : 0;

/// Les marges de l'en-tête d'un téléviseur (`ShellTvHeader`), en pixels de la
/// page TV de 1280 de large : 22 px valent 33 pt sur une Apple TV, hors de la
/// zone qu'un téléviseur peut rogner. Sa pilule fait [tvShellHeaderBarHeight].
const double tvShellHeaderTopGap = 22;
const double tvShellHeaderBottomGap = 12;
const double tvShellHeaderBarHeight = 44;

/// Height of the desktop glass nav (≥900px), from the top of the window.
///
/// Sur un téléviseur, celle de `ShellTvHeader` : la pilule des onglets et ses
/// marges (ADR-0117).
double shellHeaderHeight(BuildContext context) {
  if (TvScope.of(context)) {
    return MediaQuery.paddingOf(context).top +
        tvShellHeaderTopGap +
        tvShellHeaderBarHeight +
        tvShellHeaderBottomGap;
  }
  const headerVerticalPadding = 16.0; // matches _DesktopGlassHeader (6 + 10)
  const navRowHeight = 44.0;
  return MediaQuery.paddingOf(context).top +
      macOSWindowControlsTopInset +
      headerVerticalPadding +
      navRowHeight;
}

/// Top padding for tab bodies when the desktop glass nav overlaps content (≥900px).
double embeddedShellContentTopInset(BuildContext context) {
  const gapBelowHeader = 12.0;
  return shellHeaderHeight(context) + gapBelowHeader;
}

/// Marge du haut d'un onglet du shell, quelle que soit la barre qui flotte
/// au-dessus : la barre de verre desktop quand [embedded], sinon la barre
/// du téléphone (barre d'état + 56) ou, sur tablette, une marge fixe. Un
/// onglet qui met 28 ici passe son titre sous la barre de recherche.
double shellTabTopInset(BuildContext context, {required bool embedded}) {
  if (embedded) return embeddedShellContentTopInset(context);
  if (MediaQuery.sizeOf(context).width < AppBreakpoints.compact) {
    return MediaQuery.paddingOf(context).top + 56;
  }
  return 48;
}

/// Controls visibility of the custom desktop caption bar (Windows only).
final ValueNotifier<bool> showDesktopCaption =
    ValueNotifier<bool>(AppPlatform.isWindows);

/// Vrai tant que la barre de titre sort par-dessus le lecteur
/// ([CaptionBarPeek]) : les boutons du haut du lecteur descendent d'autant
/// ([CaptionPeekInset]) au lieu de passer dessous.
final ValueNotifier<bool> desktopCaptionPeeking = ValueNotifier<bool>(false);

/// Le nombre d'en-têtes à l'écran qui portent les contrôles de la fenêtre.
int _captionHostCount = 0;

/// Vrai tant qu'un en-tête à l'écran porte lui-même les contrôles de la
/// fenêtre ([WindowCaptionHost]) : la bande du haut n'a alors plus lieu
/// d'être (ADR-0157).
ValueListenable<bool> get windowCaptionHosted => _windowCaptionHosted;
final ValueNotifier<bool> _windowCaptionHosted = ValueNotifier<bool>(false);

/// Barre de titre maison de Windows : la zone vide déplace la fenêtre
/// (double-clic : agrandir) et les contrôles ([WindowCaptionButtons]) restent
/// en haut à droite.
///
/// Elle ne sert plus qu'où aucun en-tête ne les porte : écrans de connexion,
/// fenêtre trop étroite pour l'en-tête de verre, pages qui couvrent la
/// coquille. Sur la coquille, ils sont dans l'en-tête ([WindowCaptionHost]).
/// Le fond est celui de l'app et non une surface plus claire, qui la
/// découpait d'une bande grise.
class WindowCaptionBar extends StatelessWidget {
  /// Posée sur la vidéo ([CaptionBarPeek]) : un dégradé sombre au lieu du
  /// fond, pour garder les symboles lisibles sur une image claire.
  final bool overVideo;

  const WindowCaptionBar({super.key, this.overVideo = false});

  /// Hauteur de la barre : juste de quoi loger les boutons et rester
  /// saisissable à la souris pour déplacer la fenêtre.
  static const double height = 28;

  @override
  Widget build(BuildContext context) {
    if (!useDesktopCaptionBar) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: overVideo
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.black.withValues(alpha: 0),
                ],
              ),
            )
          : const BoxDecoration(color: AppColors.background),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            const Expanded(
              child: WindowDragArea(child: SizedBox.expand()),
            ),
            const WindowCaptionButtons(height: height),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// La bande du haut dans la colonne de l'app : là tant que [showDesktopCaption]
/// est vrai (le lecteur la retire) et qu'aucun en-tête ne porte les contrôles.
class DesktopCaptionSlot extends StatelessWidget {
  const DesktopCaptionSlot({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([showDesktopCaption, windowCaptionHosted]),
      builder: (context, _) =>
          showDesktopCaption.value && !windowCaptionHosted.value
              ? const WindowCaptionBar()
              : const SizedBox.shrink(),
    );
  }
}

/// Un en-tête qui montre lui-même les contrôles de la fenêtre : tant qu'il
/// est à l'écran, la bande du haut s'efface et lui rend sa hauteur.
///
/// « À l'écran » se lit à [TickerMode] : une page opaque poussée par-dessus
/// (« Qui regarde ? », le lecteur) met la coquille hors scène, et la bande
/// revient. Un menu ou un panneau la laisse en scène : l'en-tête reste
/// visible derrière son voile.
///
/// Le compte change après l'image : le modifier pendant la construction
/// reconstruirait un ancêtre (la colonne de l'app) en cours de route.
class WindowCaptionHost extends StatefulWidget {
  final Widget child;

  const WindowCaptionHost({super.key, required this.child});

  @override
  State<WindowCaptionHost> createState() => _WindowCaptionHostState();
}

class _WindowCaptionHostState extends State<WindowCaptionHost> {
  bool _claimed = false;

  void _claim(bool claimed) {
    if (_claimed == claimed) return;
    _claimed = claimed;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _captionHostCount += claimed ? 1 : -1;
      _windowCaptionHosted.value = _captionHostCount > 0;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _claim(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _claim(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Fait réapparaître la barre de titre par-dessus le lecteur, comme la barre
/// de menus de macOS : la barre est cachée pendant la lecture, ce qui ôtait la
/// seule poignée de la fenêtre (fermer, réduire, déplacer).
///
/// La barre se pose en surimpression au lieu de repousser la vidéo, qui ne
/// bouge donc pas d'un pixel ; seuls les boutons du haut du lecteur
/// descendent de sa hauteur ([CaptionPeekInset]) pour rester visibles. Elle
/// sort quand la souris touche le bord haut de
/// la fenêtre, y reste tant que la souris est dessus, et repart un moment
/// après qu'elle s'en est éloignée.
///
/// Inerte tant que [showDesktopCaption] est vrai : la barre a alors sa place
/// dans la colonne et rien n'est à surimposer. L'arbre ne change jamais de
/// forme, sans quoi le Navigator perdrait son état en passant au lecteur.
class CaptionBarPeek extends StatefulWidget {
  final Widget child;

  const CaptionBarPeek({super.key, required this.child});

  /// Bande du bord haut qui fait sortir la barre. Fine : elle ne doit pas
  /// se déclencher quand la souris vise un bouton du lecteur.
  static const double triggerZone = 6;

  /// Tant que la souris est dans cette zone, la barre reste : la barre
  /// elle-même plus une marge, pour ne pas la perdre en visant une pastille.
  static const double keepZone = WindowCaptionBar.height + 12;

  /// « Que ça reste un peu » : le délai avant de ranger la barre.
  static const Duration lingerDelay = Duration(milliseconds: 1800);

  @override
  State<CaptionBarPeek> createState() => _CaptionBarPeekState();
}

class _CaptionBarPeekState extends State<CaptionBarPeek> {
  bool _shown = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    showDesktopCaption.addListener(_onCaptionInLayout);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    showDesktopCaption.removeListener(_onCaptionInLayout);
    desktopCaptionPeeking.value = false;
    super.dispose();
  }

  /// La barre reprend sa place dans la colonne (on quitte le lecteur) : plus
  /// rien ne sort par-dessus, et rien ne doit rester décalé.
  void _onCaptionInLayout() {
    if (!showDesktopCaption.value) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    _setShown(false);
  }

  void _setShown(bool shown) {
    desktopCaptionPeeking.value = shown;
    if (_shown != shown) setState(() => _shown = shown);
  }

  void _onHover(PointerHoverEvent event) {
    if (!useDesktopCaptionBar || showDesktopCaption.value) return;
    final y = event.localPosition.dy;
    if (y <= CaptionBarPeek.triggerZone ||
        (_shown && y <= CaptionBarPeek.keepZone)) {
      _reveal();
    } else {
      _scheduleHide();
    }
  }

  void _reveal() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _setShown(true);
  }

  void _scheduleHide() {
    if (!_shown || _hideTimer != null) return;
    _hideTimer = Timer(CaptionBarPeek.lingerDelay, () {
      _hideTimer = null;
      if (mounted) _setShown(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: _onHover,
      child: MouseRegion(
        opaque: false,
        onExit: (_) => _scheduleHide(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (useDesktopCaptionBar)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: showDesktopCaption,
                  builder: (context, captionInLayout, _) {
                    final visible = _shown && !captionInLayout;
                    return IgnorePointer(
                      ignoring: !visible,
                      child: AnimatedSlide(
                        offset: visible ? Offset.zero : const Offset(0, -1),
                        duration: AppMotion.fade(context, AppMotion.micro),
                        curve: AppMotion.curve,
                        child: AnimatedOpacity(
                          opacity: visible ? 1 : 0,
                          duration: AppMotion.fade(context, AppMotion.micro),
                          curve: AppMotion.curve,
                          child: const WindowCaptionBar(overVideo: true),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Descend [child] de la hauteur de la barre de titre tant qu'elle sort
/// par-dessus le lecteur ([desktopCaptionPeeking]), au même rythme qu'elle :
/// les boutons du haut glissent sous la barre au lieu d'être recouverts.
class CaptionPeekInset extends StatelessWidget {
  final Widget child;

  const CaptionPeekInset({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!useDesktopCaptionBar) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: desktopCaptionPeeking,
      builder: (context, peeking, child) => AnimatedPadding(
        padding: EdgeInsets.only(top: peeking ? WindowCaptionBar.height : 0),
        duration: AppMotion.fade(context, AppMotion.micro),
        curve: AppMotion.curve,
        child: child,
      ),
      child: child,
    );
  }
}
