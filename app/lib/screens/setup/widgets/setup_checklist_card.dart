import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../setup_launcher.dart';

/// La checklist de l'accueil : ce qu'il reste à régler après l'assistant
/// (« Finir l'installation : 2/3 »). Chaque ligne rouvre l'étape ; « Ignorer »
/// ferme l'installation pour de bon (ADR-0165).
///
/// Elle ne parle pas au serveur : l'appelant lui donne l'état, et reçoit les
/// deux gestes.
class SetupChecklistCard extends StatelessWidget {
  const SetupChecklistCard({
    super.key,
    required this.state,
    required this.onOpenStep,
    required this.onDismiss,
  });

  final SetupState state;
  final ValueChanged<SetupStep> onOpenStep;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Finir l’installation : {0}/{1}',
                        [state.doneSteps, state.totalSteps]),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(tr('Ignorer')),
                ),
              ],
            ),
          ),
          _Row(
            done: state.librariesDone,
            title: tr('Ajouter vos bibliothèques'),
            subtitle: state.librariesDone
                ? trPlural(state.libraryCount, '{0} bibliothèque',
                    '{0} bibliothèques')
                : tr('Un dossier de films ou de séries de votre serveur.'),
            onTap: () => onOpenStep(SetupStep.libraries),
          ),
          _Row(
            done: state.tmdbDone,
            title: tr('Ajouter la clé TMDB'),
            subtitle: state.tmdbDone
                ? tr('Affiches et résumés activés.')
                : tr('Sans clé, pas d’affiches ni de métadonnées.'),
            onTap: () => onOpenStep(SetupStep.tmdb),
          ),
          _Row(
            done: state.requestsDone,
            title: tr('Brancher un service de demandes'),
            subtitle: state.requestsDone
                ? tr('Les demandes sont transmises.')
                : state.requestsAvailable
                    ? tr('Facultatif : MediaHub, Overseerr ou Jellyseerr.')
                    : tr('Facultatif. Configurez d’abord TMDB.'),
            onTap: () => onOpenStep(SetupStep.requests),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.done,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool done;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: done ? AppColors.success : AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: AppType.subhead,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.footnote,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
