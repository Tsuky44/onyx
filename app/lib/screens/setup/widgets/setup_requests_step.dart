import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../providers/setup_provider.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../settings/widgets/request_service_form.dart';
import '../../settings/widgets/settings_ui.dart';

/// Étape 3 : le service de demandes, facultative. Le formulaire est celui des
/// Paramètres → Services ([RequestServiceForm], avec son bouton Tester et les
/// réserves du serveur). Il reste grisé tant que le serveur n'a pas de clé
/// TMDB : le serveur refuse (409) un service de demandes sans elle, et le
/// bouton ramène à l'étape TMDB (ADR-0165).
class SetupRequestsStep extends StatefulWidget {
  const SetupRequestsStep({super.key, required this.onConfigureTmdb});

  final VoidCallback onConfigureTmdb;

  @override
  State<SetupRequestsStep> createState() => _SetupRequestsStepState();
}

class _SetupRequestsStepState extends State<SetupRequestsStep> {
  ServerSettings? _settings;
  bool _canChooseService = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final settings = await api.getServerSettings();
      var canChoose = false;
      try {
        canChoose = await api.supportsRequestServices();
      } catch (error) {
        // Sans réponse, le choix reste caché : MediaHub, comme avant.
        debugPrint('SetupRequestsStep: choix du service inconnu ($error)');
      }
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _canChooseService = canChoose;
      });
      // L'état de l'installation se relit : TMDB a pu changer à l'étape
      // d'avant, et c'est lui qui décide du verrou.
      await context.read<SetupProvider>().load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = settingsErrorText(
          e, tr('Impossible de charger les paramètres serveur.')));
    }
  }

  Future<void> _saved(ServerSettings updated) async {
    setState(() => _settings = updated);
    await context.read<SetupProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final state = context.watch<SetupProvider>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Les demandes'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          tr('Facultatif. Un service de demandes permet à vos utilisateurs de '
              'demander un film ou une série qui n’est pas encore sur le '
              'serveur : MediaHub, Overseerr ou Jellyseerr le télécharge. '
              'Vous pourrez le brancher plus tard dans Paramètres → '
              'Services.'),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.subhead,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
        if (settings == null && _error == null) const SettingsLoading(),
        if (settings != null)
          RequestServiceForm(
            settings: settings,
            canChooseService: _canChooseService,
            // Un état inconnu ne verrouille pas : le serveur refusera, avec sa
            // raison, ce qu'il ne peut pas enregistrer.
            locked: state != null && !state.requestsAvailable,
            onConfigureTmdb: widget.onConfigureTmdb,
            onSaved: _saved,
          ),
      ],
    );
  }
}
