import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:onyx/screens/player/hooks/use_player_popup.dart';
import 'package:onyx/screens/player/playback/playback_session.dart';
import 'package:onyx/screens/player/player_key_routing.dart';
import 'package:onyx/screens/player/video_display_mode.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_controls_layer.dart';
import 'package:onyx/screens/player/widgets/onyx/onyx_settings_menu.dart';
import 'package:onyx/screens/player/widgets/player_popups.dart';
import 'package:onyx/tv/nav/onyx_dpad.dart' show TvNavScope;
import 'package:onyx/tv/nav/tv_back.dart';

/// Un lecteur de banc : le Chrome Onyx télé, `routePlayerKey`, le
/// `PlayerPopupHost` et le menu de réglages, câblés comme `PlayerScreen` les
/// câble, sans moteur vidéo.
///
/// `PlayerScreen` ne se monte pas dans un test (il lui faut un moteur, une
/// session, un serveur). Ce banc reprend ce qui décide de la télécommande,
/// branche pour branche, de `player_screen_remote.dart` : qui détient le
/// focus (le lecteur, ou une commande dans son sous-arbre), le chrome levé
/// avec une commande entourée (ADR-0008), la pile du Retour (menu, chrome,
/// lecteur) et le retour du focus à la fermeture d'un menu. Les widgets, eux,
/// sont les vrais. Une divergence entre ce banc et le lecteur se corrige des
/// deux côtés ; l'écran entier se vérifie au simulateur (ADR-0110, phase 7).
class PlayerRemoteBench extends StatefulWidget {
  const PlayerRemoteBench({
    super.key,
    this.skipIntro = false,
    this.series = true,
    required this.actions,
  });

  /// La pastille « Passer l'intro » est à l'écran.
  final bool skipIntro;

  /// Un épisode : précédent, suivant et la liste des épisodes.
  final bool series;

  /// Ce que `routePlayerKey` a décidé, touche par touche.
  final List<PlayerKeyAction> actions;

  @override
  State<PlayerRemoteBench> createState() => PlayerRemoteBenchState();
}

class PlayerRemoteBenchState extends State<PlayerRemoteBench> {
  final FocusNode player = FocusNode(debugLabel: 'player');
  final FocusNode playPause = FocusNode(debugLabel: 'player-play-pause');
  final FocusNode progress = FocusNode(debugLabel: 'player-progress');

  bool chromeVisible = false;
  bool _towardScrubber = false;

  /// Les pas de recherche faits par la barre ou par les flèches.
  int seeks = 0;

  /// Le lecteur a été quitté.
  bool left = false;

  late final PlayerPopupHost popups = PlayerPopupHost(
    isActive: () => mounted && !_disposing,
    onDismissed: _handlePopupDismissed,
  );

  /// `_remoteBrowsingControls` du lecteur.
  bool get browsingControls => player.hasFocus && !player.hasPrimaryFocus;

  bool _disposing = false;

  @override
  void dispose() {
    _disposing = true;
    popups.dispose();
    player.dispose();
    playPause.dispose();
    progress.dispose();
    super.dispose();
  }

  /// `_handlePopupDismissed` du lecteur.
  void _handlePopupDismissed(FocusNode? origin) {
    if (origin != null && TvNavScope.isActive(context)) {
      origin.requestFocus();
      _showChrome();
    } else {
      _enterControlBar();
    }
  }

  void _enterControlBar({bool scrubber = false}) {
    _towardScrubber = scrubber;
    _showChrome();
  }

