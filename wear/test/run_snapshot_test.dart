import 'package:flutter_test/flutter_test.dart';
import 'package:openhiit_wear/run_snapshot.dart';

final sentAt = DateTime(2026, 10, 21, 12);

WearInterval interval(
  String action,
  int seconds, {
  int n = 0,
  int set = 1,
  String kind = 'Work',
}) => WearInterval(
  action: action,
  seconds: seconds,
  interval: n,
  total: 2,
  set: set,
  totalSets: 2,
  kind: kind,
);

RunSnapshot snapshot({
  int index = 0,
  int remainingMs = 10000,
  bool paused = false,
}) => RunSnapshot(
  runId: 'run-1',
  active: true,
  name: 'Tester',
  paused: paused,
  index: index,
  remainingMs: remainingMs,
  sentAt: sentAt,
  intervals: [
    interval('Push-ups', 10, n: 1),
    interval('Rest', 5, kind: 'Rest'),
    interval('Squats', 10, n: 2),
    interval('Rest between sets', 30, set: 2, kind: 'Break'),
    interval('Push-ups', 10, n: 1, set: 2),
  ],
);

void main() {
  group('positionAt', () {
    test('should count down within the current interval', () {
      final p = snapshot().positionAt(sentAt.add(const Duration(seconds: 3)));
      expect(p.index, 0);
      expect(p.remainingSeconds, 7);
      expect(p.elapsedTotalMs, 3000);
      expect(p.totalMs, 65000);
    });

    test('should move on to later intervals without a new snapshot', () {
      // 10s push-ups + 5s rest + 4s into squats.
      final p = snapshot().positionAt(sentAt.add(const Duration(seconds: 19)));
      expect(p.index, 2);
      expect(p.remainingSeconds, 6);
      expect(p.done, isFalse);
    });

    test('should hold still while paused', () {
      final p = snapshot(
        paused: true,
        remainingMs: 4200,
      ).positionAt(sentAt.add(const Duration(minutes: 5)));
      expect(p.index, 0);
      expect(p.remainingSeconds, 5);
    });

    test('should finish after the last interval', () {
      final p = snapshot().positionAt(sentAt.add(const Duration(minutes: 2)));
      expect(p.done, isTrue);
      expect(p.elapsedTotalMs, p.totalMs);
    });

    test('should freeze at the current position when paused on the watch', () {
      final now = sentAt.add(const Duration(seconds: 12));
      final s = snapshot();
      final paused = s.pausedAt(s.positionAt(now), now);
      final later = paused.positionAt(now.add(const Duration(seconds: 30)));
      expect(later.index, 1);
      expect(later.remainingSeconds, 3);
    });
  });

  test('should treat a run as lost when the phone goes quiet', () {
    final s = snapshot();
    // One interval ahead is normal between phone updates.
    expect(
      s.isStale(s.positionAt(sentAt.add(const Duration(seconds: 12)))),
      isFalse,
    );
    // Two ahead means the phone missed an update it always sends.
    expect(
      s.isStale(s.positionAt(sentAt.add(const Duration(seconds: 17)))),
      isTrue,
    );
    expect(
      snapshot(
        paused: true,
      ).isStale(s.positionAt(sentAt.add(const Duration(minutes: 1)))),
      isFalse,
    );
  });

  test('should label intervals and sets for the small screen', () {
    final s = snapshot();
    expect(s.intervals[0].intervalLabel, '1 of 2');
    expect(s.intervals[0].setLabel, 'Set 1/2');
    expect(s.intervals[1].intervalLabel, '');
    expect(s.intervals[3].setLabel, 'Next: Set 2/2');
  });

  test('should parse published JSON and ignore bad data', () {
    expect(RunSnapshot.tryParse(null), isNull);
    expect(RunSnapshot.tryParse('not json'), isNull);
    final s = RunSnapshot.tryParse(
      '{"runId":"r","active":true,"name":"T","paused":false,"index":0,'
      '"remainingMs":5000,"sentAt":0,"intervals":[{"action":"Work",'
      '"seconds":5,"interval":1,"total":1,"set":1,"totalSets":1,"kind":"Work"}]}',
    );
    expect(s!.intervals.single.action, 'Work');
  });

  test('should format clocks', () {
    expect(formatClock(446000), '7:26');
    expect(formatClock(3725000), '1:02:05');
    expect(formatCountdown(42), '42');
    expect(formatCountdown(90), '1:30');
  });
}
