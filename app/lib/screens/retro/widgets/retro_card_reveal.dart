import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/retro_archetypes.dart';
import '../../../l10n/tr.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/retro_motion.dart';
import '../../../theme/retro_palette.dart';
import '../../../tv/tv_mode.dart';
import '../slides/retro_slide.dart';
import 'retro_recap_ticket.dart';
import 'retro_title_card.dart';
import 'retro_type.dart';

/// Le dernier écran du Rétro : la carte du titre de l'année se retourne
/// (`design-plans/onyx-retro-revelation.html`, piste « La carte »).
///
/// La carte arrive face cachée, hésite, puis se retourne ; la couleur du
/// profil remplit l'écran depuis le centre et un reflet passe sur la carte.
/// Puis le ticket à partager arrive : à droite sur un écran large, la carte
/// rangée à gauche ; seul et en grand sur un téléphone, où la carte s'efface
/// (le personnage reste sur le ticket, en médaillon).
///
/// Elle remplace une remise de prix (rideau, enveloppe, socle doré) qui
/// tranchait avec les aplats du reste de la story. Une seule animation de
/// [duration], découpée en moments. En mode léger, sous « réduire les
/// animations » et au téléviseur, l'écran s'ouvre sur la fin.
class RetroCardReveal extends StatefulWidget {
  const RetroCardReveal({super.key, required this.data});

  final RetroStoryData data;

  static const Duration duration = Duration(milliseconds: 7400);

  /// La place laissée sous le ticket, sur un téléphone, aux boutons de fin.
  static const double actionsHeight = 84;

  @override
  State<RetroCardReveal> createState() => _RetroCardRevealState();
}

