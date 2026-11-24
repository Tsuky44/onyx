import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../widgets/global/glass_chrome.dart';
import '../../widgets/global/interface_tour/tour_anchor.dart';

/// Une page rangée derrière l'onglet « Plus » de la capsule du téléphone
/// (ADR-0146) : Listes, Hors ligne.
class PhoneMoreItem {
  const PhoneMoreItem({
    required this.tab,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.anchor,
  });

  /// L'identifiant de l'onglet (voir `ShellTabs`).
  final String tab;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// L'ancre de la visite guidée que l'onglet « Plus » porte pour elle.
  final TourAnchor? anchor;
}

/// Ouvre le menu de l'onglet « Plus » au-dessus de la capsule, aligné sur son
/// bord droit ([capsule]). La page s'assombrit un peu, sauf la capsule et le
/// rond de la recherche ([clear]), qui restent nets. Rend l'onglet choisi, ou
/// null si le menu a été refermé (toucher à côté, Retour).
Future<String?> showPhoneMoreMenu(
  BuildContext context, {
  required Rect capsule,
  required List<Rect> clear,
  required List<PhoneMoreItem> items,
  required String? selected,
}) {
  final duration =
      AppMotion.reduced(context) ? Duration.zero : AppMotion.standard;
  return Navigator.of(context, rootNavigator: true).push<String>(
    _PhoneMoreRoute(
      capsule: capsule,
      clear: clear,
      items: items,
      selected: selected,
      duration: duration,
      label: tr('Fermer'),
    ),
  );
}

class _PhoneMoreRoute extends PopupRoute<String> {
  _PhoneMoreRoute({
    required this.capsule,
    required this.clear,
    required this.items,
    required this.selected,
    required this.duration,
    required this.label,
  });

  final Rect capsule;
  final List<Rect> clear;
  final List<PhoneMoreItem> items;
  final String? selected;
  final Duration duration;
  final String label;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final size = MediaQuery.sizeOf(context);
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    return Stack(
      children: [
        // Le voile, peint et non posé : il épargne la capsule et la
        // recherche. Les touchers passent au travers jusqu'à la barrière, qui
        // referme le menu.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, _) => CustomPaint(
                painter: _ScrimPainter(clear: clear, opacity: curved.value),
              ),
            ),
          ),
        ),
        Positioned(
          right: size.width - capsule.right,
          bottom: size.height - capsule.top + 10,
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(curved),
              alignment: Alignment.bottomRight,
              child: PhoneMoreMenu(
                items: items,
                selected: selected,
                onPicked: (tab) => Navigator.of(context).pop(tab),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.clear, required this.opacity});

  final List<Rect> clear;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path()..addRect(Offset.zero & size);
    for (final rect in clear) {
      final hole = Path()
        ..addRRect(RRect.fromRectAndRadius(
            rect, Radius.circular(rect.shortestSide / 2)));
      path = Path.combine(PathOperation.difference, path, hole);
    }
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.28 * opacity),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.opacity != opacity || old.clear != clear;
}

/// Le menu de verre de l'onglet « Plus » : une rangée par page.
class PhoneMoreMenu extends StatelessWidget {
  const PhoneMoreMenu({
    super.key,
    required this.items,
    required this.selected,
    required this.onPicked,
  });

  final List<PhoneMoreItem> items;
  final String? selected;
  final ValueChanged<String> onPicked;

  static const double width = 214;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(24));

  @override
  Widget build(BuildContext context) {
    final blurs = glassBlurs(context);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        // Plus dense que la capsule : le menu porte du texte, posé sur
        // l'affiche.
        color: blurs ? null : const Color(0xF22A2A2E),
        gradient: blurs
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xA840404A), Color(0xA826262A)],
              )
            : null,
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, item) in items.indexed) ...[
              if (index > 0) const SizedBox(height: 2),
              _MenuRow(
                item: item,
                current: item.tab == selected,
                onTap: () => onPicked(item.tab),
              ),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _radius,
            child: blurs
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.current,
    required this.onTap,
  });

  final PhoneMoreItem item;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: current,
      label: item.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    current ? item.selectedIcon : item.icon,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: AppType.callout,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (current)
                    const Icon(
                      AppIcons.check,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
