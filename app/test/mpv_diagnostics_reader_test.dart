import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/playback/mpv_diagnostics.dart';

void main() {
  test('every property the diagnostics read is asked for in the batch',
      () async {
    final asked = <String>[];
    await readMpvDiagnostics((name) async {
      asked.add(name);
      return null;
    });
    expect(asked.toSet(), mpvDiagnosticProperties.toSet(),
        reason: 'une propriété absente du lot arriverait toujours vide');
  });

  test('diagnostics are read off the UI thread in one batch', () async {
    var direct = 0;
    var batches = 0;
    final reader = MpvDiagnosticsReader(
      read: (_) async {
        direct++;
        return null;
      },
      batch: (names) async {
        batches++;
        return {'video-codec': 'hevc', 'frame-drop-count': '3'};
      },
    );
    final info = await reader();
    expect(info.videoCodec, 'hevc');
    expect(info.droppedByDisplay, 3);
    expect(batches, 1);
    expect(direct, 0);
  });

  test('a batch that cannot run falls back to direct reads, once for all',
      () async {
    var direct = 0;
    var batches = 0;
    final reader = MpvDiagnosticsReader(
      read: (name) async {
        direct++;
        return name == 'video-codec' ? 'h264' : null;
      },
      batch: (_) async {
        batches++;
        throw ArgumentError('libmpv introuvable');
      },
    );
    expect((await reader()).videoCodec, 'h264');
    await reader();
    expect(batches, 1);
    expect(direct, 2 * mpvDiagnosticProperties.length);
  });
}
