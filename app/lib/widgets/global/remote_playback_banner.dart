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
import '../../utils/on_screen.dart';
import '../../utils/poster_url.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../tv/tv_mode.dart';
import '../../l10n/tr.dart';
import 'app_network_image.dart';
import 'remote_playback_tv_card.dart';

/// « Lecture en cours sur un autre appareil » : ce que le compte lit ailleurs,
/// avec de quoi le reprendre ici là où il en est.
///
/// Reprendre ouvre le lecteur, dont le premier signal met l'autre appareil en
/// pause (voir `server/handlers/playback_handoff.go`).
///
/// Sur un téléviseur le bandeau n'est pas posé par-dessus l'accueil mais dans
/// sa page ([inline]) : un élément en surimpression n'entre dans aucune rangée
/// de la télécommande, et « Reprendre » y restait hors d'atteinte.
class RemotePlaybackBanner extends StatefulWidget {
  /// Dans le flux de la page, à la largeur de ses rangées, plutôt qu'en
  /// surimpression.
  final bool inline;

  const RemotePlaybackBanner({super.key, this.inline = false});

  @override
  State<RemotePlaybackBanner> createState() => _RemotePlaybackBannerState();
}

class _RemotePlaybackBannerState extends State<RemotePlaybackBanner>
    with OnScreenState {
  static const _pollInterval = Duration(seconds: 10);

  Timer? _timer;
  RemotePlayback? _current;
  final Set<String> _dismissed = {};
  bool _opening = false;

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
    HardwareKeyboard.instance.removeHandler(_onMediaKey);
    super.dispose();
  }

  /// Lecture/pause de la télécommande : sur une télévision, c'est le geste qui
  /// reprend ce que le compte lit ailleurs, sans avoir à viser le bouton. La
  /// Siri Remote n'a qu'une touche pour cela, et c'est celle que l'on presse en
  /// pensant « reprendre ».
  ///
  /// Seulement quand l'accueil est au premier plan : sous le lecteur ou une
  /// fiche, la touche garde son sens habituel.
  bool _onMediaKey(KeyEvent event) {
    if (event is! KeyDownEvent || !TvMode.isTv) return false;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.mediaPlayPause &&
        key != LogicalKeyboardKey.mediaPlay) {
      return false;
    }
    if (_current == null || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    unawaited(_resume());
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
    Provider.of<HomeProvider>(context, listen: false).loadHome(silent: true);
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final play = _current;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: play == null
          ? const SizedBox.shrink()
          : widget.inline
              ? _tvCard(context, play)
              : _card(context, play),
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
                    onPressed: () => setState(() {
                      _dismissed.add(_dismissKey(play));
                      _current = null;
                    }),
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

  /// Sur un téléviseur : voir [RemotePlaybackTvCard].
  Widget _tvCard(BuildContext context, RemotePlayback play) {
    final baseUrl =
        Provider.of<AuthProvider>(context, listen: false).apiClient.baseUrl;
    return RemotePlaybackTvCard(
      key: ValueKey(_dismissKey(play)),
      play: play,
      posterUrl: cardPosterUrl(play.session.posterUrl, serverBaseUrl: baseUrl),
      enabled: !_opening,
      onResume: _resume,
    );
  }
}
