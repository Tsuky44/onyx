import 'package:flutter/material.dart';

import '../../../l10n/tr.dart';
import '../../../services/app_image_cache.dart';
import '../../../utils/app_platform.dart';
import 'settings_ui.dart';

/// Le cache des affiches et des fonds, avec de quoi le vider.
///
/// Il vit avec les téléchargements : les deux occupent le disque de l'appareil,
/// et c'est là qu'on vient chercher de la place. Sur une Apple TV, qui n'a pas
/// de téléchargements, il est seul à y rester.
class ImageCacheGroup extends StatefulWidget {
  const ImageCacheGroup({super.key});

  @override
  State<ImageCacheGroup> createState() => _ImageCacheGroupState();
}

class _ImageCacheGroupState extends State<ImageCacheGroup> {
  bool _clearing = false;

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      await AppImageCache.manager.emptyCache();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      if (mounted) showSettingsSnack(context, tr('Cache des images vidé.'));
    } catch (_) {
      if (mounted) {
        showSettingsSnack(context, tr('Impossible de vider le cache.'),
            error: true);
      }
    }
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) {
    // Un navigateur garde ses images lui-même : rien à vider ici.
    if (AppPlatform.isWeb) return const SizedBox.shrink();
    return SettingsGroup(
      title: tr('Images'),
      children: [
        SettingsTile(
          icon: Icons.image_outlined,
          title: tr('Cache des images'),
          subtitle: tr('Affiches et fonds gardés sur l’appareil pour '
              's’afficher sans attendre. Ils seront retéléchargés.'),
          showChevron: false,
          trailing: _clearing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _clear,
                  child: Text(tr('Vider')),
                ),
        ),
      ],
    );
  }
}
