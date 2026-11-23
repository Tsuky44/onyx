import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/screens/player/playback/mpv_d3d11_fallback.dart';
import 'package:onyx/screens/player/windows_video_render.dart';

// ADR-0158, phase 2 : les deux rendus de Windows cohabitent, le réglage est
// ouvert à tous et vaut Automatique par défaut (décisions de Tsuky).
void main() {
  tearDown(WindowsVideoRender.reset);

  group('everyone on Windows gets the stored choice', () {
    test('the default is Automatic, for someone who never touched it', () {
      WindowsVideoRender.reset();
      expect(WindowsVideoRender.stored, WindowsVideoRenderChoice.auto);
    });

    test('on Windows, the stored choice applies as is', () {
      for (final stored in WindowsVideoRenderChoice.values) {
        expect(
          WindowsVideoRender.effectiveChoice(stored: stored, isWindows: true),
          stored,
        );
      }
    });

    test('another platform is never touched', () {
      expect(
        WindowsVideoRender.effectiveChoice(
            stored: WindowsVideoRenderChoice.d3d11, isWindows: false),
        WindowsVideoRenderChoice.legacy,
      );
      for (final choice in WindowsVideoRenderChoice.values) {
        expect(
          WindowsVideoRender.requestFor(choice: choice, isWindows: false),
          isNull,
        );
      }
    });
  });

  group('what the native output is asked to try first', () {
    test('legacy asks for ANGLE', () {
      expect(
        WindowsVideoRender.requestFor(
            choice: WindowsVideoRenderChoice.legacy, isWindows: true),
        'angle',
      );
    });

    test('new asks for D3D11, even on a machine caught failing', () {
      for (final failed in [false, true]) {
        expect(
          WindowsVideoRender.requestFor(
              choice: WindowsVideoRenderChoice.d3d11,
              isWindows: true,
              d3d11Failed: failed),
          'd3d11',
        );
      }
    });

    test('automatic falls back to ANGLE once D3D11 showed nothing', () {
      expect(
        WindowsVideoRender.requestFor(
            choice: WindowsVideoRenderChoice.auto, isWindows: true),
        'd3d11',
      );
      expect(
        WindowsVideoRender.requestFor(
            choice: WindowsVideoRenderChoice.auto,
            isWindows: true,
            d3d11Failed: true),
        'angle',
      );
    });
  });

  group('a failure is remembered per adapter and driver', () {
    test('the key names the adapter and its driver version', () {
      expect(
        WindowsVideoRender.adapterKeyFor({
          'description': 'NVIDIA GeForce RTX 3070',
          'vendorId': 0x10de,
          'deviceId': 0x2484,
          'driverVersion': '32.0.15.6094',
        }),
        '10de:2484:32.0.15.6094',
      );
    });

    test('a new driver is a new key, so D3D11 is tried again', () {
      Map<String, Object?> adapter(String driver) =>
          {'vendorId': 0x8086, 'deviceId': 0x9a49, 'driverVersion': driver};
      expect(
        WindowsVideoRender.adapterKeyFor(adapter('31.0.101.4502')),
        isNot(WindowsVideoRender.adapterKeyFor(adapter('31.0.101.5186'))),
      );
    });

    test('no key without a driver version', () {
      expect(WindowsVideoRender.adapterKeyFor(null), isNull);
      expect(
        WindowsVideoRender.adapterKeyFor(
            {'vendorId': 0x1002, 'deviceId': 0x73bf, 'driverVersion': ''}),
        isNull,
      );
      expect(WindowsVideoRender.adapterKeyFor({'vendorId': 0x1002}), isNull);
    });
  });

  group('the D3D11 texture is judged on its render counters', () {
    D3D11Health judge(Map<String, Object?>? info,
            {Map<String, Object?>? previous,
            Duration since = const Duration(seconds: 3)}) =>
        MpvD3D11Fallback.judge(
            info: info, previous: previous, sinceFirstFrame: since);

    Map<String, Object?> d3d11(int rendered, int failed, {int removed = 0}) => {
          'renderApi': 'd3d11',
          'renderedFrames': rendered,
          'failedFrames': failed,
          'deviceRemovedReason': removed,
        };

    test('no render ever succeeded past the grace period: blank', () {
      expect(judge(d3d11(0, 12)), D3D11Health.blank);
      expect(judge(d3d11(0, 0)), D3D11Health.blank);
    });

    test('nothing is judged blank before the grace period', () {
      expect(judge(d3d11(0, 0), since: const Duration(seconds: 1)),
          D3D11Health.ok);
    });

    test('a removed device is lost, whatever was rendered', () {
      expect(judge(d3d11(500, 3, removed: 0x887a0005)), D3D11Health.deviceLost);
    });

    test('renders that keep failing with none succeeding: failing', () {
      expect(
          judge(d3d11(500, 40), previous: d3d11(500, 20)), D3D11Health.failing);
    });

    test('a pause renders nothing and fails nothing: ok', () {
      expect(judge(d3d11(500, 0), previous: d3d11(500, 0)), D3D11Health.ok);
    });

    test('a few stray failures among renders: ok', () {
      expect(judge(d3d11(560, 22), previous: d3d11(500, 20)), D3D11Health.ok);
      expect(judge(d3d11(500, 25), previous: d3d11(500, 20)), D3D11Health.ok);
    });

    test('another path, or no answer, is never judged', () {
      expect(
          judge({'renderApi': 'angle', 'renderedFrames': 0, 'failedFrames': 9}),
          D3D11Health.ok);
      expect(judge(null), D3D11Health.ok);
    });
  });

  // Essai du 2026-11-23 : sans périphérique audio, libérer le contexte D3D11
  // laissait mpv sans rien à lire. Il finissait le fichier, l'app y voyait une
  // coupure du flux et rouvrait, et la qualité Auto quittait le Direct Play.
  group('the live fallback never leaves mpv with nothing to play', () {
    test('on the D3D11 texture, a missing audio device plays to null', () {
      expect(MpvD3D11Fallback.nullAudioFallback(VideoRenderPath.d3d11), 'yes');
    });

    test('every other path keeps mpv’s default, on a pooled engine too', () {
      expect(MpvD3D11Fallback.nullAudioFallback(VideoRenderPath.angle), 'no');
      expect(
          MpvD3D11Fallback.nullAudioFallback(VideoRenderPath.software), 'no');
      expect(MpvD3D11Fallback.nullAudioFallback(null), 'no');
    });
  });

  test('the plugin names map to the render paths', () {
    expect(VideoRenderPath.parse('d3d11'), VideoRenderPath.d3d11);
    expect(VideoRenderPath.parse('angle'), VideoRenderPath.angle);
    expect(VideoRenderPath.parse('sw'), VideoRenderPath.software);
    expect(VideoRenderPath.parse(null), isNull);
    expect(VideoRenderPath.parse('opengl'), isNull);
  });
}
