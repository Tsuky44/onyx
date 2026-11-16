import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';
import 'package:onyx/screens/player/video_display_mode.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_chrome_buttons.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_controls_layer.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_progress_bar.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_settings_menu.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_skip_intro_button.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_tabs.dart';
import 'package:onyx/screens/player/widgets/player_chrome_fade.dart';
import 'package:onyx/utils/format.dart';

/// Le chrome d'un écran tenu en main (ADR-0136) : l'arrangement d'un
/// téléviseur, adapté au doigt. Ces tests tiennent ce que la maquette validée
/// promet — où sont les commandes, lesquelles ont un bouton — et ce qu'un
/// doigt exige : des cibles de 44, rien qui déborde sur un petit téléphone.
const _title = 'MobLand';
const _episode = 'S2 · É9 · Nervous Breakdown';
const _position = Duration(minutes: 18, seconds: 50);
const _duration = Duration(minutes: 48, seconds: 29);

/// Un iPhone couché, par défaut.
const _phone = Size(844, 390);

OnyxTabEntry _tab(OnyxTab tab, String label) => OnyxTabEntry(
      tab: tab,
      label: label,
      builder: (_) => const SizedBox.shrink(),
    );

final _tabs = [
  _tab(OnyxTab.info, 'Infos'),
  _tab(OnyxTab.episodes, 'Épisodes'),
  _tab(OnyxTab.chapters, 'Chapitres'),
  _tab(OnyxTab.watchParty, 'Regarder ensemble'),
  _tab(OnyxTab.stats, 'Stats'),
];

