import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/search_route_observer.dart';
import '../services/player_presence.dart';
import '../utils/app_platform.dart';

/// Les sons de navigation de l'Apple TV (ADR
/// `2026-11-23-fytroz-sons-de-navigation-apple-tv`).
///
/// tvOS fait entendre un clic à chaque déplacement du focus, mais c'est son
/// moteur de focus qui le joue, pour les déplacements qu'il mène lui-même.
/// Ici c'est Flutter qui déplace le focus : UIKit ne voit rien bouger, et
/// l'app était muette. L'hôte natif (`tvos/Runner/NavigationSound.swift`)
/// rejoue donc les sons du système, et ce service lui dit quand :
///
/// - **le focus s'est posé ailleurs à la suite d'un pas de direction** : le
///   clic. Le son part d'un seul endroit, l'écoute du `FocusManager`
///   ([_onFocusChange]) : c'est le seul point par où passent l'ancien système
///   de navigation, dpad (ADR-0110), les flèches que des écrans traitent
///   eux-mêmes et les pas du pavé tactile. Un pas refusé (bord de l'écran) ne
///   déplace rien, donc ne joue rien, comme sur tvOS ;
/// - **une page s'ouvre ou se referme** ([routeObserver]) : les sons que tvOS
///   nomme `navigation_push` et `navigation_pop`.
///
/// Un focus posé sans que personne n'ait appuyé (l'entrée d'une page, un
/// focus rendu après un rechargement) reste muet : seul un pas de direction
/// annoncé par [noteKey] ou [noteStep] arme le clic. C'est le module de la
/// télécommande (`TvTouchpad`) qui les annonce, parce qu'il voit passer et
/// les touches et les pas du pavé, sur Apple TV seulement.
///
/// Le lecteur est muet de bout en bout : rien ne joue pendant qu'il est
/// ouvert ([PlayerPresence]), ni dans son chrome ni quand on le quitte, et
/// l'ouvrir ne joue pas `push` non plus. Un son du système n'a rien à faire
/// par-dessus la bande-son d'un film, ni au moment où le lecteur active la
/// session audio et négocie sa route (voir `AppDelegate.swift`).
///
/// Hors Apple TV, [initialize] ne branche rien et aucun appel ne part vers le
/// canal.
abstract final class TvNavigationSound {
  static const MethodChannel _channel =
      MethodChannel('onyx/tv_navigation_sound');

  static const String _preferenceKey = 'tv_navigation_sound';

  /// L'écart minimal entre deux clics.
  ///
  /// Sous les 110 ms d'une flèche maintenue (`TvRepeatCadence`) et les 100 ms
  /// d'un glissé vertical du pavé, avec de la marge : chacun de ces pas garde
  /// son clic, sans qu'un minuteur en avance de quelques millisecondes en
  /// fasse sauter un. Au-dessus des 60 ms d'une rangée d'affiches balayée
  /// vite (`TouchpadAxisTuning.horizontal`) : elle ne sonne alors qu'un pas
  /// sur deux, au lieu de mitrailler.
  ///
  /// À écouter sur une vraie Apple TV.
  static const Duration minInterval = Duration(milliseconds: 80);

  /// Le temps laissé au focus pour se poser après un pas de direction.
  ///
  /// D'ordinaire il se pose dans la même tâche. Le seul retard connu est
  /// celui de dpad quand rien n'est construit dans la direction : il fait
  /// défiler 160 ms puis réessaie à l'image suivante (constat C6 de
  /// l'ADR-0110). Passé ce délai, un focus qui bouge ne doit plus rien à la
  /// flèche : une page qui s'ouvre après une flèche butée au bord reste
  /// muette.
  static const Duration stepWindow = Duration(milliseconds: 250);

  static final Set<LogicalKeyboardKey> _arrows = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  /// Fait croire qu'on tourne (ou non) sur Apple TV, dans les tests.
  @visibleForTesting
  static bool? debugSupported;

  /// Remplace l'horloge dans les tests.
  @visibleForTesting
  static Duration Function()? debugClock;

  /// Vrai sur l'Apple TV, seul hôte qui sert ce canal.
  static bool get supported => debugSupported ?? AppPlatform.isTvOS;

  /// Le réglage de l'app, activé par défaut. tvOS a le sien (Réglages, Vidéo
  /// et audio, Clics de navigation), mais aucune API ne le donne à une app :
  /// celui-ci permet de couper les sons d'Onyx sans toucher à ceux du
  /// système.
  static bool get enabled => _enabled;

  /// À donner au navigateur racine : ouvrir une page joue `push`, la quitter
  /// `pop`. La première route n'est pas une page qu'on ouvre, c'est l'app qui
  /// démarre : elle reste muette, comme le lecteur.
  ///
  /// Une seule instance : un observateur ne sert qu'un navigateur à la fois,
  /// et une nouvelle à chaque reconstruction de `MaterialApp` le ferait
  /// débrancher puis rebrancher pour rien.
  static final NavigatorObserver routeObserver = _RouteSounds();

