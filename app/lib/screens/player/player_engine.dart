import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:onyx_mpv_macos/onyx_mpv_macos.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../../utils/app_platform.dart';
import '../../utils/idle_hold.dart';
import '../../utils/mpv_native_view.dart';
import 'playback/mpv_startup_trace.dart';
import 'windows_video_render.dart';

/// A libmpv instance together with the video texture it renders into.
///
/// The two are created as a pair and stay a pair for their whole life: a
/// [VideoController] is bound to the player it was constructed with and cannot
/// be moved to another one.
class PlayerEngine {
  final mk.Player player;

  /// La texture de media_kit. Absente quand mpv dessine lui-même dans une vue
  /// native ([MpvNativeView]) : la créer lui imposerait `vo=libmpv`.
  final VideoController? videoController;

  /// La sortie de mpv dans une vue native, en mode [MpvNativeView].
  late final Future<MpvNativeOutput> nativeOutput = player.handle.then(
    (handle) => MpvNativeOutput(
      libmpvPath: MpvNativeView.outputLibraryPath,
      mpvHandle: handle,
    ),
  );

  /// The unload issued when this engine was parked, while it is still running.
  ///
  /// Whoever takes the engine out of the pool has to wait for this before
  /// opening anything on it. It used to be fire-and-forget, and an unload that
  /// landed *after* the next file was opened unloaded that file instead — mpv
  /// sitting idle behind a spinner that never ends, on a playback that looked
  /// like it had started. Rare on a desktop, where the stop is done long before
  /// anyone picks the next episode; not rare on a television, where the stop is
  /// slower and the next media is one press of OK away.
  Future<void>? pendingStop;

  /// Faux dès que ce moteur a quitté sa texture pour une fenêtre mpv
  /// (ADR-0061). Il n'est alors pas remis en commun : la lecture suivante en
  /// construit un neuf, plutôt que d'hériter d'une sortie vidéo et de
  /// réglages d'écran qui n'étaient que pour ce fichier-là.
  bool reusable = true;

  /// Le chemin de rendu demandé à la sortie Windows à la création (ADR-0158,
  /// phase 2), null ailleurs. Un réglage changé depuis ne s'applique qu'à un
  /// moteur neuf ([PlayerEnginePool.acquire]) ; seule une bascule vers ANGLE
  /// en pleine lecture ([fallbackToAngle]) le change en route.
  String? requestedRenderApi;

  PlayerEngine._(this.player, this.videoController, {this.requestedRenderApi});

  /// Le chemin que la sortie Windows a retenu, une fois la texture créée.
  /// Null hors de Windows, ou si le contrôleur vidéo n'a pas pu naître.
  ///
  /// L'attendre ne retarde rien : `Player.open` attend de toute façon ce même
  /// contrôleur avant d'ouvrir quoi que ce soit.
  Future<VideoRenderPath?> get renderPath async {
    final controller = videoController;
    if (controller == null || !AppPlatform.isWindows) return null;
    try {
      final platform = await controller.platform.future;
      return VideoRenderPath.parse(platform.renderApi);
    } catch (e) {
      debugPrint('PlayerEngine: chemin de rendu inconnu: $e');
      return null;
    }
  }

  /// Ce que la sortie a rendu (ADR-0158, phase 2, point 4) : null hors de
  /// Windows.
  Future<Map<String, Object?>?> renderInfo() async {
    final controller = videoController;
    if (controller == null || !AppPlatform.isWindows) return null;
    return (await controller.platform.future).renderInfo();
  }

  /// Fait passer la sortie de D3D11 à ANGLE sans changer de lecteur, et rend
  /// le chemin retenu (ADR-0158, phase 2, point 4).
  Future<String?> fallbackToAngle() async {
    final controller = videoController;
    if (controller == null || !AppPlatform.isWindows) return null;
    final api = await (await controller.platform.future).fallbackToAngle();
    if (api != null && api != 'd3d11') requestedRenderApi = 'angle';
    return api;
  }

