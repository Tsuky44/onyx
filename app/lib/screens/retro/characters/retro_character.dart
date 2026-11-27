import 'package:flutter/widgets.dart';

import '../../../models/retro.dart';
import '../../../theme/retro_palette.dart';
import 'retro_pen.dart';

/// Le personnage d'un profil du Rétro : une même silhouette ronde, de
/// l'encre du profil, habillée selon son titre (plaid et canapé pour
/// « Pilier de canapé », bonnet de nuit pour « Noctambule »…). Dessiné, sans
/// image : il se peint d'un coup, aussi sur le ticket rendu hors écran.
///
/// Proportions fixes de 200 × 260 ; [RetroCharacter] prend la hauteur qu'on
/// lui donne.
class RetroCharacter extends StatelessWidget {
  const RetroCharacter({super.key, required this.archetype});

  final RetroArchetype archetype;

  static const Size design = Size(200, 260);

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: design.width / design.height,
        child: CustomPaint(painter: RetroCharacterPainter(archetype)),
      );
}

class RetroCharacterPainter extends CustomPainter {
  const RetroCharacterPainter(this.archetype);
  final RetroArchetype archetype;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = RetroPalette.forArchetype(archetype);
    final c = colors.ink;
    final d = colors.background;
    final o = _Outfit.of(archetype, c, d);
    canvas
      ..save()
      ..scale(size.width / RetroCharacter.design.width,
          size.height / RetroCharacter.design.height);
    final pen = RetroPen(canvas);

    o.fx?.call(pen);
    pen.shape(pen.ellipse(100, 248, 54, 7), fill: const Color(0x47000000));
    o.back?.call(pen);
    if (o.legs) {
      pen
        ..shape(pen.rect(80, 196, 15, 42, 7.5), fill: d)
        ..shape(pen.rect(105, 196, 15, 42, 7.5), fill: d);
      final shoe = o.wideShoes ? 19.0 : 15.0;
      for (final x in const [85.0, 117.0]) {
        pen.shape(pen.ellipse(x, 240, shoe, 8),
            fill: o.shoe ?? d, stroke: d, width: 2.5);
      }
    }

    final body = pen.rect(48, 54, 104, 160, 52);
    pen
      ..shape(body, fill: c)
      ..clipped(body, () {
        o.onBody?.call(pen);
        pen.shape(pen.ellipse(76, 82, 16, 9), fill: const Color(0x59FFFFFF));
        o.headClipped?.call(pen);
      })
      ..shape(body, stroke: d, width: 3.5);

    const cheek = Color(0x73FF6B8A);
    pen
      ..shape(pen.ellipse(73, 125, 7, 4), fill: cheek)
      ..shape(pen.ellipse(127, 125, 7, 4), fill: cheek);
    (o.eyes ?? _eyes)(pen, d);
    o.face?.call(pen);
    (o.mouth ?? _mouth)(pen, d);
    o.head?.call(pen);
    pen
      ..arm(o.armL ?? 'M58 140 Q42 160 46 182', c, d)
      ..arm(o.armR ?? 'M142 140 Q158 160 154 182', c, d);
    o.front?.call(pen);
    canvas.restore();
  }

  static void _eyes(RetroPen pen, Color d) {
    const white = Color(0xFFFFFFFF);
    pen
      ..shape(pen.ellipse(84, 112, 6, 7), fill: d)
      ..shape(pen.ellipse(116, 112, 6, 7), fill: d)
      ..shape(pen.circle(86, 109, 2), fill: white)
      ..shape(pen.circle(118, 109, 2), fill: white);
  }

  static void _mouth(RetroPen pen, Color d) =>
      pen.line('M92 130 Q100 138 108 130', d, 3.5);

  @override
  bool shouldRepaint(RetroCharacterPainter old) => old.archetype != archetype;
}

typedef _Draw = void Function(RetroPen pen);
typedef _Ink = void Function(RetroPen pen, Color d);

/// Ce qui change d'un personnage à l'autre : sa tenue, ses accessoires, son
/// visage et la pose de ses bras. Les tracés sont ceux de la maquette.
class _Outfit {
  const _Outfit({
    this.fx,
    this.onBody,
    this.headClipped,
    this.eyes,
    this.face,
    this.mouth,
    this.head,
    this.armL,
    this.armR,
    this.front,
    this.shoe,
    this.wideShoes = false,
    this.back,
    this.legs = true,
  });

