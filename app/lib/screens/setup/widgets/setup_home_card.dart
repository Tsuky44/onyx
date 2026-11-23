// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../providers/setup_provider.dart';
import '../../settings/widgets/settings_ui.dart';
import '../setup_launcher.dart';
import 'setup_checklist_card.dart';

/// La checklist « Finir l'installation » telle que l'accueil la pose : visible
/// seulement pour qui administre le serveur ([canManage]) et tant que le
/// serveur dit que l'installation n'est pas finie (ADR-0165). Sans
/// [SetupProvider] ou sur un serveur plus ancien, elle n'existe pas.
class SetupHomeCard extends StatelessWidget {
  const SetupHomeCard({super.key, required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final setup = Provider.of<SetupProvider?>(context);
    final state = setup?.state;
    if (!canManage || setup == null || state == null || state.completed) {
      return const SizedBox.shrink();
    }
    return Center(
      child: SetupChecklistCard(
        state: state,
        onOpenStep: (step) => openSetupWizard(context, step: step),
        onDismiss: () async {
          try {
            await setup.complete();
          } catch (e) {
            if (context.mounted) {
              showSettingsSnack(context,
                  settingsErrorText(e, tr('Échec de l’enregistrement.')),
                  error: true);
            }
          }
        },
      ),
    );
  }
}
