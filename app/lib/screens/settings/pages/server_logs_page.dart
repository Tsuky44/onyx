import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_client.dart';
import '../settings_sections.dart';
import '../widgets/settings_ui.dart';

/// Ce que le serveur garde de chaque lecture : son journal et ses mesures.
///
/// Ces deux interrupteurs valent pour tous les comptes ; ils étaient dans le
/// journal de l'app (« Général »), à côté d'un tampon qui ne concerne que cet
/// appareil. Ils sont ici avec les autres réglages du serveur ; le journal de
/// l'app, lui, reste l'aide de l'appareil (ADR-0100).
class ServerLogsPage extends StatefulWidget {
  const ServerLogsPage({super.key});

  @override
  State<ServerLogsPage> createState() => _ServerLogsPageState();
}

class _ServerLogsPageState extends State<ServerLogsPage> {
  ServerSettings? _server;
  bool _logsEnabled = true;
  bool _statsEnabled = true;
  bool _savingLogs = false;
  bool _savingStats = false;
  String? _error;

  bool get _canReadHistory =>
      context.read<AuthProvider>().permissions.manageUsers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await context.read<ApiClient>().getServerSettings();
      if (!mounted) return;
      setState(() {
        _server = settings;
        _logsEnabled = settings.playbackLogsEnabled;
        _statsEnabled = settings.playbackStatsEnabled;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Un serveur plus ancien n'a pas ce réglage : la page le dit au lieu de
      // montrer des interrupteurs qui ne feraient rien.
      setState(() => _error =
          settingsErrorText(e, tr('Réglage indisponible sur ce serveur.')));
    }
  }

  Future<void> _saveLogs(bool value) async {
    setState(() {
      _logsEnabled = value;
      _savingLogs = true;
    });
    try {
      final updated = await context
          .read<ApiClient>()
          .updateServerSettings(playbackLogsEnabled: value);
      if (!mounted) return;
      setState(() {
        _server = updated;
        _logsEnabled = updated.playbackLogsEnabled;
      });
      showSettingsSnack(
        context,
        value
            ? tr('Journaux des lectures activés.')
            : tr('Journaux des lectures désactivés.'),
      );
    } catch (e) {
      if (!mounted) return;
      // Remettre l'interrupteur là où le serveur l'a laissé : un interrupteur
      // qui reste sur une position que le serveur a refusée ment.
      setState(() => _logsEnabled = _server?.playbackLogsEnabled ?? true);
      showSettingsSnack(
          context, settingsErrorText(e, tr('Échec de l\'enregistrement.')),
          error: true);
    }
    if (mounted) setState(() => _savingLogs = false);
  }

  Future<void> _saveStats(bool value) async {
    setState(() {
      _statsEnabled = value;
      _savingStats = true;
    });
    try {
      final updated = await context
          .read<ApiClient>()
          .updateServerSettings(playbackStatsEnabled: value);
      if (!mounted) return;
      setState(() {
        _server = updated;
        _statsEnabled = updated.playbackStatsEnabled;
      });
      showSettingsSnack(
        context,
        value ? tr('Mesures des lectures activées.') : tr('Mesures désactivées.'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _statsEnabled = _server?.playbackStatsEnabled ?? true);
      showSettingsSnack(
          context, settingsErrorText(e, tr('Échec de l\'enregistrement.')),
          error: true);
    }
    if (mounted) setState(() => _savingStats = false);
  }

  @override
  Widget build(BuildContext context) {
    final layout = SettingsLayout.maybeOf(context);

    return SettingsPage(
      title: tr('Journaux'),
      description: tr('Ce que le serveur garde de chaque lecture pour '
          'comprendre une panne, quel que soit l’appareil qui lisait.'),
      children: [
        SettingsGroup(
          title: tr('Journaux des lectures'),
          footer: tr('Chaque lecture envoie son journal et ses mesures en '
              'se terminant, et le serveur garde ceux des dix '
              'dernières. On les relit depuis l’Historique, en '
              'ouvrant une lecture — y compris celle d’un autre '
              'appareil, ce que le journal de l’app ne permet '
              'pas. Les mesures ont leur propre interrupteur : '
              'elles interrogent le lecteur toutes les cinq '
              'secondes, là où le journal ne coûte rien avant la '
              'fin.'),
          children: [
            if (_error != null)
              SettingsEmptyNote(_error!, icon: Icons.cloud_off_rounded)
            else ...[
              SettingsSwitchTile(
                icon: Icons.cloud_sync_rounded,
                title: tr('Conserver les journaux des lectures'),
                subtitle: _server == null
                    ? tr('Chargement…')
                    : _logsEnabled
                        ? tr('Les dix dernières lectures gardent leur '
                            'journal.')
                        : tr('Aucun journal de lecture n’est conservé.'),
                value: _logsEnabled,
                onChanged: _server == null || _savingLogs ? null : _saveLogs,
              ),
              SettingsSwitchTile(
                icon: Icons.speed_rounded,
                title: tr('Mesurer la lecture'),
                subtitle: _server == null
                    ? tr('Chargement…')
                    : _statsEnabled
                        ? tr('Cadence, débit, décodeur et images '
                            'perdues, relevés pendant la lecture.')
                        : tr('Aucune mesure n’est relevée.'),
                value: _statsEnabled,
                onChanged: _server == null || _savingStats ? null : _saveStats,
              ),
              if (_canReadHistory && layout != null)
                SettingsTile(
                  icon: Icons.history_rounded,
                  title: tr('Ouvrir l’Historique'),
                  subtitle: tr('Chaque lecture y ouvre son journal, erreurs '
                      'comprises.'),
                  onTap: () => layout.openSection(SettingsSections.activity),
                ),
            ],
          ],
        ),
      ],
    );
  }
}