  /// Derrière tout : la lune, les étoiles, les confettis.
  final _Draw? fx;

  /// Derrière le corps, devant le décor : le dossier du canapé.
  final _Draw? back;

  /// Debout. Un personnage assis cache ses jambes derrière son coussin.
  final bool legs;

  /// Sur le corps, sans en déborder : dossard, rayures, peignoir.
  final _Draw? onBody;
  final _Draw? headClipped;
  final _Ink? eyes;
  final _Draw? face;
  final _Ink? mouth;
  final _Draw? head;
  final String? armL;
  final String? armR;

  /// Devant tout : ce qu'il tient.
  final _Draw? front;
  final Color? shoe;
  final bool wideShoes;

  static const _white = Color(0xFFFFFFFF);

  static _Outfit of(RetroArchetype archetype, Color c, Color d) =>
      switch (archetype) {
        RetroArchetype.marathon => _marathon(c, d),
        RetroArchetype.nightOwl => _night(c, d),
        RetroArchetype.cinephile => _cinephile(c, d),
        RetroArchetype.explorer => _explorer(c, d),
        RetroArchetype.weekend => _weekend(c, d),
        RetroArchetype.goodAudience => _audience(c, d),
      };

  /// Pilier de canapé : assis dans son canapé, plaid sur les épaules, les
  /// pieds en chaussons sur le coussin, la télécommande en main. Les boîtes
  /// de pizza s'empilent sur l'accoudoir et neuf traits au mur comptent les
  /// épisodes de la journée.
  static _Outfit _marathon(Color c, Color d) {
    const sofa = Color(0xFF5B6F9A);
    const seat = Color(0xFF6E84B3);
    const plaid = Color(0xFFE1A44A);
    const plaidLine = Color(0xB3A8682A);
    const box = Color(0xFFF1E3C6);
    const slipper = Color(0xFFF3E6FF);
    const pompom = Color(0xFFFF9DB5);
    const red = Color(0xFFFF5A5F);
    return _Outfit(
      legs: false,
      fx: (pen) => pen.line(
          'M18 30 L18 54 M26 30 L26 54 M34 30 L34 54 M42 30 L42 54 '
          'M12 50 L48 34 M60 30 L60 54 M68 30 L68 54 M76 30 L76 54 '
          'M84 30 L84 54',
          c.withValues(alpha: 0.85),
          3.5),
      back: (pen) => pen
        ..fill(
            'M8 196 L8 128 Q8 108 30 108 L170 108 Q192 108 192 128 L192 196 Z',
            sofa,
            stroke: d)
        ..line('M100 112 L100 188', d.withValues(alpha: 0.3), 2),
      onBody: (pen) => pen
        ..fill(
            'M40 124 Q100 150 160 124 L160 240 L134 240 Q128 176 100 172 '
            'Q72 176 66 240 L40 240 Z',
            plaid)
        ..line('M54 130 L54 240 M146 130 L146 240', plaidLine, 6, round: false)
        ..line(
            'M40 160 L72 160 M128 160 L160 160 M40 196 L68 196 M132 196 L160 196',
            plaidLine,
            6,
            round: false)
        ..line('M62 132 L62 240 M138 132 L138 240',
            const Color(0xCCFFF3D6), 1.5,
            round: false)
        ..line(
            'M40 124 Q100 150 160 124 M134 240 Q128 176 100 172 Q72 176 66 240',
            d,
            2.5),
      mouth: (pen, d) => pen
        ..line('M90 129 Q100 139 110 129', d, 3.5)
        ..shape(pen.circle(114, 134, 1.5), fill: const Color(0xFFC98A2B)),
      armL: 'M58 146 Q52 168 72 176',
      armR: 'M142 146 Q158 160 150 178',
      front: (pen) {
        pen
          ..shape(pen.rect(14, 184, 172, 40, 14), fill: seat, stroke: d)
          ..line('M100 188 L100 220', d.withValues(alpha: 0.3), 2)
          ..shape(pen.rect(0, 146, 40, 84, 18), fill: sofa, stroke: d)
          ..shape(pen.rect(160, 146, 40, 84, 18), fill: sofa, stroke: d)
          ..shape(pen.rect(22, 224, 10, 12), fill: d)
          ..shape(pen.rect(168, 224, 10, 12), fill: d);
        for (final y in const <double>[116, 126, 136]) {
          pen.shape(pen.rect(2, y, 44, 10, 2), fill: box, stroke: d, width: 2);
        }
        pen
          ..shape(pen.circle(24, 121, 3), fill: const Color(0xFFE63946))
          ..shape(pen.ellipse(80, 194, 16, 9),
              fill: slipper, stroke: d, width: 2.5)
          ..shape(pen.ellipse(120, 194, 16, 9),
              fill: slipper, stroke: d, width: 2.5)
          ..shape(pen.circle(72, 188, 4), fill: pompom)
          ..shape(pen.circle(128, 188, 4), fill: pompom);
        pen.rotated(-30, 152, 168, () {
          pen
            ..shape(pen.rect(143.5, 151, 17, 34, 5),
                fill: d, stroke: c, width: 2)
            ..shape(pen.circle(152, 160, 3), fill: red)
            ..shape(pen.circle(152, 169, 2), fill: c)
            ..shape(pen.circle(152, 176, 2), fill: c);
        });
      },
    );
  }

