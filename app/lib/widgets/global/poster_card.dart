import 'dart:async';

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/lite_mode.dart';
import '../../tv/tv_focus.dart';
import '../../tv/tv_focus_ring.dart';
import '../../tv/tv_mode.dart';
import 'app_network_image.dart';
import 'pressable.dart';
import '../../theme/app_icons.dart';

/// Single poster card used by every catalog grid (films, séries, bibliothèque,
/// demandes). The poster fills the whole grid cell above the metadata block, so
/// the cell's aspect ratio — not a hardcoded height — decides the poster size.
class PosterCard extends StatefulWidget {
  /// Fully resolved image URL (see `cardPosterUrl`). Null renders the fallback.
  ///
  /// This doubles as the cache identity: two cards showing the same artwork
  /// share one download and one decode, wherever in the app they live.
  final String? posterUrl;
  final String title;

  /// Secondary line (année · note · rôle…). Rendered even when empty so every
  /// card in a grid keeps the same baseline.
  final String? subtitle;
  final VoidCallback onTap;

  /// Badges / dots stacked over the poster (already `Positioned`).
  final List<Widget> overlays;

  /// Overlay posé en bas de l'affiche (progression…), en retrait des bords.
  ///
  /// Le retrait n'est pas cosmétique : une bande collée au bord bas devrait se
  /// faire découper par l'arrondi du coin, et son rayon à elle plus celui de
  /// l'affiche se lisaient comme deux coins mal alignés. Elle flotte donc à
  /// l'intérieur, comme les badges du haut, avec le même retrait qu'eux.
  final Widget? footerOverlay;

  /// Dims the poster for titles absent from the library.
  final bool dimmed;

  /// Titre et sous-titre sous l'affiche. Faux pour une grille d'affiches
  /// seules (Demander, comme OnyxHub) : l'affiche remplit alors toute la
  /// cellule, de ratio 2:3 (`AppLayout.posterGridDelegate(withMeta: false)`),
  /// et le titre reste lu par les lecteurs d'écran.
  final bool showMeta;

  /// Posé sur l'affiche quand elle est pointée (survol ou focus TV) : titre,
  /// type, résumé. Non peint tant qu'elle ne l'est pas — rien ne coûte pour
  /// les cartes au repos d'une grille.
  final Widget? hoverDetails;

  final IconData placeholderIcon;
  final bool compact;

  /// Takes the remote's focus as soon as the card is built. One card per screen
  /// sets this — the first poster of the first row — so a television lands on
  /// the content instead of on whatever the traversal policy sorts first.
  final bool autofocus;

  /// Called when the user settles on the card (hover, remote focus, press) —
  /// the moment to warm what [onTap] is about to open. See `DetailPrefetch`.
  final VoidCallback? onPrefetch;

  const PosterCard({
    super.key,
    required this.posterUrl,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.overlays = const [],
    this.footerOverlay,
    this.dimmed = false,
    this.showMeta = true,
    this.hoverDetails,
    this.placeholderIcon = AppIcons.movie,
    this.compact = false,
    this.autofocus = false,
    this.onPrefetch,
  });

  static const double radius = 12;

  /// Retrait commun à tout ce qui flotte au-dessus de l'affiche — badges et
  /// barre de progression — pour que rien ne vienne toucher l'arrondi.
  static const double overlayInset = 9;

  /// Combien l'affiche déborde de chaque côté quand elle se soulève. Les
  /// grilles et rangées espacent leurs cartes d'au moins 10 px : avec 4 px de
  /// part et d'autre, deux voisines en pleine transition (l'une qui monte,
  /// l'autre qui redescend) ne se touchent jamais.
  static const double liftOverflow = 4;

  /// Marge à réserver au-dessus d'une rangée horizontale : le zoom est ancré
  /// vers le bas de l'affiche (pour ne pas mordre sur le titre), donc l'essentiel
  /// du débord part vers le haut, là où le viewport de la liste couperait.
  static const double liftHeadroom = 10;

  /// Le soulèvement d'une affiche focalisée sur téléviseur : elle grandit de
  /// 10 % depuis son pied (ADR-0118).
  static const double tvLift = 1.10;

  /// La place à réserver autour d'une rangée horizontale d'affiches.
  ///
  /// Sur téléviseur, l'affiche focalisée grandit vers le haut depuis son pied
  /// ([PosterLift], [tvLift]) : 27 px pour une affiche de 176 px de large,
  /// que le titre de la rangée ne doit pas recevoir. En bas, la place de
  /// l'anneau du mode léger ([TvFocusRing.reach]) ; l'ombre, elle, déborde
  /// librement, la rangée d'un téléviseur ne se découpe pas.
  static EdgeInsets railRoom(BuildContext context) => TvScope.of(context)
      ? const EdgeInsets.only(top: 30, bottom: 8)
      : const EdgeInsets.only(top: liftHeadroom);

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hovered = false;
  bool _focused = false;

