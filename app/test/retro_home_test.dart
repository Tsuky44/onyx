import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:onyx/models/retro.dart';
import 'package:onyx/providers/retro_provider.dart';
import 'package:onyx/screens/retro/home/retro_hero_slide.dart';
import 'package:onyx/screens/retro/home/retro_home_card.dart';
import 'package:onyx/screens/retro/home/retro_ring.dart';
import 'package:onyx/services/api_client.dart';
import 'package:onyx/tv/tv_mode.dart';
import 'package:onyx/widgets/global/hero_carousel.dart';

RetroReport _report() => RetroReport.fromJson({
      'year': 2026,
      'eligible': true,
      'watched_seconds': 312 * 3600,
      'plays': 410,
      'titles': 27,
      'top': [
        for (final title in const ['Severance', 'The Bear', 'Shōgun'])
          {
            'media_id': 1,
            'title': title,
            'media_type': 'show',
            'poster_url': '',
            'watched_seconds': 3600,
            'episodes': 3,
            'times': 0,
          },
      ],
      'months': List.filled(12, 3600),
      'hours': List.filled(24, 3600),
      'weekdays': List.filled(7, 3600),
      'archetype': 'marathon',
      'server': {'members': 1, 'rank': 1},
    });

RetroStatus _status(
        {bool open = true, bool eligible = true, bool seen = false}) =>
    RetroStatus(
      year: 2026,
      open: open,
      eligible: eligible,
      seen: seen,
      endsAt: DateTime(2027, 1, 16),
    );

/// Un serveur qui rend un état du Rétro choisi, sans réseau.
class _Server extends ApiClient {
  _Server(this.status);
  RetroStatus status;
  int reports = 0;

  @override
  Future<RetroStatus?> getRetroStatus() async => status;

  @override
  Future<RetroReport> getRetro(int year) async {
    reports++;
    return _report();
  }

  @override
  Future<void> markRetroSeen(int year) async {}
}

Widget _app(Widget child, {bool tv = false}) => MaterialApp(
      home: TvScope(isTv: tv, child: Scaffold(body: child)),
    );

void main() {
  group('où le Rétro se montre sur l’accueil', () {
    test('rien hors saison ni sous le seuil', () async {
      for (final status in [_status(open: false), _status(eligible: false)]) {
        final retro = RetroProvider(_Server(status));
        await retro.load();
        expect(retro.showsHero, isFalse);
        expect(retro.showsCard, isFalse);
        expect(retro.showsRing, isFalse);
      }
    });

    test('avant : la diapo et l’anneau, et le Rétro se charge pour eux',
        () async {
      final server = _Server(_status());
      final retro = RetroProvider(server);
      await retro.load();
      expect(retro.showsHero, isTrue);
      expect(retro.showsRing, isTrue);
      expect(retro.showsCard, isFalse);
      expect(server.reports, 1);
      expect(retro.report?.titles, 27);
    });

    test('« Plus tard » range la diapo, la carte prend le relais', () async {
      final retro = RetroProvider(_Server(_status()));
      await retro.load();
      retro.later();
      expect(retro.showsHero, isFalse);
      expect(retro.showsCard, isTrue);
      expect(retro.showsRing, isTrue,
          reason: 'seule l’ouverture de la story pose « vu »');
    });

    test('après : la carte seule', () async {
      final retro = RetroProvider(_Server(_status()));
      await retro.load();
      await retro.markSeen(2026);
      expect(retro.showsHero, isFalse);
      expect(retro.showsRing, isFalse);
      expect(retro.showsCard, isTrue);
    });
  });

  testWidgets('la diapo ouvre le Rétro ou se range', (tester) async {
    var opened = 0;
    var later = 0;
    await tester.pumpWidget(_app(HeroCarousel(
      slides: const [],
      onPlay: (_) {},
      leading: (context, autofocus) => RetroHeroSlide(
        status: _status(),
        report: _report(),
        name: 'Léa',
        serverBaseUrl: null,
        autofocus: autofocus,
        onOpen: () => opened++,
        onLater: () => later++,
      ),
    )));
    expect(find.text('Léa, ton année est prête.'), findsOneWidget);
    expect(find.textContaining('312 heures, 27 titres'), findsOneWidget);
    expect(find.textContaining('JUSQU’AU 15 JANVIER'), findsOneWidget);

    await tester.tap(find.text('Voir mon Rétro'));
    await tester.tap(find.text('Plus tard'));
    expect((opened, later), (1, 1));
  });

  testWidgets('au téléviseur, « Voir mon Rétro » a le focus d’office',
      (tester) async {
    await tester.pumpWidget(_app(
      HeroCarousel(
        slides: const [],
        onPlay: (_) {},
        autofocusPlay: true,
        leading: (context, autofocus) => RetroHeroSlide(
          status: _status(),
          report: null,
          name: 'Léa',
          serverBaseUrl: null,
          autofocus: autofocus,
          onOpen: () {},
          onLater: () {},
        ),
      ),
      tv: true,
    ));
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
      find.descendant(
          of: find.byWidget(focused!.widget),
          matching: find.text('Voir mon Rétro')),
      findsOneWidget,
    );
  });

  testWidgets('la carte dit « Revoir » une fois vu, et s’ouvre',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(_app(RetroHomeCard(
      status: _status(seen: true),
      report: _report(),
      name: 'Léa',
      serverBaseUrl: null,
      onOpen: () => opened++,
    )));
    expect(find.text('Revoir ton année'), findsOneWidget);
    expect(find.text('Accro aux marathons · 312 h'), findsOneWidget);
    expect(find.text('Partager'), findsOneWidget);
    await tester.tap(find.text('Revoir ton année'));
    expect(opened, 1);
  });

  testWidgets('au téléviseur, la carte ne propose pas de partager',
      (tester) async {
    await tester.pumpWidget(_app(
      RetroHomeCard(
        status: _status(seen: true),
        report: _report(),
        name: 'Léa',
        serverBaseUrl: null,
        onOpen: () {},
      ),
      tv: true,
    ));
    expect(find.text('Partager'), findsNothing);
  });

  testWidgets('l’anneau ne se dessine que tant que le Rétro attend',
      (tester) async {
    Widget ring(bool active) => _app(Center(
          child: RetroRing(
            active: active,
            diameter: 41,
            child: const SizedBox.square(dimension: 34),
          ),
        ));
    final painter = find.descendant(
        of: find.byType(RetroRing), matching: find.byType(CustomPaint));
    await tester.pumpWidget(ring(true));
    expect(painter, findsOneWidget);
    await tester.pumpWidget(ring(false));
    expect(painter, findsNothing);
  });
}
