import 'package:flutter/material.dart';

import '../../../../l10n/tr.dart';
import '../../../../models/models.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_type.dart';
import '../../../../theme/focus_fill.dart';
import '../../../../tv/tv_focus.dart';
import '../../../../tv/tv_mode.dart';
import '../../../../utils/format.dart';
import '../onyx/onyx_capsule_button.dart';
import '../onyx/onyx_chrome_theme.dart';

/// L'onglet « Chapitres » du lecteur : une carte par chapitre, avec son heure ;
/// celui qu'on regarde est marqué, OK y saute (ADR-0130).
///
/// Des cartes de texte, sans image : le serveur ne garde pas de vue par
/// chapitre, et la vignette de la barre montre déjà l'endroit visé.
class PlayerChaptersTab extends StatefulWidget {
  const PlayerChaptersTab({
    super.key,
    required this.chapters,
    required this.positionSeconds,
    required this.onSeek,
  });

  final List<VideoChapter> chapters;
  final int positionSeconds;

  /// Saute au début d'un chapitre, en secondes.
  final ValueChanged<int> onSeek;

  @override
  State<PlayerChaptersTab> createState() => _PlayerChaptersTabState();
}

class _PlayerChaptersTabState extends State<PlayerChaptersTab> {
  static const double _cardWidth = 184;
  static const double _cardHeight = 92;
  static const double _gap = 14;

  final ScrollController _scroll = ScrollController();
  final FocusNode _currentCard = FocusNode(debugLabel: 'player-chapter-now');

  @override
  void initState() {
    super.initState();
    // La rangée s'ouvre sur le chapitre en cours ; les cartes ont toutes la
    // même largeur, la position se calcule.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _currentIndex;
      if (index <= 0) return;
      _scroll.jumpTo(
        (index * (_cardWidth + _gap))
            .clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _currentCard.dispose();
    super.dispose();
  }

  /// Le dernier chapitre déjà commencé.
  int get _currentIndex {
    var current = -1;
    for (var i = 0; i < widget.chapters.length; i++) {
      if (widget.chapters[i].startTime.floor() <= widget.positionSeconds) {
        current = i;
      }
    }
    return current;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        height: _cardHeight,
        child: OnyxControlsRow(
          preferredFocus: current >= 0 ? _currentCard : null,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: widget.chapters.length,
            separatorBuilder: (_, __) => const SizedBox(width: _gap),
            itemBuilder: (context, index) {
              final chapter = widget.chapters[index];
              final isCurrent = index == current;
              final name = chapter.title.isEmpty
                  ? tr('Chapitre {0}', [chapter.id])
                  : chapter.title;
              final time = formatPlaybackTime(chapter.startTime.round());
              return _ChapterCard(
                key: ValueKey('player-chapter-$index'),
                title: '${index + 1} · $name',
                detail: isCurrent ? '$time · ${tr('En cours')}' : time,
                isCurrent: isCurrent,
                focusNode: isCurrent ? _currentCard : null,
                onTap: () => widget.onSeek(chapter.startTime.round()),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChapterCard extends StatefulWidget {
  const _ChapterCard({
    super.key,
    required this.title,
    required this.detail,
    required this.isCurrent,
    required this.onTap,
    this.focusNode,
  });

  final String title;
  final String detail;
  final bool isCurrent;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<_ChapterCard> {
  FocusNode? _ownedNode;
  bool _hovered = false;

  FocusNode get _node =>
      widget.focusNode ??
      (_ownedNode ??= FocusNode(debugLabel: 'player-chapter'));

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(12));
    final tv = TvMode.isTv;
    return TvFocusable(
      focusNode: _node,
      onSelect: widget.onTap,
      borderRadius: radius,
      // La carte focalisée devient blanche : pas d'anneau en plus.
      showRing: !tv,
      focusScale: tv ? 1.04 : 1.0,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ListenableBuilder(
            listenable: _node,
            builder: (context, _) {
              final lit = tv && _node.hasFocus;
              final ink = lit ? FocusFill.ink : OnyxChromeTheme.title;
              return AnimatedContainer(
                duration: AppMotion.move(context, AppMotion.focus),
                curve: AppMotion.curve,
                width: _PlayerChaptersTabState._cardWidth,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: lit
                      ? FocusFill.fill
                      : widget.isCurrent || _hovered
                          ? OnyxChromeTheme.glassControl
                          : OnyxChromeTheme.glassCard,
                  // Toujours deux points d'épaisseur, transparents hors du
                  // chapitre en cours : le texte ne bouge pas d'une carte à
                  // l'autre.
                  border: Border.all(
                    color: widget.isCurrent && !lit
                        ? OnyxChromeTheme.chapterMark
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: AppType.callout,
                        height: 1.2,
                        fontWeight: widget.isCurrent
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: lit
                            ? FocusFill.ink.withValues(alpha: 0.62)
                            : OnyxChromeTheme.time,
                        fontSize: AppType.subhead,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