  /// Hover and D-pad focus are the same state as far as this card is concerned:
  /// "the user is pointing at me". One flag drives one highlight, so the mouse
  /// and the remote never disagree about which card is live.
  bool get _active => _hovered || _focused;

  Timer? _prefetchTimer;

  /// How long the pointer (or the remote's focus) has to rest on the card
  /// before [PosterCard.onPrefetch] fires. Sweeping across a row does not
  /// warm every title it crosses; stopping on one does, a few hundred ms
  /// before the click.
  static const Duration _prefetchIntent = Duration(milliseconds: 120);

  void _schedulePrefetch() {
    if (widget.onPrefetch == null) return;
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(_prefetchIntent, _prefetchNow);
  }

  void _cancelPrefetch() {
    _prefetchTimer?.cancel();
    _prefetchTimer = null;
  }

  void _prefetchNow() {
    _cancelPrefetch();
    if (mounted) widget.onPrefetch?.call();
  }

  @override
  void dispose() {
    _cancelPrefetch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;

    return TvFocusable(
      onSelect: widget.onTap,
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(PosterCard.radius),
      // The artwork lights up on its own below; a ring around the title lines
      // as well would double the outline.
      showRing: false,
      // [PosterLift] soulève déjà l'affiche : un second zoom, de toute la
      // carte, la faisait déborder de la rangée.
      focusScale: 1.0,
      onFocusChange: (focused) {
        if (_focused == focused) return;
        setState(() => _focused = focused);
        focused ? _schedulePrefetch() : _cancelPrefetch();
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hovered = true);
          _schedulePrefetch();
        },
        onExit: (_) {
          setState(() => _hovered = false);
          _cancelPrefetch();
        },
        child: Pressable(
          onTap: widget.onTap,
          // Touch has no hover: the press itself is the earliest signal, a
          // hundred-odd ms before the tap is confirmed.
          onTapDown: widget.onPrefetch == null ? null : _prefetchNow,
          builder: (context, pressed) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _maybeLabelled(PressScale(
                  pressed: pressed,
                  child: PosterLift(
                    active: _active,
                    focused: _focused,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(PosterCard.radius),
                          child: _poster(),
                        ),
                        PosterHoverOverlay(
                          active: _active,
                          focused: _focused,
                          showPlay: false,
                        ),
                        if (widget.hoverDetails != null)
                          PosterHoverDetails(
                            active: _active,
                            // Le texte s'arrête au-dessus de la barre de
                            // progression, qui reste lisible sous le cartouche.
                            bottomClearance:
                                widget.footerOverlay == null ? 0 : 8,
                            child: widget.hoverDetails!,
                          ),
                        ...widget.overlays,
                        if (widget.footerOverlay != null)
                          Positioned(
                            left: PosterCard.overlayInset,
                            right: PosterCard.overlayInset,
                            bottom: PosterCard.overlayInset,
                            child: widget.footerOverlay!,
                          ),
                      ],
                    ),
                  ),
                )),
              ),
              if (widget.showMeta) ...[
                SizedBox(height: compact ? 7 : 9),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: -0.1,
                    color: widget.dimmed
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    height: 1.2,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Sans ligne de titre, l'affiche porte le nom de la carte.
  Widget _maybeLabelled(Widget poster) => widget.showMeta
      ? poster
      : Semantics(label: widget.title, button: true, child: poster);

  /// L'image grossit de 5 % sous le pointeur, lentement (700 ms), pendant que
  /// la carte se soulève : OnyxHub (`group-hover:scale-105`). Un simple
  /// agrandissement de l'image déjà décodée, que le GPU fait seul ; rien à
  /// repeindre ni à redécoder. Absent en mode léger et en mouvement réduit.
  Widget _poster() {
    final image = _posterImage();
    final motion = _posterMotion(context, _zoom);
    if (motion == Duration.zero) return image;
    return AnimatedScale(
      scale: _active ? 1.05 : 1,
      duration: motion,
      curve: Curves.easeOutCubic,
      child: image,
    );
  }

  static const Duration _zoom = Duration(milliseconds: 700);

  Widget _posterImage() {
    return AppNetworkImage(
      url: widget.posterUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      color: widget.dimmed ? AppColors.unavailableTint : null,
      colorBlendMode: widget.dimmed ? BlendMode.darken : null,
      placeholder: const ColoredBox(color: AppColors.surfaceElevated),
      errorWidget: _fallback(broken: widget.posterUrl?.isNotEmpty ?? false),
    );
  }

  Widget _fallback({bool broken = false}) {
    return ColoredBox(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(
          broken ? AppIcons.imageBroken : widget.placeholderIcon,
          color: AppColors.textMuted,
          size: 42,
        ),
      ),
    );
  }
}

