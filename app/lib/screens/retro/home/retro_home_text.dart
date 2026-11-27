import '../../../l10n/locale_formats.dart';
import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../models/retro.dart';

/// Les phrases du Rétro sur l'accueil, partagées par la diapo et la carte.
abstract final class RetroHomeText {
  /// « Rétro 2026 · jusqu'au 15 janvier ». [RetroStatus.endsAt] est le
  /// premier instant où il ne se montre plus : on annonce la veille.
  static String kicker(RetroStatus status) {
    final ends = status.endsAt;
    if (ends == null) return tr('Rétro {0}', [status.year]);
    final last = ends.toLocal().subtract(const Duration(days: 1));
    return tr('Rétro {0} · jusqu’au {1}',
        [status.year, LocaleFormats.dayMonth(last)]);
  }

  /// « 312 heures, 27 titres et un profil rien qu'à toi. »
  static String teaser(RetroReport? report) => report == null
      ? tr('Tes heures, tes titres et un profil rien qu’à toi.')
      : tr('{0} heures, {1} titres et un profil rien qu’à toi.', [
          LocaleFormats.integer(report.hoursWatched.round()),
          report.titles,
        ]);

  /// « Pilier de canapé · 312 h ».
  static String? profile(RetroReport? report) => report == null
      ? null
      : tr('{0} · {1} h', [
          retroArchetypeName(report.archetype),
          LocaleFormats.integer(report.hoursWatched.round()),
        ]);
}
