// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import '../../player/widgets/onyx/onyx_capsule_button.dart';
import '../../player/widgets/onyx/onyx_chrome_theme.dart';

/// La barre qui flotte au bas de la liste quand des titres sont cochés
/// (ADR-0160, ADR-0161) : combien, et ce qu'on peut en faire. Déplacer et
/// copier ne se proposent que s'il existe une autre liste où ranger.
///
/// Elle flotte plutôt que de remplacer les onglets : on garde sous les yeux
/// l'onglet où l'on choisit, et les actions restent à portée du pouce quand
/// la grille défile.
///
/// [onMove] et [onCopy] reçoivent le contexte de leur bouton : le choix de la
/// liste s'ouvre collé à lui.
class ListSelectionBar extends StatelessWidget {
  const ListSelectionBar({
    super.key,
    required this.count,
    required this.total,
    required this.canMoveOrCopy,
    required this.onClose,
    required this.onSelectAll,
    required this.onMove,
    required this.onCopy,
    required this.onRemove,
  });

  final int count;
  final int total;
  final bool canMoveOrCopy;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final ValueChanged<BuildContext> onMove;
  final ValueChanged<BuildContext> onCopy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final some = count > 0;
    final compact = AppLayout.isCompact(context);
    // Sur un téléphone, les libellés courts : la barre tient sur une ligne.
    final moveLabel = compact ? tr('Déplacer') : tr('Déplacer vers…');
    final copyLabel = compact ? tr('Copier') : tr('Copier vers…');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: OnyxChromeTheme.glassBorder),
        boxShadow: const [
          BoxShadow(
            color: OnyxChromeTheme.glassShadow,
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            IconButton(
              tooltip: tr('Terminer la sélection'),
              onPressed: onClose,
              icon: const Icon(AppIcons.close, size: 20),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                trPlural(
                    count, '{0} titre sélectionné', '{0} titres sélectionnés'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppType.callout,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (count < total)
              OnyxCapsuleButton(
                label: tr('Tout sélectionner'),
                onPressed: onSelectAll,
              ),
            if (canMoveOrCopy) ...[
              Builder(
                builder: (b) => OnyxCapsuleButton(
                  label: moveLabel,
                  icon: AppIcons.forward,
                  onPressed: some ? () => onMove(b) : null,
                ),
              ),
              Builder(
                builder: (b) => OnyxCapsuleButton(
                  label: copyLabel,
                  icon: AppIcons.copy,
                  onPressed: some ? () => onCopy(b) : null,
                ),
              ),
            ],
            _RemoveCapsule(onPressed: some ? onRemove : null),
          ],
        ),
      ),
    );
  }
}

/// « Retirer », en rouge sur rouge pâle : la seule action de la barre qui
/// enlève quelque chose (et qui se défait, ADR-0160 §6).
class _RemoveCapsule extends StatelessWidget {
  const _RemoveCapsule({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: AppColors.error.withValues(alpha: 0.16),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.delete, size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text(
                    tr('Retirer'),
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: AppType.callout,
                      fontWeight: FontWeight.w600,
                    ),
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
