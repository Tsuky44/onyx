import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../models/calendar.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../utils/poster_url.dart';
import '../../../widgets/global/app_network_image.dart';
import '../calendar_entry_launch.dart';

/// Utilitaires de formatage et briques visuelles partagés par les quatre vues
/// du calendrier (Agenda, Semaine, Mois, Affiche).
abstract final class CalendarFormat {
  static String weekdayShort(int weekday) {
    final labels = [
      tr('lun.'),
      tr('mar.'),
      tr('mer.'),
      tr('jeu.'),
      tr('ven.'),
      tr('sam.'),
      tr('dim.'),
    ];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  static String monthShort(int month) {
    final labels = [
      tr('janv.'),
      tr('févr.'),
      tr('mars'),
      tr('avr.'),
      tr('mai'),
      tr('juin'),
      tr('juil.'),
      tr('août'),
      tr('sept.'),
      tr('oct.'),
      tr('nov.'),
      tr('déc.'),
    ];
    return labels[(month - 1).clamp(0, 11)];
  }

  static String monthFull(int month) {
    final labels = [
      tr('Janvier'),
      tr('Février'),
      tr('Mars'),
      tr('Avril'),
      tr('Mai'),
      tr('Juin'),
      tr('Juillet'),
      tr('Août'),
      tr('Septembre'),
      tr('Octobre'),
      tr('Novembre'),
      tr('Décembre'),
    ];
    return labels[(month - 1).clamp(0, 11)];
  }

  static String dayHeader(DateTime day, DateTime today) {
    final n = day.difference(today).inDays;
    if (n == 0) return tr('Aujourd’hui');
    if (n == 1) return tr('Demain');
    final w = weekdayShort(day.weekday);
    final cap = w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';
    return tr('{0} {1} {2}', [cap, day.day, monthShort(day.month)]);
  }

  static String shortDayLabel(CalendarEntry entry, DateTime today) {
    final n = entry.date.difference(today).inDays;
    if (n == 0) {
      final t = entry.timeLabel;
      if (t != null && t.compareTo('18') > 0) return tr('Ce soir');
      return tr('Aujourd’hui');
    }
    if (n == 1) return tr('Demain');
    final w = weekdayShort(entry.date.weekday);
    final cap = w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}';
    return tr('{0} {1}', [cap, entry.date.day]);
  }

  static String relativeInDays(DateTime day, DateTime today) {
    final n = day.difference(today).inDays;
    if (n == 0) return tr('Aujourd’hui');
    if (n == 1) return tr('Demain');
    if (n > 1) return tr('dans {0} jours', [n]);
    return tr('il y a {0} jours', [-n]);
  }

  static String rangeLabel(DateTime start, DateTime end) {
    if (start.month == end.month) {
      return tr('{0} – {1} {2}', [start.day, end.day, monthShort(end.month)]);
    }
    return tr('{0} {1} – {2} {3}', [
      start.day,
      monthShort(start.month),
      end.day,
      monthShort(end.month),
    ]);
  }

  static String sourceLabel(CalendarSource source, {bool ready = false}) {
    if (ready) return tr('Disponible');
    return switch (source) {
      CalendarSource.watching => tr('En cours'),
      CalendarSource.followed => tr('Suivie'),
      CalendarSource.request => tr('Demandé'),
      CalendarSource.server => tr('Sur le serveur'),
    };
  }

  static String whyLabel(CalendarSource source) => switch (source) {
        CalendarSource.watching => tr('Vous regardez'),
        CalendarSource.followed => tr('Suivie par vous'),
        CalendarSource.request => tr('Demandé par vous'),
        CalendarSource.server => tr('Dans la bibliothèque'),
      };
}

/// Retourne le dégradé factice fidèle à la maquette pour un titre donné.
List<Color> calendarHueGradient(double hue) {
  final h1 = hue % 360;
  final h2 = (hue + 28) % 360;
  final h3 = (hue + 40) % 360;
  return [
    HSLColor.fromAHSL(1, h1, 0.42, 0.36).toColor(),
    HSLColor.fromAHSL(1, h2, 0.46, 0.14).toColor(),
    HSLColor.fromAHSL(1, h3, 0.40, 0.08).toColor(),
  ];
}

