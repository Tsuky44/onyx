import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_language.dart';
import '../../../l10n/tr.dart';
import '../../../models/models.dart';
import '../../../services/api_client.dart';
import 'integration_fields.dart';
import 'settings_ui.dart';

/// Les langues des métadonnées que TMDB sert et que l'app propose.
const List<(String, String)> kTmdbLanguages = [
  ('fr-FR', 'Français'),
  ('en-US', 'English'),
  ('es-ES', 'Español'),
  ('de-DE', 'Deutsch'),
  ('it-IT', 'Italiano'),
];

/// La langue TMDB qui correspond à la langue de l'app : celle qu'un serveur
/// neuf propose avant tout réglage.
String tmdbLanguageForApp() =>
    AppLanguage.current == AppLanguage.english ? 'en-US' : 'fr-FR';

/// Le formulaire de la clé TMDB : la clé, la langue des titres, **Tester** (le
/// serveur essaie la clé et dit si c'est la clé qu'il refuse ou TMDB qu'il ne
/// joint pas), Enregistrer et Effacer.
///
/// Partagé par la page Services des Paramètres et par l'étape TMDB de
/// l'assistant de première installation (ADR-0165) : une seule règle pour dire
/// ce qu'un échec veut dire.
class TmdbSettingsForm extends StatefulWidget {
  const TmdbSettingsForm({
    super.key,
    required this.settings,
    required this.onSaved,
    this.defaultLanguage,
    this.saveLabel,
  });

  final ServerSettings settings;

  /// Appelé avec les réglages que le serveur renvoie après un enregistrement
  /// ou un effacement.
  final ValueChanged<ServerSettings> onSaved;

  /// La langue proposée tant que le serveur n'a pas de clé : celle de l'app,
  /// pour un serveur neuf. Un serveur qui a déjà une clé garde la sienne.
  final String? defaultLanguage;

  /// Le texte du bouton d'enregistrement ; « Enregistrer » par défaut.
  final String? saveLabel;

  @override
  State<TmdbSettingsForm> createState() => _TmdbSettingsFormState();
}

class _TmdbSettingsFormState extends State<TmdbSettingsForm> {
  final _key = TextEditingController();
  late String _language = _initialLanguage();
  bool _saving = false;
  bool _testing = false;
  TmdbTest? _result;

  /// Vrai quand le serveur n'a pas su tester : un serveur d'avant le test.
  bool _testUnsupported = false;

  String _initialLanguage() {
    final saved = widget.settings.tmdbLanguage;
    final preferred = !widget.settings.tmdbApiKeySet
        ? widget.defaultLanguage ?? saved
        : saved;
    return kTmdbLanguages.any((l) => l.$1 == preferred) ? preferred : 'fr-FR';
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save({bool clearKey = false}) async {
    setState(() => _saving = true);
    final key = _key.text.trim();
    try {
      final updated = await context.read<ApiClient>().updateServerSettings(
            tmdbApiKey: key.isEmpty ? null : key,
            clearTmdbApiKey: clearKey,
            tmdbLanguage: _language,
          );
      if (!mounted) return;
      _key.clear();
      setState(() => _result = null);
      showSettingsSnack(
          context, clearKey ? tr('Clé TMDB effacée.') : tr('TMDB enregistré.'));
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

  /// La clé du champ, pas encore enregistrée, est celle qu'on teste ; champ
  /// vide, le serveur teste celle qu'il a.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final result =
          await context.read<ApiClient>().testTmdbKey(apiKey: _key.text.trim());
      if (!mounted) return;
      setState(() {
        _testUnsupported = result == null;
        _result = result;
      });
    } catch (e) {
      if (mounted) {
        showSettingsSnack(
            context, settingsErrorText(e, tr('Le test n’a pas pu se faire.')),
            error: true);
      }
    }
    if (mounted) setState(() => _testing = false);
  }

  /// Ce que chaque cause veut dire, en phrases : une clé refusée se corrige
  /// chez TMDB, un TMDB injoignable se corrige chez soi.
  String _resultText(TmdbTest result) => switch (result.reason) {
        TmdbTestReason.ok => tr('La clé est acceptée par TMDB.'),
        TmdbTestReason.invalidKey => tr('TMDB refuse cette clé. Copiez la clé '
            'API (v3), pas le jeton d’accès.'),
        TmdbTestReason.unreachable => tr('Le serveur n’arrive pas à joindre '
            'TMDB. La clé n’est pas en cause : vérifiez la connexion Internet '
            'du serveur.'),
        TmdbTestReason.noKey => tr('Collez d’abord une clé à tester.'),
        TmdbTestReason.unknown => result.message.isNotEmpty
            ? result.message
            : result.ok
                ? tr('La clé est acceptée par TMDB.')
                : tr('Le test a échoué.'),
      };

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntegrationKeyField(
          controller: _key,
          label: tr('Clé API TMDB'),
          configured: settings.tmdbApiKeySet,
          hint: settings.tmdbApiKeyHint,
        ),
        const SizedBox(height: 12),
        DropdownMenu<String>(
          initialSelection: _language,
          label: Text(tr('Langue des métadonnées')),
          leadingIcon: const Icon(Icons.translate_rounded),
          expandedInsets: EdgeInsets.zero,
          onSelected: (value) {
            if (value != null) setState(() => _language = value);
          },
          dropdownMenuEntries: [
            for (final (code, label) in kTmdbLanguages)
              DropdownMenuEntry(value: code, label: label),
          ],
        ),
        const SizedBox(height: 14),
        if (result != null)
          SettingsBanner(
            _resultText(result),
            tone: result.ok ? BannerTone.success : BannerTone.error,
          ),
        if (_testUnsupported)
          SettingsBanner(
            tr('Ce serveur est trop ancien pour tester la clé. Mettez-le à '
                'jour, ou enregistrez-la directement.'),
          ),
        IntegrationActions(
          saving: _saving || _testing,
          testing: _testing,
          onTest: _test,
          onSave: _save,
          saveLabel: widget.saveLabel,
          onClear:
              settings.tmdbApiKeySet ? () => _save(clearKey: true) : null,
        ),
      ],
    );
  }
}