  /// `_showControlsTransient`, puis `_ensureRemoteInChrome`.
  void _showChrome() {
    setState(() => chromeVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !chromeVisible || popups.isOpen) return;
      if (browsingControls) return;
      final preferred =
          _towardScrubber ? [progress, playPause] : [playPause, progress];
      _towardScrubber = false;
      for (final node in preferred) {
        if (node.context != null) {
          node.requestFocus();
          return;
        }
      }
    });
  }

  void _leaveControlBar() {
    player.requestFocus();
    setState(() => chromeVisible = false);
  }

  void _leave() {
    if (left) return;
    left = true;
    Navigator.of(context).pop();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final browsing = browsingControls;
    final action = routePlayerKey(
      event,
      isTv: true,
      browsingControls: browsing,
      chromeVisible: chromeVisible,
      skipIntroShown: widget.skipIntro,
    );
    widget.actions.add(action);
    switch (action) {
      case PlayerKeyIgnored():
        return KeyEventResult.ignored;
      case PlayerKeyRemoteSeek():
        seeks++;
        _enterControlBar(scrubber: true);
      case PlayerKeyEnterControlBar():
        _enterControlBar();
      case PlayerKeyBack():
        if (!TvBack.claimKey(context)) break;
        if (popups.back()) break;
        if (browsing) {
          _leaveControlBar();
          break;
        }
        _leave();
      case PlayerKeyConsumed():
      case PlayerKeySkipIntro():
      case PlayerKeyTogglePlayback():
      case PlayerKeyShortcut():
      case PlayerKeySeek():
      case PlayerKeyVolume():
        break;
    }
    return KeyEventResult.handled;
  }

  /// `_handleBack` du lecteur : le Retour du système.
  void _handleBack() {
    if (popups.back()) return;
    if (browsingControls) {
      _leaveControlBar();
      return;
    }
    _leave();
  }

  void _openSettings() {
    popups.insert(
      context,
      (dismiss) => PlayerCenteredPopup(
        onDismiss: dismiss,
        child: MediaQuery(
          // La police de test est à chasse fixe et bien plus large que la
          // vraie : sans ça les libellés débordent des 292 px du panneau.
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(0.4)),
          child: OnyxSettingsMenu(
            session: BenchPlaybackSession(),
            currentMode: VideoDisplayMode.original,
            onModeChanged: (_) {},
            playbackRate: 1.0,
            playbackRates: const [0.5, 1.0, 1.5, 2.0],
            onRateChanged: (_) {},
            onClose: dismiss,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: player,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: OnyxControlsLayer(
            visible: chromeVisible,
            isTv: true,
            isPlaying: true,
            position: const Duration(minutes: 42),
            duration: const Duration(hours: 2),
            buffered: 0.5,
            title: 'Film',
            overline: '2022',
            volume: 70,
            onPlayPause: () {},
            onRewind: () => seeks++,
            onForward: () => seeks++,
            onScrubStepBack: () => seeks++,
            onScrubStepForward: () => seeks++,
            onSeekFraction: (_) {},
            onVolumeChanged: (_) {},
            onBack: _leave,
            onToggleSubtitles: () {},
            onOpenAudio: () {},
            onCycleSpeed: () {},
            onOpenSettings: _openSettings,
            onToggleFullscreen: () {},
            onSkipNext: widget.series ? () {} : null,
            onSkipPrevious: widget.series ? () {} : null,
            onOpenEpisodes: widget.series ? () {} : null,
            onSkipIntro: widget.skipIntro ? () {} : null,
            playPauseFocusNode: playPause,
            progressFocusNode: progress,
          ),
        ),
      ),
    );
  }
}

/// L'écran d'où l'on lance le banc : une carte, que la sortie du lecteur
/// doit retrouver.
class PlayerBenchHome extends StatelessWidget {
  const PlayerBenchHome({super.key, required this.card, required this.player});

  /// Le nœud de la carte.
  final FocusNode card;

  /// Le lecteur poussé par OK sur la carte.
  final Widget Function() player;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Focus(
          focusNode: card,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent ||
                event.logicalKey != LogicalKeyboardKey.select) {
              return KeyEventResult.ignored;
            }
            unawaited(Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => player()),
            ));
            return KeyEventResult.handled;
          },
          child: const SizedBox(width: 200, height: 120, child: Text('Carte')),
        ),
      ),
    );
  }
}

/// Une session sans moteur : deux pistes audio, l'anglaise jouée.
class BenchPlaybackSession implements PlaybackSession {
  PlaybackTrack? chosen;

  @override
  List<PlaybackTrack> get audioTracks => const [
        PlaybackTrack(id: '1', title: 'Français', language: 'fra'),
        PlaybackTrack(id: '2', title: 'English', language: 'eng'),
      ];

  @override
  List<PlaybackTrack> get subtitleTracks => const [
        PlaybackTrack(id: 'no'),
        PlaybackTrack(id: '3', title: 'Français', language: 'fra'),
      ];

  @override
  PlaybackTrack? get currentAudioTrack => audioTracks[1];

  @override
  PlaybackTrack? get currentSubtitleTrack => subtitleTracks.first;

  @override
  Future<void> setAudioTrack(PlaybackTrack track) async => chosen = track;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
