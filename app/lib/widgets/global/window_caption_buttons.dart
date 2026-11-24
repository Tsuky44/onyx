import 'package:flutter/foundation.dart' show ValueListenable;
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../utils/window_controls.dart';
import 'glass_chrome.dart';

/// Réduire, agrandir ou restaurer, fermer : les contrôles de la fenêtre
/// Windows, dans l'ordre et au dessin de Windows 11 (traits d'un pixel), mais
/// à la forme des boutons de l'en-tête de verre (ADR-0157).
///
/// Au repos, rien que les symboles posés sur le verre. Au survol, le voile et
/// l'arrondi du champ Rechercher ; Fermer, lui, rougit comme partout sous
/// Windows. Fenêtre au second plan, les symboles s'éteignent.
///
/// Pas de `Tooltip` : la bande du haut ([WindowCaptionBar]) les monte
/// au-dessus du Navigator, donc sans Overlay, où un Tooltip lève « No Overlay
/// widget found ».
class WindowCaptionButtons extends StatelessWidget {
  /// La hauteur des boutons : par défaut celle du champ Rechercher, pour
  /// qu'ils s'alignent sur la rangée de l'en-tête.
  final double? height;

  /// Les doublures des tests. Nuls, la vraie fenêtre ([WindowControls]).
  final ValueListenable<WindowFrameState>? state;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onClose;

  const WindowCaptionButtons({
    super.key,
    this.height,
    this.state,
    this.onMinimize,
    this.onToggleMaximize,
    this.onClose,
  });

  /// Largeur d'un bouton : un peu plus que haut, comme ceux de Windows,
  /// sans leurs 46 px qui alourdissaient la rangée.
  static const double buttonWidth = 40;

  static void _toggleMaximize(bool maximized) {
    if (maximized) {
      WindowControls.unmaximize();
    } else {
      WindowControls.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = height ?? GlassSearchInput.heightFor(large: false);
    return ValueListenableBuilder<WindowFrameState>(
      valueListenable: state ?? WindowControls.frameState,
      builder: (context, frame, _) {
        final dimmed = !frame.focused;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CaptionButton(
              glyph: _Glyph.minimize,
              label: tr('Réduire'),
              height: h,
              dimmed: dimmed,
              onPressed: onMinimize ?? WindowControls.minimize,
            ),
            const SizedBox(width: 2),
            _CaptionButton(
              glyph: frame.maximized ? _Glyph.restore : _Glyph.maximize,
              label: frame.maximized ? tr('Restaurer') : tr('Agrandir'),
              height: h,
              dimmed: dimmed,
              onPressed: onToggleMaximize ??
                  () => _toggleMaximize(frame.maximized),
            ),
            const SizedBox(width: 2),
            _CaptionButton(
              glyph: _Glyph.close,
              label: tr('Fermer'),
              height: h,
              dimmed: dimmed,
              onPressed: onClose ?? WindowControls.close,
            ),
          ],
        );
      },
    );
  }
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  final _Glyph glyph;
  final String label;
  final double height;
  final bool dimmed;
  final VoidCallback onPressed;

  const _CaptionButton({
    required this.glyph,
    required this.label,
    required this.height,
    required this.dimmed,
    required this.onPressed,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _isClose => widget.glyph == _Glyph.close;

  Color get _fill {
    if (_isClose && (_hovered || _pressed)) {
      return _pressed
          ? AppColors.windowClose.withValues(alpha: 0.85)
          : AppColors.windowClose;
    }
    // Les voiles du champ Rechercher (`GlassSearchInput`) : 10 % au survol,
    // un peu moins sous le doigt, comme un bouton qu'on enfonce.
    if (_pressed) return Colors.white.withValues(alpha: 0.06);
    if (_hovered) return Colors.white.withValues(alpha: 0.1);
    return Colors.transparent;
  }

  Color get _ink {
    if (_isClose && (_hovered || _pressed)) return Colors.white;
    return widget.dimmed ? AppColors.textMuted : AppColors.textPrimary;
  }

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: AppMotion.fade(context, AppMotion.micro),
            curve: AppMotion.curve,
            width: WindowCaptionButtons.buttonWidth,
            height: widget.height,
            decoration: BoxDecoration(
              color: _fill,
              borderRadius: BorderRadius.circular(widget.height / 2),
            ),
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size.square(_GlyphPainter.extent),
              painter: _GlyphPainter(widget.glyph, _ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Les symboles de Windows 11, tracés et non pris dans une police d'icônes :
/// celles de Material ont des traits de 2 px et des bouts arrondis qui ne
/// ressemblent à aucune fenêtre de Windows.
class _GlyphPainter extends CustomPainter {
  static const double extent = 10;

  final _Glyph glyph;
  final Color color;

  const _GlyphPainter(this.glyph, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const corner = Radius.circular(1.5);
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(const Offset(0, 5.5), const Offset(10, 5.5), paint);
      case _Glyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(0.5, 0.5, 9, 9), corner),
          paint,
        );
      case _Glyph.restore:
        // La fenêtre de devant, et le coin de celle de derrière qui dépasse.
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(0.5, 2.5, 7, 7), corner),
          paint,
        );
        final back = Path()
          ..moveTo(2.5, 2.5)
          ..lineTo(2.5, 2)
          ..arcToPoint(const Offset(4, 0.5), radius: corner)
          ..lineTo(8, 0.5)
          ..arcToPoint(const Offset(9.5, 2), radius: corner)
          ..lineTo(9.5, 6)
          ..arcToPoint(const Offset(8, 7.5), radius: corner)
          ..lineTo(7.5, 7.5);
        canvas.drawPath(back, paint);
      case _Glyph.close:
        canvas.drawLine(const Offset(0.5, 0.5), const Offset(9.5, 9.5), paint);
        canvas.drawLine(const Offset(9.5, 0.5), const Offset(0.5, 9.5), paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
