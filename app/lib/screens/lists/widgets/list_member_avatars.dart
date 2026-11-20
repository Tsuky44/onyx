import 'package:flutter/material.dart';

import '../../../screens/settings/widgets/settings_ui.dart' show UserAvatar;

/// Les visages d'une liste qui se chevauchent : qui la remplit ou la voit,
/// d'un coup d'œil, dans l'en-tête et sur « Partager ». Au-delà de [max], une
/// pastille « +N ».
///
/// [ring] est la couleur du fond sous la pile : le liseré qui détache chaque
/// visage du suivant prend la couleur de ce qu'il recouvre.
class ListMemberAvatars extends StatelessWidget {
  const ListMemberAvatars({
    super.key,
    required this.names,
    required this.ring,
    this.size = 28,
    this.max = 3,
  });

  final List<String> names;
  final Color ring;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = names.length > max ? names.sublist(0, max - 1) : names;
    final extra = names.length - shown.length;
    final overlap = size * 0.3;
    final faces = [
      for (final name in shown) UserAvatar(name, size: size - 4),
      if (extra > 0)
        SizedBox.square(
          dimension: size - 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
            ),
            child: Center(
              child: Text('+$extra',
                  style: TextStyle(
                      fontSize: size * 0.36, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
    ];
    return ExcludeSemantics(
      child: SizedBox(
        height: size,
        width: size + (faces.length - 1) * (size - overlap),
        child: Stack(
          children: [
            for (var i = 0; i < faces.length; i++)
              Positioned(
                left: i * (size - overlap),
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
                  child: faces[i],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
