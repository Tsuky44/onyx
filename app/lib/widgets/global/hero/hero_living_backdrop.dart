import 'dart:async';

import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../utils/on_screen.dart';
import '../app_network_image.dart';

/// Une image du fond du bandeau, et l'épisode d'où elle vient.
@immutable
class HeroBackdropFrame {
  const HeroBackdropFrame(this.url, {this.caption});

  final String url;

  /// « S1 E5 · La tempête ». Nul pour l'image de la série ou du film.
  final String? caption;

  @override
  bool operator ==(Object other) =>
      other is HeroBackdropFrame &&
      other.url == url &&
      other.caption == caption;

  @override
  int get hashCode => Object.hash(url, caption);
}

/// Le fond vivant du bandeau d'accueil (ADR-0154) : ses images passent de
/// l'une à l'autre en fondu, chacune sous un zoom lent.
///
/// Une image seule zoome aussi, une fois, puis se fige. Sans [animate] (sur un
/// téléviseur, en mode léger, sous « réduire les animations », ou sur une
/// diapositive voisine que le carrousel construit hors de la vue), seule la
/// première image est posée, immobile.
///
/// L'image suivante se décode pendant que la précédente est à l'écran : le
/// fondu ne passe jamais par le noir d'une image encore en route.
class HeroLivingBackdrop extends StatefulWidget {
  const HeroLivingBackdrop({
    super.key,
    required this.frames,
    required this.animate,
    required this.decodeWidth,
    this.frame,
  });

  /// Le temps d'une image à l'écran, fondu compris.
  static const Duration frameDuration = Duration(seconds: 4);

  static const Duration crossfade = Duration(milliseconds: 900);

  /// Le zoom d'une image seule : plus long que la diapositive, il ne
  /// s'arrête pas sous les yeux.
  static const Duration soloDrift = Duration(seconds: 20);

  /// Jusqu'où l'image grossit : assez pour qu'on la sente vivre, pas assez
  /// pour couper un visage au bord.
  static const double driftScale = 1.06;

  final List<HeroBackdropFrame> frames;
  final bool animate;

  /// La largeur logique de décodage, celle de [AppNetworkImage.decodeWidth].
  final double decodeWidth;

  /// Le rang de l'image affichée, que lit [HeroBackdropCaption].
  final ValueNotifier<int>? frame;

  @override
  State<HeroLivingBackdrop> createState() => _HeroLivingBackdropState();
}

class _HeroLivingBackdropState extends State<HeroLivingBackdrop>
    with OnScreenState {
  int _index = 0;
  Timer? _timer;

  /// Les images décodées : on ne passe qu'à l'une d'elles.
  final Set<String> _ready = {};

  bool get _cycles => widget.animate && widget.frames.length > 1 && isOnScreen;

  @override
  void didChangeOnScreen(bool onScreen) => _schedule();

  @override
  void didUpdateWidget(HeroLivingBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = !listEquals(oldWidget.frames, widget.frames);
    if (changed && _index >= widget.frames.length) {
      _index = 0;
      // Pas pendant la construction : la légende qui écoute se reconstruit
      // à l'image suivante.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.frame?.value = _index;
      });
    }
    if (changed || oldWidget.animate != widget.animate) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_cycles) return;
    _warm((_index + 1) % widget.frames.length);
    _timer = Timer(HeroLivingBackdrop.frameDuration, _advance);
  }

  void _warm(int index) {
    final url = widget.frames[index].url;
    if (_ready.contains(url)) return;
    AppNetworkImage.precache(
      url,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      decodeWidth: widget.decodeWidth,
    ).then((_) => _ready.add(url));
  }

  void _advance() {
    _timer = null;
    if (!mounted || !_cycles) return;
    final next = (_index + 1) % widget.frames.length;
    if (next != 0 && !_ready.contains(widget.frames[next].url)) {
      // Encore en route : l'image affichée reste un peu plus.
      _timer = Timer(const Duration(seconds: 1), _advance);
      return;
    }
    setState(() => _index = next);
    widget.frame?.value = next;
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frames.isEmpty) {
      return const ColoredBox(color: AppColors.background);
    }
    final index = _index.clamp(0, widget.frames.length - 1);
    final frame = widget.frames[index];
    final drift = widget.frames.length > 1
        ? HeroLivingBackdrop.frameDuration + HeroLivingBackdrop.crossfade
        : HeroLivingBackdrop.soloDrift;
    return AnimatedSwitcher(
      duration: AppMotion.fade(context, HeroLivingBackdrop.crossfade),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: _Drift(
        key: ValueKey('${frame.url}#$index'),
        animate: widget.animate,
        duration: drift,
        // Une image sur deux grossit vers l'autre côté : deux zooms de suite
        // vers le même point se lisaient comme un seul, saccadé.
        alignment: index.isOdd
            ? const Alignment(-0.3, 0.2)
            : const Alignment(0.4, -0.2),
        child: AppNetworkImage(
          url: frame.url,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.high,
          decodeWidth: widget.decodeWidth,
          fadeInDuration: AppMotion.emphasis,
          placeholder: const ColoredBox(color: AppColors.background),
          errorWidget: const ColoredBox(color: AppColors.background),
        ),
      ),
    );
  }
}

/// Le zoom lent d'une image. L'arbre ne change pas avec [animate] : passer de
/// l'un à l'autre recréait l'image, qui rejouait son apparition en fondu.
class _Drift extends StatelessWidget {
  const _Drift({
    super.key,
    required this.animate,
    required this.duration,
    required this.alignment,
    required this.child,
  });

  final bool animate;
  final Duration duration;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: 1,
        end: animate ? HeroLivingBackdrop.driftScale : 1,
      ),
      duration: animate ? duration : Duration.zero,
      curve: Curves.easeOut,
      child: child,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: alignment,
        child: child,
      ),
    );
  }
}

/// D'où vient l'image du fond : « S1 E5 · La tempête », qui change avec elle.
/// Rien sous l'image de la série elle-même.
class HeroBackdropCaption extends StatelessWidget {
  const HeroBackdropCaption({
    super.key,
    required this.frames,
    required this.frame,
    this.textAlign = TextAlign.end,
  });

  final List<HeroBackdropFrame> frames;
  final ValueListenable<int> frame;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: frame,
      builder: (context, index, _) {
        final caption = index < frames.length ? frames[index].caption : null;
        return AnimatedSwitcher(
          duration: AppMotion.fade(context, HeroLivingBackdrop.crossfade),
          child: Text(
            caption ?? '',
            key: ValueKey(caption),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppType.footnote,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
            ),
          ),
        );
      },
    );
  }
}
