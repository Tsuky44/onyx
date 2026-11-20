import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/request_service.dart';
import '../../../providers/media_requests_provider.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_deferred_keyboard.dart';
import 'integration_fields.dart';
import 'settings_ui.dart';

/// Le formulaire du service de demandes : MediaHub (ADR-0089), Overseerr ou
/// Jellyseerr (ADR-0136). Le choix du service, son adresse, sa clé, **Tester**
/// (avec les réserves du serveur), Enregistrer et Effacer.
///
/// Sorti de la page Services pour que l'étape « Demandes » de l'assistant de
/// première installation emploie le même code (ADR-0165).
///
/// [locked] grise le formulaire : le serveur refuse (409) un service de
/// demandes tant qu'il n'a pas de clé TMDB, qui lui sert à chercher les
/// titres. [onConfigureTmdb] est alors le bouton qui y ramène.
class RequestServiceForm extends StatefulWidget {
  const RequestServiceForm({
    super.key,
    required this.settings,
    required this.canChooseService,
    required this.onSaved,
    this.locked = false,
    this.onConfigureTmdb,
  });

  final ServerSettings settings;

  /// Faux pour un serveur d'avant le choix : il ne connaît que MediaHub, et
  /// refuserait un réglage qu'il ne lit pas.
  final bool canChooseService;
  final ValueChanged<ServerSettings> onSaved;
  final bool locked;
  final VoidCallback? onConfigureTmdb;

  @override
  State<RequestServiceForm> createState() => _RequestServiceFormState();
}

class _RequestServiceFormState extends State<RequestServiceForm> {
  final _url = TextEditingController();
  final _key = TextEditingController();

  /// Le service choisi dans le formulaire, enregistré ou non.
  late RequestService _service = widget.settings.requestService;
  bool _saving = false;
  bool _testing = false;

  /// Les réserves du dernier test de liaison réussi (compte absent du
  /// service, notifications de MediaHub sans adresse).
  List<String> _linkNotes = const [];

  @override
  void initState() {
    super.initState();
    _url.text = widget.settings.mediaHubUrl;
  }

