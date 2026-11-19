import 'package:flutter_test/flutter_test.dart';

import 'package:onyx/screens/player/windows_video_render.dart';

// ADR-0158, phase 2 : les deux rendus de Windows cohabitent, un admin choisit,
// et tout le monde reste sur l'ancien par défaut.
void main() {
  tearDown(WindowsVideoRender.reset);

  group('only an admin on Windows leaves the legacy path', () {
    test('a member stays on legacy, whatever is stored', () {
      for (final stored in WindowsVideoRenderChoice.values) {
        expect(
          WindowsVideoRender.effectiveChoice(
              stored: stored, isWindows: true, isAdmin: false),
          WindowsVideoRenderChoice.legacy,
        );
      }
    });

    test('an admin gets what they chose', () {
      for (final stored in WindowsVideoRenderChoice.values) {
        expect(
          WindowsVideoRender.effectiveChoice(
              stored: stored, isWindows: true, isAdmin: true),
          stored,
        );
      }
    });

    test('another platform is never touched', () {
      expect(
        WindowsVideoRender.effectiveChoice(
            stored: WindowsVideoRenderChoice.d3d11,
            isWindows: false,
            isAdmin: true),
        WindowsVideoRenderChoice.legacy,
      );
      for (final choice in WindowsVideoRenderChoice.values) {
        expect(
          WindowsVideoRender.requestFor(choice: choice, isWindows: false),
          isNull,
        );
      }
    });

    test('the default is legacy', () {
      expect(WindowsVideoRender.stored, WindowsVideoRenderChoice.legacy);
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

    test('new asks for D3D11, even after a blank texture', () {
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

  group('a D3D11 texture without a picture', () {
    test('is one where no render ever succeeded', () {
      expect(
        WindowsVideoRender.isBlankD3D11(
            {'renderApi': 'd3d11', 'renderedFrames': 0, 'failedFrames': 12}),
        isTrue,
      );
      expect(
        WindowsVideoRender.isBlankD3D11(
            {'renderApi': 'd3d11', 'renderedFrames': 0, 'failedFrames': 0}),
        isTrue,
      );
    });

    test('is not one that rendered, or another path, or no answer', () {
      expect(
        WindowsVideoRender.isBlankD3D11(
            {'renderApi': 'd3d11', 'renderedFrames': 40, 'failedFrames': 2}),
        isFalse,
      );
      expect(
        WindowsVideoRender.isBlankD3D11(
            {'renderApi': 'angle', 'renderedFrames': 0}),
        isFalse,
      );
      expect(WindowsVideoRender.isBlankD3D11(null), isFalse);
      expect(WindowsVideoRender.isBlankD3D11({'renderApi': 'd3d11'}), isFalse);
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
