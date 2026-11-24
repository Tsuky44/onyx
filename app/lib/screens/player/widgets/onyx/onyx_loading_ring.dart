import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import '../../../../l10n/tr.dart';
import '../../../../theme/app_motion.dart';
import '../../../../widgets/global/glass_chrome.dart';
import 'onyx_chrome_theme.dart';

/// L'attente du lecteur (ADR-0140) : un anneau blanc et fin dont la tête
/// tourne et dont la traîne s'efface, posé sur une ombre pour se lire sur un
/// plan clair comme sur le noir du démarrage.
///
/// Il remplace le cercle bleu de Material, d'une autre couleur que tout le
/// chrome (blanc sur l'image, verre, ADR-0130), et centré sur l'écran quand le
/// bouton lecture d'un écran tenu en main est à 42 % de sa hauteur.
///
/// **Il vit toujours.** Immobile, une attente se lit comme un plantage : sur
/// une Apple TV HD, que son matériel met d'office en mode léger, l'anneau ne
/// tournait jamais. Le mode léger et « réduire les animations » changent sa
/// façon de vivre, pas le fait qu'il vive :
///
/// - là où le verre ne floute pas ([glassBlurs] : mode léger, web), son ombre
///   floue devient un halo plat. C'est le flou, refait à chaque image, qui
///   coûte à une puce A8, pas un arc de 52 points ;
/// - sous « réduire les animations » du système, il ne tourne plus : il
///   respire, par l'opacité seule ([AppMotion.waitBreath]).
///
/// Chaque image ne repeint que lui : le dessin écoute l'animation
/// (`repaint:`), rien n'est reconstruit, et un [RepaintBoundary] l'isole. Ni
/// `saveLayer` ni calque d'opacité : son arrivée en fondu et sa respiration
/// passent par l'alpha des traits.
///
/// Il part comme il arrive ([present]) : en fondu, et sans perdre son tour si
/// l'attente reprend aussitôt. Démonté net à la fin de chaque attente, il
/// claquait à l'écran et repartait du haut à la suivante, ce qui, dans une
/// suite de tampons courts après une recherche, se lisait comme une saccade.
class OnyxLoadingRing extends StatefulWidget {
  const OnyxLoadingRing({
    super.key,
    this.size = defaultSize,
    this.present = true,
    this.onGone,
  });

  /// Le diamètre : celui du disque de lecture/pause qu'il remplace sur un
  /// écran tenu en main, un peu moins que sa cible de 78.
  static const double defaultSize = 52;

  final double size;

  /// Faux : l'attente est finie. L'anneau s'efface comme il est arrivé, sans
  /// cesser de tourner, puis appelle [onGone]. Redevenu vrai avant la fin, il
  /// remonte de là où il en était, sur le même tour.
  final bool present;

  /// L'anneau a fini de s'effacer : il peut être démonté.
  final VoidCallback? onGone;

  @override
  State<OnyxLoadingRing> createState() => _OnyxLoadingRingState();
}

class _OnyxLoadingRingState extends State<OnyxLoadingRing>
    with TickerProviderStateMixin {
  /// Le cycle sans fin : un tour, ou une respiration.
  late final AnimationController _cycle = AnimationController(vsync: this);

  /// L'arrivée : l'anneau monte en opacité au lieu de surgir, pour qu'un
  /// tampon vide d'un quart de seconde ne clignote pas au milieu de l'image.
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  )
    ..addStatusListener(_onArrivalStatus)
    ..forward();

  void _onArrivalStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.present) {
      widget.onGone?.call();
    }
  }

  @override
  void didUpdateWidget(covariant OnyxLoadingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.present == widget.present) return;
    if (widget.present) {
      _arrival.forward();
    } else {
      _arrival.reverse();
    }
  }

  OnyxLoadingRingPainter? _painter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Le réglage du système seul, pas `AppMotion.reduced` : le mode léger
    // allège le dessin, il n'arrête pas l'anneau.
    final breathes = MediaQuery.disableAnimationsOf(context);
    final soft = glassBlurs(context);
    final previous = _painter;
    if (previous != null &&
        previous.breathes == breathes &&
        previous.soft == soft) {
      return;
    }
    _painter = OnyxLoadingRingPainter(
      cycle: _cycle,
      arrival: _arrival,
      breathes: breathes,
      soft: soft,
    );
    if (previous != null && previous.breathes == breathes) return;
    if (breathes) {
      _cycle.repeat(reverse: true, period: AppMotion.waitBreath);
    } else {
      _cycle.repeat(period: AppMotion.waitTurn);
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Chargement'),
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _painter,
        ),
      ),
    );
  }
}