  static final Stopwatch _clock = Stopwatch()..start();

  static bool _enabled = true;
  static bool _listening = false;
  static bool _prepared = false;

  /// Faux quand l'hôte n'a pas ce canal (son fichier Swift n'est pas compilé,
  /// ou c'est un test) : on ne lui redemande rien de la séance.
  static bool _hostAnswers = true;

  /// L'instant du dernier pas de direction, tant que le focus ne s'est pas
  /// posé depuis.
  static Duration? _armedAt;

  static Duration? _lastClickAt;

  static Duration get _now => debugClock?.call() ?? _clock.elapsed;

  /// Lit le réglage et branche l'écoute du focus. Une fois, au démarrage, et
  /// sur Apple TV seulement.
  static Future<void> initialize() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_preferenceKey) ?? true;
    } catch (_) {
      // Faute de disque, le réglage garde sa valeur par défaut.
      _enabled = true;
    }
    if (!_listening) {
      _listening = true;
      FocusManager.instance.addListener(_onFocusChange);
    }
    if (_enabled) unawaited(_prepare());
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (value && _listening) unawaited(_prepare());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_preferenceKey, value);
    } catch (_) {
      // Faute de disque, le réglage vaut pour la séance.
    }
  }

  /// Une touche de la télécommande vient d'arriver. Une flèche arme le clic ;
  /// toute autre touche le désarme : le focus qui bouge après OK ou Retour
  /// est celui d'une page qui s'ouvre ou se referme, pas un pas.
  static void noteKey(KeyEvent event) {
    if (!_listening || event is KeyUpEvent) return;
    _armedAt = _arrows.contains(event.logicalKey) ? _now : null;
  }

  /// Un pas de direction qui n'est pas une touche part : un cran du pavé
  /// tactile de la Siri Remote, ou de sa lancée.
  static void noteStep() {
    if (_listening) _armedAt = _now;
  }

  static void _onFocusChange() {
    final armedAt = _armedAt;
    if (armedAt == null) return;
    final focus = FocusManager.instance.primaryFocus;
    // Une portée seule : le focus est entré quelque part sans se poser sur
    // rien. Le pas n'a pas encore abouti, on attend sa cible.
    if (focus == null || focus is FocusScopeNode || focus.context == null) {
      return;
    }
    // Un pas, un clic : le second focus qu'une même flèche déclencherait
    // (une entrée de zone qui redirige) ne sonne pas.
    _armedAt = null;
    final now = _now;
    if (now - armedAt > stepWindow) return;
    final last = _lastClickAt;
    if (last != null && now - last < minInterval) return;
    if (_play('move')) _lastClickAt = now;
  }

  /// Demande [sound] à l'hôte, et dit si la demande est partie.
  static bool _play(String sound) {
    if (!_listening ||
        !_enabled ||
        !_hostAnswers ||
        PlayerPresence.isOpen()) {
      return false;
    }
    unawaited(_invoke(sound));
    return true;
  }

  /// Fait charger les sons à l'hôte avant le premier pas, pour que celui-ci
  /// ne les attende pas, et note dans le journal d'où ils viennent : c'est ce
  /// qu'on lira si l'Apple TV reste muette.
  static Future<void> _prepare() async {
    if (_prepared) return;
    _prepared = true;
    final sources = await _invoke('prepare');
    if (sources != null) debugPrint('Sons de navigation : $sources');
  }

  static Future<Object?> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<Object?>(method);
    } on MissingPluginException {
      _hostAnswers = false;
      debugPrint('Sons de navigation : l’hôte n’a pas ce canal');
    } on PlatformException catch (error) {
      debugPrint('Sons de navigation : $method refusé ($error)');
    }
    return null;
  }

  @visibleForTesting
  static void resetForTest() {
    if (_listening) FocusManager.instance.removeListener(_onFocusChange);
    _listening = false;
    _enabled = true;
    _prepared = false;
    _hostAnswers = true;
    _armedAt = null;
    _lastClickAt = null;
    debugSupported = null;
    debugClock = null;
  }
}

class _RouteSounds extends NavigatorObserver {
  /// Le lecteur, que tous ses appelants poussent sous ce nom. Quand il se
  /// referme, [PlayerPresence] le dit encore ouvert ; quand il s'ouvre, pas
  /// encore : c'est le nom de la route qui le fait reconnaître.
  static bool _isPlayer(Route<dynamic> route) =>
      route.settings.name == SearchRouteObserver.playerRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Le focus qui va se poser est celui de la page, pas un pas : une flèche
    // butée au bord juste avant ne lui vaut pas de clic.
    TvNavigationSound._armedAt = null;
    if (previousRoute == null || _isPlayer(route)) return;
    TvNavigationSound._play('push');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    TvNavigationSound._armedAt = null;
    if (_isPlayer(route)) return;
    TvNavigationSound._play('pop');
  }
}
