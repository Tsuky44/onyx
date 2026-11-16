import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/models/models.dart';
import 'package:onyx/screens/library/show_episode_actions.dart';
import 'package:onyx/screens/library/version_picker.dart';
import 'package:onyx/tv/tv_mode.dart';

MediaVersion _version(int id, String label) => MediaVersion(
      label: label,
      item: HomeMediaItem(
        media: Media(
          id: id,
          type: MediaType.episode,
          title: 'Épisode',
          duration: 3000,
          createdAt: DateTime(2026),
        ),
        currentPositionSeconds: 0,
        duration: 3000,
        isFinished: false,
      ),
    );

final _versions = [
  _version(1, '3840 × 2160 · HEVC · ep.4k.mkv'),
  _version(2, '1920 × 1080 · H264 · ep.1080.mkv'),
  _version(3, 'Qualité inconnue · ep.mkv'),
];

void main() {
  test('le libellé du serveur se range en résolution, codec et fichier', () {
    final full = VersionLabel.parse('3840 × 2160 · HEVC · ep.mkv');
    expect(full.resolution, '4K');
    expect(full.short, '4K · HEVC');
    expect(full.detail, 'HEVC · ep.mkv');

    final noCodec = VersionLabel.parse('1080p · ep.mkv');
    expect(noCodec.short, '1080p');
    expect(noCodec.detail, 'ep.mkv');

    expect(VersionLabel.parse('720p').detail, isNull);
  });

  testWidgets('la capsule ouvre le menu et rend la version choisie',
      (tester) async {
    MediaVersion? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VersionPicker(
          versions: _versions,
          selectedId: 1,
          onSelected: (v) => picked = v,
        ),
      ),
    ));
    expect(find.text('4K · HEVC'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);

    await tester.tap(find.text('4K · HEVC'));
    await tester.pumpAndSettle();
    expect(find.text('H264 · ep.1080.mkv'), findsOneWidget);
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    expect(picked?.item.media.id, 2);
  });

  testWidgets('sur TV, la liste déroulante reste en place', (tester) async {
    await tester.pumpWidget(TvScope(
      isTv: true,
      child: MaterialApp(
        home: Scaffold(
          body: VersionPicker(
            versions: _versions,
            selectedId: 1,
            onSelected: (_) {},
          ),
        ),
      ),
    ));
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
  });

  testWidgets('le dialogue de lecture d’un épisode propose la capsule',
      (tester) async {
    final episode = _versions.first.item;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => playShowEpisode(
            context,
            HomeMediaItem(
              media: Media(
                id: 1,
                type: MediaType.episode,
                title: 'Épisode',
                duration: 3000,
                createdAt: DateTime(2026),
                versions: _versions,
              ),
              currentPositionSeconds: 0,
              duration: 3000,
              isFinished: false,
            ),
            siblings: [episode],
          ),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(VersionPicker), findsOneWidget);
    expect(find.text('4K · HEVC'), findsOneWidget);

    await tester.tap(find.text('4K · HEVC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    // Le choix est pris dans le dialogue, qui reste ouvert.
    expect(find.text('1080p · H264'), findsOneWidget);
    expect(find.byType(VersionPicker), findsOneWidget);
  });
}
