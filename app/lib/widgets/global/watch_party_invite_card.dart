import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../models/watch_party_invite.dart';
import '../../screens/player/widgets/onyx/onyx_capsule_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_type.dart';
import '../../utils/poster_url.dart';
import 'app_network_image.dart';
import 'glass_chrome.dart';

/// « alex vous invite à regarder ensemble » : la carte d'une invitation
/// (ADR-0148), du même verre que la lecture d'un autre appareil
/// (`RemotePlaybackNotice`), et posée au même endroit sur l'accueil.
///
/// Deux réponses, chacune un bouton : « Ignorer » et « Rejoindre ». Sous la
/// télécommande, « Rejoindre » reçoit le focus ([acceptFocus]) et OK y
/// répond ; gauche mène à « Ignorer ». Un toucher ou un clic répond partout.
///
/// Dans le lecteur, la carte ne reste que dix secondes : [countdown] descend
/// de 1 à 0 sous les boutons, et [glass] la pose sur le verre du lecteur, le
/// seul qui ait le droit de flouter le film.
class WatchPartyInviteCard extends StatelessWidget {
  const WatchPartyInviteCard({
    super.key,
    required this.invite,
    required this.serverBaseUrl,
    required this.onAccept,
    required this.onDecline,
    this.joining = false,
    this.compact = false,
    this.countdown,
    this.acceptFocus,
    this.glass,
  });

  final WatchPartyInvite invite;
  final String? serverBaseUrl;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// La séance est en train d'être rejointe : « Rejoindre » tourne.
  final bool joining;

  /// Sur un téléphone : à la largeur de l'écran, plutôt que la largeur fixe
  /// d'une notification.
  final bool compact;

  /// Le temps qu'il reste à la carte du lecteur, de 1 à 0.
  final Animation<double>? countdown;

  final FocusNode? acceptFocus;

  /// Le verre sous la carte. Par défaut celui de l'accueil ([GlassSurface]).
  final Widget Function(BorderRadius radius, Widget child)? glass;

  /// La largeur d'une notification de l'accueil : celle de la lecture d'un
  /// autre appareil, pour que les deux s'alignent quand elles s'empilent.
  static const double width = 388;
  static const double compactMaxWidth = 560;

  static const double _posterWidth = 46;
  static const double _posterHeight = 69;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(22));

  /// Ce que la carte dit de l'invitation : le titre, et l'épisode s'il y en a.
  static (String headline, String? detail) describe(WatchPartyInvite invite) {
    final item = invite.media;
    if (item == null) return (tr('Regarder ensemble'), null);
    final media = item.media;
    final season = media.seasonNumber;
    final episode = media.episodeNumber;
    final number = season != null && episode != null
        ? tr('S{0} E{1}', [season, episode])
        : null;
    final episodeTitle = item.episodeTitle;
    final detail = [
      if (number != null) number,
      if (episodeTitle != null && episodeTitle.isNotEmpty) episodeTitle,
    ].join(' · ');
    return (
      item.showTitle ?? media.title,
      detail.isEmpty ? null : detail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (headline, detail) = describe(invite);
    final item = invite.media;
    final poster = cardPosterUrl(
      item?.showPosterUrl ?? item?.media.posterUrl,
      serverBaseUrl: serverBaseUrl,
    );
    final from = invite.from.isEmpty ? tr('Quelqu’un') : invite.from;

    final posterBox = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _posterWidth,
        height: _posterHeight,
        child: poster == null
            ? const ColoredBox(color: AppColors.surfaceHover)
            : AppNetworkImage(
                url: poster,
                width: _posterWidth,
                height: _posterHeight,
                errorWidget: const ColoredBox(color: AppColors.surfaceHover),
              ),
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(AppIcons.watchParty,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tr('Invitation à regarder ensemble').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          tr('{0} vous invite', [from]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: AppType.headline,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            height: 1.25,
          ),
        ),
        Text(
          detail == null ? headline : '$headline · $detail',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppType.subhead,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ],
    );

    final countdown = this.countdown;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 12),
          child: Row(
            children: [
              posterBox,
              const SizedBox(width: 14),
              Expanded(child: text),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          // Gauche et droite y restent sous la télécommande ; « Rejoindre »
          // est à droite, là où l'œil finit la ligne.
          child: OnyxControlsRow(
            preferredFocus: acceptFocus,
            child: Row(
              children: [
                Expanded(
                  child: OnyxCapsuleButton(
                    key: const ValueKey('watch-party-invite-decline'),
                    label: tr('Ignorer'),
                    expanded: true,
                    onPressed: joining ? null : onDecline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OnyxCapsuleButton(
                    key: const ValueKey('watch-party-invite-accept'),
                    label: tr('Rejoindre'),
                    icon: AppIcons.play,
                    primary: true,
                    expanded: true,
                    busy: joining,
                    focusNode: acceptFocus,
                    onPressed: onAccept,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (countdown != null)
          AnimatedBuilder(
            animation: countdown,
            builder: (context, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: countdown.value.clamp(0.0, 1.0),
                child: const ColoredBox(
                  color: AppColors.textPrimary,
                  child: SizedBox(height: 3),
                ),
              ),
            ),
          ),
      ],
    );

    final surface = glass?.call(_radius, body) ??
        GlassSurface(borderRadius: _radius, dense: true, child: body);
    final card = DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 44,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: _radius, child: surface),
    );

    return Semantics(
      container: true,
      liveRegion: true,
      label: tr('{0} vous invite à regarder {1} ensemble.', [from, headline]),
      child: compact
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: compactMaxWidth),
              child: card,
            )
          : SizedBox(width: width, child: card),
    );
  }
}
