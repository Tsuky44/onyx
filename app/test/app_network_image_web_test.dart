import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/widgets/global/app_network_image.dart';

void main() {
  test('le web décode via HttpGet pour que memCacheWidth soit respecté', () {
    // `HtmlImage` (défaut du paquet) ignore memCacheWidth et décode à la
    // taille source ; le widget et providerFor passent tous deux par cette
    // constante pour garder la même clé de cache.
    expect(AppNetworkImage.webRenderMethod, ImageRenderMethodForWeb.HttpGet);
  });
}
