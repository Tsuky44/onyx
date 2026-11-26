import '../models/retro.dart';
import 'tr.dart';

/// Les noms des profils du Rétro et la phrase qui les justifie.
///
/// Onyx ne connaît pas le genre de ses membres : chaque nom se lit tel quel,
/// sans accord ni forme inclusive (ADR 2026-11-26-tsuky-retro-annuel).
String retroArchetypeName(RetroArchetype archetype) => switch (archetype) {
      RetroArchetype.marathon => tr('Accro aux marathons'),
      RetroArchetype.nightOwl => tr('Oiseau de nuit'),
      RetroArchetype.cinephile => tr('Cinéphile'),
      RetroArchetype.explorer => tr('Touche-à-tout'),
      RetroArchetype.weekend => tr('Fidèle du dimanche'),
      RetroArchetype.goodAudience => tr('Bon public'),
    };

/// La phrase sous le nom : le chiffre qui a fait le profil.
String retroArchetypeReason(RetroReport report) {
  int percent(double share) => (share * 100).round();
  switch (report.archetype) {
    case RetroArchetype.marathon:
      final marathon = report.marathon;
      if (marathon == null) break;
      return tr('{0} épisodes de {1} en une seule journée.',
          [marathon.episodes, marathon.title]);
    case RetroArchetype.nightOwl:
      return tr('{0} % de ton temps entre 22 h et 4 h.',
          [percent(report.nightShare)]);
    case RetroArchetype.cinephile:
      return tr('{0} % de ton temps passé sur des films.',
          [percent(report.movieShare)]);
    case RetroArchetype.explorer:
      return tr('{0} titres différents commencés cette année.',
          [report.titles]);
    case RetroArchetype.weekend:
      return tr('{0} % de ton temps le samedi et le dimanche.',
          [percent(report.weekendShare)]);
    case RetroArchetype.goodAudience:
      break;
  }
  return tr('Un peu de tout, toujours au bon moment.');
}
