import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/client_log.dart';
import '../../../theme/app_colors.dart';
import '../widgets/settings_ui.dart';
import '../../../theme/app_type.dart';
import '../../../l10n/tr.dart';

/// Ce que l'app a écrit sur elle-même, lisible sans câble.
///
/// La page ne fabrique rien : elle montre le tampon de [ClientLog], que
/// l'application remplit de toute façon. Son intérêt tient au bouton « Copier »
/// — une panne qu'on peut coller dans un message est une panne qu'on peut
/// corriger, là où « ça ne se lance pas » n'a jamais rien appris à personne.
///
/// Les journaux que les lectures laissent sur le serveur se règlent dans
/// « Serveur », pas ici : ce tampon-ci ne concerne que cet appareil (ADR-0100).
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  bool _errorsOnly = false;

  Future<void> _copy(List<LogEntry> shown) async {
    await Clipboard.setData(
      ClipboardData(text: ClientLog.export(errorsOnly: _errorsOnly)),
    );
    if (!mounted) return;
    showSettingsSnack(
      context,
      tr('{0} ligne{1} copiée{2}.', [shown.length, shown.length > 1 ? 's' : '', shown.length > 1 ? 's' : '']),
    );
  }

  Future<void> _clear() async {
    final confirmed = await confirmSettingsAction(
      context,
      title: tr('Vider le journal ?'),
      message:
          tr('Les lignes déjà enregistrées sont perdues. L’app continue '
              'd’en écrire de nouvelles.'),
      confirmLabel: tr('Vider'),
    );
    if (!confirmed || !mounted) return;
    ClientLog.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Le journal s'écrit pendant qu'on le regarde : une lecture lancée depuis
    // un autre onglet, une requête qui échoue en arrière-plan. La page suit.
    return ValueListenableBuilder<int>(
      valueListenable: ClientLog.revision,
      builder: (context, _, __) {
        final all = ClientLog.entries;
        final errors =
            all.where((e) => e.level == LogLevel.error).toList(growable: false);
        final shown = _errorsOnly ? errors : all;

        return SettingsPage(
          title: tr('Journal'),
          description:
              tr('Ce que cette application enregistre sur elle-même : '
                  'démarrages de lecture, réponses du serveur, pannes. Rien '
                  'n’en sort tant que vous ne copiez pas — le journal vit en '
                  'mémoire et disparaît à la fermeture de l’app. Les '
                  'journaux que les lectures laissent sur le serveur, eux, '
                  'se relisent depuis n’importe quel appareil.'),
          actions: [
            FilledButton.icon(
              onPressed: shown.isEmpty ? null : () => _copy(shown),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(tr('Copier')),
            ),
            OutlinedButton.icon(
              onPressed: all.isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(tr('Vider')),
            ),
          ],
          children: [
            SettingsGroup(
              title: tr('Journal de cette application'),
              children: [
                SettingsSwitchTile(
                  icon: Icons.filter_alt_rounded,
                  title: tr('Erreurs seulement'),
                  subtitle: errors.isEmpty
                      ? tr('Aucune erreur enregistrée depuis le démarrage de '
                          'l’app.')
                      : tr('{0} erreur{1} sur {2} ligne{3}.', [errors.length, errors.length > 1 ? 's' : '', all.length, all.length > 1 ? 's' : '']),
                  value: _errorsOnly,
                  onChanged: (value) => setState(() => _errorsOnly = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (shown.isEmpty)
              SettingsEmptyNote(
                _errorsOnly
                    ? tr('Aucune erreur. Si quelque chose vient de mal se '
                        'passer, coupez ce filtre : la cause est souvent '
                        'dans les lignes ordinaires.')
                    : tr('Rien pour l’instant. Reproduisez le problème, puis '
                        'revenez ici.'),
                icon: Icons.receipt_long_rounded,
              )
            else
              // Les plus récentes en haut : ce qu'on cherche vient de se
              // produire, et faire défiler six cents lignes pour l'atteindre
              // serait une drôle de façon de le présenter.
              SettingsGroup(
                title: tr('Les plus récentes d’abord'),
                padded: true,
                children: [
                  for (final entry in shown.reversed) _LogLine(entry: entry),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Une ligne, sélectionnable.
///
/// `SelectableText` plutôt que `Text` : sur un ordinateur, copier la seule
/// ligne qui compte vaut mieux que copier les six cents.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isError = entry.level == LogLevel.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Un filet plutôt qu'une pastille : il tient sur toute la hauteur
          // d'une ligne qui se replie sur quatre, là où une icône n'aurait
          // marqué que la première.
          Container(
            width: 3,
            constraints: const BoxConstraints(minHeight: 18),
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: isError ? AppColors.error : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SelectableText(
              entry.format(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: ['Menlo', 'Consolas', tr('Roboto Mono')],
                fontSize: AppType.footnote,
                height: 1.4,
                color: isError ? AppColors.error : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
