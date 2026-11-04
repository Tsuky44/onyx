import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onyx_player_apple/onyx_player_apple.dart';

import '../tv/tv_mode.dart';
import '../utils/app_platform.dart';

/// The film in a corner of the home screen, while the phone is used for
/// something else.
///
/// **Android and iPhone/iPad, each by its own mechanism** (ADR-0012, §3 as
/// amended). On Android the activity asks for the window and the same Flutter
/// view is simply drawn smaller. On iOS the window is an
/// `AVPictureInPictureController` built around the layer AetherEngine plays on
/// (ADR-0038) — which is what the mpv texture of the earlier player could not
/// offer, and why this was Android only until AetherEngine. The plugin builds
/// the controller; this class only arms it for the player that is on screen.
///
/// The window is *armed* rather than opened: both systems only let it be
/// created at the instant the user leaves, so the player says in advance that
/// it may, and the system does the rest.
abstract final class PictureInPicture {
  const PictureInPicture._();

  static const MethodChannel _channel = MethodChannel('onyx/device');

  /// iOS: the player the window is armed for, set by the playback session once
  /// the native player exists. Null on Android, which has one activity.
  static OnyxApplePlayer? _apple;
  static bool _armed = false;

  /// Whether the platform can do it at all. False until [initialize] has asked.
  static bool get supported => _supported;
  static bool _supported = false;

  /// True while the film is playing in the little window.
  ///
  /// The interface listens: in that window there is no room for chrome, and
  /// nothing to tap it with.
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// Raised when the window is closed rather than restored — the film has
  /// nowhere left to play and the player has to let go.
  static final ValueNotifier<int> closed = ValueNotifier<int>(0);

  /// Asked once, at startup, and the answers wired up.
  static Future<void> initialize() async {
    if (!_canAsk) return;
    if (AppPlatform.isIOS) return _initializeApple();
    _channel.setMethodCallHandler(_onPlatformCall);
    try {
      _supported =
          await _channel.invokeMethod<bool>('supportsPictureInPicture') ??
              false;
    } catch (error) {
      debugPrint('Picture-in-picture: unavailable ($error)');
      _supported = false;
    }
  }

  static Future<void> _initializeApple() async {
    try {
      _supported = await OnyxApplePlayer.supportsPictureInPicture();
    } catch (error) {
      debugPrint('Picture-in-picture: unavailable ($error)');
      _supported = false;
    }
    if (!_supported) return;
    OnyxApplePlayer.pictureInPictureChanges.listen((change) {
      // Two players are alive for an instant when an episode hands over to the
      // next; only the one the window is armed for speaks for the screen.
      final player = _apple;
      if (player == null || change.playerId != player.id) return;
      active.value = change.active;
      if (change.closed) closed.value++;
    }, onError: (Object error) {
      debugPrint('Picture-in-picture: stream interrupted ($error)');
    });
  }

  /// iOS: the native player now on screen. Arms it at once if the screen
  /// already asked, since the player is built a moment after the screen is.
  static void attach(OnyxApplePlayer player) {
    _apple = player;
    if (_armed) unawaited(_armApple(player, true));
  }

  /// iOS: [player] is going away. The next episode's player is built before
  /// this one is released, so a stale one must not unseat its successor.
  static void detach(OnyxApplePlayer player) {
    if (!identical(_apple, player)) return;
    _apple = null;
    active.value = false;
  }

  static Future<void> _armApple(OnyxApplePlayer player, bool armed) async {
    try {
      await player.setPictureInPictureArmed(armed);
    } catch (error) {
      // The player may already be released when the screen disarms on the way
      // out; there is then nothing left to disarm.
      debugPrint('Picture-in-picture: cannot arm ($error)');
    }
  }

  /// Arms the window for a film of [width] × [height] pixels, or disarms it
  /// when either is zero — leaving the player, or a film that has not said how
  /// big it is yet.
  static Future<void> arm({required int width, required int height}) async {
    if (!_supported) return;
    if (AppPlatform.isIOS) {
      // iOS reads the shape off the layer itself; all it needs to know is
      // whether the window may open.
      _armed = width > 0 && height > 0;
      final player = _apple;
      if (player != null) await _armApple(player, _armed);
      return;
    }
    final shape = shapeFor(width, height);
    try {
      await _channel.invokeMethod<bool>('setPictureInPicture', <String, int>{
        'width': shape.$1,
        'height': shape.$2,
      });
    } catch (error) {
      debugPrint('Picture-in-picture: cannot arm ($error)');
    }
  }

  static Future<void> disarm() => arm(width: 0, height: 0);

  /// The shape the little window may take, which is not always the film's.
  ///
  /// Android refuses an aspect ratio outside 1:2.39 … 2.39:1 — it throws rather
  /// than clamping — and 2.39:1 is exactly the shape of a scope film. So the
  /// ratio is brought inside the range here, and the last of the picture is
  /// left slightly letterboxed in the corner rather than not shown at all.
  static (int, int) shapeFor(int width, int height) {
    if (width <= 0 || height <= 0) return (0, 0);
    final ratio = width / height;
    // Rounded down in both directions, and that is the whole subtlety: rounding
    // to the nearest lands a hair *outside* the range as often as inside, and
    // Android does not forgive a hair — it throws. Down makes a wide picture
    // narrower and a tall one shorter, which is inside either way.
    if (ratio > _maxRatio) return ((height * _maxRatio).floor(), height);
    if (ratio < 1 / _maxRatio) return (width, (width * _maxRatio).floor());
    return (width, height);
  }

  /// Android's own limit, both ways up.
  static const double _maxRatio = 2.39;

  /// A television has its own idea of this, and the chrome here is not built
  /// for it; a desktop has windows already.
  static bool get _canAsk =>
      (AppPlatform.isAndroid || AppPlatform.isIOS) &&
      !AppPlatform.isWeb &&
      !TvMode.isTv;

  static Future<dynamic> _onPlatformCall(MethodCall call) async {
    if (call.method != 'pictureInPictureChanged') return null;
    final arguments = (call.arguments as Map?)?.cast<String, dynamic>();
    active.value = arguments?['inPictureInPicture'] as bool? ?? false;
    if (arguments?['closed'] as bool? ?? false) closed.value++;
    return null;
  }
}
