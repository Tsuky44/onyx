import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/l10n/app_language.dart';
import 'package:onyx/l10n/en.dart';
import 'package:onyx/l10n/tr.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/settings/widgets/about_group.dart';
import 'package:onyx/widgets/global/detail_info_table.dart';
import 'package:onyx/widgets/global/media_countdown.dart';

/// Lit à partir de [start] un ou plusieurs littéraux entre apostrophes collés
/// par juxtaposition. Renvoie la clé et l'index qui suit, ou `null` s'il n'y a
/// pas de littéral (un `tr(x)` sur une variable n'est pas contrôlé).
(String, int)? _literalAt(String source, int start) {
  var i = start;
  final key = StringBuffer();
  var found = false;
  while (i < source.length && source[i] == "'") {
    found = true;
    i++;
    while (source[i] != "'") {
      if (source[i] == r'\') {
        i++;
        key.write(switch (source[i]) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          final other => other,
        });
      } else {
        key.write(source[i]);
      }
      i++;
    }
    i++;
    while (i < source.length && ' \t\r\n'.contains(source[i])) {
      i++;
    }
  }
  return found ? (key.toString(), i) : null;
}

/// Les clés littérales passées à `tr(...)` dans [source], et les deux formes
/// d'un `trPlural(n, one, other)`.
Iterable<String> _keysIn(String source) sync* {
  final call = RegExp(r'(?<![A-Za-z0-9_.])tr\(\s*');
  for (final match in call.allMatches(source)) {
    final literal = _literalAt(source, match.end);
    if (literal != null) yield literal.$1;
  }
  final plural = RegExp(r'(?<![A-Za-z0-9_.])trPlural\(\s*[^,]+,\s*');
  for (final match in plural.allMatches(source)) {
    final one = _literalAt(source, match.end);
    if (one == null) continue;
    yield one.$1;
    var i = one.$2;
    if (i >= source.length || source[i] != ',') continue;
    i++;
    while (i < source.length && ' \t\r\n'.contains(source[i])) {
      i++;
    }
    final other = _literalAt(source, i);
    if (other != null) yield other.$1;
  }
}

void main() {
  tearDown(AppLanguage.resetForTest);

  // Une phrase ajoutée en français et oubliée dans le dictionnaire resterait
  // en français au milieu d'une interface anglaise, sans que rien ne casse.
  test('chaque texte passé à tr() a sa traduction anglaise', () {
    final missing = <String>{};
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.uri.path.contains('/l10n/'))) {
      for (final key in _keysIn(file.readAsStringSync())) {
        if (!kEnglish.containsKey(key)) missing.add('${file.uri.path}: $key');
      }
    }
    expect(missing, isEmpty,
        reason: 'ajoute ces clés à lib/l10n/en.dart (une entrée identique à '
            'sa clé convient pour un mot qui ne se traduit pas)');
  });

  // Un `{2}` présent en anglais et absent du français s'afficherait tel quel.
  test('une traduction ne réclame aucune valeur que sa clé n’a pas', () {
    final placeholder = RegExp(r'\{\d+\}');
    final broken = <String>[];
    kEnglish.forEach((french, english) {
      final offered = placeholder.allMatches(french).map((m) => m[0]).toSet();
      final wanted = placeholder.allMatches(english).map((m) => m[0]).toSet();
      if (!offered.containsAll(wanted)) broken.add(french);
    });
    expect(broken, isEmpty);
  });

  test('tr() rend le français tant que la langue est le français', () {
    expect(tr('Annuler'), 'Annuler');
    expect(tr('Saison {0}', [3]), 'Saison 3');
  });

  test('tr() traduit et place les valeurs quand la langue est l’anglais', () {
    AppLanguage.notifier.value = AppLanguage.english;

    expect(tr('Annuler'), 'Cancel');
    expect(tr('Saison {0}', [3]), 'Season 3');
    expect(tr('Texte absent du dictionnaire'), 'Texte absent du dictionnaire');
  });

  test('trPlural suit la règle de la langue : 0 est singulier en français',
      () {
    expect(trPlural(0, '{0} lecture', '{0} lectures'), '0 lecture');
    expect(trPlural(2, '{0} lecture', '{0} lectures'), '2 lectures');

    AppLanguage.notifier.value = AppLanguage.english;
    expect(trPlural(0, '{0} lecture', '{0} lectures'), '0 plays');
    expect(trPlural(1, '{0} lecture', '{0} lectures'), '1 play');
    expect(trPlural(5, '{0} lecture', '{0} lectures'), '5 plays');
  });

  // Les tables constantes (langues, mois, libellés d'énumérations) ne peuvent
  // pas appeler tr() : c'est leur point d'affichage qui traduit.
  test('une table constante est traduite à l’affichage', () {
    AppLanguage.notifier.value = AppLanguage.english;

    expect(languageName('fra'), 'French');
    expect(languageName('xx'), 'XX');
  });

  test('les libellés de langue et de pays du cartel se rendent en anglais', () {
    expect(formatLanguage('ja'), 'Japonais');
    expect(formatCountry('KR'), 'Corée du Sud');

    AppLanguage.notifier.value = AppLanguage.english;
    expect(formatLanguage('ja'), 'Japanese');
    expect(formatCountry('KR'), 'South Korea');
    expect(formatCountry('XX'), 'XX');
  });

  test('le modèle du compte à rebours se rend en anglais', () {
    AppLanguage.notifier.value = AppLanguage.english;
    final model = CountdownModel.forShow(
      nextEpisode: const EpisodeAirRef(
          seasonNumber: 2, episodeNumber: 9, airDate: '2030-01-10'),
      now: DateTime(2030, 1, 1),
    )!;
    expect(model.label, 'Next episode');
    expect(model.caption, 'Season 2 · Episode 9');
    expect(
        CountdownModel.episodeCaption(const EpisodeAirRef(
            seasonNumber: 0, episodeNumber: 0, airDate: '2030-01-10')),
        'New episode');
    expect(
        CountdownModel.forMovie(releaseDate: '2030-01-10', now: DateTime(2030))!
            .caption,
        'Upcoming movie');
  });

  testWidgets('un écran construit en anglais affiche l’anglais',
      (tester) async {
    AppLanguage.notifier.value = AppLanguage.english;
    addTearDown(AppLanguage.resetForTest);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AboutGroup())),
    ));

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('À propos'), findsNothing);
  });

  testWidgets('le compte à rebours affiche l’anglais', (tester) async {
    AppLanguage.notifier.value = AppLanguage.english;
    final model = CountdownModel.forShow(
      nextEpisode: const EpisodeAirRef(
          seasonNumber: 2, episodeNumber: 9, airDate: '2030-01-10'),
      now: DateTime(2030, 1, 1),
    )!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaCountdown(model: model, now: DateTime(2030, 1, 1)),
      ),
    ));

    expect(find.text('NEXT EPISODE'), findsOneWidget);
    expect(find.text('D-9'), findsOneWidget);
    expect(find.text('Thursday'), findsOneWidget);
    expect(find.text('January 10'), findsOneWidget);
    expect(find.text('Season 2 · Episode 9'), findsOneWidget);
    expect(find.text('PROCHAIN ÉPISODE'), findsNothing);

    // Le point pulse en boucle : on démonte pour que le test se termine.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('un appareil qui n’est pas en français reçoit l’anglais', () {
    expect(AppLanguage.forDevice(const Locale('fr', 'CA')), AppLanguage.french);
    expect(AppLanguage.forDevice(const Locale('de')), AppLanguage.english);
  });
}
