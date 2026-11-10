import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/media_details.dart';
import 'package:onyx/widgets/global/media_countdown.dart';

void main() {
  group('CountdownModel', () {
    final fixedNow = DateTime.utc(2026, 11, 7); // Samedi 7 novembre 2026

    test('forShow avec un prochain épisode à venir', () {
      final model = CountdownModel.forShow(
        nextEpisode: const EpisodeAirRef(
          airDate: '2026-11-13',
          episodeNumber: 9,
          seasonNumber: 2,
        ),
        lastEpisode: const EpisodeAirRef(
          airDate: '2026-11-06',
          episodeNumber: 8,
          seasonNumber: 2,
        ),
        status: 'Returning Series',
        now: fixedNow,
      );

      expect(model, isNotNull);
      expect(model!.kind, CountdownKind.next);
      expect(model.label, 'Prochain épisode');
      expect(model.target, '2026-11-13');
      expect(model.from, '2026-11-06');
      expect(model.caption, 'Saison 2 · Épisode 9');
    });

    test('forShow avec série terminée (Ended)', () {
      final model = CountdownModel.forShow(
        nextEpisode: null,
        lastEpisode: const EpisodeAirRef(
          airDate: '2021-05-23',
          episodeNumber: 10,
          seasonNumber: 5,
        ),
        status: 'Ended',
        now: fixedNow,
      );

      expect(model, isNotNull);
      expect(model!.kind, CountdownKind.last);
      expect(model.label, 'Dernier épisode');
      expect(model.target, '2021-05-23');
      expect(model.caption, 'Saison 5 · Épisode 10');
    });

    test('forShow avec date de prochain épisode dépassée retourne null', () {
      final model = CountdownModel.forShow(
        nextEpisode: const EpisodeAirRef(
          airDate: '2026-10-31',
          episodeNumber: 7,
          seasonNumber: 2,
        ),
        status: 'Returning Series',
        now: fixedNow,
      );

      expect(model, isNull);
    });

    test(
        'forShow en cours sans prochain épisode ni statut terminé retourne null',
        () {
      final model = CountdownModel.forShow(
        nextEpisode: null,
        lastEpisode: const EpisodeAirRef(
          airDate: '2026-05-01',
          episodeNumber: 10,
          seasonNumber: 1,
        ),
        status: 'Returning Series',
        now: fixedNow,
      );

      expect(model, isNull);
    });

    test('forMovie avec film à venir', () {
      final model = CountdownModel.forMovie(
        releaseDate: '2026-12-25',
        now: fixedNow,
      );

      expect(model, isNotNull);
      expect(model!.kind, CountdownKind.release);
      expect(model.label, 'Sortie');
      expect(model.target, '2026-12-25');
      expect(model.caption, 'Film à venir');
    });

    test('forMovie avec film déjà sorti retourne null', () {
      final model = CountdownModel.forMovie(
        releaseDate: '2024-05-15',
        now: fixedNow,
      );

      expect(model, isNull);
    });

    test('daysBetween calcule l’écart exact en jours', () {
      expect(CountdownModel.daysBetween('2026-11-07', '2026-11-13'), 6);
      expect(CountdownModel.daysBetween('2026-11-07', '2026-11-07'), 0);
      expect(CountdownModel.daysBetween('2026-11-07', '2026-11-06'), -1);
    });
  });

  group('MediaCountdown Widget', () {
    final fixedNow = DateTime.utc(2026, 11, 7);

    testWidgets('affiche J-6, vendredi, 13 novembre pour le prochain épisode',
        (tester) async {
      const model = CountdownModel(
        kind: CountdownKind.next,
        label: 'Prochain épisode',
        target: '2026-11-13',
        from: '2026-11-06',
        caption: 'Saison 2 · Épisode 9',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaCountdown(
                model: model,
                now: fixedNow,
              ),
            ),
          ),
        ),
      );

      // Label en majuscules
      expect(find.text('PROCHAIN ÉPISODE'), findsOneWidget);
      // Chiffre géant
      expect(find.text('J-6'), findsOneWidget);
      // Jour de semaine
      expect(find.text('vendredi'), findsOneWidget);
      // Jour et mois
      expect(find.text('13 novembre'), findsOneWidget);
      // Légende
      expect(find.text('Saison 2 · Épisode 9'), findsOneWidget);
    });

    testWidgets('affiche Jour J et aujourd’hui le jour même', (tester) async {
      const model = CountdownModel(
        kind: CountdownKind.next,
        label: 'Prochain épisode',
        target: '2026-11-07',
        caption: 'Saison 2 · Épisode 10',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaCountdown(
                model: model,
                now: fixedNow,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Jour J'), findsOneWidget);
      expect(find.text("aujourd'hui"), findsOneWidget);
      expect(find.text('7 novembre'), findsOneWidget);
    });

    testWidgets(
        'affiche Fin, diffusé le et date complète pour une série terminée',
        (tester) async {
      const model = CountdownModel(
        kind: CountdownKind.last,
        label: 'Dernier épisode',
        target: '2021-05-23',
        caption: 'Saison 5 · Épisode 10',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaCountdown(
                model: model,
                now: fixedNow,
              ),
            ),
          ),
        ),
      );

      expect(find.text('DERNIER ÉPISODE'), findsOneWidget);
      expect(find.text('Fin'), findsOneWidget);
      expect(find.text('diffusé le'), findsOneWidget);
      expect(find.text('23 mai 2021'), findsOneWidget);
      expect(find.text('Saison 5 · Épisode 10'), findsOneWidget);
    });

    testWidgets('fromDetails retourne un widget si applicable, sinon null',
        (tester) async {
      final widgetPresent = MediaCountdown.fromDetails(
        isTv: true,
        nextEpisode: const EpisodeAirRef(
          airDate: '2026-11-13',
          episodeNumber: 9,
          seasonNumber: 2,
        ),
        now: fixedNow,
      );
      expect(widgetPresent, isNotNull);

      final widgetAbsent = MediaCountdown.fromDetails(
        isTv: true,
        nextEpisode: null,
        status: 'Returning Series',
        now: fixedNow,
      );
      expect(widgetAbsent, isNull);
    });
  });
}
