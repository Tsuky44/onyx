import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../models/models.dart';
import '../../../models/server_activity.dart';
import '../../../services/api_client.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../widgets/stats_charts.dart';
import '../widgets/settings_ui.dart';
import '../../../theme/app_type.dart';
import '../../../l10n/tr.dart';
import '../../../widgets/global/onyx_menu.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  static const _periods = [
    (7, '7 jours'),
    (30, '30 jours'),
    (90, '3 mois'),
    (365, '1 an')
  ];

  int _days = 30;
  int? _userId;
  List<User> _users = const [];
  PlaybackStats? _stats;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    context.read<ApiClient>().getUsers().then((users) {
      if (mounted) setState(() => _users = users);
    }).catchError((_) {
      // Sans la liste des comptes, le filtre par utilisateur ne s'affiche pas.
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await context
          .read<ApiClient>()
          .getPlaybackStats(days: _days, userId: _userId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            settingsErrorText(e, tr('Impossible de calculer les statistiques.'));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final perDay = stats == null || stats.days == 0
        ? 0
        : stats.watchedSeconds ~/ stats.days;

    return SettingsPage(
      title: tr('Statistiques'),
      description:
          tr('Ce qui se regarde sur le serveur : temps de visionnage, '
              'titres préférés, habitudes et applications utilisées.'),
      onRefresh: _load,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (days, label) in _periods)
                ChoiceChip(
                  label: Text(label),
                  selected: _days == days,
                  showCheckmark: false,
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  backgroundColor: Colors.transparent,
                  side: AppTheme.chipSide(
                      BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  onSelected: (_) {
                    if (_days == days) return;
                    setState(() => _days = days);
                    _load();
                  },
                ),
              if (_users.length > 1)
                OnyxMenuButton<int?>(
                  tooltip: tr('Filtrer par utilisateur'),
                  onSelected: (id) {
                    setState(() => _userId = id);
                    _load();
                  },
                  items: [
                    OnyxMenuItem<int?>(
                      value: null,
                      label: tr('Tout le monde'),
                      checked: _userId == null,
                    ),
                    for (final user in _users)
                      OnyxMenuItem<int?>(
                        value: user.id,
                        leading: UserAvatar(user.username, size: 20),
                        label: user.username,
                        checked: _userId == user.id,
                      ),
                  ],
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(_userId == null
                          ? tr('Tout le monde')
                          : _users
                                  .where((u) => u.id == _userId)
                                  .map((u) => u.username)
                                  .firstOrNull ??
                              '—'),
                      const Icon(Icons.arrow_drop_down_rounded,
                          color: AppColors.textSecondary),
                    ]),
                  ),
                ),
              if (_loading && stats != null)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        if (_error != null) SettingsBanner(_error!, tone: BannerTone.error),
        if (stats == null && _loading)
          const SettingsLoading()
        else if (stats != null) ...[
          StatGrid(children: [
            StatTile(
              icon: Icons.schedule_rounded,
              label: tr('Temps de visionnage'),
              value: formatWatchTime(stats.watchedSeconds),
              hint: tr('≈ {0} par jour', [formatWatchTime(perDay)]),
            ),
            StatTile(
              icon: Icons.play_arrow_rounded,
              label: tr('Lectures'),
              value: '${stats.plays}',
              hint:
                  tr('{0} utilisateur{1} actif{2}', [stats.activeUsers, stats.activeUsers > 1 ? 's' : '', stats.activeUsers > 1 ? 's' : '']),
              color: AppColors.success,
            ),
            StatTile(
              icon: Icons.movie_outlined,
              label: tr('Films différents'),
              value: '${stats.movies}',
              color: AppColors.warning,
            ),
            StatTile(
              icon: Icons.tv_rounded,
              label: tr('Épisodes différents'),
              value: '${stats.episodes}',
              color: AppColors.accentMuted,
            ),
          ]),
          SettingsGroup(
            title: tr('Temps de visionnage par jour'),
            padded: true,
            children: [DailyWatchChart(stats.daily)],
          ),
          SettingsGroup(
            title: tr('Heures de visionnage'),
            footer: tr('Réparti selon l’heure de début de chaque lecture.'),
            padded: true,
            children: [HourWatchChart(stats.hourOfDay)],
          ),
          SettingsGroup(
            title: tr('Titres les plus regardés'),
            children: [
              if (stats.topMedia.isEmpty)
                SettingsEmptyNote(tr('Aucune lecture sur cette période.'))
              else
                for (final (i, media) in stats.topMedia.indexed)
                  RankedMediaRow(
                    rank: i + 1,
                    media: media,
                    max: stats.topMedia.first.watchedSeconds,
                  ),
            ],
          ),
          if (_userId == null && stats.topUsers.isNotEmpty)
            SettingsGroup(
              title: tr('Utilisateurs les plus actifs'),
              children: [
                for (final user in stats.topUsers)
                  StatBarRow(
                    leading: UserAvatar(user.label, size: 30),
                    label: user.label,
                    detail: trPlural(user.plays, '{0} lecture', '{0} lectures'),
                    value: user.watchedSeconds,
                    max: stats.topUsers.first.watchedSeconds,
                  ),
              ],
            ),
          LayoutBuilder(builder: (context, constraints) {
            final apps = SettingsGroup(
              title: tr('Applications'),
              children: [
                if (stats.clients.isEmpty)
                  const SettingsEmptyNote('—')
                else
                  for (final client in stats.clients)
                    StatBarRow(
                      leading:
                          SettingsIcon(deviceIconFor(client.label), size: 30),
                      label: client.label,
                      detail:
                          trPlural(client.plays, '{0} lecture', '{0} lectures'),
                      value: client.watchedSeconds,
                      max: stats.clients.first.watchedSeconds,
                    ),
              ],
            );
            final methods = SettingsGroup(
              title: tr('Méthodes de lecture'),
              footer:
                  tr('Direct Play et Direct Stream ne coûtent presque rien '
                      'au serveur ; le transcodage sollicite le processeur.'),
              padded: true,
              children: [_MethodsBreakdown(stats.playMethods)],
            );
            if (constraints.maxWidth < 640) {
              return Column(children: [apps, methods]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: apps),
                const SizedBox(width: 16),
                Expanded(child: methods),
              ],
            );
          }),
        ],
      ],
    );
  }
}

class _MethodsBreakdown extends StatelessWidget {
  const _MethodsBreakdown(this.methods);
  final List<StatBucket> methods;

  @override
  Widget build(BuildContext context) {
    final total = methods.fold<int>(0, (s, m) => s + m.plays);
    if (total == 0) {
      return SettingsEmptyNote(tr('Aucune lecture sur cette période.'));
    }
    final parsed = [
      for (final m in methods) (PlayMethod.parse(m.key), m.plays),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final (method, plays) in parsed)
                  Expanded(
                    flex: math.max(1, (plays * 1000 / total).round()),
                    child: Container(color: playMethodColor(method)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final (method, plays) in parsed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: playMethodColor(method),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(method.label)),
                Text(
                  '${(plays * 100 / total).round()} %',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    trPlural(plays, '{0} lecture', '{0} lectures'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: AppType.footnote),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
