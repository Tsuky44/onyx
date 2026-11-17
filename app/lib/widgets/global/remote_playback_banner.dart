import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/remote_playback.dart';
import '../../navigation/search_route_observer.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../screens/player/player_screen.dart';
import '../../theme/app_motion.dart';
import '../../utils/on_screen.dart';
import '../../utils/poster_url.dart';
import '../../tv/tv_mode.dart';
import 'remote_playback_notice.dart';
import 'remote_playback_slot.dart';

/// « Lecture en cours sur un autre appareil » : ce que le compte lit ailleurs,
/// avec de quoi le reprendre ici là où il en est.
///
/// Reprendre ouvre le lecteur, dont le premier signal met l'autre appareil en
/// pause (voir `server/handlers/playback_handoff.go`).
///
/// Deux dessins (ADR-0127) :
///
/// - partout sauf sur un téléphone, une notification de verre en haut à
///   droite de l'accueil ([RemotePlaybackBanner.notice],
///   [RemotePlaybackNotice]). Avec une télécommande ([hold]), on reprend en
///   maintenant la touche lecture/pause. Hors Apple TV ([selectable]), OK
///   reprend aussi : depuis le bouton « Reprendre ici » de la barre du haut
///   ([RemotePlaybackSlot]), ou depuis la notification elle-même hors de la
///   coquille (ADR-0136) ;
/// - sur un téléphone, la même en plus ramassé, en bas de l'écran : toucher
///   reprend, la croix l'écarte.
class RemotePlaybackBanner extends StatefulWidget {
  /// La notification en haut à droite, et non la carte ramassée du
  /// téléphone.
  final bool notice;

  /// Vrai sur un téléviseur : un appui maintenu sur lecture/pause reprend,
  /// un appui court ne fait rien.
  final bool hold;

  /// Vrai sur un téléviseur dont la télécommande peut ne pas avoir de touche
  /// lecture/pause, ou ne pas savoir la maintenir (tout sauf la Siri
  /// Remote) : OK reprend aussi, depuis le bouton de la barre du haut
  /// ([RemotePlaybackSlot]) ou, sans barre, depuis la notification. Le focus
  /// y va de lui-même quand la notification arrive avec l'accueil, et un
  /// appui court sur lecture/pause l'y amène (ADR-0136).
  final bool selectable;

  const RemotePlaybackBanner({super.key})
      : notice = false,
        hold = false,
        selectable = false;

  const RemotePlaybackBanner.notice({
    super.key,
    this.hold = false,
    this.selectable = false,
  }) : notice = true;

  /// Le temps que lecture/pause doit rester enfoncée pour reprendre. Assez
  /// long pour ne pas partir d'un appui machinal, assez court pour ne pas
  /// faire douter : l'anneau se remplit sous les yeux.
  static const Duration holdDuration = Duration(milliseconds: 900);

  /// Un relâchement suivi d'un nouvel appui dans ce délai est le même appui
  /// qui continue : la télécommande du simulateur Apple TV coupe un appui
  /// tenu en « enfoncé, relâché, ré-enfoncé » (voir `TvFocusable`).
  static const Duration holdBounce = Duration(milliseconds: 40);

  /// Les touches qui valent lecture/pause. Une télécommande de téléviseur
  /// passée par HDMI-CEC (celle d'un Hisense qui pilote un Fire TV) envoie
  /// souvent « lecture » et « pause » séparément, et non la touche
  /// combinée : seules celle-ci et « lecture » étaient écoutées, et « pause »
  /// ne faisait rien.
  static final Set<LogicalKeyboardKey> playKeys = {
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.mediaPlay,
    LogicalKeyboardKey.mediaPause,
  };

  @override
  State<RemotePlaybackBanner> createState() => _RemotePlaybackBannerState();
}