  @override
  void didUpdateWidget(RequestServiceForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.settings, widget.settings)) {
      // Des réglages neufs (après un enregistrement) : le formulaire repart de
      // ce que le serveur a retenu, la clé saisie est partie avec lui.
      _url.text = widget.settings.mediaHubUrl;
      _service = widget.settings.requestService;
      _key.clear();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Le service du formulaire n'est plus celui des réglages : la clé
  /// enregistrée est celle de l'ancien.
  bool get _serviceChanged => _service != widget.settings.requestService;

  Future<void> _save({bool clearKey = false}) async {
    final key = _key.text.trim();
    final settings = widget.settings;
    if (!clearKey &&
        _serviceChanged &&
        settings.mediaHubApiKeySet &&
        key.isEmpty) {
      // Laisser vide garderait la clé de l'ancien service, que le nouveau
      // refuserait à la première demande.
      showSettingsSnack(
          context,
          tr('Collez la clé de {0} : celle de {1} ne lui sert pas.',
              [_service.label, settings.requestService.label]),
          error: true);
      return;
    }
    setState(() => _saving = true);
    final service = _service;
    try {
      final updated = await context.read<ApiClient>().updateServerSettings(
            mediaHubUrl: _url.text.trim(),
            mediaHubApiKey: key.isEmpty ? null : key,
            clearMediaHubApiKey: clearKey,
            // Effacer la clé n'enregistre pas un service à moitié choisi.
            requestService:
                widget.canChooseService && !clearKey ? service : null,
          );
      if (!mounted) return;
      setState(() => _linkNotes = const []);
      // L'onglet Demandes paraît ou disparaît avec le compagnon.
      unawaited(context.read<MediaRequestsProvider>().recheckCompanion());
      showSettingsSnack(
          context,
          clearKey
              ? tr('Clé effacée.')
              : tr('{0} enregistré.', [service.label]));
      widget.onSaved(updated);
    } catch (e) {
      if (mounted) {
        showSettingsSnack(
            context, settingsErrorText(e, tr('Échec de l’enregistrement.')),
            error: true);
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  /// Les valeurs du formulaire, pas encore enregistrées, sont celles qu'on
  /// teste : on vérifie avant d'enregistrer, pas après.
  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final result = await context.read<ApiClient>().testMediaHubLink(
            url: _url.text.trim(),
            apiKey: _key.text.trim(),
            service: widget.canChooseService ? _service : null,
          );
      if (!mounted) return;
      if (result == null) {
        showSettingsSnack(
            context,
            tr('Ce serveur est trop ancien pour cette fonction. Mettez-le à '
                'jour.'),
            error: true);
      } else {
        setState(() => _linkNotes = result.ok ? result.notes : const []);
        showSettingsSnack(context, result.message, error: !result.ok);
      }
    } catch (e) {
      if (mounted) {
        showSettingsSnack(
            context, settingsErrorText(e, tr('Le test n’a pas pu se faire.')),
            error: true);
      }
    }
    if (mounted) setState(() => _testing = false);
  }

  String _explanation(BuildContext context) => _service.isSeerr
      ? tr(
          'Les demandes faites depuis l’onglet Demander sont '
          'transmises à {0}, qui les confie à Radarr et Sonarr. La '
          'clé API se lit dans {0}, sous Paramètres → Général. Un '
          'compte Onyx y agit comme le compte du même nom ; sans '
          'homonyme, il passe par le compte de la clé.',
          [_service.label])
      : tr(
          'Les demandes faites depuis l’onglet Demander sont '
          'transmises à MediaHub pour être téléchargées. La clé est '
          'PLAYER_INTEGRATION_API_KEY de MediaHub. Pour que MediaHub '
          'prévienne Onyx des imports, réglez-y ONYX_WEBHOOK_URL sur '
          '{0}/api/integrations/mediahub/events.',
          [context.read<ApiClient>().baseUrl]);

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final locked = widget.locked;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canChooseService)
          SettingsChoiceTile<RequestService>(
            title: tr('Service'),
            subtitle: tr('Celui qui reçoit les demandes et les fait '
                'télécharger.'),
            value: _service,
            options: [
              for (final service in RequestService.values)
                (service, service.label),
            ],
            // Les réserves du dernier test parlaient de l'autre service.
            onChanged: (service) => setState(() {
              _service = service;
              _linkNotes = const [];
            }),
          ),
        Padding(
          // Le retrait de 16 de la rangée du choix, juste au-dessus.
          padding:
              EdgeInsets.fromLTRB(16, widget.canChooseService ? 2 : 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvDeferredKeyboard(
                builder: (context, focusNode, canRequestFocus) => TextField(
                  focusNode: focusNode,
                  canRequestFocus: canRequestFocus,
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: tr('Adresse de {0}', [_service.label]),
                    hintText: _service.urlExample,
                    prefixIcon: const Icon(Icons.link_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              IntegrationKeyField(
                controller: _key,
                label: _service.isSeerr
                    ? tr('Clé API {0}', [_service.label])
                    : tr('Clé d’intégration MediaHub'),
                // La clé enregistrée est celle du service des réglages : un
                // autre choisi, il n'y en a pas encore pour lui.
                configured: settings.mediaHubApiKeySet && !_serviceChanged,
                hint: settings.mediaHubApiKeyHint,
              ),
              const SizedBox(height: 14),
              for (final note in _linkNotes) ...[
                SettingsBanner(note),
                const SizedBox(height: 10),
              ],
              IntegrationActions(
                saving: _saving || _testing,
                onTest: _test,
                testing: _testing,
                onSave: _save,
                onClear: settings.mediaHubApiKeySet
                    ? () => _save(clearKey: true)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                _explanation(context),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppType.footnote,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!locked) return form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsBanner(
                tr('Configurez d’abord TMDB : le service de demandes en a '
                    'besoin pour chercher les films et les séries.'),
              ),
              if (widget.onConfigureTmdb != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: widget.onConfigureTmdb,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: Text(tr('Configurer TMDB')),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Grisé et hors du parcours : un formulaire qu'on ne peut pas remplir
        // ne doit pas prendre le focus de la télécommande.
        ExcludeFocus(
          child: IgnorePointer(child: Opacity(opacity: 0.4, child: form)),
        ),
      ],
    );
  }
}