/// Affiche 2:3 ou vignette 16:9 d'une entrée du calendrier (image réseau si
/// disponible, sinon dégradé Quiet Premium avec titre optionnel).
class CalendarPoster extends StatelessWidget {
  const CalendarPoster({
    super.key,
    required this.title,
    required this.hue,
    this.posterUrl,
    this.serverBaseUrl,
    this.aspectRatio = 2 / 3,
    this.borderRadius = 10,
    this.showTitleOverlay = false,
    this.showPlayBadge = false,
    this.compactOverlay = false,
  });

  final String title;
  final double hue;
  final String? posterUrl;
  final String? serverBaseUrl;
  final double aspectRatio;
  final double borderRadius;
  final bool showTitleOverlay;
  final bool showPlayBadge;
  final bool compactOverlay;

  @override
  Widget build(BuildContext context) {
    final resolved = posterUrl != null
        ? resolvePosterUrl(posterUrl, serverBaseUrl: serverBaseUrl)
        : null;
    final colors = calendarHueGradient(hue);

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                  stops: const [0.0, 0.7, 1.0],
                ),
              ),
            ),
            if (resolved != null)
              AppNetworkImage(
                url: resolved,
                fit: BoxFit.cover,
                errorWidget: const SizedBox.shrink(),
              ),
            if (showTitleOverlay)
              Positioned(
                left: compactOverlay ? 6 : 8,
                right: compactOverlay ? 6 : 8,
                bottom: compactOverlay ? 6 : 8,
                child: Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compactOverlay ? AppType.micro : AppType.caption,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: 0.3,
                    color: AppColors.textPrimary.withValues(alpha: 0.94),
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            if (showPlayBadge)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    AppIcons.play,
                    size: 12,
                    color: AppColors.background,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pastille de statut / provenance d'une sortie (« En cours », « Suivie »,
/// « Demandé », « Sur le serveur », « Disponible »).
class CalendarSourcePill extends StatelessWidget {
  const CalendarSourcePill({
    super.key,
    required this.source,
    this.ready = false,
  });

  final CalendarSource source;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final label = CalendarFormat.sourceLabel(source, ready: ready);
    final isReadyOrServer = ready || source == CalendarSource.server;
    final isRequest = !ready && source == CalendarSource.request;
    final isWatching = !ready && source == CalendarSource.watching;

    final Color textColor;
    final Color bgColor;
    final Color borderColor;
    if (isReadyOrServer) {
      textColor = AppColors.success;
      bgColor = AppColors.glassFill;
      borderColor = AppColors.glassBorder;
    } else if (isRequest) {
      textColor = AppColors.accentMuted;
      bgColor = AppColors.request.withValues(alpha: 0.16);
      borderColor = AppColors.request.withValues(alpha: 0.35);
    } else if (isWatching) {
      textColor = AppColors.textPrimary;
      bgColor = AppColors.glassFill;
      borderColor = AppColors.glassBorder;
    } else {
      textColor = AppColors.textSecondary;
      bgColor = AppColors.glassFill;
      borderColor = AppColors.glassBorder;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: textColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton rond en verre utilisé dans l'en-tête Agenda (« Gérer les séries
/// suivies ») et pour la navigation entre semaines / mois.
class CalendarRoundIconButton extends StatelessWidget {
  const CalendarRoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.glassFill,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: iconSize, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Puce cliquable (« Semaine » / « Mois », ou filtre d'origine).
class CalendarChip extends StatelessWidget {
  const CalendarChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.textPrimary : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? AppColors.textPrimary : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: AnimatedContainer(
            duration: AppMotion.fade(context, AppMotion.micro),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppType.footnote,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.background : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ouvre la fiche d'une sortie (voir [openCalendarEntry]).
void notifyCalendarEntryTap(BuildContext context, CalendarEntry entry) {
  openCalendarEntry(context, entry);
}
