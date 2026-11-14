import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';

/// L'annonce d'un geste venu d'un autre appareil — « Alex a mis en pause ».
///
/// Visible même quand les commandes sont masquées : c'est précisément quand on
/// ne touche à rien qu'il faut savoir pourquoi le film s'est arrêté.
class WatchPartyToast extends StatelessWidget {
  const WatchPartyToast(
      {super.key, required this.message, required this.visible});

  final String? message;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible && message != null ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_rounded,
                  size: 16, color: AppColors.accentMuted),
              const SizedBox(width: 8),
              Text(
                message ?? '',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppType.subhead,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