class _RetroCardRevealState extends State<RetroCardReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t =
      AnimationController(vsync: this, duration: RetroCardReveal.duration);

  bool _started = false;

  /// Le fond avant la révélation : neutre, pour que la couleur du profil
  /// arrive avec la carte retournée.
  static const _stage = Color(0xFF0E0F13);
  static const _flip = Cubic(0.5, 0, 0.2, 1);

  /// La part d'un moment de l'écran, de [from] à [to] secondes.
  double _at(double from, double to, [Curve curve = Curves.linear]) {
    final total = RetroCardReveal.duration.inMilliseconds / 1000;
    return Interval(from / total, to / total, curve: curve).transform(_t.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (RetroMotion.still(context) || TvScope.of(context)) {
      _t.value = 1;
    } else {
      _t.forward();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.data.report;
    final palette = RetroPalette.forArchetype(report.archetype);
    final units = RetroUnits.of(context);
    final landscape = units.landscape;
    final w = units.size.width, h = units.size.height;

    final cardH = landscape
        ? h * 0.64
        : math.min(w * 0.70 / RetroTitleCard.ratio, h * 0.62);
    final cardW = cardH * RetroTitleCard.ratio;
    final cardCenter = Offset(w / 2, h * (landscape ? 0.47 : 0.46));

    // Ce qui ne change pas pendant l'animation, construit une fois.
    final back = RetroTitleCard.back(year: report.year);
    final reason = Text(
      retroArchetypeReason(report),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        color: const Color(0xD9FFFFFF),
        fontSize: h * (landscape ? 0.028 : 0.02),
        height: 1.3,
      ),
    );
    final intro = _Intro(year: report.year, width: w, height: h);
    final ticket = FittedBox(
      child: RetroRecapTicket(report: report, name: widget.data.name),
    );
    final ratio = RetroRecapTicket.size.width / RetroRecapTicket.size.height;
    final ticketHeight = landscape
        ? math.min(h * 0.82, w * 0.4 / ratio)
        : math.min(h - units.padding.top - RetroCardReveal.actionsHeight - 8,
            (w - 32) / ratio);
    final diagonal = math.sqrt(w * w + h * h);

    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final arrive = _at(0.2, 1.0, RetroMotion.back);
        final wobble = _at(1.3, 2.2);
        final flip = _at(2.3, 3.2, _flip);
        final flood = _at(2.65, 3.45, RetroMotion.inOut);
        final glint = _at(3.4, 4.4, Curves.easeInOut);
        final told = _at(3.7, 4.3, RetroMotion.out);
        final introIn = _at(0.9, 1.5, RetroMotion.out);
        final introOut = _at(2.2, 2.55, Curves.easeIn);
        final move = _at(5.6, 6.6, RetroMotion.inOut);
        final deal = _at(6.0, 7.1, RetroMotion.back);

        // Le retournement : le dos jusqu'à mi-course, puis la face, déjà
        // tournée d'un demi-tour pour ne pas se lire à l'envers.
        final angle = flip * math.pi;
        final showFace = angle > math.pi / 2;
        Widget card = SizedBox(
          width: cardW,
          height: cardH,
          child: showFace
              ? RetroTitleCard.front(
                  archetype: report.archetype,
                  year: report.year,
                  glint: glint,
                )
              : back,
        );
        card = Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(showFace ? angle - math.pi : angle),
          child: Transform.scale(
            scale: 1 + 0.08 * math.sin(flip * math.pi),
            child: card,
          ),
        );
        // L'hésitation, avant de se retourner.
        card = Transform.rotate(
          angle: math.sin(wobble * 3 * math.pi) *
              (1 - wobble) *
              3 *
              math.pi /
              180,
          child: Transform.scale(
            scale: 1 + 0.03 * math.sin(wobble * math.pi),
            child: card,
          ),
        );
        card = Opacity(
          opacity: _at(0.2, 0.6),
          child: Transform.translate(
            offset: Offset(0, h * 0.3 * (1 - arrive)),
            child: Transform.rotate(
              angle: -10 * math.pi / 180 * (1 - arrive),
              child: Transform.scale(scale: 0.9 + 0.1 * arrive, child: card),
            ),
          ),
        );

        Widget scene = Stack(
          children: [
            Positioned(
              left: cardCenter.dx - cardW / 2,
              top: cardCenter.dy - cardH / 2,
              width: cardW,
              height: cardH,
              child: card,
            ),
            Positioned(
              left: w * 0.1,
              right: w * 0.1,
              top: cardCenter.dy + cardH / 2 + h * 0.04,
              child: Opacity(
                opacity: told.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, h * 0.02 * (1 - told)),
                  child: reason,
                ),
              ),
            ),
          ],
        );
        // La fin : la carte se range à gauche d'un écran large ; sur un
        // téléphone, elle s'efface vers le haut pour laisser le ticket seul.
        scene = landscape
            ? Transform.translate(
                offset: Offset(-w * 0.22 * move, 0),
                child: Transform.scale(scale: 1 - 0.08 * move, child: scene),
              )
            : Opacity(
                opacity: 1 - move,
                child: Transform.translate(
                  offset: Offset(0, -h * 0.14 * move),
                  child: Transform.scale(scale: 1 - 0.06 * move, child: scene),
                ),
              );

        final dealt = Opacity(
          opacity: deal.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, h * 0.4 * (1 - deal)),
            child: Transform.rotate(
              angle: (landscape ? -12 + 14 * deal : -8 + 9.5 * deal) *
                  math.pi /
                  180,
              child: Transform.scale(scale: 0.85 + 0.15 * deal, child: ticket),
            ),
          ),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _stage),
            if (flood > 0)
              Center(
                child: OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: SizedBox.square(
                    dimension: diagonal * flood,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.background,
                      ),
                    ),
                  ),
                ),
              ),
            if (introIn > 0 && introOut < 1)
              Positioned(
                left: w * 0.08,
                right: w * 0.08,
                bottom: h * 0.06,
                child: Opacity(
                  opacity: introIn.clamp(0.0, 1.0) * (1 - introOut),
                  child: Transform.translate(
                    offset: Offset(0, h * 0.02 * (1 - introIn)),
                    child: intro,
                  ),
                ),
              ),
            scene,
            if (deal > 0)
              landscape
                  ? Positioned(
                      right: w * 0.09,
                      top: (h - ticketHeight) / 2,
                      width: ticketHeight * ratio,
                      height: ticketHeight,
                      child: dealt,
                    )
                  : Positioned(
                      left: (w - ticketHeight * ratio) / 2,
                      bottom: RetroCardReveal.actionsHeight,
                      width: ticketHeight * ratio,
                      height: ticketHeight,
                      child: dealt,
                    ),
          ],
        );
      },
    );
  }
}

/// Sous la carte encore cachée : « Ton titre de l'année est dans cette
/// carte. »
class _Intro extends StatelessWidget {
  const _Intro({required this.year, required this.width, required this.height});

  final int year;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('Rétro {0}', [year]).toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: const Color(0x8CFFFFFF),
              fontSize: height * 0.018,
              fontWeight: FontWeight.w700,
              letterSpacing: height * 0.003,
            ),
          ),
          SizedBox(height: height * 0.012),
          Text(
            tr('Ton titre de l’année est dans cette carte.'),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: const Color(0xFFFFFFFF),
              fontSize: math.min(height * 0.05, width * 0.06),
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
        ],
      );
}
