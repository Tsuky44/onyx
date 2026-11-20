import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/screens/player/player_wheel_volume.dart';

PointerScrollEvent _scroll(double dy, {PointerDeviceKind? kind}) =>
    PointerScrollEvent(
      kind: kind ?? PointerDeviceKind.mouse,
      scrollDelta: Offset(0, dy),
    );

void main() {
  group('molette de souris sur le lecteur', () {
    test('vers le bas baisse le volume, vers le haut le monte', () {
      expect(playerWheelVolumeDelta(_scroll(100)), -playerWheelVolumeStep);
      expect(playerWheelVolumeDelta(_scroll(-100)), playerWheelVolumeStep);
    });

    test('le pas ne dépend pas de la valeur du défilement', () {
      expect(playerWheelVolumeDelta(_scroll(3)), -playerWheelVolumeStep);
      expect(playerWheelVolumeDelta(_scroll(-480)), playerWheelVolumeStep);
    });

    test('le pavé tactile ne touche pas au volume', () {
      expect(
        playerWheelVolumeDelta(
            _scroll(100, kind: PointerDeviceKind.trackpad)),
        isNull,
      );
    });

    test('un défilement horizontal ou nul est ignoré', () {
      expect(playerWheelVolumeDelta(_scroll(0)), isNull);
      expect(
        playerWheelVolumeDelta(PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          scrollDelta: const Offset(40, 0),
        )),
        isNull,
      );
    });

    test('ce qui n\'est pas un défilement est ignoré', () {
      expect(
        playerWheelVolumeDelta(const PointerScaleEvent(scale: 2)),
        isNull,
      );
    });
  });
}
