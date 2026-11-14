import 'package:flutter/material.dart';

/// L'image du film, rétrécie dans un coin quand une page de fin la remplace.
///
/// The video shrinks into a corner while the end-of-season card is up, so the
/// credits stay watchable — the card never hides what is still playing.
/// Scaling instead of resizing keeps the media_kit texture at one size, which
/// avoids a reallocation hitch mid-animation.
class PlayerVideoStage extends StatefulWidget {
  const PlayerVideoStage({
    super.key,
    required this.scale,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  /// How much of the screen the video keeps: 1 at full size.
  final double scale;

  /// Vers quel coin l'image se range. Sans effet à pleine taille.
  final Alignment alignment;
  final Widget child;

  /// La page de l'épisode suivant (ADR-0130) : l'image du générique en haut à
  /// gauche, sur un peu plus du tiers de l'écran, pour laisser à droite la
  /// place de l'épisode qui vient.
  static const double nextEpisodeScale = 0.39;
  static const Alignment nextEpisodeAlignment = Alignment(-0.864, -0.563);

  /// Où tombe l'image rétrécie, dans un écran de [size].
  static Rect frameFor(Size size, {required double scale, required Alignment alignment}) {
    final width = size.width * scale;
    final height = size.height * scale;
    return Rect.fromLTWH(
      (size.width - width) * (1 + alignment.x) / 2,
      (size.height - height) * (1 + alignment.y) / 2,
      width,
      height,
    );
  }

  @override
  State<PlayerVideoStage> createState() => _PlayerVideoStageState();
}

class _PlayerVideoStageState extends State<PlayerVideoStage> {
  static const Duration _duration = Duration(milliseconds: 320);

  /// Le coin de la dernière page de fin. Gardé pendant le retour à pleine
  /// taille : l'image doit revenir du coin où elle était, pas sauter vers
  /// celui de la page suivante.
  late Alignment _alignment = widget.alignment;

  @override
  void didUpdateWidget(PlayerVideoStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scale < 1) _alignment = widget.alignment;
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    // Corner radius of the shrunk video, pre-divided by the scale so it looks
    // like 16pt on screen. Zero at full size, where rounding would just crop.
    final cornerRadius = scale < 1 ? 16 / scale : 0.0;
    return RepaintBoundary(
      child: AnimatedScale(
        scale: scale,
        alignment: _alignment,
        duration: _duration,
        curve: Curves.easeOutCubic,
        child: AnimatedPadding(
          padding: EdgeInsets.all(scale < 1 ? 26 : 0),
          duration: _duration,
          curve: Curves.easeOutCubic,
          // Radius and shadow are divided by the scale so they read
          // at their intended size once shrunk, instead of being
          // squashed along with the picture.
          child: AnimatedPhysicalModel(
            duration: _duration,
            curve: Curves.easeOutCubic,
            color: Colors.black,
            shadowColor: Colors.black,
            elevation: scale < 1 ? 24 / scale : 0,
            borderRadius: BorderRadius.circular(cornerRadius),
            // Only while the card has actually shrunk the picture.
            // At full size the radius is 0, so this clips a
            // rectangle to itself — an antialiased full-screen clip
            // over every decoded frame, for nothing. It is free to
            // skip on a desktop GPU and it is not free on a stick.
            clipBehavior: scale < 1 ? Clip.antiAlias : Clip.none,
            animateColor: false,
            child: SizedBox.expand(child: widget.child),
          ),
        ),
      ),
    );
  }
}
