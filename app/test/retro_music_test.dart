import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:onyx/screens/retro/hooks/retro_music.dart';
import 'package:onyx/screens/retro/hooks/retro_music_backend.dart';
import 'package:onyx/screens/retro/hooks/retro_story_controller.dart';
import 'package:onyx/screens/retro/widgets/retro_story_chrome.dart';
import 'package:onyx/theme/app_icons.dart';
import 'package:onyx/tv/tv_mode.dart';

class _FakeBackend implements RetroMusicBackend {
  int starts = 0;
  int disposes = 0;
  final List<bool> muteCalls = [];

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  void setMuted(bool muted) {
    muteCalls.add(muted);
  }

  @override
  void dispose() {
    disposes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la bande-son du Rétro démarre une fois, bascule le muet et libère', () {
    final backend = _FakeBackend();
    final music = RetroMusic(backendFactory: () => backend);

    music.start();
    music.start();
    expect(backend.starts, 1);
    expect(music.muted, isFalse);

    music.toggleMute();
    expect(music.muted, isTrue);
    expect(backend.muteCalls, [true]);

    music.toggleMute();
    expect(music.muted, isFalse);
    expect(backend.muteCalls, [true, false]);

    music.dispose();
    expect(backend.disposes, 1);
  });

  test('couper avant le démarrage diffère l’ouverture jusqu’au rétablissement',
      () {
    final backend = _FakeBackend();
    final music = RetroMusic(backendFactory: () => backend);

    music.toggleMute();
    music.start();
    expect(backend.starts, 0);

    music.toggleMute();
    expect(backend.starts, 1);

    music.dispose();
  });

  test('l’asset audio cinéma du Rétro est bien embarqué dans le bundle',
      () async {
    final data = await rootBundle.load('assets/audio/retro_theme_cinema.m4a');
    expect(data.lengthInBytes, greaterThan(100000));
  });

  testWidgets('le bouton muet bascule l’icône sur mobile/bureau, absent sur TV',
      (tester) async {
    final story = RetroStoryController(count: 3);
    final music = RetroMusic(backendFactory: _FakeBackend.new);

    await tester.pumpWidget(MaterialApp(
      home: TvScope(
        isTv: false,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([story, music]),
            builder: (_, __) => RetroStoryChrome(
              story: story,
              ink: Colors.white,
              year: 2026,
              muted: music.muted,
              onToggleMute: music.toggleMute,
              onClose: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.byIcon(AppIcons.volumeOn), findsOneWidget);
    expect(find.byIcon(AppIcons.volumeOff), findsNothing);

    await tester.tap(find.byIcon(AppIcons.volumeOn));
    await tester.pump();
    expect(music.muted, isTrue);
    expect(find.byIcon(AppIcons.volumeOff), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: TvScope(
        isTv: true,
        child: Scaffold(
          body: RetroStoryChrome(
            story: story,
            ink: Colors.white,
            year: 2026,
            muted: music.muted,
            onToggleMute: music.toggleMute,
            onClose: () {},
          ),
        ),
      ),
    ));
    expect(find.byIcon(AppIcons.volumeOn), findsNothing);
    expect(find.byIcon(AppIcons.volumeOff), findsNothing);

    music.dispose();
  });
}
