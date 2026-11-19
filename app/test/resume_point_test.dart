import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/screens/player/resume_point.dart';

void main() {
  test('a point past or near the end restarts the media instead of ending it',
      () {
    // Le cas du journal : un film de 6299 s ouvert à 6300 s.
    expect(usableResumePoint(6300, durationSeconds: 6299), 0);
    expect(usableResumePoint(6280, durationSeconds: 6299), 0);
    expect(usableResumePoint(6200, durationSeconds: 6299), 6200);
  });

  test('a point under three seconds is not worth resuming', () {
    expect(usableResumePoint(2, durationSeconds: 6299), 0);
    expect(usableResumePoint(3, durationSeconds: 6299), 3);
  });

  test('an unknown duration leaves the point as it is', () {
    expect(usableResumePoint(6300, durationSeconds: 0), 6300);
  });
}
