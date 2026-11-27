import 'package:material_ui/material_ui.dart';

import '../../l10n/tr.dart';
import '../../models/media_details.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_type.dart';
import '../../tv/nav/tv_focusable.dart';
import '../../tv/tv_mode.dart';
import '../../utils/responsive.dart';

/// Type de compte à rebours d'un média (prochain épisode, dernier épisode d'une
/// série terminée, ou date de sortie d'un film).
enum CountdownKind {
  next,
  last,
  release,
}

/// Modèle de calcul pour le compte à rebours de l'en-tête (équivalent à
/// `media-countdown.ts` dans MediaHub).
class CountdownModel {
  final CountdownKind kind;
  final String label;

  /// Date visée (YYYY-MM-DD).
  final String target;

  /// Date de l'épisode précédent (YYYY-MM-DD) pour la barre de progression.
  final String? from;

  /// Légende sous la barre (ex. « Saison 2 · Épisode 9 »).
  final String caption;

  const CountdownModel({
    required this.kind,
    required this.label,
    required this.target,
    this.from,
    required this.caption,
  });

  static final RegExp _dayRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Convertit une chaîne YYYY-MM-DD en Date UTC au jour près.
  static DateTime? parseDay(String? raw) {
    if (raw == null || !_dayRegex.hasMatch(raw)) return null;
    final parts = raw.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Écart en jours calendaires entre deux dates YYYY-MM-DD (`to - from`).
  static int daysBetween(String from, String to) {
    final f = parseDay(from);
    final t = parseDay(to);
    if (f == null || t == null) return 0;
    return t.difference(f).inDays;
  }

  /// Formate la légende d'un épisode (« Saison X · Épisode Y »).
  static String episodeCaption(EpisodeAirRef ep) {
    if (ep.seasonNumber > 0 && ep.episodeNumber > 0) {
      return tr(
          'Saison {0} · Épisode {1}', [ep.seasonNumber, ep.episodeNumber]);
    }
    if (ep.episodeNumber > 0) {
      return tr('Épisode {0}', [ep.episodeNumber]);
    }
    return tr('Nouvel épisode');
  }

  /// Calcule le modèle de compte à rebours pour une série TV.
  static CountdownModel? forShow({
    EpisodeAirRef? nextEpisode,
    EpisodeAirRef? lastEpisode,
    String? status,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final todayStr = _toDayString(clock);

    final nextAir = nextEpisode?.airDate;
    if (nextAir != null &&
        _dayRegex.hasMatch(nextAir) &&
        nextAir.compareTo(todayStr) >= 0) {
      final lastAir = lastEpisode?.airDate;
      return CountdownModel(
        kind: CountdownKind.next,
        label: tr('Prochain épisode'),
        target: nextAir,
        from: (lastAir != null && _dayRegex.hasMatch(lastAir)) ? lastAir : null,
        caption: episodeCaption(nextEpisode!),
      );
    }

    final normalizedStatus = (status ?? '').trim().toLowerCase();
    final isEnded = normalizedStatus == 'ended' ||
        normalizedStatus == 'canceled' ||
        normalizedStatus == 'cancelled';
    final lastAir = lastEpisode?.airDate;
    if (isEnded && lastAir != null && _dayRegex.hasMatch(lastAir)) {
      return CountdownModel(
        kind: CountdownKind.last,
        label: tr('Dernier épisode'),
        target: lastAir,
        caption: episodeCaption(lastEpisode!),
      );
    }

    return null;
  }

  /// Calcule le modèle de compte à rebours pour un film à venir.
  static CountdownModel? forMovie({
    String? releaseDate,
    DateTime? now,
  }) {
    if (releaseDate == null || !_dayRegex.hasMatch(releaseDate)) return null;
    final clock = now ?? DateTime.now();
    final todayStr = _toDayString(clock);
    if (releaseDate.compareTo(todayStr) >= 0) {
      return CountdownModel(
        kind: CountdownKind.release,
        label: tr('Sortie'),
        target: releaseDate,
        caption: tr('Film à venir'),
      );
    }
    return null;
  }

  /// Calcule le compte à rebours selon le type de média.
  static CountdownModel? fromDetails({
    required bool isTv,
    EpisodeAirRef? nextEpisode,
    EpisodeAirRef? lastEpisode,
    String? status,
    String? releaseDate,
    DateTime? now,
  }) {
    if (isTv) {
      return forShow(
        nextEpisode: nextEpisode,
        lastEpisode: lastEpisode,
        status: status,
        now: now,
      );
    }
    return forMovie(releaseDate: releaseDate, now: now);
  }

  static String _toDayString(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// Le widget du compte à rebours de l'en-tête (« J-6 », la date de diffusion et
/// la barre de progression lumineuse), inspiré de MediaHub (`MediaCountdown.tsx`).
class MediaCountdown extends StatefulWidget {
  final CountdownModel model;

  /// Horloge injectable pour les tests.
  final DateTime? now;

  /// Force l'alignement à droite (sur grand écran) ou à gauche (sur mobile).
  final bool? alignEnd;

  /// Action déclenchée pour ouvrir le calendrier sur ce jour.
  final VoidCallback? onOpenCalendar;

  /// Mention discrète sous le lien (ex. « Suivie car vous la regardez »).
  final String? calendarNote;

  const MediaCountdown({
    super.key,
    required this.model,
    this.now,
    this.alignEnd,
    this.onOpenCalendar,
    this.calendarNote,
  });

  /// Factory pratique retournant directement le widget ou `null` s'il n'y a
  /// rien à annoncer.
  static Widget? fromDetails({
    required bool isTv,
    EpisodeAirRef? nextEpisode,
    EpisodeAirRef? lastEpisode,
    String? status,
    String? releaseDate,
    DateTime? now,
    bool? alignEnd,
    VoidCallback? onOpenCalendar,
    String? calendarNote,
  }) {
    final model = CountdownModel.fromDetails(
      isTv: isTv,
      nextEpisode: nextEpisode,
      lastEpisode: lastEpisode,
      status: status,
      releaseDate: releaseDate,
      now: now,
    );
    if (model == null) return null;
    return MediaCountdown(
      model: model,
      now: now,
      alignEnd: alignEnd,
      onOpenCalendar: onOpenCalendar,
      calendarNote: calendarNote,
    );
  }

  @override
  State<MediaCountdown> createState() => _MediaCountdownState();
}

class _MediaCountdownState extends State<MediaCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  // Les tables ne peuvent pas appeler tr() : c'est l'affichage qui traduit.
  static const _frenchWeekdays = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];

  static const _frenchMonths = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 2.8).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOut,
      ),
    );
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.55, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 70.0,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 30.0,
      ),
    ]).animate(_pulseController);

    if (widget.model.kind == CountdownKind.next ||
        widget.model.kind == CountdownKind.release) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(MediaCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldPulse = widget.model.kind == CountdownKind.next ||
        widget.model.kind == CountdownKind.release;
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Widget _buildDot(BuildContext context) {
    const dotSize = 7.0;
    const dotColor = Color(0xFF85C174);

    if (widget.model.kind == CountdownKind.last) {
      return Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFA8A5A1),
            width: 1.5,
          ),
        ),
      );
    }

    final reduced = AppMotion.reduced(context);
    return SizedBox(
      width: dotSize,
      height: dotSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (!reduced)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: dotSize,
                      height: dotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            dotColor.withValues(alpha: _opacityAnimation.value),
                      ),
                    ),
                  );
                },
              ),
            ),
          Container(
            width: dotSize,
            height: dotSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final target = CountdownModel.parseDay(model.target);
    if (target == null) return const SizedBox.shrink();

    final clock = widget.now ?? DateTime.now();
    final today = DateTime.utc(clock.year, clock.month, clock.day);
    final left = target.difference(today).inDays;

    if (model.kind != CountdownKind.last && left < 0) {
      return const SizedBox.shrink();
    }

    final compact = AppLayout.isCompact(context);
    final alignEnd = widget.alignEnd ?? !compact;

    final sameYear = target.year == today.year;
    final monthLabel = tr(_frenchMonths[target.month - 1]);
    final dayMonth = sameYear
        ? tr('{0} {1}', [target.day, monthLabel])
        : tr('{0} {1} {2}', [target.day, monthLabel, target.year]);

    String big;
    String line1;
    String line2;

    if (model.kind == CountdownKind.last) {
      big = tr('Fin');
      line1 = tr('diffusé le');
      line2 = tr('{0} {1} {2}', [target.day, monthLabel, target.year]);
    } else if (left == 0) {
      big = tr('Jour J');
      line1 = tr('aujourd’hui');
      line2 = dayMonth;
    } else {
      big = tr('J-{0}', [left]);
      line1 =
          left == 1 ? tr('demain') : tr(_frenchWeekdays[target.weekday - 1]);
      line2 = dayMonth;
    }

    double progress = 1.0;
    if (model.kind != CountdownKind.last) {
      final span =
          model.from != null && CountdownModel.parseDay(model.from) != null
              ? CountdownModel.daysBetween(model.from!, model.target)
              : 60;
      final raw = span > 0 ? (1.0 - left / span) : 1.0;
      progress = raw.clamp(0.04, 1.0);
    }

    final crossAxis =
        alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Semantics(
      label: tr('{0} : {1}, {2} {3}, {4}',
          [model.label, big, line1, line2, model.caption]),
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              const Color(0xFF0C0D0D).withValues(alpha: 0.62),
              Colors.transparent,
            ],
          ),
        ),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: crossAxis,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Pastille + surtitre en capitales espacées
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDot(context),
                  const SizedBox(width: 8),
                  Text(
                    model.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: Color(0xFFA8A5A1),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 10),

              // 2. Chiffre géant épuré + filet vertical + date
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    big,
                    style: TextStyle(
                      fontSize: compact
                          ? AppType.countdownCompact
                          : AppType.countdown,
                      fontWeight: FontWeight.w200,
                      height: 0.9,
                      letterSpacing: -2.5,
                      color: const Color(0xFFF2F0ED),
                      shadows: const [
                        Shadow(
                          color: Color(0x80000000),
                          blurRadius: 24,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Container(
                    width: 1,
                    height: compact ? 38 : 44,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        line1,
                        style: TextStyle(
                          fontSize: compact ? AppType.body : AppType.callout,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: const Color(0xFFDFDCD9),
                        ),
                      ),
                      Text(
                        line2,
                        style: TextStyle(
                          fontSize: compact ? AppType.body : AppType.callout,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                          color: const Color(0xFFDFDCD9),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 10),

              // 3. Barre lumineuse pleine largeur du bloc
              SizedBox(
                height: 3,
                child: Stack(
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0x59F2F0ED),
                              Color(0xFFF2F0ED),
                            ],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66F2F0ED),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 8 : 10),

              // 4. Légende de l'épisode / statut
              Text(
                model.caption,
                style: const TextStyle(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (widget.onOpenCalendar != null) ...[
                const SizedBox(height: 10),
                _CalendarJumpLink(
                  onTap: widget.onOpenCalendar!,
                  note: widget.calendarNote,
                  alignEnd: alignEnd,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarJumpLink extends StatelessWidget {
  const _CalendarJumpLink({
    required this.onTap,
    required this.note,
    required this.alignEnd,
  });

  final VoidCallback onTap;
  final String? note;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final link = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          AppIcons.calendar,
          size: 14,
          color: AppColors.textPrimary,
        ),
        const SizedBox(width: 6),
        Text(
          tr('Voir dans le calendrier'),
          style: const TextStyle(
            fontSize: AppType.footnote,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 2),
        const Icon(
          AppIcons.chevronRight,
          size: 14,
          color: AppColors.textSecondary,
        ),
      ],
    );

    final interactive = TvScope.of(context)
        ? TvFocusable(
            borderRadius: BorderRadius.circular(8),
            onSelect: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: link,
            ),
          )
        : InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: link,
            ),
          );

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        interactive,
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            style: const TextStyle(
              fontSize: AppType.caption,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
