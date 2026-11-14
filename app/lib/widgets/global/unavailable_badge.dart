import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';

/// La pastille de verre d'un titre que le serveur n'a pas, posée sur son
/// affiche voilée (`AppColors.unavailableTint`) : le signe commun à toutes les
/// listes qui mêlent la bibliothèque et le reste du catalogue (titres
/// similaires, filmographies, recherche, ADR-0129).
///
/// Elle dit « Indispo » tant que personne n'a demandé le titre, et « Demandé »,
/// du jaune des demandes en cours, quand il est déjà en route : on ne le
/// redemande pas, on sait qu'il arrive.
class UnavailableBadge extends StatelessWidget {
  const UnavailableBadge({super.key, this.requested = false});

  /// Vrai quand une demande court déjà pour ce titre.
  final bool requested;

  /// Le texte de la pastille, que l'écran de recherche du système de l'Apple
  /// TV dessine lui-même (`TvSystemSearch`).
  static String labelFor({required bool requested}) =>
      requested ? tr('Demandé') : tr('Indispo');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        labelFor(requested: requested),
        style: TextStyle(
          fontSize: AppType.micro,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: requested
              ? AppColors.warning
              : Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