  /// Noctambule : pyjama rayé, bonnet à pompon, tasse fumante, yeux mi-clos,
  /// la lune derrière.
  static _Outfit _night(Color c, Color d) {
    const cloth = Color(0xFFF3E6FF);
    const moon = Color(0xFFFFE9A8);
    return _Outfit(
      shoe: cloth,
      fx: (pen) => pen
        ..shape(
            Path.combine(PathOperation.difference, pen.circle(36, 56, 17),
                pen.circle(45, 50, 14)),
            fill: moon)
        ..fill('M160 22 l2 6 6 2 -6 2 -2 6 -2 -6 -6 -2 6 -2z', moon)
        ..fill(
            'M22 96 l1.5 4 4 1.5 -4 1.5 -1.5 4 -1.5 -4 -4 -1.5 4 -1.5z', moon),
      onBody: (pen) {
        for (final x in const <double>[58, 74, 90, 106, 122, 138]) {
          pen.shape(pen.rect(x, 54, 7, 170), fill: d.withValues(alpha: 0.1));
        }
        pen
          ..shape(pen.circle(100, 186, 2.6), fill: d.withValues(alpha: 0.5))
          ..shape(pen.circle(100, 200, 2.6), fill: d.withValues(alpha: 0.5));
      },
      head: (pen) => pen
        ..fill(
            'M52 92 Q56 40 102 34 Q150 30 176 74 Q162 64 150 68 Q150 80 150 92 Z',
            const Color(0xFF5B2E91),
            stroke: d)
        ..fill('M49 90 Q100 78 151 90 L151 101 Q100 89 49 101 Z', cloth,
            stroke: d)
        ..shape(pen.circle(176, 76, 10), fill: cloth, stroke: d),
      eyes: (pen, d) => pen
        ..line('M76 114 Q84 108 92 114', d, 3.5)
        ..line('M108 114 Q116 108 124 114', d, 3.5)
        ..line('M78 121 Q84 124 90 121', d.withValues(alpha: 0.35), 2)
        ..line('M110 121 Q116 124 122 121', d.withValues(alpha: 0.35), 2),
      mouth: (pen, d) => pen.shape(pen.ellipse(100, 134, 5, 6), fill: d),
      armL: 'M58 142 Q64 164 88 166',
      armR: 'M142 142 Q136 164 112 166',
      front: (pen) => pen
        ..line('M94 146 q-5 -7 0 -13 q5 -7 0 -13',
            _white.withValues(alpha: 0.75), 2.5)
        ..line('M106 146 q-5 -7 0 -13 q5 -7 0 -13',
            _white.withValues(alpha: 0.6), 2.5)
        ..shape(pen.rect(84, 150, 32, 30, 6), fill: _white, stroke: d)
        ..line('M116 157 q11 0 11 8 q0 8 -11 8', d, 3)
        ..text('zZ', 100, 171, 10, d),
    );
  }

