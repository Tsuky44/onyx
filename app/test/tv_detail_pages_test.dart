import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/tv/nav/tv_nav_engine.dart';
import 'package:onyx/tv/nav/tv_sections_scroll.dart';

import 'support/tv_detail_bench.dart';
import 'support/tv_nav_harness.dart';

/// Les fiches de la bibliothèque à la télécommande (ADR-0128) : les vrais
/// écrans, à l'échelle d'un téléviseur, sur les deux systèmes de navigation
/// tant que le drapeau `ONYX_TV_NAV` existe.
///
/// Ce que ces tests tiennent, vu sur Apple TV avant eux : le focus s'ouvrait
/// sur le bouton retour d'une série ; depuis ce bouton, Bas sautait
/// « Lecture » et la distribution pour une section plus bas, et Haut y
/// ramenait toujours, jamais sur « Lecture » ; la page montait et redescendait
/// d'un pas à l'autre.

const _up = TraversalDirection.up;
const _down = TraversalDirection.down;
const _right = TraversalDirection.right;

const _focused = TvDetailBench.focused;
const _section = TvDetailBench.focusedSection;

void main() {
  setUp(TvDetailBench.setUp);

  TvNavHarness.forEachEngine((engine) {
    group('fiche d’un film', () {
      testWidgets(
          'à l’ouverture, la télécommande est sur la lecture et la page '
          'tout en haut', (tester) async {
        await TvDetailBench.pumpMovie(tester, engine: engine);
        expect(_focused(), 'Reprendre');
        expect(TvDetailBench.offset(tester), 0);
      });

      testWidgets(
          'Bas descend la fiche section par section, Haut la remonte par le '
          'même chemin', (tester) async {
        final nav = await TvDetailBench.pumpMovie(tester, engine: engine);

        final down = <String?>[];
        for (var i = 0; i < 3; i++) {
          await TvDetailBench.press(tester, nav, _down);
          down.add(_section());
        }
        expect(down, ['info', 'collection', 'similar']);
        expect(_focused(), 'Similaire 0');

        final up = <String?>[];
        for (var i = 0; i < 3; i++) {
          await TvDetailBench.press(tester, nav, _up);
          up.add(_section());
        }
        expect(up, ['collection', 'info', 'hero']);
        expect(_focused(), 'Reprendre');
      });

      testWidgets(
          'depuis le bouton retour, Bas mène à la lecture, pas à une '
          'section plus bas', (tester) async {
        final nav = await TvDetailBench.pumpMovie(tester, engine: engine);
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Retour');

        await TvDetailBench.press(tester, nav, _down);
        expect(_focused(), 'Reprendre');
      });

      testWidgets(
          'en remontant dans l’en-tête, on arrive toujours sur la lecture, '
          'quelle que soit l’action ou le bouton quitté', (tester) async {
        final nav = await TvDetailBench.pumpMovie(tester, engine: engine);

        // Parti d'une action voisine.
        await TvDetailBench.press(tester, nav, _right);
        expect(_focused(), 'Marquer vu');
        await TvDetailBench.press(tester, nav, _down);
        expect(_section(), 'info');
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Reprendre');

        // Passé par le bouton retour : c'était le piège, Haut y ramenait
        // toujours ensuite.
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Retour');
        await TvDetailBench.press(tester, nav, _down);
        await TvDetailBench.press(tester, nav, _down);
        expect(_section(), 'info');
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Reprendre');
      });

      testWidgets(
          'un synopsis coupé est une ligne de l’en-tête, entre le bouton '
          'retour et les actions', (tester) async {
        final nav = await TvDetailBench.pumpMovie(
          tester,
          engine: engine,
          api: TvDetailApi(overview: 'Un résumé qui ne tient pas. ' * 30),
        );
        expect(_focused(), 'Reprendre');

        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), startsWith('Un résumé'));
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Retour');
        await TvDetailBench.press(tester, nav, _down);
        expect(_focused(), startsWith('Un résumé'));
        await TvDetailBench.press(tester, nav, _down);
        expect(_focused(), 'Reprendre');
        expect(TvDetailBench.offset(tester), 0,
            reason: 'aucune ligne de l’en-tête ne fait défiler la page');
      });

      testWidgets(
          'chaque ligne a une seule place : la page s’y pose d’où qu’on '
          'vienne, la section calée en haut de l’écran', (tester) async {
        final nav = await TvDetailBench.pumpMovie(tester, engine: engine);

        final goingDown = <String, double>{};
        for (var i = 0; i < 3; i++) {
          await TvDetailBench.press(tester, nav, _down);
          goingDown[_section()!] = TvDetailBench.offset(tester);
        }
        expect(
          TvDetailBench.sectionTop(tester, 'similar'),
          lessThan(TvDetailBench.screenHeight(tester) / 2),
          reason: 'la dernière section est montrée en entier',
        );

        final goingUp = <String, double>{};
        for (var i = 0; i < 3; i++) {
          await TvDetailBench.press(tester, nav, _up);
          goingUp[_section()!] = TvDetailBench.offset(tester);
          if (_section() == 'info') {
            expect(
              TvDetailBench.sectionTop(tester, 'info'),
              moreOrLessEquals(TvSectionsScroll.topMargin, epsilon: 1),
              reason: 'la distribution se cale à la marge du haut',
            );
          }
        }
        expect(goingUp['hero'], 0, reason: 'l’en-tête pose la page en haut');
        expect(goingUp['info'], goingDown['info']);
        expect(goingUp['collection'], goingDown['collection']);
      });

      testWidgets('la ligne focalisée est toujours entière à l’écran',
          (tester) async {
        final nav = await TvDetailBench.pumpMovie(tester, engine: engine);
        final height = TvDetailBench.screenHeight(tester);
        for (final direction in [_down, _down, _down, _up, _up, _up, _up]) {
          await TvDetailBench.press(tester, nav, direction);
          final rect = TvDetailBench.focusedRect();
          expect(rect.top, greaterThanOrEqualTo(0), reason: '${_focused()}');
          expect(rect.bottom, lessThanOrEqualTo(height),
              reason: '${_focused()}');
        }
      });

      testWidgets(
          'dans la distribution, gauche et droite changent de carte sans '
          'déplacer la page', (tester) async {
        final nav = await TvDetailBench.pumpMovie(tester, engine: engine);
        await TvDetailBench.press(tester, nav, _down);
        expect(_focused(), 'A0');
        final rest = TvDetailBench.offset(tester);

        await TvDetailBench.press(tester, nav, _right);
        expect(_focused(), 'A1');
        await TvDetailBench.press(tester, nav, _right);
        expect(_focused(), 'A2');
        expect(TvDetailBench.offset(tester), rest);
      });

      testWidgets(
          'sur un téléviseur, les flèches de la distribution ne sont pas '
          'deux crans de plus sous la lecture', (tester) async {
        await TvDetailBench.pumpMovie(tester, engine: engine);
        expect(find.text('Distribution'), findsOneWidget);
        expect(find.byTooltip('Acteur suivant'), findsNothing);
      });
    });

    group('fiche d’une série', () {
      testWidgets('à l’ouverture, la télécommande est sur la lecture',
          (tester) async {
        await TvDetailBench.pumpShow(tester, engine: engine);
        expect(_focused(), 'Lecture S1 E1');
        expect(TvDetailBench.offset(tester), 0);
      });

      testWidgets(
          'la pastille de lecture, arrivée après l’ouverture, reprend le '
          'focus resté sur le bouton retour', (tester) async {
        await TvDetailBench.pumpShow(
          tester,
          engine: engine,
          api: TvDetailApi(resumeDelay: const Duration(milliseconds: 400)),
        );
        // L'épisode à lire n'est pas encore connu : pas de pastille.
        expect(find.text('Lecture S1 E1'), findsNothing);
        expect(_focused(), isNot('Lecture S1 E1'));

        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(_focused(), 'Lecture S1 E1');
      });

      testWidgets(
          'la pastille arrivée en retard ne reprend pas le focus à qui est '
          'déjà descendu dans la page', (tester) async {
        final nav = await TvDetailBench.pumpShow(
          tester,
          engine: engine,
          api: TvDetailApi(resumeDelay: const Duration(milliseconds: 400)),
        );
        await TvDetailBench.focusOn(tester, 'Saison 1');
        expect(_section(), 'seasons');

        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.text('Lecture S1 E1'), findsOneWidget);
        expect(_focused(), 'Saison 1');

        // Et la lecture reste à un pas : Haut y mène.
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Lecture S1 E1');
      });

      testWidgets(
          'Bas descend : saisons, « marquer vue », épisodes un à un, '
          'distribution, titres similaires ; Haut remonte par le même '
          'chemin', (tester) async {
        final nav = await TvDetailBench.pumpShow(tester, engine: engine);
        final path = <String>[
          'Saison 1',
          'Marquer la saison vue',
          'Télécharger la saison',
          for (var n = 1; n <= TvDetailBench.episodeCount; n++) 'Épisode $n',
          'A0',
          'Similaire 0',
        ];

        for (final stop in path) {
          await TvDetailBench.press(tester, nav, _down);
          expect(_focused(), stop);
        }
        for (final stop in path.reversed.skip(1)) {
          await TvDetailBench.press(tester, nav, _up);
          expect(_focused(), stop);
        }
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Lecture S1 E1');
        expect(TvDetailBench.offset(tester), 0);
      });

      testWidgets(
          'les lignes d’une courte section partagent sa place, et une '
          'longue liste défile ligne à ligne', (tester) async {
        final nav = await TvDetailBench.pumpShow(tester, engine: engine);
        final offsets = <String, double>{};
        Future<void> down() async {
          await TvDetailBench.press(tester, nav, _down);
          offsets[_focused()!] = TvDetailBench.offset(tester);
        }

        for (var i = 0; i < 3 + TvDetailBench.episodeCount; i++) {
          await down();
        }

        // Les saisons : une seule place pour les bulles et leur bouton.
        expect(offsets['Saison 1'], greaterThan(0));
        expect(offsets['Marquer la saison vue'], offsets['Saison 1']);

        // Les épisodes : l'en-tête de la liste et ses premières lignes ne
        // font rien défiler, puis chaque ligne fait monter la page de sa
        // hauteur.
        final header = offsets['Télécharger la saison']!;
        expect(header, greaterThan(offsets['Saison 1']!));
        expect(offsets['Épisode 1'], header);
        expect(offsets['Épisode 2'], header);
        final last = TvDetailBench.episodeCount;
        final pitch = offsets['Épisode $last']! - offsets['Épisode ${last - 1}']!;
        expect(pitch, greaterThan(100));
        expect(
          offsets['Épisode ${last - 1}']! - offsets['Épisode ${last - 2}']!,
          moreOrLessEquals(pitch, epsilon: 0.5),
        );

        // La ligne focalisée d'une longue liste se tient à la même hauteur,
        // la suivante visible dessous.
        final rect = TvDetailBench.focusedRect();
        expect(
          rect.bottom,
          moreOrLessEquals(
            TvDetailBench.screenHeight(tester) * TvSectionsScroll.focusBottom,
            epsilon: 1,
          ),
        );

        // Et la même place au retour.
        await TvDetailBench.press(tester, nav, _up);
        expect(TvDetailBench.offset(tester), offsets['Épisode ${last - 1}']);
      });

      testWidgets(
          'on entre dans les saisons par la saison affichée, et l’on y '
          'retrouve la bulle quittée', (tester) async {
        final nav = await TvDetailBench.pumpShow(tester, engine: engine);
        // Depuis une action plus à droite que les bulles.
        await TvDetailBench.press(tester, nav, _right);
        await TvDetailBench.press(tester, nav, _down);
        expect(_focused(), 'Saison 1');

        await TvDetailBench.press(tester, nav, _right);
        await TvDetailBench.press(tester, nav, _right);
        expect(_focused(), 'Saison 3');
        await TvDetailBench.press(tester, nav, _down);
        expect(_focused(), 'Marquer la saison vue');
        await TvDetailBench.press(tester, nav, _up);
        expect(_focused(), 'Saison 3');
      });
    });
  });

  testWidgets('hors téléviseur, la distribution garde ses flèches',
      (tester) async {
    await TvDetailBench.pumpMovie(
      tester,
      engine: TvNavEngine.legacy,
      isTv: false,
    );
    expect(find.byTooltip('Acteur suivant'), findsOneWidget);
  });
}