/// Durée commune aux animations de survol des affiches. Coupée net quand le
/// système demande de réduire les animations.
Duration _posterMotion(BuildContext context, Duration base) =>
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
            LiteScope.of(context)
        ? Duration.zero
        : base;

/// Soulève une affiche quand elle est pointée : un léger zoom et une ombre qui
/// s'épaissit, comme si elle sortait de l'écran.
///
/// Le zoom est calculé en pixels plutôt qu'en pourcentage, pour que le débord
/// ([PosterCard.liftOverflow]) reste le même d'une petite carte de rangée à une
/// grande carte de grille — et ne vienne jamais toucher la voisine.
///
/// Sur téléviseur, c'est le soulèvement lui-même qui dit où est le focus
/// (ADR-0118, qui remplace l'ADR-0111) : l'affiche grandit de
/// [PosterCard.tvLift] et porte une ombre profonde, sans anneau. En mode
/// léger, où l'ombre est retirée (ADR-0086), l'anneau revient : sans l'un ni
/// l'autre, 10 % de taille ne suffiraient pas à se repérer.
class PosterLift extends StatelessWidget {
  final bool active;

  /// Focus télécommande : l'anneau ([TvFocusRing]) se pose autour de
  /// l'affiche, à un jour de son bord, et suit son soulèvement.
  final bool focused;
  final Widget child;

  const PosterLift({
    super.key,
    required this.active,
    this.focused = false,
    required this.child,
  });

  static const Duration duration = Duration(milliseconds: 260);

  /// Point fixe du zoom : aux trois quarts de la hauteur, l'affiche grandit
  /// surtout vers le haut et à peine vers le titre en dessous.
  static const Alignment anchor = Alignment(0, 0.5);

  /// Sur téléviseur, le pied de l'affiche ne bouge pas : son anneau reste
  /// au-dessus du titre, à la place que [PosterCard.railRoom] lui réserve.
  static const Alignment tvAnchor = Alignment.bottomCenter;

