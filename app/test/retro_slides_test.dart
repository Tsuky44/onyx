import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:onyx/l10n/retro_archetypes.dart';
import 'package:onyx/models/retro.dart';
import 'package:onyx/screens/retro/slides/retro_slide.dart';
import 'package:onyx/screens/retro/slides/retro_slides.dart';

/// Un Rétro plausible : Léa, 312 h, Severance en tête.
RetroReport _report({
  Map<String, Object?>? marathon = const {
    'title': 'Severance',
    'date': '2026-03-14',
    'episodes': 9,
  },
  int members = 14,
  String archetype = 'marathon',
}) =>
    RetroReport.fromJson({
      'year': 2026,
      'eligible': true,
      'watched_seconds': 312 * 3600,
      'plays': 410,
      'titles': 27,
      'movie_seconds': 56 * 3600,
      'top': [
        for (final (title, type) in const [
          ('Severance', 'show'),
          ('The Bear', 'show'),
          ('Shōgun', 'show'),
          ('Slow Horses', 'show'),
          ('Dune : Deuxième partie, le très long titre d’un film', 'movie'),
        ])
          {
            'media_id': 1,
            'title': title,
            'media_type': type,
            'poster_url': '',
            'watched_seconds': 17 * 3600,
            'episodes': 19,
            'times': 2,
          },
      ],
      'months': [22, 31, 44, 26, 18, 12, 9, 14, 29, 38, 41, 0]
          .map((h) => h * 3600)
          .toList(),
      'hours': [for (var h = 0; h < 24; h++) h == 21 ? 40 * 3600 : 3 * 3600],
      'weekdays': [40, 40, 40, 40, 40, 60, 52].map((h) => h * 3600).toList(),
      'marathon': marathon,
      'first_play': {'title': 'Slow Horses', 'at': '2026-01-01T11:02'},
      'latest_night': {'title': 'The Bear', 'at': '2026-06-10T03:47'},
      'devices': [
        {'key': 'TV du salon', 'label': 'TV du salon', 'watched_seconds': 200 * 3600},
        {'key': 'iPhone', 'label': 'iPhone', 'watched_seconds': 70 * 3600},
        {'key': '', 'label': '', 'watched_seconds': 42 * 3600},
      ],
      'direct_percent': 93,
      'archetype': archetype,
      'server': {
        'members': members,
        'watched_seconds': 4820 * 3600,
        'rank': members > 1 ? 2 : 1,
        'top_title': 'Severance',
        'top_title_viewers': members > 1 ? 9 : 1,
      },
    });

void main() {
  test('le Rétro tire ses chiffres dérivés de la réponse', () {
    final r = _report();
    expect(r.peakHour, 21);
    expect(r.bestMonth, 3);
    expect(r.server.aheadOfPercent, 92);
    expect(r.months, hasLength(12));
    expect(RetroArchetype.parse('inconnu'), RetroArchetype.goodAudience,
        reason: 'un profil d’un serveur plus récent ne vide pas la carte');
  });

  test('chaque profil a un nom et une phrase', () {
    for (final archetype in RetroArchetype.values) {
      final r = _report(archetype: archetype.wire);
      expect(retroArchetypeName(archetype), isNotEmpty);
      expect(retroArchetypeReason(r), isNotEmpty);
    }
  });

  // La même story sur un téléphone, une fenêtre de PC et un téléviseur : aucun
  // écran ne déborde, avec ou sans marathon, seul ou nombreux sur le serveur.
  for (final (name, size) in const [
    ('téléphone', Size(390, 844)),
    ('PC', Size(1280, 800)),
    ('téléviseur', Size(1920, 1080)),
    ('petite fenêtre', Size(640, 480)),
  ]) {
    for (final (variant, report) in [
      ('complet', _report()),
      ('sans marathon, seul sur le serveur', _report(marathon: null, members: 1)),
    ]) {
      testWidgets('les dix écrans tiennent en $name ($variant)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = RetroStoryData(
          report: report,
          name: 'Léa',
          serverBaseUrl: 'http://maison.local',
        );
        for (final slide in kRetroSlides) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: Builder(builder: (c) => slide.build(c, data))),
          ));
          expect(tester.takeException(), isNull,
              reason: '${slide.runtimeType} en $name');
          expect(slide.summary(data), isNotEmpty);
        }
      });
    }
  }
}
