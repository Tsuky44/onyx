import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../widgets/integration_fields.dart';
import '../widgets/request_service_form.dart';
import '../widgets/settings_ui.dart';
import '../widgets/tmdb_settings_form.dart';
import '../../../l10n/tr.dart';

/// TMDB (métadonnées, affiches, catalogue de demandes), Fanart.tv (affiches
/// en plus, ADR-0068) et le service de demandes : MediaHub (ADR-0089 ; un
/// OnyxHub à la même adresse est reconnu par le serveur), Overseerr ou
/// Jellyseerr (ADR-0136). Les clés ne sont jamais renvoyées en clair par le
/// serveur.
///
/// Les formulaires de TMDB et du service de demandes sont ceux de l'assistant
/// de première installation (ADR-0165). Le service de demandes reste grisé
/// tant que le serveur n'a pas de clé TMDB : il refuserait de l'enregistrer. Le
/// groupe TMDB est juste au-dessus : le verrou n'a pas de bouton de retour,
/// que la télécommande n'aurait pas besoin de défiler à la main (un seul
/// défilement par pas de focus, ADR-0110).
class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  final _fanartKey = TextEditingController();

  ServerSettings? _settings;

  /// Faux pour un serveur d'avant le choix : il ne connaît que MediaHub.
  bool _canChooseService = false;

  /// Ce que le serveur dit de l'installation ; null pour un serveur d'avant
  /// l'assistant, qui ne verrouille rien (comportement d'avant).
  SetupState? _guide;
  String? _error;
  bool _savingFanart = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fanartKey.dispose();
    super.dispose();
  }

  void _apply(ServerSettings settings) {
    _settings = settings;
    _fanartKey.clear();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final settings = await api.getServerSettings();
      var canChoose = false;
      try {
        canChoose = await api.supportsRequestServices();
      } catch (error) {
        // Sans réponse, le choix reste caché : l'écran règle MediaHub comme
        // avant, ce que tout serveur sait faire.
        debugPrint('IntegrationsPage: choix du service inconnu ($error)');
      }
      final guide = await _readGuide(api);
      if (!mounted) return;
      setState(() {
        _apply(settings);
        _canChooseService = canChoose;
        _guide = guide;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = settingsErrorText(
          e, tr('Impossible de charger les paramètres serveur.')));
    }
  }

  Future<SetupState?> _readGuide(ApiClient api) async {
    try {
      return await api.getSetupGuide();
    } catch (error) {
      // Sans réponse, rien n'est verrouillé : c'est le serveur qui refusera
      // (409) un service de demandes sans TMDB, avec sa raison.
      debugPrint('IntegrationsPage: état de l’installation inconnu ($error)');
      return null;
    }
  }

  /// TMDB vient d'être enregistré ou effacé : le verrou du service de demandes
  /// suit ce que le serveur en dit.
  Future<void> _tmdbSaved(ServerSettings updated) async {
    final guide = await _readGuide(context.read<ApiClient>());
    if (!mounted) return;
    setState(() {
      _apply(updated);
      _guide = guide;
    });
  }

  Future<void> _saveFanart({bool clearKey = false}) async {
    setState(() => _savingFanart = true);
    final key = _fanartKey.text.trim();
    try {
      final updated = await context.read<ApiClient>().updateServerSettings(
            fanartApiKey: key.isEmpty ? null : key,
            clearFanartApiKey: clearKey,
          );
      if (!mounted) return;
      setState(() => _apply(updated));
      showSettingsSnack(
          context,
          clearKey
              ? tr('Clé Fanart.tv effacée.')
              : tr('Fanart.tv enregistré.'));
    } catch (e) {
      if (mounted) {
        showSettingsSnack(
            context, settingsErrorText(e, tr('Échec de l’enregistrement.')),
            error: true);
      }
    }
    if (mounted) setState(() => _savingFanart = false);
  }

  Widget _status(bool configured) => SettingsPill(
        configured ? tr('Configuré') : tr('Non configuré'),
        color: configured ? AppColors.success : AppColors.warning,
        icon: configured ? Icons.check_rounded : Icons.error_outline_rounded,
      );

  @override
  Widget build(BuildContext context) {
    final settings = _settings;

    return SettingsPage(
      title: tr('Services'),
      description:
          tr('Les services extérieurs auxquels le serveur se connecte : ceux '
              'qui donnent au catalogue ses affiches et ses résumés, et celui '
              'qui reçoit les demandes de médias.'),
      children: [
        if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
        if (settings == null && _error == null) const SettingsLoading(),
        if (settings != null) ...[
          SettingsGroup(
            title: tr('The Movie Database (TMDB)'),
            trailing: _status(settings.tmdbApiKeySet),
            footer: tr('Sert à identifier les fichiers, récupérer affiches, '
                'résumés et distribution, et alimenter le catalogue des '
                'demandes.'),
            padded: true,
            children: [
              TmdbSettingsForm(settings: settings, onSaved: _tmdbSaved),
            ],
          ),
          SettingsGroup(
            title: tr('Fanart.tv'),
            trailing: _status(settings.fanartApiKeySet),
            footer: tr('Facultatif. Ajoute les affiches de Fanart.tv à celles '
                'de TMDB quand on change l’affiche d’un film ou d’une série. '
                'Clé personnelle gratuite sur fanart.tv.'),
            padded: true,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IntegrationKeyField(
                    controller: _fanartKey,
                    label: tr('Clé API Fanart.tv'),
                    configured: settings.fanartApiKeySet,
                    hint: settings.fanartApiKeyHint,
                  ),
                  const SizedBox(height: 14),
                  IntegrationActions(
                    saving: _savingFanart,
                    onSave: () => _saveFanart(),
                    onClear: settings.fanartApiKeySet
                        ? () => _saveFanart(clearKey: true)
                        : null,
                  ),
                ],
              ),
            ],
          ),
          SettingsGroup(
            title: tr('Service de demandes'),
            trailing: _status(
                settings.mediaHubUrl.isNotEmpty && settings.mediaHubApiKeySet),
            // Une seule rangée pour le groupe : le choix et son formulaire
            // vont ensemble, sans le filet qui sépare deux réglages.
            children: [
              RequestServiceForm(
                settings: settings,
                canChooseService: _canChooseService,
                locked: _guide != null && !_guide!.requestsAvailable,
                onSaved: (updated) => setState(() => _apply(updated)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
