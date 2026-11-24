// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/models.dart';
import '../../providers/setup_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_type.dart';
import '../../utils/external_url.dart';
import '../settings/widgets/settings_ui.dart';
import 'setup_launcher.dart';
import 'widgets/setup_finish_step.dart';
import 'widgets/setup_libraries_step.dart';
import 'widgets/setup_requests_step.dart';
import 'widgets/setup_tmdb_step.dart';

/// L'assistant de première installation (ADR-0165) : bibliothèques, clé TMDB,
/// service de demandes, puis un résumé. Un écran guidé, une barre de
/// progression, un bouton Précédent.
///
/// Chaque étape agit sur le serveur tout de suite (la bibliothèque créée
/// commence son analyse pendant qu'on règle TMDB) : quitter l'assistant ne perd
/// rien, et la checklist de l'accueil rouvre l'étape où l'on s'était arrêté.
class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({
    super.key,
    this.initialStep,
    this.openUrl = openExternalUrl,
  });

  /// L'étape où l'on s'ouvre ; la première pas encore faite par défaut.
  final SetupStep? initialStep;

  /// Ouvre une adresse dans le navigateur ; faux quand l'appareil n'en a pas.
  /// Une doublure de test remplace celui de l'app.
  final Future<bool> Function(String url) openUrl;

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  late SetupStep _step = widget.initialStep ?? _firstUndone();
  bool _finishing = false;

  SetupStep _firstUndone() {
    final state = context.read<SetupProvider>().state;
    if (state == null || !state.librariesDone) return SetupStep.libraries;
    if (!state.tmdbDone) return SetupStep.tmdb;
    if (!state.requestsDone) return SetupStep.requests;
    return SetupStep.finish;
  }

  void _go(SetupStep step) => setState(() => _step = step);

  void _next() {
    if (_step.index < SetupStep.values.length - 1) {
      _go(SetupStep.values[_step.index + 1]);
    }
  }

  void _previous() {
    if (_step.index > 0) _go(SetupStep.values[_step.index - 1]);
  }

  /// « Terminer » : l'installation est close pour tous les appareils, la
  /// checklist ne reparaît plus.
  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      await context.read<SetupProvider>().complete();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      showSettingsSnack(
          context, settingsErrorText(e, tr('Échec de l’enregistrement.')),
          error: true);
    }
  }

  /// Le texte du bouton principal : une étape pas faite se passe, une étape
  /// faite se continue.
  String _primaryLabel(SetupState? state) {
    final done = switch (_step) {
      SetupStep.libraries => state?.librariesDone ?? false,
      SetupStep.tmdb => state?.tmdbDone ?? false,
      SetupStep.requests => state?.requestsDone ?? false,
      SetupStep.finish => true,
    };
    if (_step == SetupStep.finish) return tr('Terminer');
    return done ? tr('Continuer') : tr('Passer');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SetupProvider>().state;
    final progress = (_step.index + 1) / SetupStep.values.length;
    final body = switch (_step) {
      SetupStep.libraries => const SetupLibrariesStep(),
      SetupStep.tmdb => SetupTmdbStep(openUrl: widget.openUrl),
      SetupStep.requests =>
        SetupRequestsStep(onConfigureTmdb: () => _go(SetupStep.tmdb)),
      SetupStep.finish => SetupFinishStep(onOpenStep: _go),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Installation du serveur')),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: tr('Fermer l’assistant'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColors.glassBorder,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Text(
                    tr('Étape {0} sur {1}',
                        [_step.index + 1, SetupStep.values.length]),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppType.footnote,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: body,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      if (_step.index > 0)
                        OutlinedButton(
                          onPressed: _finishing ? null : _previous,
                          child: Text(tr('Précédent')),
                        ),
                      const Spacer(),
                      FilledButton(
                        autofocus: true,
                        onPressed: _finishing
                            ? null
                            : _step == SetupStep.finish
                                ? _finish
                                : _next,
                        child: Text(_primaryLabel(state)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