  /// Projectionniste : béret, lunettes rondes, écharpe, le clap à la main.
  static _Outfit _cinephile(Color c, Color d) {
    const wine = Color(0xFF8B1E2D);
    const scarf = Color(0xFFC0392B);
    return _Outfit(
      shoe: wine,
      head: (pen) {
        pen.rotated(-9, 94, 62, () {
          pen.shape(pen.ellipse(94, 62, 47, 15),
              fill: wine, stroke: d, width: 3.5);
        });
        pen.rotated(-9, 92, 46, () {
          pen.shape(pen.rect(88, 40, 7, 11, 3.5), fill: d);
        });
      },
      face: (pen) => pen
        ..shape(pen.circle(84, 112, 12.5),
            fill: _white.withValues(alpha: 0.22), stroke: d)
        ..shape(pen.circle(116, 112, 12.5),
            fill: _white.withValues(alpha: 0.22), stroke: d)
        ..line('M96.5 110 Q100 107 103.5 110', d, 3)
        ..line('M71.5 110 L58 106 M128.5 110 L142 106', d, 3),
      mouth: (pen, d) => pen.line('M92 132 Q102 137 111 129', d, 3.5),
      onBody: (pen) => pen.fill(
          'M44 136 Q100 154 156 136 L156 152 Q100 170 44 152 Z', scarf),
      armR: 'M142 140 Q162 150 166 170',
      front: (pen) {
        pen
          ..fill('M66 150 L58 200 L74 202 L78 152 Z', scarf, stroke: d)
          ..line('M58 200 l-2 7 M63 201 l-1 7 M68 201 l0 7 M73 202 l1 7', d, 2);
        pen.rotated(-10, 172, 172, () {
          pen.shape(pen.rect(152, 162, 42, 28, 3),
              fill: d, stroke: c, width: 2);
          pen.rotated(-20, 152, 160, () {
            pen
              ..shape(pen.rect(152, 150, 42, 11),
                  fill: _white, stroke: d, width: 2.5)
              ..line('M160 150 l6 11 M172 150 l6 11 M184 150 l6 11', d, 4,
                  round: false);
          });
          pen
            ..shape(pen.rect(158, 170, 30, 2.5),
                fill: _white.withValues(alpha: 0.6))
            ..shape(pen.rect(158, 177, 20, 2.5),
                fill: _white.withValues(alpha: 0.6));
        });
      },
    );
  }

  /// Globe-trotter : chapeau d'explorateur, jumelles, sac à dos, une carte
  /// annotée, les yeux grands ouverts.
  static _Outfit _explorer(Color c, Color d) {
    const leather = Color(0xFF7A5A2B);
    const route = Color(0xFFE74C3C);
    return _Outfit(
      shoe: leather,
      eyes: (pen, d) => pen
        ..shape(pen.ellipse(84, 112, 7, 8.5), fill: d)
        ..shape(pen.ellipse(116, 112, 7, 8.5), fill: d)
        ..shape(pen.circle(86.5, 108.5, 2.6), fill: _white)
        ..shape(pen.circle(118.5, 108.5, 2.6), fill: _white),
      mouth: (pen, d) => pen.shape(pen.ellipse(100, 134, 6, 7), fill: d),
      onBody: (pen) => pen
        ..line('M62 70 L82 214', leather, 8, round: false)
        ..line('M138 70 L118 214', leather, 8, round: false),
      head: (pen) => pen
        ..fill('M60 76 Q62 34 100 32 Q138 34 140 76 Z', const Color(0xFFD9B77A),
            stroke: d)
        ..shape(pen.rect(61, 64, 78, 10), fill: leather)
        ..shape(pen.ellipse(100, 77, 68, 12),
            fill: const Color(0xFFC9A66B), stroke: d, width: 3.5),
      armL: 'M58 140 Q44 150 44 168',
      front: (pen) => pen
        ..line('M86 142 L82 152 M114 142 L118 152', d, 2.5)
        ..shape(pen.rect(78, 150, 18, 26, 6), fill: d)
        ..shape(pen.rect(104, 150, 18, 26, 6), fill: d)
        ..shape(pen.rect(94, 157, 12, 9), fill: d)
        ..shape(pen.circle(87, 171, 4), fill: c.withValues(alpha: 0.7))
        ..shape(pen.circle(113, 171, 4), fill: c.withValues(alpha: 0.7))
        ..fill('M8 160 L28 153 L48 160 L48 198 L28 191 L8 198 Z',
            const Color(0xFFFFF3D6),
            stroke: d)
        ..line('M28 153 L28 191', d.withValues(alpha: 0.4), 1.5)
        ..line('M14 188 Q24 170 42 176', route, 2.4, round: false, dash: 3)
        ..line('M39 170 l6 6 M45 170 l-6 6', route, 2.4),
    );
  }

