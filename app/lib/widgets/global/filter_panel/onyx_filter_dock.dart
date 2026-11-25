import 'package:material_ui/material_ui.dart';

import '../../../theme/app_motion.dart';
import '../../../utils/responsive.dart';
import 'onyx_filter_panel.dart';

/// Pose le panneau des filtres ([panel], nul quand il est fermé) à droite
/// de [page], sur grand écran.
///
/// À partir de [AppBreakpoints.expanded], la page se resserre pour lui
/// faire place : la grille reste entièrement visible et cliquable à côté.
/// Plus étroite, la page n'aurait plus que deux ou trois affiches par
/// rangée : le panneau passe alors par-dessus, et un clic à côté appelle
/// [onDismiss]. Voir l'ADR du 2026-11-25.
class OnyxFilterDock extends StatelessWidget {
  const OnyxFilterDock({
    super.key,
    required this.page,
    required this.panel,
    required this.top,
    required this.onDismiss,
  });

  final Widget page;
  final Widget? panel;

  /// Le haut du panneau : sous la barre du shell (`shellTabTopInset`).
  final double top;
  final VoidCallback onDismiss;

  /// L'écart entre le panneau et les bords de la fenêtre.
  static const double margin = 12;

  /// Vrai quand une fenêtre de [width] garde la page à côté du panneau
  /// plutôt que dessous.
  static bool docksAt(double width) => width >= AppBreakpoints.expanded;

  @override
  Widget build(BuildContext context) {
    final panel = this.panel;
    final open = panel != null;
    final docked = docksAt(MediaQuery.sizeOf(context).width);
    return Stack(
      children: [
        AnimatedPadding(
          duration: AppMotion.move(context),
          curve: AppMotion.curve,
          padding: EdgeInsets.only(
              right: open && docked ? OnyxFilterPanel.width + margin : 0),
          child: page,
        ),
        if (open && !docked)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
            ),
          ),
        Positioned(
          top: top,
          right: margin,
          bottom: margin,
          width: OnyxFilterPanel.width,
          child: AnimatedSwitcher(
            duration: AppMotion.fade(context),
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.curve,
            transitionBuilder: (child, animation) {
              final faded = FadeTransition(opacity: animation, child: child);
              if (AppMotion.reduced(context)) return faded;
              return SlideTransition(
                position: Tween(begin: const Offset(0.06, 0), end: Offset.zero)
                    .animate(animation),
                child: faded,
              );
            },
            child: panel ?? const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
