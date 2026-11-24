// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';

/// Les deux sortes de lignes de la feuille des filtres des demandes.

/// Une ligne de l'index : l'icône et le nom du filtre, sa valeur en dessous
/// (« Tous », « Action, Drame »…) et un chevron vers le détail. La valeur
/// passe en blanc dès que le filtre est posé.
class RequestFilterIndexRow extends StatelessWidget {
  const RequestFilterIndexRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: AppLayout.minTouchTarget(context) + 16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.subhead,
                        color: active
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
              const Icon(AppIcons.chevronRight,
                  size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne de choix dans le détail d'un filtre, cochée ou non. Le même
/// dessin sert au choix simple (tri, langue) et au choix multiple (genres,
/// services).
class RequestFilterOptionRow extends StatelessWidget {
  const RequestFilterOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Ce qui précède le libellé : le logo d'un service de streaming.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: AppLayout.minTouchTarget(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.body,
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected)
                const Icon(AppIcons.check,
                    size: 20, color: AppColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
