import 'dart:async';

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';

import 'theme/app_colors.dart';
import 'theme/app_motion.dart';
import 'tv/tv_mode.dart';
import 'utils/app_platform.dart';
import 'utils/responsive.dart';
import 'utils/window_controls.dart';
import 'l10n/tr.dart';

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

/// Barre de titre maison de Windows, affichée tant que [showDesktopCaption]
/// est vrai. La zone vide déplace la fenêtre (double-clic : agrandir) et les
/// contrôles restent en haut à droite, dans l'ordre Windows, sous forme de
/// pastilles [WindowControlPills].
class WindowCaptionBar extends StatefulWidget {
  const WindowCaptionBar({super.key});

  /// Hauteur de la barre : juste de quoi loger les pastilles et rester
  /// saisissable à la souris pour déplacer la fenêtre.
  static const double height = 28;

  @override
  State<WindowCaptionBar> createState() => _WindowCaptionBarState();
}

class _WindowCaptionBarState extends State<WindowCaptionBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _syncMaximized();
  }

  Future<void> _syncMaximized() async {
    if (!useDesktopCaptionBar) return;
    final maximized = await WindowControls.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await WindowControls.unmaximize();
    } else {
      await WindowControls.maximize();
    }
    await _syncMaximized();
  }

  @override
  Widget build(BuildContext context) {
    if (!useDesktopCaptionBar) {
      return const SizedBox.shrink();
    }

    return Container(
      height: WindowCaptionBar.height,
      color: AppColors.surface,
      child: Row(
        children: [
          // Draggable / double-tap area (empty space only)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => WindowControls.startDragging(),
              onDoubleTap: _toggleMaximize,
              child: const SizedBox.expand(),
            ),
          ),
          WindowControlPills(
            isMaximized: _isMaximized,
            onMinimize: WindowControls.minimize,
            onToggleMaximize: _toggleMaximize,
            onClose: WindowControls.close,
          ),
        ],
      ),
    );
  }
}

/// Fait réapparaître la barre de titre par-dessus le lecteur, comme la barre
/// de menus de macOS : la barre est cachée pendant la lecture, ce qui ôtait la
/// seule poignée de la fenêtre (fermer, réduire, déplacer).
///
/// La barre se pose en surimpression au lieu de repousser la vidéo, qui ne
/// bouge donc pas d'un pixel. Elle sort quand la souris touche le bord haut de
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
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
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
    if (!_shown) setState(() => _shown = true);
  }

  void _scheduleHide() {
    if (!_shown || _hideTimer != null) return;
    _hideTimer = Timer(CaptionBarPeek.lingerDelay, () {
      _hideTimer = null;
      if (mounted) setState(() => _shown = false);
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
                          child: const WindowCaptionBar(),
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

/// Les trois contrôles de fenêtre en pastilles façon macOS, gardés dans
/// l'ordre Windows : réduire, agrandir/restaurer, fermer tout à droite.
///
/// Comme sur macOS, les symboles n'apparaissent qu'au survol du groupe : au
/// repos, la barre ne montre que trois points de couleur.
class WindowControlPills extends StatefulWidget {
  final bool isMaximized;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  const WindowControlPills({
    super.key,
    required this.isMaximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  @override
  State<WindowControlPills> createState() => _WindowControlPillsState();
}

class _WindowControlPillsState extends State<WindowControlPills> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ControlPill(
              color: AppColors.warning,
              icon: Icons.remove_rounded,
              label: tr('Réduire'),
              showGlyph: _hovering,
              onPressed: widget.onMinimize,
            ),
            _ControlPill(
              color: AppColors.success,
              icon: widget.isMaximized
                  ? Icons.close_fullscreen_rounded
                  : Icons.add_rounded,
              label: widget.isMaximized ? tr('Restaurer') : tr('Agrandir'),
              showGlyph: _hovering,
              onPressed: widget.onToggleMaximize,
            ),
            _ControlPill(
              color: AppColors.error,
              icon: Icons.close_rounded,
              label: tr('Fermer'),
              showGlyph: _hovering,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlPill extends StatelessWidget {
  /// Diamètre de la pastille, celui des contrôles de macOS.
  static const double _diameter = 12;

  /// Largeur cliquable : la pastille plus 4 px de chaque côté, sur toute la
  /// hauteur de la barre, pour ne pas avoir à viser un disque de 12 px.
  static const double _hitWidth = 20;

  final Color color;
  final IconData icon;
  final String label;
  final bool showGlyph;
  final VoidCallback onPressed;

  const _ControlPill({
    required this.color,
    required this.icon,
    required this.label,
    required this.showGlyph,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Pas de `Tooltip` : la barre vit au-dessus du Navigator, donc sans
    // Overlay, et un Tooltip y lève « No Overlay widget found ».
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: _hitWidth,
          height: WindowCaptionBar.height,
          child: Center(
            child: Container(
              width: _diameter,
              height: _diameter,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AnimatedOpacity(
                opacity: showGlyph ? 1 : 0,
                duration: AppMotion.fade(context, AppMotion.micro),
                curve: AppMotion.curve,
                child: Icon(
                  icon,
                  size: 9,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
