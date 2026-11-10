@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/device_video.dart';
import 'package:onyx/services/device_library/device_library.dart';
import 'package:onyx/services/local_playback_source.dart';
import 'package:path/path.dart' as p;

void main() {
  group('vidéos de l’appareil', () {
    test('un identifiant de vidéo locale est négatif et stable', () {
      final id = deviceVideoIdFor('/films/Vacances 2024.mp4');
      expect(id, isNegative);
      expect(isDeviceVideoId(id), isTrue);
      expect(deviceVideoIdFor('/films/./Vacances 2024.mp4'), id);
      expect(deviceVideoIdFor('/films/Autre.mp4'), isNot(id));
    });

    test('seuls les fichiers vidéo visibles sont retenus', () {
      expect(isDeviceVideoPath('/a/Film.MKV'), isTrue);
      expect(isDeviceVideoPath('/a/clip.mp4'), isTrue);
      expect(isDeviceVideoPath('/a/._clip.mp4'), isFalse);
      expect(isDeviceVideoPath('/a/notes.txt'), isFalse);
      expect(isDeviceVideoPath('/a/sous-titres.srt'), isFalse);
    });

    test('le titre se lit sans séparateurs ni étiquettes', () {
      expect(deviceVideoTitle('/a/Mon.Film.2019.1080p.mkv'),
          'Mon Film 2019 1080p');
      expect(deviceVideoTitle('/a/[Groupe] Mon_Anime_01.mkv'), 'Mon Anime 01');
      expect(deviceVideoTitle('/a/Vacances.mp4'), 'Vacances');
    });

    test('une vidéo locale part au lecteur comme un film', () {
      final video = DeviceVideo(
        path: '/films/Vacances.mp4',
        folder: '/films',
        sizeBytes: 1,
        modifiedAt: DateTime(2026),
      );
      final item = video.toHomeMediaItem();
      expect(item.media.id, video.id);
      expect(item.media.title, 'Vacances');
      expect(item.media.type.name, 'movie');
    });
  });

  group('DeviceLibrary', () {
    late Directory root;
    late Directory state;
    late Directory videos;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('device_library_test');
      state = await Directory(p.join(root.path, 'state')).create();
      videos = await Directory(p.join(root.path, 'Vidéos')).create();
      await File(p.join(videos.path, 'Vacances.mp4')).writeAsString('x');
      await Directory(p.join(videos.path, 'Été')).create();
      await File(p.join(videos.path, 'Été', 'Plage.mkv')).writeAsString('xy');
      await File(p.join(videos.path, 'notes.txt'))
          .writeAsString('pas une vidéo');
      await Directory(p.join(videos.path, '.cache')).create();
      await File(p.join(videos.path, '.cache', 'cachée.mp4'))
          .writeAsString('x');
    });

    tearDown(() => root.delete(recursive: true));

    DeviceLibrary make() => DeviceLibrary(
          stateDirectory: () async => state,
          appFolder: () async => null,
        );

    test('un dossier ajouté rend ses vidéos, sous-dossiers compris', () async {
      final library = make();
      expect(await library.addFolder(videos.path), isTrue);
      expect(
        library.videos.map((v) => v.title),
        unorderedEquals(['Vacances', 'Plage']),
      );
      final plage = library.videos.firstWhere((v) => v.title == 'Plage');
      expect(plage.subfolder, 'Été');
      expect(plage.sizeBytes, 2);
    });

    test('un dossier introuvable est refusé', () async {
      final library = make();
      expect(await library.addFolder(p.join(root.path, 'absent')), isFalse);
      expect(library.folders, isEmpty);
    });

    test('un dossier parent remplace ses enfants : pas de doublons', () async {
      final library = make();
      await library.addFolder(p.join(videos.path, 'Été'));
      await library.addFolder(videos.path);
      expect(library.folders, [p.normalize(videos.path)]);
      expect(library.videos, hasLength(2));
      // Un enfant d'un dossier déjà suivi n'ajoute rien.
      await library.addFolder(p.join(videos.path, 'Été'));
      expect(library.folders, hasLength(1));
    });

    test('les dossiers et l’avancement survivent à un relancement', () async {
      final first = make();
      await first.addFolder(videos.path);
      final video = first.videos.firstWhere((v) => v.title == 'Vacances');
      await first.recordProgress(
        id: video.id,
        positionSeconds: 120,
        durationSeconds: 600,
        isFinished: false,
      );

      final second = make();
      await second.initialize();
      expect(second.folders, [p.normalize(videos.path)]);
      final again = second.videos.firstWhere((v) => v.title == 'Vacances');
      expect(again.progress?.positionSeconds, 120);
      expect(second.progressFor(video.id)?.durationSeconds, 600);
    });

    test('un fichier effacé hors de l’app disparaît au scan suivant', () async {
      final library = make();
      await library.addFolder(videos.path);
      final video = library.videos.firstWhere((v) => v.title == 'Vacances');
      expect(library.pathFor(video.id), video.path);
      await File(video.path).delete();
      expect(library.pathFor(video.id), isNull);
      await library.rescan();
      expect(library.videos.map((v) => v.title), ['Plage']);
    });

    test(
        'ne plus suivre un dossier retire ses vidéos sans toucher aux fichiers',
        () async {
      final library = make();
      await library.addFolder(videos.path);
      await library.removeFolder(p.normalize(videos.path));
      expect(library.videos, isEmpty);
      expect(File(p.join(videos.path, 'Vacances.mp4')).existsSync(), isTrue);
    });
  });

  test('un identifiant de serveur ne passe jamais par la bibliothèque locale',
      () {
    // Positif : c'est un téléchargement ou le serveur, jamais un fichier de
    // l'appareil — même si un chemin y avait le même hachage.
    expect(isDeviceVideoId(42), isFalse);
    expect(localPlaybackTracks(-5), isNull);
  });
}
