import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../providers/setup_provider.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../utils/on_screen.dart';
import '../../settings/widgets/settings_ui.dart';
import '../setup_launcher.dart';

/// Étape 4 : ce qui est configuré, et où en est l'analyse des bibliothèques.
/// Une ligne non faite renvoie à son étape ; « Terminer » clôt l'installation
/// (ADR-0165).
class SetupFinishStep extends StatefulWidget {
  const SetupFinishStep({
    super.key,
    required this.onOpenStep,
    this.pollEvery = const Duration(seconds: 3),
  });

  final ValueChanged<SetupStep> onOpenStep;

  /// Le rythme du sondage de l'analyse ; une doublure de test l'allonge.
  final Duration pollEvery;

  @override
  State<SetupFinishStep> createState() => _SetupFinishStepState();
}

class _SetupFinishStepState extends State<SetupFinishStep>
    with OnScreenState<SetupFinishStep> {
  Timer? _poll;

  /// Null tant que le serveur n'a pas répondu, ou s'il ne sait pas le dire.
  bool? _scanning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SetupProvider>().load();
    });
  }

  /// Le sondage ne tourne que tant que l'étape est vue : page recouverte ou
  /// fenêtre cachée, il s'arrête.
  @override
  void didChangeOnScreen(bool onScreen) {
    _poll?.cancel();
    _poll = null;
    if (!onScreen) return;
    _readScan();
    _poll = Timer.periodic(widget.pollEvery, (_) => _readScan());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _readScan() async {
    try {
      final scanning = await context.read<ApiClient>().getScanStatus();
      if (mounted) setState(() => _scanning = scanning);
    } catch (e) {
      // L'analyse est un confort de cet écran : sans réponse on n'affiche pas
      // de progression plutôt qu'une erreur au moment de finir.
      debugPrint('SetupFinishStep: état de l’analyse indisponible: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SetupProvider>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('C’est presque fini'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          tr('Voici ce qui est réglé. Ce qui ne l’est pas reste dans la '
              'checklist de l’accueil, et se change à tout moment dans les '
              'Paramètres.'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.subhead,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        if (state != null)
          SettingsGroup(
            dividerIndent: 64,
            children: [
              _SummaryTile(
                done: state.librariesDone,
                title: tr('Bibliothèques'),
                subtitle: state.librariesDone
                    ? trPlural(state.libraryCount, '{0} bibliothèque',
                        '{0} bibliothèques')
                    : tr('Aucune pour l’instant'),
                onTap: () => widget.onOpenStep(SetupStep.libraries),
              ),
              _SummaryTile(
                done: state.tmdbDone,
                title: tr('Clé TMDB'),
                subtitle: state.tmdbDone
                    ? tr('Affiches et résumés activés')
                    : tr('Ignorée : pas d’affiches ni de métadonnées'),
                onTap: () => widget.onOpenStep(SetupStep.tmdb),
              ),
              _SummaryTile(
                done: state.requestsDone,
                title: tr('Service de demandes'),
                subtitle: state.requestsDone
                    ? tr('Branché')
                    : tr('Non branché (facultatif)'),
                onTap: () => widget.onOpenStep(SetupStep.requests),
              ),
            ],
          ),
        if (_scanning == true) ...[
          const SizedBox(height: 4),
          Text(
            tr('Analyse de vos bibliothèques en cours…'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.subhead,
            ),
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (_scanning == false && (state?.librariesDone ?? false))
          SettingsBanner(
            tr('L’analyse est terminée : vos titres sont dans le catalogue.'),
            tone: BannerTone.success,
          ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
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
    return SettingsTile(
      icon: done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
      iconColor: done ? AppColors.success : AppColors.textMuted,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}