class _RemotePlaybackBannerState extends State<RemotePlaybackBanner>
    with OnScreenState, SingleTickerProviderStateMixin {
  static const _pollInterval = Duration(seconds: 10);

  Timer? _timer;
  RemotePlayback? _current;
  final Set<String> _dismissed = {};
  bool _opening = false;

  /// Les lectures déjà montrées : la notification ne prend le focus d'elle-
  /// même qu'à la première fois ([RemotePlaybackBanner.selectable]).
  final Set<String> _announced = {};

  /// Le focus de la notification, hors Apple TV et hors de la coquille.
  final FocusNode _noticeFocus =
      FocusNode(debugLabel: 'Lecture sur un autre appareil');

  /// Le bouton « Reprendre ici » de la barre du haut, hors Apple TV : c'est
  /// lui qui prend le focus, au même niveau que les onglets, et non la
  /// notification, posée sur le chemin d'aucune rangée (ADR-0136).
  RemotePlaybackSlot? _slot;

  /// Là où va le focus qui reprend : le bouton de la barre, ou la
  /// notification sans barre.
  FocusNode get _target => _slot?.focus ?? _noticeFocus;

  /// L'appui en cours sur lecture/pause ([RemotePlaybackBanner.hold]) :
  /// il avance tant que la touche est tenue, et la lecture reprend au bout.
  late final AnimationController _hold;

  /// Le relâchement en attente de [RemotePlaybackBanner.holdBounce].
  Timer? _release;

  @override
  void initState() {
    super.initState();
    // Ici et non à la première lecture : un bandeau qui ne s'en sert pas le
    // créerait dans `dispose`, quand l'arbre ne se lit plus.
    _hold = AnimationController(
      vsync: this,
      duration: RemotePlaybackBanner.holdDuration,
      reverseDuration: const Duration(milliseconds: 180),
    )..addStatusListener(_onHoldStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final slot = widget.selectable
        ? RemotePlaybackSlotScope.maybeOf(context, listen: false)
        : null;
    if (identical(slot, _slot)) return;
    _slot?.focus.removeListener(_onSlotFocus);
    _slot = slot;
    slot?.focus.addListener(_onSlotFocus);
  }

  /// La notification s'éclaire quand le bouton de la barre a le focus.
  void _onSlotFocus() {
    if (mounted) setState(() {});
  }

  /// Retire le bouton de la barre. Après l'image : ceci arrive aussi dans
  /// `didChangeOnScreen` et `dispose`, quand la barre ne peut pas se
  /// reconstruire.
  void _withdraw() {
    final slot = _slot;
    if (slot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isOnScreen) slot.offer(null, null);
    });
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_current == null) {
      // L'autre appareil s'est arrêté pendant l'appui : rien à reprendre, et
      // l'anneau ne doit pas rester plein pour la prochaine fois.
      _hold.value = 0;
      return;
    }
    unawaited(_resume());
  }

  /// Le sondage ne tourne que quand l'accueil est vu : sous le lecteur, dans
  /// un autre onglet ou fenêtre réduite, il demandait au serveur toutes les
  /// dix secondes un bandeau que personne ne verrait. Au retour, une relecture
  /// tout de suite remet le bandeau à jour.
  @override
  void didChangeOnScreen(bool onScreen) {
    _timer?.cancel();
    _timer = null;
    HardwareKeyboard.instance.removeHandler(_onMediaKey);
    if (!onScreen) {
      // Le bouton ne vaut que pour l'accueil : un autre onglet, une fiche ou
      // le lecteur par-dessus le retirent de la barre.
      _withdraw();
      return;
    }
    HardwareKeyboard.instance.addHandler(_onMediaKey);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _refresh(arriving: true));
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _release?.cancel();
    HardwareKeyboard.instance.removeHandler(_onMediaKey);
    _slot?.focus.removeListener(_onSlotFocus);
    _withdraw();
    _hold.dispose();
    _noticeFocus.dispose();
    super.dispose();
  }

  /// Lecture/pause de la télécommande : sur une télévision, c'est le geste qui
  /// reprend ce que le compte lit ailleurs, sans avoir à viser un bouton. La
  /// Siri Remote n'a qu'une touche pour cela, et c'est celle que l'on presse en
  /// pensant « reprendre ». Il faut la maintenir ([_onHoldKey]).
  ///
  /// Seulement quand l'accueil est au premier plan : sous le lecteur ou une
  /// fiche, la touche garde son sens habituel.
  bool _onMediaKey(KeyEvent event) {
    if (!TvMode.isTv) return false;
    if (!RemotePlaybackBanner.playKeys.contains(event.logicalKey)) {
      return false;
    }
    return widget.hold && _onHoldKey(event);
  }

  /// Il faut maintenir la touche : un appui court ne reprend rien, pour
  /// qu'une lecture ne parte pas d'un geste machinal. L'appui avance [_hold],
  /// le relâchement le ramène à zéro.
  ///
  /// Hors Apple TV ([RemotePlaybackBanner.selectable]), beaucoup de
  /// télécommandes ne savent pas tenir la touche : par HDMI-CEC, un appui
  /// maintenu arrive en « enfoncé, relâché » répétés, et l'anneau ne se
  /// remplissait jamais. Un appui court y amène donc le focus, et un second
  /// appui (ou OK) reprend : deux gestes voulus, jamais un seul machinal
  /// (ADR-0136).
  bool _onHoldKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      // Toujours entendu, même une fois le lecteur ouvert par-dessus : sans
      // cela l'appui resterait « tenu » au retour.
      if (_hold.value == 0 && _release == null) return false;
      _release?.cancel();
      _release = Timer(RemotePlaybackBanner.holdBounce, () {
        _release = null;
        if (!mounted || _opening) return;
        if (widget.selectable &&
            _current != null &&
            _hold.status != AnimationStatus.completed) {
          _target.requestFocus();
        }
        _hold.reverse();
      });
      return true;
    }
    if (_current == null || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    if (event is KeyDownEvent && widget.selectable && _target.hasFocus) {
      // La notification a déjà le focus : l'appui court qui l'y a amenée
      // était le premier geste, celui-ci est le second.
      unawaited(_resume());
      return true;
    }
    if (event is KeyDownEvent && !_opening) {
      _release?.cancel();
      _release = null;
      if (_hold.status != AnimationStatus.completed) _hold.forward();
    }
    // La répétition d'une touche tenue ne relance rien.
    return true;
  }

  Future<List<RemotePlayback>> _fetch() async {
    final api = Provider.of<AuthProvider>(context, listen: false).apiClient;
    try {
      return await api.getMyRemotePlaybacks();
    } catch (_) {
      return const []; // Serveur plus ancien : pas de reprise, rien d'autre.
    }
  }

  /// [arriving] : l'accueil vient d'apparaître (ouverture de l'app, retour au
  /// premier plan, retour d'une autre page). C'est le moment où l'on prend
  /// la télécommande pour reprendre ce que le téléphone lisait : hors Apple
  /// TV, la notification prend alors le focus, une fois par lecture, et OK
  /// suffit. Pendant que l'on parcourt l'accueil, un sondage ne le vole
  /// jamais.
  Future<void> _refresh({bool arriving = false}) async {
    if (!mounted || _opening) return;
    // Rien à proposer pendant que le lecteur de cet appareil est ouvert.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final plays = await _fetch();
    // Parti ailleurs pendant la requête : le bouton de la barre a été retiré,
    // il ne doit pas revenir.
    if (!mounted || !isOnScreen) return;
    final next =
        plays.where((p) => !_dismissed.contains(_dismissKey(p))).firstOrNull;
    // L'autre appareil a changé d'épisode ou s'est arrêté : la rangée
    // « Reprendre la lecture » d'ici date d'avant, on la relit.
    final previous = _current;
    if (previous != null && previous.session.mediaId != next?.session.mediaId) {
      unawaited(Provider.of<HomeProvider>(context, listen: false)
          .loadHome(silent: true));
    }
    setState(() => _current = next);
    _slot?.offer(next, _resume);
    if (next == null || !_announced.add(_dismissKey(next))) return;
    if (!arriving || !widget.selectable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _current == null || _opening) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      _target.requestFocus();
    });
  }

  String _dismissKey(RemotePlayback p) =>
      '${p.session.sessionId}:${p.session.mediaId}';

  Future<void> _resume() async {
    final shown = _current;
    if (shown == null || _opening) return;
    setState(() => _opening = true);
    // La position d'il y a dix secondes ne suffit pas : on la redemande.
    final fresh = (await _fetch())
            .where((p) => p.session.sessionId == shown.session.sessionId)
            .firstOrNull ??
        shown;
    if (!mounted) return;
    setState(() => _current = null);
    _slot?.offer(null, null);
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      settings: const RouteSettings(name: SearchRouteObserver.playerRouteName),
      builder: (_) => PlayerScreen(
        media: fresh.media,
        resumeAtSeconds: fresh.session.positionSeconds,
      ),
    ));
    if (!mounted) return;
    _opening = false;
    _hold.value = 0;
    Provider.of<HomeProvider>(context, listen: false).loadHome(silent: true);
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final play = _current;
    if (widget.notice) {
      // Elle entre et sort par la droite, comme une notification de tvOS.
      return AnimatedSwitcher(
        duration: AppMotion.move(context, AppMotion.emphasis),
        switchInCurve: AppMotion.curve,
        switchOutCurve: AppMotion.curve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topRight,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.12, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: play == null ? const SizedBox.shrink() : _notice(play),
      );
    }
    // Sur un téléphone, elle monte du bas de l'écran.
    return AnimatedSwitcher(
      duration: AppMotion.move(context, AppMotion.emphasis),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: play == null ? const SizedBox.shrink() : _notice(play),
    );
  }

  void _dismiss(RemotePlayback play) => setState(() {
        _dismissed.add(_dismissKey(play));
        _current = null;
      });

  /// Voir [RemotePlaybackNotice].
  Widget _notice(RemotePlayback play) {
    final baseUrl =
        Provider.of<AuthProvider>(context, listen: false).apiClient.baseUrl;
    // Sur Apple TV, rien ne reprend d'un seul appui : il n'y a que la touche
    // maintenue.
    final direct = !widget.hold || widget.selectable;
    return RemotePlaybackNotice(
      key: ValueKey(_dismissKey(play)),
      play: play,
      posterUrl: cardPosterUrl(play.session.posterUrl, serverBaseUrl: baseUrl),
      hold: widget.hold ? _hold : null,
      // Avec la barre, c'est son bouton qui prend le focus : la notification
      // s'éclaire seulement.
      selectable: widget.selectable && _slot == null,
      focusNode: widget.selectable && _slot == null ? _noticeFocus : null,
      headerFocused: _slot?.focus.hasFocus,
      compact: !widget.notice,
      onResume: direct && !_opening ? _resume : null,
      onDismiss: widget.hold ? null : () => _dismiss(play),
    );
  }
}
