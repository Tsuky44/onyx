import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/pause_info_content.dart';
import 'package:onyx/screens/player/player_media_info.dart';
import 'package:onyx/screens/player/widgets/pause_info_overlay.dart';

/// Ce que dit l'écran « Vous regardez » d'un film en pause (ADR-0137).
void main() {
  final now = DateTime(2026, 11, 17, 22, 0);

  test('un film montre sa fiche : accroche, résumé, réalisation, distribution',
      () {
    final info = PlayerMediaInfo(Media(
      id: 9,
      type: MediaType.movie,
      title: 'Le Dernier Phare',
      duration: 7620,
      overview: 'Le résumé du fichier.',
      releaseDate: '2024-03-01',
      createdAt: DateTime(2024),
    ));
    final content = PauseInfoContent.from(
      info: info,
      details: MediaDetails(
        id: 9,
        type: MediaType.movie,
        title: 'Le Dernier Phare',
        tagline: 'Certaines lumières ne s’éteignent jamais.',
        overview: 'Le résumé de la fiche.',
        runtime: 127,
        voteAverage: 7.84,
        genres: const ['Drame', 'Thriller', 'Mystère'],
        director: 'Claire Varenne',
        cast: [
          CastMember(name: 'Inès Morel'),
          CastMember(name: 'Thomas Ardent'),
          CastMember(name: 'Jules Kerbrat'),
          CastMember(name: 'Quatrième rôle'),
        ],
      ),
      positionSeconds: 3300,
      durationSeconds: 7620,
      logoUrl: 'https://image.tmdb.org/t/p/w500/phare.png',
      now: now,
    );

    expect(content.isEpisode, isFalse);
    expect(content.title, 'Le Dernier Phare');
    // Le logo du chrome, plutôt que le titre écrit en toutes lettres.
    expect(content.logoUrl, 'https://image.tmdb.org/t/p/w500/phare.png');
    // Deux genres au plus : la ligne tient sur une ligne.
    expect(content.meta, ['2024', 'Drame, Thriller', '2h 7min']);
    expect(content.ratingLabel, '7.8');
    expect(content.overview, 'Le résumé de la fiche.');
    expect(content.director, 'Claire Varenne');
    expect(content.cast, 'Inès Morel, Thomas Ardent, Jules Kerbrat');
    expect(content.remaining, '1h 12min restantes');
    expect(content.endClock, '23:12');
    expect(content.progress, closeTo(0.433, 0.001));
  });

  test('sans fiche en cache, un film garde son titre et le résumé du média',
      () {
    final info = PlayerMediaInfo(Media(
      id: 9,
      type: MediaType.movie,
      title: 'Dune',
      duration: 600,
      overview: 'Sur Arrakis.',
      createdAt: DateTime(2024),
    ));
    final content = PauseInfoContent.from(
      info: info,
      positionSeconds: 0,
      durationSeconds: 0,
      now: now,
    );

    expect(content.title, 'Dune');
    expect(content.overview, 'Sur Arrakis.');
    expect(content.rating, isNull);
    expect(content.tagline, isNull);
    expect(content.logoUrl, isNull);
  });

  test(
      'un épisode montre le logo et la note de la série, son résumé, '
      'et l’image du suivant', () {
    final info = PlayerMediaInfo(HomeMediaItem(
      media: Media(
        id: 7,
        type: MediaType.episode,
        title: 'S02E05',
        duration: 2880,
        overview: 'Nora accepte un rendez-vous.',
        releaseDate: '2025-03-14',
        seasonNumber: 2,
        episodeNumber: 5,
        createdAt: DateTime(2024),
      ),
      currentPositionSeconds: 0,
      duration: 2880,
      isFinished: false,
      showTitle: 'Lignes Parallèles',
      showId: 2,
      episodeTitle: 'Le point de bascule',
    ));
    final next = HomeMediaItem(
      media: Media(
        id: 8,
        type: MediaType.episode,
        title: 'S02E06',
        duration: 3120,
        seasonNumber: 2,
        episodeNumber: 6,
        posterUrl: '/images/episodes/8.jpg',
        createdAt: DateTime(2024),
      ),
      currentPositionSeconds: 0,
      duration: 3120,
      isFinished: false,
      episodeTitle: 'Contre-courant',
    );
    final content = PauseInfoContent.from(
      info: info,
      // La fiche en cache d'un épisode est celle de la série.
      details: MediaDetails(
        id: 2,
        type: MediaType.show,
        title: 'Lignes Parallèles',
        voteAverage: 8.24,
      ),
      nextEpisode: next,
      positionSeconds: 1020,
      durationSeconds: 2880,
      logoUrl: 'https://image.tmdb.org/t/p/w500/lignes.png',
      serverBaseUrl: 'https://onyx.example/',
      now: now,
    );

    expect(content.isEpisode, isTrue);
    expect(content.showTitle, 'Lignes Parallèles');
    expect(content.episodeLine, 'Saison 2 · Épisode 5');
    expect(content.title, 'Le point de bascule');
    expect(content.overview, 'Nora accepte un rendez-vous.');
    expect(content.meta.first, contains('2025'));
    expect(content.nextEpisodeTitle, 'Contre-courant');
    expect(content.nextEpisodeMeta, contains('52min'));
    // L'image de l'épisode suivant, servie par le serveur.
    expect(content.nextEpisodeStillUrl,
        'https://onyx.example/images/episodes/8.jpg');
    // Le logo et la note sont ceux de la série.
    expect(content.logoUrl, 'https://image.tmdb.org/t/p/w500/lignes.png');
    expect(content.ratingLabel, '8.2');
    expect(content.endClock, '22:31');
  });

  testWidgets('l’écran tient en largeur d’ordinateur et ne prend aucun geste',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const content = PauseInfoContent(
      isEpisode: false,
      title: 'Le Dernier Phare',
      meta: ['2024', 'Drame', '2h 7min'],
      rating: 7.8,
      tagline: 'Une accroche.',
      overview: 'Un résumé assez long pour remplir plusieurs lignes. '
          'Un résumé assez long pour remplir plusieurs lignes. '
          'Un résumé assez long pour remplir plusieurs lignes.',
      director: 'Claire Varenne',
      cast: 'Inès Morel, Thomas Ardent',
      remaining: '1h 12min restantes',
      endClock: '23:41',
      progress: 0.43,
    );
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        Positioned.fill(
          child: GestureDetector(onTap: () => tapped++),
        ),
        const Positioned.fill(
          child: PauseInfoOverlay(content: content, visible: true, isTv: true),
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('pause-info-title')), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    // Un clic traverse jusqu'à l'image, qui relance la lecture.
    await tester.tapAt(const Offset(640, 360));
    expect(tapped, 1);
  });
}