Future<void> _pump(
  WidgetTester tester, {
  Size size = _phone,
  bool episode = true,
  bool isPlaying = true,
  String? logoUrl,
  VoidCallback? onSkipIntro,
  OnyxMenuSection? openMenu,
  void Function(OnyxMenuSection section, BuildContext anchor)? onOpenMenu,
  VoidCallback? onOpenSettings,
  ValueChanged<OnyxTab?>? onTabChanged,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: OnyxControlsLayer(
          visible: true,
          handheld: true,
          showVolume: false,
          isPlaying: isPlaying,
          position: _position,
          duration: _duration,
          buffered: 0.5,
          title: _title,
          overline: _episode,
          logoUrl: logoUrl,
          volume: 70,
          onPlayPause: () {},
          onRewind: () {},
          onForward: () {},
          onSeekFraction: (_) {},
          onVolumeChanged: (_) {},
          brightness: 0.6,
          onBrightnessChanged: (_) {},
          onBack: () {},
          onLockScreen: () {},
          onToggleSubtitles: () {},
          onOpenAudio: () {},
          onCycleSpeed: () {},
          onOpenSettings: onOpenSettings ?? () {},
          onToggleFullscreen: () {},
          onSkipPrevious: episode ? () {} : null,
          onSkipNext: episode ? () {} : null,
          onOpenEpisodes: episode ? () {} : null,
          onOpenInfo: () {},
          onOpenWatchParty: () {},
          onSkipIntro: onSkipIntro,
          tabs: _tabs,
          onTabChanged: onTabChanged ?? (_) {},
          onOpenMenu: onOpenMenu,
          openMenu: openMenu,
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _key(String id) => find.byKey(ValueKey('onyx-$id'));

void main() {
  testWidgets('lecture et ±10 s sont au milieu de l’image, entre les barres',
      (tester) async {
    await _pump(tester);

    final play = tester.getCenter(_key('play-pause'));
    final rewind = tester.getCenter(_key('rewind'));
    final forward = tester.getCenter(_key('forward'));

    expect(play.dx, closeTo(_phone.width / 2, 1));
    expect(rewind.dx, lessThan(play.dx));
    expect(forward.dx, greaterThan(play.dx));
    expect(rewind.dy, closeTo(play.dy, 1));
    expect(forward.dy, closeTo(play.dy, 1));

    // Sous le bouton Retour, au-dessus du titre : ni l'un ni l'autre ne doit
    // pouvoir prendre un doigt qui visait la pause.
    expect(
      tester.getRect(_key('play-pause')).top,
      greaterThan(tester.getRect(_key('back')).bottom),
    );
    expect(
      tester.getRect(_key('play-pause')).bottom,
      lessThan(tester.getRect(find.text(_title)).top),
    );
  });

  testWidgets('l’essentiel a son bouton, le reste est derrière la roue crantée',
      (tester) async {
    await _pump(tester);

    final row = [
      for (final id in ['previous', 'subtitles', 'audio', 'settings', 'next'])
        tester.getCenter(_key(id)),
    ];
    for (var i = 1; i < row.length; i++) {
      expect(row[i].dx, greaterThan(row[i - 1].dx));
      expect(row[i].dy, closeTo(row.first.dy, 1));
    }

    // Ce que la rangée d'avant portait et qui a changé de place : la vitesse
    // et le plein écran dans la roue crantée ou nulle part, les épisodes et la
    // séance dans les onglets.
    for (final gone in ['speed', 'fullscreen', 'episodes', 'watch-party']) {
      expect(_key(gone), findsNothing, reason: gone);
    }
  });

  testWidgets('un film n’a ni épisode précédent ni suivant', (tester) async {
    await _pump(tester, episode: false);

    expect(_key('previous'), findsNothing);
    expect(_key('next'), findsNothing);
    expect(_key('subtitles'), findsOneWidget);
    expect(_key('settings'), findsOneWidget);
  });

  testWidgets('un bouton de verre garde la cible d’un doigt, son disque non',
      (tester) async {
    await _pump(tester);

    for (final id in ['back', 'lock', 'settings', 'previous']) {
      final button = _key(id);
      expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(44),
          reason: 'cible de $id');
      final disc = find.descendant(
        of: button,
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(disc), const Size.square(OnyxIconButton.handheldDisc),
          reason: 'disque de $id');
    }
  });

  testWidgets('le titre est au-dessus de la ligne de l’épisode, à gauche',
      (tester) async {
    await _pump(tester);

    final title = tester.getRect(find.text(_title));
    final episode = tester.getRect(find.text(_episode));
    expect(title.bottom, lessThanOrEqualTo(episode.top));
    expect(title.left, closeTo(episode.left, 1));
    // Sur la même rangée que les boutons ronds, à leur gauche.
    expect(title.right, lessThan(tester.getRect(_key('subtitles')).left));
    // Sans logo, le haut ne le répète pas.
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('la barre garde la hauteur d’un doigt et porte les temps',
      (tester) async {
    await _pump(tester);

    final bar = tester.getRect(find.byType(OnyxProgressBar));
    expect(bar.height, greaterThanOrEqualTo(44));
    expect(tester.widget<OnyxProgressBar>(find.byType(OnyxProgressBar)).marker,
        isTrue);

    final elapsed = find.text(formatPlaybackTime(_position.inSeconds));
    final remaining = find.text(
      '-${formatPlaybackTime((_duration - _position).inSeconds)}',
    );
    expect(elapsed, findsOneWidget);
    // Le restant seul : pas d'heure de fin, comme sur un téléviseur.
    expect(remaining, findsOneWidget);
    expect(tester.getCenter(elapsed).dx, lessThan(tester.getCenter(remaining).dx));
    // Sous le trait de la barre, sans ajouter une rangée entière.
    expect(tester.getRect(elapsed).top, greaterThan(bar.center.dy));
    expect(tester.getRect(elapsed).bottom, lessThanOrEqualTo(bar.bottom + 8));
  });

  testWidgets('les onglets sont sous la barre, et en toucher un le demande',
      (tester) async {
    OnyxTab? asked;
    await _pump(tester, onTabChanged: (tab) => asked = tab);

    final bar = tester.getRect(find.byType(OnyxProgressBar));
    for (final entry in _tabs) {
      final tab = _key('tab-${entry.tab.name}');
      expect(tester.getRect(tab).top, greaterThanOrEqualTo(bar.bottom),
          reason: entry.label);
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(44),
          reason: 'cible de ${entry.label}');
    }
    // Le texte du premier onglet s'aligne sur le titre.
    expect(
      tester.getRect(find.text('Infos')).left,
      closeTo(tester.getRect(find.text(_title)).left, 1),
    );

    await tester.tap(_key('tab-episodes'));
    expect(asked, OnyxTab.episodes);
  });

  testWidgets('sous-titres et audio ouvrent chacun leur menu, sur leur bouton',
      (tester) async {
    final opened = <OnyxMenuSection>[];
    var settings = 0;
    await _pump(
      tester,
      onOpenMenu: (section, anchor) {
        opened.add(section);
        // Le repère est le bouton lui-même : le menu se pose au-dessus.
        expect(anchor.findRenderObject(), isNotNull);
      },
      onOpenSettings: () => settings++,
    );

    await tester.tap(_key('subtitles'));
    await tester.tap(_key('audio'));
    await tester.tap(_key('settings'));

    expect(opened, [OnyxMenuSection.subtitles, OnyxMenuSection.audio]);
    expect(settings, 1);
  });

  testWidgets('un menu ouvert allume son bouton et efface le milieu',
      (tester) async {
    PlayerChromeFade transport() => tester.widget<PlayerChromeFade>(
          find
              .ancestor(
                of: _key('play-pause'),
                matching: find.byType(PlayerChromeFade),
              )
              .first,
        );
    OnyxIconButton button(String id) => tester.widget<OnyxIconButton>(
          find.descendant(
            of: _key(id),
            matching: find.byType(OnyxIconButton),
            matchRoot: true,
          ),
        );

    await _pump(tester);
    expect(transport().visible, isTrue);
    expect(button('audio').lit, isFalse);

    await _pump(tester, openMenu: OnyxMenuSection.audio);
    expect(transport().visible, isFalse);
    expect(button('audio').lit, isTrue);
    expect(button('settings').lit, isFalse);

    // La roue crantée ouvre l'index : c'est elle qui s'allume.
    await _pump(tester, openMenu: OnyxMenuSection.root);
    expect(transport().visible, isFalse);
    expect(button('settings').lit, isTrue);
    expect(button('audio').lit, isFalse);
  });

  testWidgets('« Passer l’intro » est une capsule de verre', (tester) async {
    await _pump(tester, onSkipIntro: () {});

    expect(
      tester
          .widget<OnyxSkipIntroButton>(find.byType(OnyxSkipIntroButton))
          .capsule,
      isTrue,
    );
    // Au-dessus de la rangée du titre, sans déplacer les commandes du milieu.
    await _pump(tester);
    final without = tester.getCenter(_key('play-pause'));
    await _pump(tester, onSkipIntro: () {});
    expect(tester.getCenter(_key('play-pause')), without);
  });

  testWidgets('tient sur le plus petit téléphone couché', (tester) async {
    await _pump(tester, size: const Size(568, 320));

    expect(tester.takeException(), isNull);
    // Encore sur une rangée : le titre à gauche des boutons.
    expect(
      tester.getCenter(find.text(_title)).dy,
      closeTo(tester.getCenter(_key('settings')).dy, 24),
    );
    expect(
      tester.getRect(_key('play-pause')).bottom,
      lessThan(tester.getRect(find.text(_title)).top),
    );
  });

  testWidgets('sur une tablette en écran partagé, le titre et les boutons '
      's’empilent', (tester) async {
    await _pump(tester, size: const Size(400, 700));

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text(_episode)).bottom,
      lessThanOrEqualTo(tester.getRect(_key('settings')).top),
    );
  });

  testWidgets('l’index de la roue crantée ne répète pas ce que le chrome porte',
      (tester) async {
    Future<void> pumpIndex(Set<OnyxMenuSection> omits) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                // La police de test est bien plus large que la vraie.
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(0.4),
                ),
                child: OnyxSettingsMenu(
                  session: _FakeSession(),
                  currentMode: VideoDisplayMode.original,
                  onModeChanged: (_) {},
                  playbackRate: 1.0,
                  playbackRates: const [0.5, 1.0, 1.5, 2.0],
                  onRateChanged: (_) {},
                  indexOmits: omits,
                  onClose: () {},
                ),
              ),
            ),
          ),
        );

    await pumpIndex(const {});
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Sous-titres'), findsOneWidget);

    await pumpIndex(const {OnyxMenuSection.audio, OnyxMenuSection.subtitles});
    expect(find.text('Audio'), findsNothing);
    expect(find.text('Sous-titres'), findsNothing);
    for (final kept in [
      'Vitesse de lecture',
      'Format d’image',
      'Minuterie de veille',
    ]) {
      expect(find.text(kept), findsOneWidget, reason: kept);
    }
  });
}

class _FakeSession implements PlaybackSession {
  @override
  List<PlaybackTrack> get audioTracks => const [
        PlaybackTrack(id: '1', title: 'Français', language: 'fra'),
      ];

  @override
  List<PlaybackTrack> get subtitleTracks => const [PlaybackTrack(id: 'no')];

  @override
  PlaybackTrack? get currentAudioTrack => audioTracks.first;

  @override
  PlaybackTrack? get currentSubtitleTrack => subtitleTracks.first;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
