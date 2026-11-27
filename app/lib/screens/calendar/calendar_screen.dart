import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../desktop_window.dart';
import '../../../models/calendar.dart';
import '../../../providers/calendar_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../tv/tv_mode.dart';
import 'widgets/calendar_agenda_view.dart';
import 'widgets/calendar_display_view.dart';
import 'widgets/calendar_month_view.dart';
import 'widgets/calendar_week_view.dart';

/// Onglet « À venir » : calendrier personnel des prochaines sorties.
///
/// S'adapte au format de l'écran selon la maquette :
/// - TV (`TvScope`) : vue **D · Affiche** (hero + rangées navigables au D-pad) ;
/// - Téléphone (`< 700 px`) : vue **A · Agenda** ;
/// - Bureau et tablette (`>= 700 px`) : bascule entre **B · Semaine** et **C · Mois**.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, this.embedded = false});

  /// Sous l'en-tête de la coquille large : le contenu commence plus bas.
  final bool embedded;

  /// Seuil choisi dans la maquette entre Agenda mobile et Semaine bureau.
  static const double desktopBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final isTv = TvScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final topInset = embedded
        ? shellHeaderHeight(context)
        : MediaQuery.paddingOf(context).top + 56;

    Widget child;
    if (isTv) {
      child = CalendarDisplayView(topInset: topInset);
    } else if (width < desktopBreakpoint) {
      child = CalendarAgendaView(topInset: topInset);
    } else {
      final mode = context.select<CalendarProvider, CalendarViewMode>(
        (c) => c.desktopMode,
      );
      child = switch (mode) {
        CalendarViewMode.week => CalendarWeekView(topInset: topInset),
        CalendarViewMode.month => CalendarMonthView(topInset: topInset),
      };
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: child,
    );
  }
}