  /// Pro du dimanche : peignoir, chaussons tout doux, masque de nuit remonté
  /// sur le front, un croissant.
  static _Outfit _weekend(Color c, Color d) {
    const robe = Color(0xFFF7C6D9);
    const belt = Color(0xFFE895B4);
    const mask = Color(0xFF2C3E50);
    return _Outfit(
      shoe: _white,
      wideShoes: true,
      onBody: (pen) => pen
        ..fill('M40 122 L100 172 L160 122 L160 230 L40 230 Z', robe)
        ..line('M48 122 L100 172 L152 122', d, 3)
        ..shape(pen.rect(40, 184, 120, 10), fill: belt, stroke: d, width: 2)
        ..shape(pen.circle(100, 189, 6), fill: belt, stroke: d, width: 2),
      headClipped: (pen) => pen.shape(pen.rect(40, 78, 120, 8), fill: mask),
      head: (pen) => pen
        ..fill(
            'M70 70 Q84 62 100 70 Q116 62 130 70 Q132 88 116 89 Q100 83 84 89 Q68 88 70 70Z',
            mask,
            stroke: d,
            width: 2.5)
        ..line('M78 79 Q84 75 90 79 M110 79 Q116 75 122 79', _white, 2),
      eyes: (pen, d) => pen
        ..line('M77 115 Q84 107 91 115', d, 3.5)
        ..line('M109 115 Q116 107 123 115', d, 3.5),
      mouth: (pen, d) => pen.line('M90 129 Q100 139 110 129', d, 3.5),
      armR: 'M142 140 Q160 152 160 168',
      front: (pen) => pen
        ..fill('M146 176 Q160 146 186 164 Q170 164 164 182 Z',
            const Color(0xFFE9A94B),
            stroke: d, width: 2.5)
        ..line('M158 160 L164 172 M168 156 L170 168 M176 158 L174 168',
            d.withValues(alpha: 0.5), 1.8),
    );
  }

  /// Fan de premier rang : lunettes 3D, seau de popcorn, main géante en
  /// mousse « 1 », le plus grand sourire de la salle.
  static _Outfit _audience(Color c, Color d) {
    const foam = Color(0xFFFFD23F);
    const corn = Color(0xFFFFF3C4);
    return _Outfit(
      shoe: foam,
      fx: (pen) {
        pen.rotated(20, 27, 43, () {
          pen.shape(pen.rect(24, 40, 7, 7), fill: foam);
        });
        pen.rotated(-15, 179, 123, () {
          pen.shape(pen.rect(176, 120, 7, 7), fill: const Color(0xFF3FD0FF));
        });
        pen.rotated(40, 37, 113, () {
          pen.shape(pen.rect(34, 110, 6, 6), fill: const Color(0xFFFF4D6D));
        });
      },
      face: (pen) => pen
        ..shape(pen.rect(66, 101, 68, 22, 6), fill: _white, stroke: d)
        ..shape(pen.rect(71, 105, 25, 14, 3), fill: const Color(0xE6FF4D6D))
        ..shape(pen.rect(104, 105, 25, 14, 3), fill: const Color(0xE63FD0FF)),
      eyes: (pen, d) {},
      mouth: (pen, d) => pen
        ..fill('M84 130 Q100 156 116 130 Z', d)
        ..fill('M92 142 Q100 151 108 142 Z', const Color(0xFFFF7A8A)),
      armL: 'M58 142 Q50 160 60 176',
      armR: 'M142 132 Q160 112 162 92',
      front: (pen) {
        pen
          ..fill('M40 160 L80 160 L74 206 L46 206 Z', _white, stroke: d)
          ..line('M50 162 L53 204 M60 162 L60 204 M70 162 L67 204',
              const Color(0xFFE63946), 5,
              round: false);
        for (final (x, y) in const [
          (46.0, 156.0),
          (54.0, 149.0),
          (62.0, 153.0),
          (70.0, 148.0),
          (77.0, 156.0),
          (60.0, 144.0),
          (50.0, 162.0),
        ]) {
          pen.shape(pen.circle(x, y, 7), fill: corn, stroke: d, width: 2);
        }
        pen
          ..shape(pen.rect(150, 62, 28, 32, 9), fill: foam, stroke: d)
          ..shape(pen.rect(158, 34, 11, 34, 5.5), fill: foam, stroke: d)
          ..text('1', 164, 86, 14, d);
      },
    );
  }
}