  factory PlayerEngine._create() {
    if (MpvNativeView.enabled) {
      // Aucune sortie vidéo tant qu'aucune vue n'est là : sans `vo=null`, mpv
      // ouvrirait sa propre fenêtre dès le premier film.
      final player = mk.Player(
        configuration: const mk.PlayerConfiguration(
          vo: 'null',
          logLevel: _logLevel,
        ),
      );
      // media_kit démarre avec `vid=no` et compte sur le VideoController pour
      // poser `vid=auto`. Sans lui, la piste vidéo resterait coupée : le son
      // joue, rien n'est décodé, et l'écran reste noir derrière le spinner.
      unawaited(
        player.setVideoTrack(mk.VideoTrack.auto()).catchError((Object e) {
          debugPrint('PlayerEngine: piste vidéo non réactivée: $e');
        }),
      );
      return PlayerEngine._(player, null);
    }
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(logLevel: _logLevel),
    );
    final renderApi = WindowsVideoRender.nativeRequest;
    return PlayerEngine._(
      player,
      VideoController(
        player,
        configuration:
            VideoControllerConfiguration(windowsRenderApi: renderApi),
      ),
      requestedRenderApi: renderApi,
    );
  }

  /// Verbeux, pour que la trace de démarrage ([MpvStartupProbe]) voie
  /// l'ouverture du flux, l'index et le seek initial — rien de tout ça n'est
  /// écrit en `info`. Le niveau se fixe à la création du contexte libmpv, pas
  /// après. Hors démarrage, personne n'écoute : en lecture établie, mpv
  /// n'écrit presque rien à ce niveau (debug et trace, eux, suivent chaque
  /// paquet et restent coupés).
  static const _logLevel = mk.MPVLogLevel.v;

  int _readsInFlight = 0;
  Completer<void>? _readsDone;

  /// Lit [names] hors du thread de l'interface ([MpvNativeOutput]).
  ///
  /// Compté : la destruction du moteur attend la fin des lectures en cours,
  /// sans quoi l'isolate lirait un contexte mpv déjà libéré.
  Future<Map<String, String?>> readProperties(List<String> names) async {
    _readsInFlight++;
    try {
      return await (await nativeOutput).getProperties(names);
    } finally {
      if (--_readsInFlight == 0) {
        _readsDone?.complete();
        _readsDone = null;
      }
    }
  }

  /// Détruit le moteur une fois ses lectures hors interface terminées.
  Future<void> _dispose() async {
    if (_readsInFlight > 0) {
      await (_readsDone ??= Completer<void>()).future;
    }
    await player.dispose();
  }

  /// Waits out the parked unload, if there is one. Idempotent.
  Future<void> settle() async {
    final pending = pendingStop;
    if (pending == null) return;
    await pending;
    // Only clear what we waited on: a stop issued in the meantime is not ours.
    if (identical(pendingStop, pending)) pendingStop = null;
  }
}

/// Keeps one idle [PlayerEngine] alive between playbacks.
///
/// Building an engine is the expensive, invisible part of opening a media:
/// libmpv has to create its context, the video controller has to allocate its
/// texture and negotiate the render path with the platform. None of that
/// depends on which file is about to play, and none of it has to happen while
/// the user is staring at a spinner — so it is done once, off the critical
/// path, and the same engine is handed to every playback that follows.
///
/// Un moteur prêt n'attend que [idleLimit] : passé ce délai, il est détruit
/// et la lecture suivante en construit un neuf (ADR-0166).
///
/// At most one engine is idle at a time. A second one is only ever built when a
/// playback starts while the previous screen still holds its engine (the
/// episode auto-advance builds the new screen before the old one is disposed);
/// whichever comes back last is the one kept warm.
class PlayerEnginePool {
  PlayerEnginePool._();

  /// Combien de temps un moteur prêt attend sa lecture avant d'être détruit.
  ///
  /// Deux minutes couvrent l'épisode suivant choisi à la main et le film
  /// lancé juste après l'ouverture de l'app ; au-delà, le contexte libmpv et
  /// ses surfaces ne font qu'occuper la mémoire. Le reconstruire coûte une
  /// fraction de seconde au lancement suivant.
  static const Duration idleLimit = Duration(minutes: 2);

  static final IdleHold<PlayerEngine> _idle = IdleHold<PlayerEngine>(
    limit: idleLimit,
    discard: _discard,
  );

