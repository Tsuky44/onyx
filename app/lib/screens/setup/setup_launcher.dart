// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/setup_provider.dart';
import 'setup_wizard_screen.dart';

/// Les étapes de l'assistant de première installation (ADR-0165), dans l'ordre.
enum SetupStep { libraries, tmdb, requests, finish }

/// Ouvre l'assistant, à [step] ou à la première étape pas encore faite.
Future<void> openSetupWizard(BuildContext context, {SetupStep? step}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SetupWizardScreen(initialStep: step),
    ),
  );
}

/// Dit si l'assistant doit s'ouvrir tout seul : une fois par appareil et par
/// serveur, pour le compte qui administre ([manageSettings]) un serveur dont
/// l'installation n'est pas finie.
///
/// Le serveur est consulté d'abord : un serveur plus ancien (404) ne laisse
/// aucun état, donc rien ne s'ouvre. La réponse « oui » marque l'appareil : quitté
/// en cours de route, l'assistant ne revient pas de lui-même, la checklist de
/// l'accueil prend le relais et chaque ligne y rouvre l'étape.
Future<bool> shouldOpenSetupWizard(
  SetupProvider setup, {
  required bool manageSettings,
}) async {
  if (!manageSettings) return false;
  await setup.load();
  if (!setup.needsSetup) return false;
  if (!await setup.wizardNotOfferedYet()) return false;
  await setup.markWizardOffered();
  return true;
}

/// Ouvre l'assistant tout seul quand [shouldOpenSetupWizard] le décide.
Future<void> maybeOpenSetupWizard(BuildContext context) async {
  final auth = context.read<AuthProvider?>();
  final setup = context.read<SetupProvider?>();
  if (auth == null || setup == null) return;
  final open = await shouldOpenSetupWizard(setup,
      manageSettings: auth.permissions.manageSettings);
  if (!open || !context.mounted) return;
  await openSetupWizard(context);
}
