import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/remote_playback.dart';
import '../../navigation/search_route_observer.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../screens/player/player_screen.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../utils/on_screen.dart';
import '../../utils/poster_url.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_mode.dart';
import '../../l10n/tr.dart';
import 'app_network_image.dart';
import 'remote_playback_notice.dart';

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
///   maintenant la touche lecture/pause ;
/// - sur un téléphone, une carte en bas de l'écran, avec son bouton.
class RemotePlaybackBanner extends StatefulWidget {
  /// La notification, et non la carte du téléphone.
  final bool notice;

  /// Vrai sur un téléviseur : un appui maintenu sur lecture/pause reprend,
  /// un appui court ne fait rien.
  final bool hold;

  /// Vrai sur un téléviseur dont la télécommande peut ne pas avoir de touche
  /// lecture/pause (tout sauf la Siri Remote) : la notification prend aussi
  /// le focus, et OK reprend.
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
    if (!onScreen) return;
    HardwareKeyboard.instance.addHandler(_onMediaKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _release?.cancel();
    HardwareKeyboard.instance.removeHandler(_onMediaKey);
    _hold.dispose();
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
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.mediaPlayPause &&
        key != LogicalKeyboardKey.mediaPlay) {
      return false;
    }
    return widget.hold && _onHoldKey(event);
  }

  /// Il faut maintenir la touche : un appui court ne reprend rien, pour
  /// qu'une lecture ne parte pas d'un geste machinal. L'appui avance [_hold],
  /// le relâchement le ramène à zéro.
  bool _onHoldKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      // Toujours entendu, même une fois le lecteur ouvert par-dessus : sans
      // cela l'appui resterait « tenu » au retour.
      if (_hold.value == 0 && _release == null) return false;
      _release?.cancel();
      _release = Timer(RemotePlaybackBanner.holdBounce, () {
        _release = null;
        if (mounted && !_opening) _hold.reverse();
      });
      return true;
    }
    if (_current == null || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
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

  Future<void> _refresh() async {
    if (!mounted || _opening) return;
    // Rien à proposer pendant que le lecteur de cet appareil est ouvert.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final plays = await _fetch();
    if (!mounted) return;
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: play == null ? const SizedBox.shrink() : _card(context, play),
    );
  }

  void _dismiss(RemotePlayback play) => setState(() {
        _dismissed.add(_dismissKey(play));
        _current = null;
      });

  /// Partout sauf sur un téléphone : voir [RemotePlaybackNotice].
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
      selectable: widget.selectable,
      onResume: direct && !_opening ? _resume : null,
      onDismiss: widget.hold ? null : () => _dismiss(play),
    );
  }

  Widget _card(BuildContext context, RemotePlayback play) {
    final s = play.session;
    final baseUrl =
        Provider.of<AuthProvider>(context, listen: false).apiClient.baseUrl;
    final poster = cardPosterUrl(s.posterUrl, serverBaseUrl: baseUrl);
    final device =
        s.deviceName.isNotEmpty ? s.deviceName : tr('un autre appareil');

    final card = ConstrainedBox(
      key: ValueKey(_dismissKey(play)),
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(
        color: AppColors.surfaceElevated,
        elevation: 12,
        shadowColor: Colors.black,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 40,
                      height: 60,
                      child: poster == null
                          ? const ColoredBox(color: AppColors.surfaceHover)
                          : AppNetworkImage(
                              url: poster,
                              width: 40,
                              height: 60,
                              errorWidget: const ColoredBox(
                                  color: AppColors.surfaceHover),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr('Lecture en cours sur {0}', [device]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: AppType.footnote,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppType.callout,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (s.detail.isNotEmpty)
                          Text(
                            s.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: AppType.footnote,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _opening ? null : _resume,
                    icon: const Icon(AppIcons.play, size: 20),
                    label: Text(tr('Reprendre')),
                  ),
                  IconButton(
                    tooltip: tr('Ignorer'),
                    onPressed: () => _dismiss(play),
                    icon: const Icon(AppIcons.close,
                        color: AppColors.textSecondary, size: 20),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: s.progress,
              minHeight: 3,
              color: AppColors.progress,
              backgroundColor: AppColors.border,
            ),
          ],
        ),
      ),
    );
    return card;
  }
}
