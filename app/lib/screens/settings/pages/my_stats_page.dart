import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../l10n/tr.dart';
import '../../../models/server_activity.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../widgets/my_stats/my_stats_sections.dart';
import '../widgets/my_stats/my_stats_titles.dart';
import '../widgets/settings_ui.dart';
import '../widgets/stats_charts.dart';

/// « Mes stats » : ce que le compte a regardé, pour tout le monde, admin ou
/// pas (GET /api/me/stats). Les statistiques du serveur entier restent dans
/// Activité. Voir l'ADR 2026-11-26-tsuky-statistiques-personnelles.
class MyStatsPage extends StatefulWidget {
  const MyStatsPage({super.key});

  @override
  State<MyStatsPage> createState() => _MyStatsPageState();
}

/// Une période : un nombre de jours, ou tout l'historique (null).
typedef _Period = ({int? days});

String _periodLabel(_Period period) => switch (period.days) {
      7 => tr('7 jours'),
      30 => tr('30 jours'),
      365 => tr('12 mois'),
      _ => tr('Depuis le début'),
    };

class _MyStatsPageState extends State<MyStatsPage> {
  static const List<_Period> _periods = [
    (days: 7),
    (days: 30),
    (days: 365),
    (days: null),
  ];

  _Period _period = _periods[1];
  PlaybackStats? _stats;
  String? _error;
  bool _loading = true;

  /// Une réponse lente d'une période qu'on a déjà quittée ne remplace pas
  /// celle de la période choisie ensuite.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final days = _period.days;
      final stats = await context.read<ApiClient>().getMyPlaybackStats(
            days: days ?? 30,
            allTime: days == null,
          );
      if (!mounted || request != _request) return;
      setState(() {
        _stats = stats;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = settingsErrorText(
            e, tr('Impossible de calculer vos statistiques.'));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final personal = stats?.personal;
    return SettingsPage(
      title: tr('Mes stats'),
      description: tr('Ce que vous avez regardé : votre temps, vos habitudes, '
          'vos séries et vos genres. Vous seul les voyez.'),
      onRefresh: _load,
      children: [
        _PeriodPicker(
          periods: _periods,
          selected: _period,
          busy: _loading && stats != null,
          onSelected: (period) {
            if (period == _period) return;
            setState(() => _period = period);
            _load();
          },
        ),
        if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
        if (stats == null && _loading)
          const SettingsLoading()
        else if (stats != null) ...[
          MyOverviewGrid(stats),
          SettingsGroup(
            title: switch (groupDailyForChart(stats.daily).step) {
              ChartStep.day => tr('Temps regardé par jour'),
              ChartStep.week => tr('Temps regardé par semaine'),
              ChartStep.month => tr('Temps regardé par mois'),
            },
            padded: true,
            children: [DailyWatchChart(stats.daily)],
          ),
          if (personal != null)
            MyHabitsGroup(stats)
          else
            SettingsGroup(
              title: tr('Heures de visionnage'),
              padded: true,
              children: [HourWatchChart(stats.hourOfDay)],
            ),
          if (personal != null) MyShowsGroup(personal),
          SettingsGroup(
            title: tr('Mes titres les plus regardés'),
            children: [
              if (stats.topMedia.isEmpty)
                SettingsEmptyNote(tr('Aucune lecture sur cette période.'))
              else
                for (final (i, media) in stats.topMedia.indexed)
                  StatsRowFocus(
                    child: RankedMediaRow(
                      rank: i + 1,
                      media: media,
                      max: stats.topMedia.first.watchedSeconds,
                    ),
                  ),
            ],
          ),
          if (personal != null) ...[
            MyGenresGroup(personal.genres, hasPlays: stats.plays > 0),
            _Pair(
              left: MyMoviesGroup(personal),
              right: MyDecadesGroup(personal.decades),
            ),
            MyDevicesGroup(personal.devices),
            MyLifetimeGroup(personal),
          ],
        ],
      ],
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({
    required this.periods,
    required this.selected,
    required this.busy,
    required this.onSelected,
  });

  final List<_Period> periods;
  final _Period selected;
  final bool busy;
  final ValueChanged<_Period> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final period in periods)
            ChoiceChip(
              label: Text(_periodLabel(period)),
              selected: period == selected,
              showCheckmark: false,
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              backgroundColor: Colors.transparent,
              side: AppTheme.chipSide(
                  BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              onSelected: (_) => onSelected(period),
            ),
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

/// Deux groupes côte à côte en largeur desktop, l'un sous l'autre sinon.
class _Pair extends StatelessWidget {
  const _Pair({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 640) return Column(children: [left, right]);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 16),
          Expanded(child: right),
        ],
      );
    });
  }
}
