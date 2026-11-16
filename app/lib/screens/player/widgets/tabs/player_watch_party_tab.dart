import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/tr.dart';
import '../../../../models/watch_party.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_type.dart';
import '../../../../tv/tv_mode.dart';
import '../onyx/onyx_capsule_button.dart';
import '../onyx/onyx_chrome_theme.dart';

/// L'onglet « Regarder ensemble » du lecteur : démarrer une séance, ou en voir
/// le code et les participants, et la quitter (ADR-0130).
///
/// Une colonne de présentation à gauche, les lignes à droite.
class PlayerWatchPartyTab extends StatefulWidget {
  const PlayerWatchPartyTab({
    super.key,
    required this.code,
    required this.members,
    required this.onStart,
    required this.onLeave,
  });

  /// Nul hors séance : l'onglet propose alors d'en démarrer une.
  final String? code;
  final List<WatchPartyMember> members;

  /// Ouvre la séance sur le média en cours. Lève en cas d'échec.
  final Future<void> Function() onStart;
  final VoidCallback onLeave;

  @override
  State<PlayerWatchPartyTab> createState() => _PlayerWatchPartyTabState();
}

class _PlayerWatchPartyTabState extends State<PlayerWatchPartyTab> {
  bool _starting = false;
  String? _error;
  bool _copied = false;

  /// Le bouton de l'onglet : « Démarrer une séance », puis « Quitter la
  /// séance ». Un seul nœud pour les deux : quand l'un remplace l'autre sous
  /// la télécommande, elle reste sur le bouton de l'onglet au lieu de se
  /// retrouver nulle part.
  final FocusNode _action = FocusNode(debugLabel: 'player-party-action');

  @override
  void didUpdateWidget(PlayerWatchPartyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = (oldWidget.code == null) != (widget.code == null);
    // Lu ici, avant que l'ancien bouton ne soit démonté.
    if (!changed || !TvMode.isTv || !_action.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _action.requestFocus();
    });
  }

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await widget.onStart();
      if (mounted) setState(() => _starting = false);
    } catch (_) {
      // L'échec se dit dans l'onglet, là où le bouton a été pressé : le
      // serveur a refusé ou n'a pas répondu, et réessayer est le seul geste.
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = tr('Impossible de démarrer la séance. Réessayez.');
      });
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.code;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: code == null ? _buildIdle() : _buildCode(code),
        ),
        const SizedBox(width: 40),
        Expanded(
          flex: 6,
          child: code == null ? _buildSteps() : _buildMembers(),
        ),
      ],
    );
  }

  // --- Hors séance ---------------------------------------------------------

  Widget _buildIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Regardez à plusieurs'), style: _headline),
        const SizedBox(height: 8),
        Flexible(
          child: Text(
            _error ??
                tr('Lecture, pauses et déplacements sont partagés entre tous, '
                    'chacun sur son appareil.'),
            overflow: TextOverflow.fade,
            style: _body.copyWith(
              color: _error == null ? OnyxChromeTheme.time : AppColors.error,
            ),
          ),
        ),
        const SizedBox(height: 16),
        OnyxControlsRow(
          child: OnyxCapsuleButton(
            key: const ValueKey('player-party-start'),
            label: tr('Démarrer une séance'),
            icon: Icons.play_arrow_rounded,
            primary: true,
            busy: _starting,
            focusNode: _action,
            onPressed: _start,
          ),
        ),
      ],
    );
  }

  Widget _buildSteps() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Comment ça marche'), style: _eyebrow),
        const SizedBox(height: 10),
        _row('1', tr('Démarrez la séance'),
            tr('Depuis ce panneau, pendant la lecture.')),
        _row('2', tr('Partagez le code'),
            tr('Il s’affiche ici une fois la séance ouverte.')),
        _row('3', tr('Chacun la rejoint'),
            tr('Menu du compte › Rejoindre une séance.')),
      ],
    );
  }

  // --- En séance -----------------------------------------------------------

  Widget _buildCode(String code) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Code de la séance').toUpperCase(), style: _eyebrow),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            code,
            key: const ValueKey('player-party-code'),
            maxLines: 1,
            style: const TextStyle(
              color: OnyxChromeTheme.title,
              fontSize: AppType.hero,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: Text(
            tr('Pour rejoindre : menu du compte › Rejoindre une séance.'),
            overflow: TextOverflow.fade,
            style: _body.copyWith(color: OnyxChromeTheme.time),
          ),
        ),
        const SizedBox(height: 16),
        OnyxControlsRow(
          // Passe à la ligne sur un écran étroit plutôt que de déborder.
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              // « Copier » n'a pas de sens à la télécommande.
              if (!TvMode.isTv)
                OnyxCapsuleButton(
                  label: _copied ? tr('Copié') : tr('Copier'),
                  icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                  onPressed: () => _copy(code),
                ),
              OnyxCapsuleButton(
                key: const ValueKey('player-party-leave'),
                label: tr('Quitter la séance'),
                icon: Icons.logout_rounded,
                focusNode: _action,
                onPressed: widget.onLeave,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMembers() {
    final members = widget.members;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          members.length > 1
              ? tr('{0} participants', [members.length])
              : tr('En attente des autres participants…'),
          style: _eyebrow,
        ),
        const SizedBox(height: 10),
        // Défile quand la séance dépasse ce que le volet montre : une liste de
        // noms, sans rien à activer.
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final member in members)
                () {
                  final name =
                      member.username.isEmpty ? tr('Invité') : member.username;
                  return _row(
                    name.characters.first.toUpperCase(),
                    member.isYou ? tr('{0} (vous)', [name]) : name,
                    member.device,
                    trailing: member.isHost ? tr('Hôte') : null,
                  );
                }(),
            ],
          ),
        ),
      ],
    );
  }

  /// Une ligne à pastille : une étape, un participant.
  Widget _row(String badge, String title, String? detail, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: OnyxChromeTheme.glassControl,
              shape: BoxShape.circle,
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: OnyxChromeTheme.title,
                fontSize: AppType.callout,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: OnyxChromeTheme.title,
                    fontSize: AppType.callout,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: OnyxChromeTheme.meta,
                      fontSize: AppType.footnote,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(
                color: OnyxChromeTheme.time,
                fontSize: AppType.subhead,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  static const TextStyle _headline = TextStyle(
    color: OnyxChromeTheme.title,
    fontSize: AppType.title2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static const TextStyle _body = TextStyle(
    fontSize: AppType.callout,
    height: 1.4,
  );

  static const TextStyle _eyebrow = TextStyle(
    color: OnyxChromeTheme.meta,
    fontSize: AppType.footnote,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
}
