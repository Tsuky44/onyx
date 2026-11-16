import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../models/media_request.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_type.dart';
import '../../../utils/responsive.dart';
import 'request_season_panel.dart' show seasonTitle;

/// Les saisons d'une série qu'on peut encore demander, à cocher une à une :
/// « Compléter » une demande, ou « Demander » quand MediaHub laisse choisir
/// les saisons ([RequestAccess.seasonChoice]). Rend les numéros cochés, ou
/// `null` si on referme sans rien envoyer.
class RequestSeasonPickerSheet extends StatefulWidget {
  const RequestSeasonPickerSheet({
    super.key,
    required this.details,
    this.completing = true,
  });

  final RequestMediaDetails details;

  /// `true` : on ajoute des saisons à une demande ; `false` : première
  /// demande de la série.
  final bool completing;

  static Future<List<int>?> show(
    BuildContext context,
    RequestMediaDetails details, {
    bool completing = true,
  }) {
    return showDialog<List<int>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (_) => RequestSeasonPickerSheet(
        details: details,
        completing: completing,
      ),
    );
  }

  @override
  State<RequestSeasonPickerSheet> createState() =>
      _RequestSeasonPickerSheetState();
}

class _RequestSeasonPickerSheetState extends State<RequestSeasonPickerSheet> {
  final _picked = <int>{};

  List<RequestSeason> get _seasons => widget.details.requestableSeasons;

  bool get _allPicked => _picked.length == _seasons.length;

  void _toggle(int number, bool on) {
    setState(() => on ? _picked.add(number) : _picked.remove(number));
  }

  void _toggleAll() {
    setState(() {
      if (_allPicked) {
        _picked.clear();
      } else {
        _picked.addAll(_seasons.map((season) => season.number));
      }
    });
  }

  /// Ce que la bibliothèque a déjà d'une saison à moitié là, sinon son
  /// nombre d'épisodes.
  String _subtitle(RequestSeason season) {
    if (season.status == RequestMediaStatus.partial &&
        season.availableEpisodes > 0) {
      return tr('{0} épisodes sur {1} déjà là',
          [season.availableEpisodes, season.episodeCount]);
    }
    return season.episodeCount > 0
        ? tr('{0} épisodes', [season.episodeCount])
        : '';
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppLayout.isCompact(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: compact ? 24 : 40,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.glassBorder),
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: 480, maxHeight: size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final season in _seasons)
                    CheckboxListTile(
                      value: _picked.contains(season.number),
                      onChanged: (on) => _toggle(season.number, on ?? false),
                      title: Text(seasonTitle(season)),
                      subtitle: _subtitle(season).isEmpty
                          ? null
                          : Text(_subtitle(season)),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.completing
                      ? tr('Compléter la demande')
                      : tr('Choisir les saisons'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: AppType.headline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.completing
                      ? tr('Cochez les saisons à ajouter.')
                      : tr('Cochez les saisons à demander.'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppType.subhead,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Fermer'),
            icon: const Icon(AppIcons.close, color: AppColors.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          if (_seasons.length > 1)
            TextButton(
              onPressed: _toggleAll,
              child: Text(_allPicked ? tr('Tout décocher') : tr('Tout cocher')),
            ),
          const Spacer(),
          FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(_picked.toList()..sort()),
            child: Text(tr('Demander ({0})', [_picked.length])),
          ),
        ],
      ),
    );
  }
}
