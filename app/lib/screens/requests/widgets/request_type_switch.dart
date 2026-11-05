import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_type.dart';
import '../../../l10n/tr.dart';
import '../../../utils/responsive.dart';

/// Sélecteur Tout / Films / Séries : un bloc segmenté dont le curseur glisse
/// d'un choix à l'autre au lieu de sauter. Les segments ont tous la même
/// largeur, ce qui permet de positionner le curseur sans mesurer le texte.
class RequestTypeSwitch extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const RequestTypeSwitch({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _tabs = [
    (value: 'all', label: 'Tout'),
    (value: 'movie', label: 'Films'),
    (value: 'tv', label: 'Séries'),
  ];

  static const double _segmentWidth = 92;
  static const double _inset = 3;

  /// Largeur totale, bordure comprise : l'écran s'en sert pour savoir si le
  /// sélecteur tient à côté de la recherche.
  static const double width = _segmentWidth * 3 + _inset * 2 + 2;

  @override
  Widget build(BuildContext context) {
    final height = AppLayout.isCompact(context) ? 44.0 : 38.0;
    final index = _tabs.indexWhereValue(selected);
    return Semantics(
      container: true,
      label: tr('Type de média'),
      child: Container(
        padding: const EdgeInsets.all(_inset),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: SizedBox(
          width: _segmentWidth * _tabs.length,
          height: height - _inset * 2,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: AppMotion.move(context, AppMotion.standard),
                curve: AppMotion.curve,
                left: _segmentWidth * index,
                top: 0,
                bottom: 0,
                width: _segmentWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHover,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final tab in _tabs)
                    SizedBox(
                      width: _segmentWidth,
                      child: _Segment(
                        label: tr(tab.label),
                        selected: selected == tab.value,
                        onTap: () {
                          if (selected != tab.value) onChanged(tab.value);
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on List<({String value, String label})> {
  /// Position du choix courant ; « Tout » si la valeur est inconnue.
  int indexWhereValue(String value) {
    final i = indexWhere((tab) => tab.value == value);
    return i < 0 ? 0 : i;
  }
}

class _Segment extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        borderRadius: BorderRadius.circular(999),
        // Le focus n'était que le voile de 10 % de Material, sur une pilule
        // déjà grise : à la télécommande, aucun des trois choix ne montrait
        // qu'il était visé. Même anneau que les autres boutons de l'app.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _focused ? AppColors.accent : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: AppMotion.fade(context, AppMotion.micro),
              curve: AppMotion.curve,
              style: TextStyle(
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: AppType.subhead,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