  /// Détruit un moteur qui n'est plus voulu, après son arrêt en cours.
  static void _discard(PlayerEngine engine) {
    unawaited(engine.settle().then((_) => engine._dispose()).catchError((_) {
      // Une instance déjà détruite refuse la commande : il n'y a plus rien
      // à arrêter.
    }));
  }

  /// Takes the warm engine, or builds one when the pool is empty.
  ///
  /// Un moteur préparé pour un autre chemin de rendu que celui demandé
  /// maintenant (réglage changé, D3D11 marqué en panne, admin connecté après
  /// le préchauffage) est jeté : le choix s'applique à la lecture suivante.
  static PlayerEngine acquire() {
    final warm = _idle.take();
    if (warm != null) {
      final wanted = WindowsVideoRender.nativeRequest;
      if (warm.requestedRenderApi == wanted) return warm;
      debugPrint('PlayerEnginePool: rendu ${warm.requestedRenderApi} → '
          '$wanted, moteur reconstruit');
      _discard(warm);
    }
    return PlayerEngine._create();
  }

  /// Gives an engine back after a playback ends.
  static void release(PlayerEngine engine) {
    if (!engine.reusable) {
      // La fenêtre d'abord, par la même file que la surface : détruire mpv
      // pendant qu'une option de sortie est encore en route, c'est lui parler
      // après sa mort.
      unawaited(engine.nativeOutput
          .then((output) => output.setProperty('vo', 'null'))
          .catchError((Object e) {
        debugPrint('PlayerEnginePool: sortie vidéo non rendue: $e');
      }).whenComplete(() => engine._dispose().catchError((_) {
                // Une instance déjà détruite refuse la commande : il n'y a
                // plus rien à arrêter.
              })));
      return;
    }
    if (_idle.isHolding) {
      // Already holding one — a second idle engine is memory nobody asked for.
      // `dispose` stops the player on its way out, so this covers the unload
      // too; racing it with a separate `stop` would only produce a rejected
      // command against an instance that is already gone.
      unawaited(engine._dispose().catchError((_) {
        // Une instance déjà détruite refuse la commande : il n'y a plus rien à arrêter.
      }));
      return;
    }

    // `stop` is not optional housekeeping: an engine parked with a file still
    // loaded would keep its HTTP connection open and keep reading the stream
    // for as long as it sits in the pool. It also clears the position,
    // duration and track list, so the next media cannot inherit a stale state
    // through the reused instance. Volume and playback rate deliberately
    // survive it — they belong to the person watching, not to the file.
    //
    // Kept rather than dropped: the next playback has to wait for it. See
    // [PlayerEngine.pendingStop].
    engine.pendingStop = engine.player.stop().catchError((_) {
      // Un arrêt refusé ne doit pas bloquer la lecture qui attend ce moteur.
    });
    _idle.put(engine);
  }

  /// Builds the first engine ahead of time, so the first playback of the
  /// session is as fast as the ones after it.
  ///
  /// Call once the app is idle: this competes with whatever is loading at
  /// startup, and it exists precisely to move the cost somewhere the user is
  /// not waiting.
  static void prewarm() {
    // The web backend is an HTMLVideoElement — there is no mpv context to
    // build, so there is nothing to gain and a stray <video> to avoid.
    if (AppPlatform.isWeb) return;
    // Les appareils Apple lisent par AetherEngine (ADR-0038) : un moteur mpv
    // préparé d'avance n'y servirait jamais. Sur l'Apple TV, c'est lui qu'on
    // amorce : le premier lecteur du processus charge FFmpeg et son pont de
    // journal, ce qu'une Apple TV HD ne fait pas en un clin d'œil.
    if (AppPlatform.isApple) {
      if (AppPlatform.isTvOS) unawaited(_prewarmAether());
      return;
    }
    if (_idle.isHolding) return;
    try {
      _idle.put(PlayerEngine._create());
    } catch (e) {
      // A player that cannot be built ahead of time will simply be built on
      // demand; failing to prewarm must never stop the app from starting.
      debugPrint('PlayerEnginePool: prewarm failed: $e');
    }
  }

  static Future<void> _prewarmAether() async {
    try {
      await OnyxApplePlayer.prewarm();
    } catch (e) {
      // Sans amorce, la première lecture paie simplement ce coût elle-même.
      debugPrint('PlayerEnginePool: amorce AetherEngine impossible : $e');
    }
  }
}