  /// L'ombre d'une affiche soulevée sur téléviseur : une large et lointaine
  /// qui la détache de la rangée, une courte qui garde son bord net.
  static const List<BoxShadow> _tvShadow = [
    BoxShadow(
      color: Color(0xB3000000),
      blurRadius: 44,
      spreadRadius: -6,
      offset: Offset(0, 26),
    ),
    BoxShadow(
      color: Color(0x73000000),
      blurRadius: 14,
      offset: Offset(0, 6),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final motion = _posterMotion(context, duration);
    // Une ombre floutée par affiche, repeinte à chaque image d'un défilement :
    // une grille de cinquante affiches en paie cinquante. Le mode léger garde
    // le zoom et retire l'ombre (ADR-0086).
    final shadows = !LiteScope.of(context);
    final tv = TvScope.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final lifted = tv && focused
            ? PosterCard.tvLift
            : width.isFinite && width > 0
                ? (1 + PosterCard.liftOverflow * 2 / width).clamp(1.0, 1.06)
                : 1.0;

        return AnimatedScale(
          scale: active ? lifted : 1.0,
          alignment: tv ? tvAnchor : anchor,
          duration: motion,
          curve: active ? Curves.easeOutCubic : Curves.easeOutQuart,
          child: AnimatedContainer(
            duration: motion,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PosterCard.radius),
              // Au repos, aucune ombre : une ombre transparente restait une
              // ombre floutée à dessiner pour chaque affiche d'une grille, à
              // chaque image d'un défilement. `lerp` entre « aucune » et la
              // liste la fait grandir depuis rien, et revenir à rien.
              boxShadow: !shadows || !active
                  ? null
                  : tv && focused
                      ? _tvShadow
                      : const [
                          BoxShadow(
                            color: Color(0x8C000000),
                            blurRadius: 22,
                            spreadRadius: -4,
                            offset: Offset(0, 12),
                          ),
                        ],
            ),
            // L'ombre se redessine à chaque image du survol ; sans calque
            // propre, l'affiche et ses voiles le feraient avec elle.
            child: TvFocusRing(
              visible: focused && tv && !shadows,
              outset: true,
              borderRadius: BorderRadius.circular(PosterCard.radius),
              child: RepaintBoundary(child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Ce qui se pose sur l'affiche pointée : un voile qui s'assombrit vers le bas,
/// le bouton lecture qui éclot au centre et le liseré de sélection.
///
/// Tout reste monté et s'anime en fondu : un voile qui apparaissait d'un coup
/// clignotait à chaque passage de souris sur une rangée.
class PosterHoverOverlay extends StatelessWidget {
  final bool active;

  /// Focus clavier : le liseré passe au blanc du focus. Sur téléviseur, il
  /// s'efface devant l'anneau que [PosterLift] trace autour de l'affiche.
  final bool focused;

  /// Voile + bouton lecture — seulement pour ce qui se lance directement.
  final bool showPlay;
  final double playSize;

  const PosterHoverOverlay({
    super.key,
    required this.active,
    this.focused = false,
    this.showPlay = true,
    this.playSize = 50,
  });

  static const Duration _fade = Duration(milliseconds: 220);
  static const Duration _pop = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    final fade = _posterMotion(context, _fade);
    final pop = _posterMotion(context, _pop);
    final radius = BorderRadius.circular(PosterCard.radius);
    final ringed = focused && !TvScope.of(context);

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showPlay)
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: fade,
              curve: Curves.easeOutCubic,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  // Plus léger en haut, où sont les visages et le titre de
                  // l'affiche ; plus dense en bas, sous le bouton et la barre
                  // de progression qui doivent ressortir.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.12),
                      Colors.black.withValues(alpha: 0.30),
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          if (showPlay)
            Center(
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: fade,
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: active ? 1 : 0.7,
                  duration: pop,
                  curve: active ? Curves.easeOutBack : Curves.easeInCubic,
                  child: _PlayDisc(size: playSize),
                ),
              ),
            ),
          AnimatedContainer(
            duration: fade,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: !active || (focused && !ringed)
                    ? Colors.white.withValues(alpha: 0)
                    : ringed
                        ? AppColors.focus
                        : Colors.white.withValues(alpha: 0.22),
                width: ringed ? TvFocusRing.width : 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le cartouche d'une affiche pointée, à la manière des cartes d'OnyxHub : un
/// dégradé qui monte du bas et les [HoverLine] de [child] (titre, type,
/// résumé) qui montent l'une après l'autre en apparaissant.
///
/// Au repos, l'opacité nulle saute la peinture entière du sous-arbre : une
/// grille de cinquante affiches n'en dessine aucun. Le glissé passe par
/// [_posterMotion], donc disparaît en mode léger ; le fondu reste.
class PosterHoverDetails extends StatelessWidget {
  final bool active;
  final Widget child;

  /// La place à laisser sous le texte pour ce qui flotte en bas de l'affiche.
  final double bottomClearance;

  const PosterHoverDetails({
    super.key,
    required this.active,
    required this.child,
    this.bottomClearance = 0,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: AppMotion.fade(context),
        curve: AppMotion.curve,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PosterCard.radius),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.92),
                Colors.black.withValues(alpha: 0.4),
                Colors.black.withValues(alpha: 0),
              ],
              stops: const [0, 0.5, 0.85],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: _HoverActive(
              active: active,
              child: Padding(
                padding: const EdgeInsets.all(PosterCard.overlayInset + 3)
                    .copyWith(
                        bottom: PosterCard.overlayInset + 3 + bottomClearance),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverActive extends InheritedWidget {
  final bool active;

  const _HoverActive({required this.active, required super.child});

  @override
  bool updateShouldNotify(_HoverActive old) => active != old.active;
}

/// Une ligne du cartouche : elle monte de quelques pixels quand la carte est
/// pointée, [rank] fois 75 ms après la précédente (`delay-75`, `delay-100`
/// chez OnyxHub), et redescend aussitôt, sans attendre son tour.
///
/// Un seul `AnimatedSlide` par ligne et pas de contrôleur : le retard est
/// une part de la durée (`Interval`), pas une minuterie.
class HoverLine extends StatelessWidget {
  final int rank;
  final Widget child;

  const HoverLine({super.key, required this.rank, required this.child});

  static const Duration _rise = Duration(milliseconds: 300);
  static const Duration _step = Duration(milliseconds: 75);

  @override
  Widget build(BuildContext context) {
    final active =
        context.dependOnInheritedWidgetOfExactType<_HoverActive>()?.active ??
            true;
    final wait = _step * rank;
    final total = active ? _rise + wait : AppMotion.micro;
    return AnimatedSlide(
      offset: active ? Offset.zero : const Offset(0, 0.7),
      duration: _posterMotion(context, total),
      curve: active
          ? Interval(wait.inMicroseconds / total.inMicroseconds, 1,
              curve: Curves.easeOutCubic)
          : Curves.easeIn,
      child: child,
    );
  }
}

class _PlayDisc extends StatelessWidget {
  final double size;

  const _PlayDisc({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.96),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // Pas de décalage ajouté : le glyphe Phosphor est déjà posé sur son
      // centre de gravité, à droite du milieu de sa case. Le pousser encore
      // le faisait sortir du centre du disque.
      alignment: Alignment.center,
      child: Icon(
        AppIcons.play,
        size: size * 0.62,
        color: Colors.black.withValues(alpha: 0.88),
      ),
    );
  }
}
