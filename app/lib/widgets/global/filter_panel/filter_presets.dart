import '../../../l10n/tr.dart';

/// Un choix rapide d'une plage (période ou durée) : un libellé et ses deux
/// bornes, vides quand la plage est ouverte de ce côté.
typedef FilterRangePreset = ({String label, String from, String to});

/// Les décennies du panneau des filtres, en dates `AAAA-MM-JJ`. Dans les
/// Demandes, le champ précis reste derrière « Dates précises ».
List<FilterRangePreset> filterPeriodPresets() => [
      (label: tr('Depuis 2020'), from: '2020-01-01', to: ''),
      (label: tr('2010 – 2019'), from: '2010-01-01', to: '2019-12-31'),
      (label: tr('2000 – 2009'), from: '2000-01-01', to: '2009-12-31'),
      (label: tr('Avant 2000'), from: '', to: '1999-12-31'),
    ];

/// Les tranches de durée du panneau des filtres, en minutes.
List<FilterRangePreset> filterDurationPresets() => [
      (label: tr('Moins de 1 h 30'), from: '', to: '90'),
      (label: tr('1 h 30 à 2 h'), from: '90', to: '120'),
      (label: tr('Plus de 2 h'), from: '120', to: ''),
    ];

/// Le choix rapide qui correspond exactement à [from]–[to], ou nul : une
/// plage saisie à la main n'allume aucune capsule.
FilterRangePreset? matchingPreset(
    List<FilterRangePreset> presets, String from, String to) {
  for (final p in presets) {
    if (p.from == from && p.to == to) return p;
  }
  return null;
}

/// La valeur d'une plage sous le titre de sa section : le libellé d'un
/// choix rapide, sinon la plage telle que les capsules des Demandes
/// l'écrivent (« Dès 2015-01-01 », « 90 – 150 min ») ; [none] quand rien
/// n'est posé.
String filterRangeLabel(List<FilterRangePreset> presets, String from, String to,
    String unit, String none) {
  if (from.isEmpty && to.isEmpty) return none;
  final preset = matchingPreset(presets, from, to);
  if (preset != null) return preset.label;
  final suffix = unit.isEmpty ? '' : ' $unit';
  if (from.isNotEmpty && to.isNotEmpty) return '$from – $to$suffix';
  if (from.isNotEmpty) return tr('Dès {0}', ['$from$suffix']);
  return tr('Jusqu’à {0}', ['$to$suffix']);
}
