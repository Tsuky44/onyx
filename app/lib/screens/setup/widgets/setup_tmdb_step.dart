import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../providers/setup_provider.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_type.dart';
import '../../../tv/tv_mode.dart';
import '../../settings/widgets/settings_ui.dart';
import '../../settings/widgets/tmdb_settings_form.dart';

/// La page où TMDB donne sa clé API.
const String kTmdbApiSettingsUrl = 'https://www.themoviedb.org/settings/api';

/// Étape 2 : la clé TMDB. À quoi elle sert, comment l'obtenir (compte gratuit,
/// clé API v3 et pas le jeton d'accès), un lien qui ouvre la page de TMDB, le
/// champ, **Tester** et Enregistrer (ADR-0165).
///
/// Sur un téléviseur, taper une clé à la télécommande est pénible et il n'y a
/// pas de navigateur : l'adresse est écrite en clair au lieu du bouton, et
/// l'étape se passe (la checklist de l'accueil la reprend, depuis un autre
/// appareil).
class SetupTmdbStep extends StatefulWidget {
  const SetupTmdbStep({super.key, required this.openUrl});

  final Future<bool> Function(String url) openUrl;

  @override
  State<SetupTmdbStep> createState() => _SetupTmdbStepState();
}

class _SetupTmdbStepState extends State<SetupTmdbStep> {
  ServerSettings? _settings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await context.read<ApiClient>().getServerSettings();
      if (mounted) setState(() => _settings = settings);
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

  /// Sans navigateur (téléphone, web bloqué), l'adresse passe dans le
  /// presse-papiers : on ne laisse pas un bouton qui ne fait rien.
  Future<void> _openTmdb() async {
    final opened = await widget.openUrl(kTmdbApiSettingsUrl);
    if (opened || !mounted) return;
    try {
      await Clipboard.setData(const ClipboardData(text: kTmdbApiSettingsUrl));
    } catch (e) {
      // Pas de presse-papiers (certains téléviseurs) : l'adresse reste dite
      // dans le message, et écrite sous le bouton.
      debugPrint('SetupTmdbStep: presse-papiers indisponible: $e');
    }
    if (!mounted) return;
    showSettingsSnack(
        context, tr('Adresse : {0}', ['themoviedb.org/settings/api']));
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final isTv = TvScope.of(context);
    const muted = TextStyle(
      color: AppColors.textSecondary,
      fontSize: AppType.subhead,
      height: 1.45,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('La clé TMDB'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          tr('TMDB est la base de données qui donne à Onyx les affiches, les '
              'résumés, les logos et les titres traduits, et qui lui permet '
              'd’identifier vos films et vos séries.'),
          style: muted,
        ),
        const SizedBox(height: 12),
        Text(
          tr('Pour obtenir une clé : créez un compte gratuit sur '
              'themoviedb.org, ouvrez Paramètres → API, demandez une clé '
              '« Developer », puis copiez la clé API (v3), pas le jeton '
              'd’accès.'),
          style: muted,
        ),
        const SizedBox(height: 12),
        SettingsBanner(
          tr('La clé est gratuite pour un usage non commercial. Un usage '
              'commercial demande une licence auprès de TMDB.'),
        ),
        if (isTv) ...[
          const SelectableText(
            'themoviedb.org/settings/api',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppType.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SettingsBanner(
            tr('Taper une clé à la télécommande est pénible : passez cette '
                'étape et faites-le depuis un téléphone ou un ordinateur. La '
                'checklist de l’accueil vous le rappellera.'),
          ),
        ] else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openTmdb,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(tr('Ouvrir themoviedb.org/settings/api')),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
        if (settings == null && _error == null) const SettingsLoading(),
        if (settings != null) ...[
          TmdbSettingsForm(
            settings: settings,
            defaultLanguage: tmdbLanguageForApp(),
            onSaved: _saved,
          ),
          if (!settings.tmdbApiKeySet) ...[
            const SizedBox(height: 16),
            SettingsBanner(
              tr('Sans clé, pas d’affiches ni de métadonnées : le catalogue '
                  'n’affichera que les noms de fichiers.'),
            ),
          ],
        ],
      ],
    );
  }
}
