import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../l10n/tr.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../widgets/global/app_network_image.dart';
import '../pause_info_content.dart';
import 'onyx/onyx_chrome_theme.dart';

/// L'écran « Vous regardez » posé sur un film laissé en pause (ADR-0137).
///
/// Il ne prend aucun geste : un clic traverse jusqu'à l'image (qui relance la
/// lecture sur un ordinateur), et c'est le lecteur qui le retire au premier
/// mouvement. Pas de verre ni de flou : un voile plat, dense à gauche, comme
/// le chrome au repos (ADR-0048).
class PauseInfoOverlay extends StatelessWidget {
  const PauseInfoOverlay({
    super.key,
    required this.content,
    required this.visible,
    required this.isTv,
  });

  final PauseInfoContent content;
  final bool visible;

  /// Sur un téléviseur, OK relance la lecture ; ailleurs, Espace.
  final bool isTv;

  static const Color _muted = OnyxChromeTheme.meta;
  static const Color _soft = OnyxChromeTheme.time;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey('pause-info'),
        opacity: visible ? 1 : 0,
        duration: AppMotion.fade(context, AppMotion.emphasis),
        curve: AppMotion.curve,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final pad = (width * 0.06).clamp(24.0, 80.0);
          final column = math.min(620.0, width * 0.5);
          return Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: OnyxChromeTheme.pauseInfoSideScrim,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.36,
                  widthFactor: 1,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: OnyxChromeTheme.pauseInfoBottomScrim,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: pad * 0.6,
                right: pad * 0.7,
                child: const _PausedBadge(),
              ),
              Positioned(
                left: pad,
                top: pad * 1.3,
                bottom: 120,
                width: column,
                child: _Summary(content: content),
              ),
              Positioned(
                left: pad,
                right: pad * 0.7,
                bottom: pad * 0.6,
                child: _Footer(
                  content: content,
                  progressWidth: column,
                  isTv: isTv,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _PausedBadge extends StatelessWidget {
  const _PausedBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.pause_rounded,
            size: 20, color: PauseInfoOverlay._soft),
        const SizedBox(width: 8),
        Text(
          tr('En pause').toUpperCase(),
          style: const TextStyle(
            color: PauseInfoOverlay._soft,
            fontSize: AppType.callout,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.content});

  final PauseInfoContent content;

  @override
  Widget build(BuildContext context) {
    final c = content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Vous regardez').toUpperCase(),
          style: const TextStyle(
            color: PauseInfoOverlay._muted,
            fontSize: AppType.subhead,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 14),
        if (c.showTitle != null) ...[
          _TitleLogo(
            url: c.logoUrl,
            height: 76,
            fallback: Text(
              c.showTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: OnyxChromeTheme.time,
                fontSize: AppType.display,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (c.episodeLine != null) ...[
          Text(
            c.episodeLine!,
            style: const TextStyle(
              color: PauseInfoOverlay._soft,
              fontSize: AppType.headline,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
        ],
        // Un film se présente par son logo ; un épisode, par son titre sous
        // le logo de la série.
        if (c.isEpisode)
          _title(c)
        else
          _TitleLogo(url: c.logoUrl, height: 124, fallback: _title(c)),
        const SizedBox(height: 14),
        _MetaRow(content: c),
        if (c.tagline != null) ...[
          const SizedBox(height: 16),
          Text(
            '« ${c.tagline!} »',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: OnyxChromeTheme.title,
              fontSize: AppType.title3,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (c.overview != null) ...[
          const SizedBox(height: 14),
          // Le résumé prend ce qui reste et se coupe plutôt que de pousser
          // le générique hors de l'écran.
          Flexible(
            child: Text(
              c.overview!,
              key: const ValueKey('pause-info-overview'),
              overflow: TextOverflow.fade,
              style: const TextStyle(
                color: OnyxChromeTheme.title,
                fontSize: AppType.headline,
                height: 1.55,
              ),
            ),
          ),
        ],
        if (c.director != null) ...[
          const SizedBox(height: 14),
          _Credit(label: tr('Réalisation'), value: c.director!),
        ],
        if (c.cast != null) ...[
          const SizedBox(height: 6),
          _Credit(label: tr('Avec'), value: c.cast!),
        ],
      ],
    );
  }
}

Widget _title(PauseInfoContent c) {
  return Text(
    c.title,
    key: const ValueKey('pause-info-title'),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: OnyxChromeTheme.title,
      fontSize: AppType.hero,
      height: 1.08,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
    ),
  );
}

/// Le logo-titre TMDB, à gauche, à sa hauteur et jamais plus large que la
/// colonne. Le texte tient la place tant qu'il charge, et la garde si le
/// titre n'en a pas : l'écran ne saute pas et ne reste jamais vide.
class _TitleLogo extends StatelessWidget {
  const _TitleLogo({
    required this.url,
    required this.height,
    required this.fallback,
  });

  final String? url;
  final double height;
  final Widget fallback;

  static const double _maxWidth = 460;

  @override
  Widget build(BuildContext context) {
    final logo = url;
    if (logo == null || logo.isEmpty) return fallback;
    return ConstrainedBox(
      key: const ValueKey('pause-info-logo'),
      constraints: BoxConstraints(maxWidth: _maxWidth, maxHeight: height),
      child: AppNetworkImage(
        url: logo,
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        fadeInDuration: const Duration(milliseconds: 120),
        // La même image que le chrome du lecteur et l'en-tête de la fiche :
        // décodée à sa taille, elle est déjà en mémoire.
        decodeAtSourceSize: true,
        placeholder: fallback,
        errorWidget: fallback,
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.content});

  final PauseInfoContent content;

  @override
  Widget build(BuildContext context) {
    final rating = content.ratingLabel;
    const style = TextStyle(
      color: PauseInfoOverlay._soft,
      fontSize: AppType.callout,
      fontWeight: FontWeight.w500,
    );
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (content.meta.isNotEmpty)
          Text(content.meta.join('  ·  '), style: style),
        if (rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 17, color: AppColors.rating),
              const SizedBox(width: 4),
              Text(
                rating,
                style: const TextStyle(
                  color: AppColors.rating,
                  fontSize: AppType.callout,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '$label   ',
          style: const TextStyle(color: PauseInfoOverlay._muted),
        ),
        TextSpan(text: value),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: PauseInfoOverlay._soft,
        fontSize: AppType.callout,
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.content,
    required this.progressWidth,
    required this.isTv,
  });

  final PauseInfoContent content;
  final double progressWidth;
  final bool isTv;

  @override
  Widget build(BuildContext context) {
    final c = content;
    const timeStyle = TextStyle(
      color: PauseInfoOverlay._soft,
      fontSize: AppType.callout,
      fontWeight: FontWeight.w500,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: progressWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (c.remaining != null)
                    Expanded(child: Text(c.remaining!, style: timeStyle)),
                  if (c.endClock != null)
                    Text(tr('Fin vers {0}', [c.endClock!]), style: timeStyle),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: OnyxChromeTheme.progressTrack),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: c.progress,
                        child: const ColoredBox(
                          color: OnyxChromeTheme.progressPlayed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (c.nextEpisodeTitle != null) ...[
              _NextEpisodeCard(
                title: c.nextEpisodeTitle!,
                meta: c.nextEpisodeMeta,
                stillUrl: c.nextEpisodeStillUrl,
              ),
              const SizedBox(height: 14),
            ],
            _ResumeHint(keyLabel: isTv ? tr('OK') : tr('Espace')),
          ],
        ),
      ],
    );
  }
}

class _NextEpisodeCard extends StatelessWidget {
  const _NextEpisodeCard({required this.title, this.meta, this.stillUrl});

  final String title;
  final String? meta;
  final String? stillUrl;

  static const double _width = 300;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(14));

  @override
  Widget build(BuildContext context) {
    final still = stillUrl;
    return Container(
      width: _width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: OnyxChromeTheme.glassSurfaceDense,
        borderRadius: _radius,
        border: Border.all(color: OnyxChromeTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // L'image de l'épisode, en 16:9 : une image tirée de l'épisode, que
          // le format d'une affiche rognerait. Sans image, la carte garde
          // son texte seul plutôt qu'un cadre vide.
          if (still != null && still.isNotEmpty)
            AspectRatio(
              key: const ValueKey('pause-info-next-still'),
              aspectRatio: 16 / 9,
              child: AppNetworkImage(
                url: still,
                width: _width,
                fit: BoxFit.cover,
                errorWidget: const ColoredBox(
                  color: OnyxChromeTheme.progressTrack,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _nextEpisodeText(),
          ),
        ],
      ),
    );
  }

  Widget _nextEpisodeText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Épisode suivant').toUpperCase(),
          style: const TextStyle(
            color: PauseInfoOverlay._muted,
            fontSize: AppType.footnote,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        if (meta != null && meta!.isNotEmpty)
          Text(
            meta!,
            style: const TextStyle(
              color: PauseInfoOverlay._soft,
              fontSize: AppType.subhead,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: OnyxChromeTheme.title,
            fontSize: AppType.headline,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ResumeHint extends StatelessWidget {
  const _ResumeHint({required this.keyLabel});

  final String keyLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: OnyxChromeTheme.iconDisabled),
          ),
          child: Text(
            keyLabel,
            style: const TextStyle(
              color: OnyxChromeTheme.title,
              fontSize: AppType.subhead,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          tr('pour reprendre la lecture'),
          style: const TextStyle(
            color: PauseInfoOverlay._soft,
            fontSize: AppType.callout,
          ),
        ),
      ],
    );
  }
}
