import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_focus.dart';

/// Qui peut voir une liste : elle seule et ses invités, ou tout le serveur
/// (ADR-0070, ADR-0161). Deux cartes côte à côte plutôt qu'un interrupteur :
/// les deux issues se lisent avant de choisir, et chacune dit ce qu'elle
/// donne.
///
/// Le panneau « Partager » et la création d'une liste la partagent.
class ListVisibilityChoice extends StatelessWidget {
  const ListVisibilityChoice({
    super.key,
    required this.shared,
    required this.onChanged,
    this.busy = false,
    this.autofocus = false,
  });

  final bool shared;

  /// Null : le choix se lit sans se changer.
  final ValueChanged<bool>? onChanged;

  /// Le serveur enregistre le choix précédent : les cartes attendent.
  final bool busy;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final onChanged = busy ? null : this.onChanged;
    return Semantics(
      container: true,
      label: tr('Qui peut la voir'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Card(
              icon: AppIcons.privateList,
              title: tr('Privée'),
              detail: tr('Vous et les personnes invitées.'),
              selected: !shared,
              autofocus: autofocus && !shared,
              onTap: onChanged == null ? null : () => onChanged(false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Card(
              icon: AppIcons.sharedList,
              title: tr('Tout le serveur'),
              detail: tr('Tous les comptes la voient, sans la modifier.'),
              selected: shared,
              autofocus: autofocus && shared,
              onTap: onChanged == null ? null : () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;
  final bool autofocus;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      child: TvFocusable(
        onSelect: onTap,
        enabled: onTap != null,
        autofocus: autofocus,
        focusScale: 1.0,
        borderRadius: _radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: onTap,
            borderRadius: _radius,
            child: AnimatedContainer(
              duration: AppMotion.fade(context, AppMotion.micro),
              curve: AppMotion.curve,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: _radius,
                color: selected
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03),
                border: Border.all(
                  color: selected ? AppColors.focus : AppColors.glassBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (selected)
                        Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.focus,
                          ),
                          child: const Icon(AppIcons.check,
                              size: 12, color: AppColors.background),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.footnote,
                      height: 1.4,
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
