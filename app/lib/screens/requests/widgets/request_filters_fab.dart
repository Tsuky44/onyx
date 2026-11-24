import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';

/// Le bouton des filtres qui flotte en bas à droite de la grille des
/// demandes et reste à l'écran pendant le défilement : on ouvre les filtres
/// à tout moment, sans remonter. Volontairement discret (un rond sombre,
/// l'icône seule) pour ne pas couvrir les affiches ; une pastille blanche
/// porte le compte des filtres posés. Voir ADR-0132.
class RequestFiltersFab extends StatelessWidget {
  const RequestFiltersFab({
    super.key,
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final label = activeCount > 0
        ? tr('Filtres · {0}', [activeCount])
        : tr('Filtres');
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: AppColors.surfaceElevated.withValues(alpha: 0.92),
                shape: CircleBorder(
                  side: BorderSide(color: AppColors.glassBorder),
                ),
                child: InkWell(
                  onTap: onPressed,
                  customBorder: const CircleBorder(),
                  child: const SizedBox.square(
                    dimension: size,
                    child: Icon(AppIcons.filters,
                        size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ),
              if (activeCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: IgnorePointer(
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: AppColors.background, width: 1.5),
                      ),
                      child: Text(
                        '$activeCount',
                        style: const TextStyle(
                          color: AppColors.background,
                          fontSize: AppType.micro,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
