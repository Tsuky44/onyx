import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/tr.dart';
import '../../models/media.dart';
import '../../providers/calendar_provider.dart';
import '../../theme/app_icons.dart';
import 'detail_hero.dart';
import 'onyx_toast.dart';

/// Pilule « + Suivre / ✓ Suivie » sur la fiche d'une série (variante 1 de la
/// maquette). Pilote l'état en mémoire dans [CalendarProvider] en attendant le
/// branchement serveur.
class FollowShowButton extends StatelessWidget {
  const FollowShowButton({
    super.key,
    required this.show,
    this.nextAirDate,
    this.nextAirCaption,
  });

  final Media show;
  final String? nextAirDate;
  final String? nextAirCaption;

  @override
  Widget build(BuildContext context) {
    final calendar = Provider.of<CalendarProvider?>(context);
    if (calendar == null) return const SizedBox.shrink();

    final followed = calendar.isFollowingShow(show);
    return HeroPill(
      label: followed ? tr('Suivie') : tr('Suivre'),
      icon: followed ? AppIcons.check : AppIcons.add,
      style: followed ? HeroPillStyle.status : HeroPillStyle.glass,
      onPressed: () {
        final nowFollowed = calendar.toggleFollowShow(
          show,
          nextAirDate: nextAirDate,
          nextCaption: nextAirCaption,
        );
        showOnyxToast(
          context,
          nowFollowed
              ? tr('Ajoutée au calendrier')
              : tr('Retirée du calendrier'),
        );
      },
    );
  }
}
