import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/player/hooks/use_player_stats.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';
import 'package:onyx/screens/player/widgets/tabs/player_stats_tab.dart';

/// L'onglet « Stats » du lecteur (ADR-0130) : ce que le moteur dit, relu
/// seulement tant que quelqu'un regarde.
void main() {
  PlayerLiveStats stats({
    required Future<PlaybackDiagnostics> Function() read,
    String? quality,
    bool local = false,
    String? filePath = '/films/phare.mkv',
    MediaVideoTrack? track,
    DateTime Function()? now,
  }) =>
      PlayerLiveStats(
        now: now,
        readDiagnostics: read,
        currentQuality: () => quality,
        isLocalPlayback: () => local,
        videoParams: () => const PlaybackVideoParams(width: 3840, height: 2160),
        videoTrack: () => track,
        filePath: filePath,
      );

  String value(PlayerLiveStats stats, String label) =>
      stats.lines.firstWhere((line) => line.label == label).value;

  test('les mêmes mesures que l’écran natif, dans le même ordre', () {
    final live = stats(read: () async => PlaybackDiagnostics.none);
    addTearDown(live.dispose);

    expect(live.lines.map((line) => line.label), [
      'Chemin de lecture',
      'Codec vidéo',
      'Décodeur vidéo',
      'Décodeur audio',
      'Images par seconde',
      'Cadence du fichier',
      'Images perdues',
      'Débit moyen',
      'Débit vidéo',
      'Format vidéo',
      'Sortie audio',
      'Conteneur',
    ]);
  });

  test('une mesure que le moteur ne donne pas s’écrit « — », jamais zéro', () {
    final live = stats(read: () async => PlaybackDiagnostics.none);
    addTearDown(live.dispose);

    for (final label in [
      'Codec vidéo',
      'Décodeur vidéo',
      'Images par seconde',
      'Images perdues',
      'Débit moyen',
      'Débit vidéo',
      'Sortie audio',
    ]) {
      expect(value(live, label), PlayerLiveStats.unknown, reason: label);
    }
  });

  // `testWidgets` pour son faux temps : la minuterie d'une seconde s'y avance
  // à la main.
  testWidgets('rien ne se relève tant que personne ne regarde', (tester) async {
    var reads = 0;
    final live = stats(read: () async {
      reads++;
      return PlaybackDiagnostics.none;
    });
    addTearDown(live.dispose);

    await tester.pump(const Duration(seconds: 5));
    expect(reads, 0);

    live.watch();
    await tester.pump(const Duration(milliseconds: 3500));
    // Un relevé à l'arrivée, puis un par seconde.
    expect(reads, 4);

    live.unwatch();
    await tester.pump(const Duration(seconds: 5));
    expect(reads, 4);
  });

  testWidgets('en Direct : le fichier, son format HDR et son conteneur',
      (tester) async {
    {
      final live = stats(
        read: () async => const PlaybackDiagnostics(
          videoCodec: 'hevc',
          hardwareDecoder: 'videotoolbox',
          audioCodec: 'eac3',
          estimatedFps: 23.98,
          containerFps: 23.976,
          droppedByDisplay: 2,
          droppedByDecoder: 1,
          videoBitrate: 18400000,
          sourceChannels: '5.1',
          outputChannels: 'stereo',
        ),
        track: MediaVideoTrack(
          codec: 'hevc',
          width: 3840,
          height: 2160,
          hdrFormat: 'HDR10',
        ),
      );
      live.watch();
      await tester.pump();

      expect(value(live, 'Chemin de lecture'), 'Direct');
      expect(value(live, 'Codec vidéo'), 'hevc');
      expect(value(live, 'Décodeur vidéo'), 'videotoolbox');
      expect(value(live, 'Images par seconde'), '23.98 fps');
      expect(value(live, 'Cadence du fichier'), '23.976 fps');
      expect(value(live, 'Images perdues'), '3');
      expect(value(live, 'Débit vidéo'), '18.4 Mb/s');
      expect(value(live, 'Format vidéo'), '3840 × 2160 · HDR10');
      expect(value(live, 'Sortie audio'), '5.1 → stereo');
      expect(value(live, 'Conteneur'), 'MKV');
      live
        ..unwatch()
        ..dispose();
    }
  });

  test('en transcodage : le barreau, sans le HDR du fichier, en HLS', () {
    final live = stats(
      read: () async => PlaybackDiagnostics.none,
      quality: '2160p',
      track: MediaVideoTrack(
        codec: 'hevc',
        width: 3840,
        height: 2160,
        hdrFormat: 'HDR10',
      ),
    );
    addTearDown(live.dispose);

    expect(value(live, 'Chemin de lecture'), 'Transcodage · 4K');
    expect(value(live, 'Format vidéo'), '3840 × 2160');
    expect(value(live, 'Conteneur'), 'HLS');
  });

  test('un média téléchargé le dit', () {
    final live = stats(read: () async => PlaybackDiagnostics.none, local: true);
    addTearDown(live.dispose);

    expect(value(live, 'Chemin de lecture'), 'Téléchargé');
  });

  testWidgets('le débit moyen se mesure depuis l’ouverture de l’onglet',
      (tester) async {
    var bytes = 1000000;
    // Une horloge à la main : `DateTime.now` ne suit pas le faux temps.
    var clock = DateTime(2026);
    final live = stats(
      now: () => clock,
      read: () async {
        bytes += 1000000;
        return PlaybackDiagnostics(bytesLoaded: bytes);
      },
    );
    addTearDown(live.dispose);
    live.watch();
    await tester.pump();
    // Sous deux secondes, ce ne serait qu'un à-coup de remplissage.
    expect(value(live, 'Débit moyen'), PlayerLiveStats.unknown);

    for (var second = 0; second < 4; second++) {
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
    // 4 Mo en 4 s : 8 Mb/s.
    expect(value(live, 'Débit moyen'), '8.0 Mb/s');
    live.unwatch();
  });

  testWidgets('un relevé qui échoue garde la mesure précédente',
      (tester) async {
    var fail = false;
    final live = stats(read: () async {
      if (fail) throw StateError('moteur fermé');
      return const PlaybackDiagnostics(videoCodec: 'h264');
    });
    addTearDown(live.dispose);
    live.watch();
    await tester.pump();
    expect(value(live, 'Codec vidéo'), 'h264');

    fail = true;
    await tester.pump(const Duration(seconds: 2));
    expect(value(live, 'Codec vidéo'), 'h264');
    live.unwatch();
  });

  testWidgets('l’onglet relève tant qu’il est à l’écran, et s’arrête avec lui',
      (tester) async {
    var reads = 0;
    final live = stats(read: () async {
      reads++;
      return const PlaybackDiagnostics(videoCodec: 'hevc');
    });
    addTearDown(live.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox(
          width: 1174,
          height: 238,
          child: PlayerStatsTab(stats: live),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Codec vidéo'), findsOneWidget);
    expect(find.text('hevc'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 2));
    final whileShown = reads;
    expect(whileShown, greaterThanOrEqualTo(3));

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 3));
    expect(reads, whileShown);
  });
}
