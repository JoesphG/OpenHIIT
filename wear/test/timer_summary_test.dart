import 'package:flutter_test/flutter_test.dart';
import 'package:openhiit_wear/timer_summary.dart';

void main() {
  test('should parse the phone timer list and describe each timer', () {
    final timers = TimerSummary.parseList(
      '{"timers":[{"id":"a","name":"20/20 · 4×4","color":4280391411,'
      '"totalTime":630,"activeIntervals":4,"sets":4,"workTime":20,'
      '"restTime":20},{"id":"b","name":"Quick","color":1,"totalTime":45,'
      '"activeIntervals":1,"sets":1,"workTime":30,"restTime":15}]}',
    );

    expect(timers.map((t) => t.id), ['a', 'b']);
    expect(timers[0].details, '4 sets · 20/20s · 11 min');
    expect(timers[1].details, '30/15s · 45s');
  });

  test('should ignore missing or bad timer lists', () {
    expect(TimerSummary.parseList(null), isEmpty);
    expect(TimerSummary.parseList('nope'), isEmpty);
  });
}
