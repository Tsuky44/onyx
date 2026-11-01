import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../desktop_window.dart';
import '../../l10n/tr.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../utils/app_platform.dart';

/// Floating back control for detail screens — sits below macOS traffic lights
/// or below the status bar / notch on mobile.
///
/// Un disque translucide, sans flou : posé sur l'image, il ne doit pas faire
/// une tache. Un fond noir à 50 % (puis du verre à 45 %) ressortait comme un
/// bouton collé sur le fond ; un voile clair à peine visible et un filet
/// suffisent, car le haut gauche des fiches est déjà assombri par le
/// dégradé du fond. La zone tactile fait [_hitSize], mais le disque, lui, ne
/// fait que [_discSize] : pour l'aligner sur la marge de la page, pose-le à
/// `pagePadding - discInset`.
class OverlayBackButton extends StatefulWidget {
  final VoidCallback? onPressed;

  const OverlayBackButton({super.key, this.onPressed});

  static const double _hitSize = 48;
  static const double _discSize = 36;

  /// Ce que la zone tactile garde autour du disque, de chaque côté.
  static const double discInset = (_hitSize - _discSize) / 2;

  static double get leadingWidth => _hitSize;

  static double toolbarHeightFor(BuildContext context) {
    final top = _topInset(context);
    return kToolbarHeight + top;
  }

  /// The window's own controls on macOS, or whatever the screen reserves at
  /// the top — the status bar, or the app's nav bar when the page opens
  /// under it (see `MainShell`). The larger wins: on macOS under the nav bar,
  /// the padding already includes the traffic lights.
  static double _topInset(BuildContext context) {
    final padding = MediaQuery.paddingOf(context).top;
    return AppPlatform.isMacOS
        ? math.max(macOSWindowControlsTopInset, padding)
        : padding;
  }

  static double get toolbarHeight =>
      kToolbarHeight + macOSWindowControlsTopInset;

  @override
  State<OverlayBackButton> createState() => _OverlayBackButtonState();
}

class _OverlayBackButtonState extends State<OverlayBackButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final topInset = OverlayBackButton._topInset(context);
    final lit = _hovered || _focused;

    return SizedBox(
      width: OverlayBackButton._hitSize,
      height: kToolbarHeight + topInset,
      child: Padding(
        padding: EdgeInsets.only(top: topInset),
        child: Align(
          alignment: Alignment.topLeft,
          child: Semantics(
            button: true,
            label: tr('Retour'),
            excludeSemantics: true,
            child: Tooltip(
              message: tr('Retour'),
              child: SizedBox(
                width: OverlayBackButton._hitSize,
                height: OverlayBackButton._hitSize,
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => setState(() => _pressed = true),
                    onTapCancel: () => setState(() => _pressed = false),
                    onTapUp: (_) => setState(() => _pressed = false),
                    onTap: widget.onPressed ??
                        () => Navigator.of(context).maybePop(),
                    child: FocusableActionDetector(
                      onShowHoverHighlight: (v) => setState(() => _hovered = v),
                      onShowFocusHighlight: (v) => setState(() => _focused = v),
                      mouseCursor: SystemMouseCursors.click,
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (_) {
                            (widget.onPressed ??
                                () => Navigator.of(context).maybePop())();
                            return null;
                          },
                        ),
                      },
                      child: AnimatedScale(
                        scale: _pressed ? 0.92 : 1,
                        duration: AppMotion.move(context, AppMotion.micro),
                        curve: AppMotion.curve,
                        child: SizedBox.square(
                          dimension: OverlayBackButton._discSize,
                          child: AnimatedContainer(
                            duration: AppMotion.fade(context, AppMotion.micro),
                            curve: AppMotion.curve,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white
                                  .withValues(alpha: lit ? 0.16 : 0.07),
                              border: Border.all(
                                color: _focused
                                    ? Colors.white
                                    : Colors.white
                                        .withValues(alpha: lit ? 0.22 : 0.10),
                                width: _focused ? 2 : 1,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                AppIcons.back,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