/// Le dessin de [OnyxLoadingRing] : il se repeint à chaque pas de [cycle] et
/// de [arrival], sans que rien ne soit reconstruit.
class OnyxLoadingRingPainter extends CustomPainter {
  OnyxLoadingRingPainter({
    required this.cycle,
    required this.arrival,
    this.breathes = false,
    this.soft = true,
  }) : super(repaint: Listenable.merge([cycle, arrival]));

  /// Le cycle sans fin, de 0 à 1 : un tour, ou une demi-respiration qui
  /// repart en sens inverse quand l'anneau [breathes].
  final Animation<double> cycle;

  /// L'arrivée de l'anneau, de 0 (absent) à 1 (présent).
  final Animation<double> arrival;

  /// L'anneau ne tourne pas, il respire : sous « réduire les animations ».
  final bool breathes;

  /// L'ombre est floue. Faux là où le verre ne floute pas : un halo plat.
  final bool soft;

  /// L'épaisseur du trait, rapportée au diamètre.
  static const double strokeRatio = 0.075;

  /// La longueur de la traîne, en fraction du tour.
  static const double sweep = 0.78;

  /// Le creux d'une respiration : assez bas pour qu'on voie l'anneau vivre,
  /// assez haut pour qu'il ne disparaisse pas d'un plan clair.
  static const double breathFloor = 0.38;

  /// La fraction du tour où en est la tête. Nulle quand l'anneau respire.
  double get turn => breathes ? 0 : cycle.value;

  /// L'opacité de l'anneau entier : son arrivée, et sa respiration.
  double get opacity {
    if (!breathes) return arrival.value;
    final dip = Curves.easeInOut.transform(cycle.value);
    return arrival.value * lerpDouble(1, breathFloor, dip)!;
  }

  final Paint _shadow = Paint()..style = PaintingStyle.stroke;
  final Paint _track = Paint()..style = PaintingStyle.stroke;
  final Paint _trail = Paint()..style = PaintingStyle.stroke;
  final Paint _head = Paint();

  // Le dégradé de la traîne ne dépend que de la taille : il est calculé une
  // fois, et c'est le canevas qui tourne dessous.
  Rect? _trailRect;
  Shader? _trailShader;

  Shader _trailFor(Rect rect) {
    if (_trailRect != rect) {
      _trailRect = rect;
      _trailShader = SweepGradient(
        endAngle: sweep * 2 * math.pi,
        colors: [
          OnyxChromeTheme.progressPlayed.withValues(alpha: 0),
          OnyxChromeTheme.progressPlayed,
        ],
      ).createShader(rect);
    }
    return _trailShader!;
  }

  static Color _dim(Color color, double factor) =>
      color.withValues(alpha: color.a * factor);

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = this.opacity;
    if (opacity <= 0) return;
    final stroke = size.shortestSide * strokeRatio;
    final rect = (Offset.zero & size).deflate(stroke);
    final centre = rect.center;
    final radius = rect.width / 2;

    // L'ombre d'abord : sans elle, le blanc disparaît sur un ciel.
    if (soft) {
      canvas.drawCircle(
        centre,
        radius,
        _shadow
          ..strokeWidth = stroke * 2.4
          ..color = _dim(OnyxChromeTheme.glassShadow, 0.35 * opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.6),
      );
    } else {
      // Sans flou : deux traits plats, le plus large le plus pâle, font le
      // dégradé de l'ombre pour le prix de deux cercles.
      canvas.drawCircle(
        centre,
        radius,
        _shadow
          ..strokeWidth = stroke * 3.2
          ..color = _dim(OnyxChromeTheme.glassShadow, 0.16 * opacity),
      );
      canvas.drawCircle(
        centre,
        radius,
        _shadow
          ..strokeWidth = stroke * 2
          ..color = _dim(OnyxChromeTheme.glassShadow, 0.24 * opacity),
      );
    }
    canvas.drawCircle(
      centre,
      radius,
      _track
        ..strokeWidth = stroke
        ..color = _dim(OnyxChromeTheme.progressTrack, opacity),
    );

    final start = -math.pi / 2 + turn * 2 * math.pi;
    const length = sweep * 2 * math.pi;
    final white = _dim(OnyxChromeTheme.progressPlayed, opacity);
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(start);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.drawArc(
      rect,
      0,
      length,
      false,
      // Bout plat : un bout rond déborderait sous zéro, où le dégradé reprend
      // sa dernière couleur, et la traîne finirait sur un point blanc.
      // L'alpha du trait module le dégradé : c'est lui qui porte l'opacité.
      _trail
        ..strokeWidth = stroke
        ..shader = _trailFor(rect)
        ..color = white,
    );
    // La tête, ronde.
    canvas.drawCircle(
      centre + Offset(math.cos(length), math.sin(length)) * radius,
      stroke / 2,
      _head..color = white,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OnyxLoadingRingPainter old) =>
      old.breathes != breathes ||
      old.soft != soft ||
      old.cycle != cycle ||
      old.arrival != arrival;
}
