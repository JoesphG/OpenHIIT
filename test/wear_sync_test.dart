import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhiit/core/models/timer_type.dart';
import 'package:openhiit/core/utils/interval_calculation.dart';
import 'package:openhiit/features/run_timer/wear_sync.dart';
import 'package:openhiit/features/run_timer/widgets/functions/functions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('openhiit/wear');
  final published = <Map<String, dynamic>>[];
  final publishedTimers = <Map<String, dynamic>>[];

  setUp(() {
    published.clear();
    publishedTimers.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'publish') {
        final args = call.arguments as Map;
        final json = jsonDecode(args['json'] as String);
        (args['path'] == WearLink.runPath ? published : publishedTimers)
            .add(json);
      }
      return null;
    });
  });

  /// Delivers [command] as if the watch had sent it.
  Future<void> fromWatch(String command) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('command', command)),
      (_) {},
    );
  }

  WearSync buildSync() {
    final timer = TimerType.empty()
      ..name = 'Sets Tester'
      ..activeIntervals = 2
      ..activities = ['Push-ups', 'Squats'];
    timer.timeSettings
      ..getReadyTime = 10
      ..workTime = 10
      ..restTime = 5
      ..breakTime = 30
      ..restarts = 1;
    final intervals = generateIntervalsFromTimer(timer);
    return WearSync(
        name: timer.name,
        intervals: intervals,
        tiles: listItems(timer, intervals));
  }

  test('should publish only when the interval or pause state changes', () {
    final sync = buildSync();
    sync.update(
        index: 0, remainingMicroSeconds: 10000000, paused: false, ended: false);
    sync.update(
        index: 0, remainingMicroSeconds: 9000000, paused: false, ended: false);
    sync.update(
        index: 0, remainingMicroSeconds: 8000000, paused: true, ended: false);
    sync.update(
        index: 1, remainingMicroSeconds: 10000000, paused: true, ended: false);

    expect(published.map((s) => [s['index'], s['paused']]).toList(), [
      [0, false],
      [0, true],
      [1, true],
    ]);
    expect(published[1]['remainingMs'], 8000);
  });

  test('should send interval labels and set numbers for the watch', () {
    final sync = buildSync();
    sync.update(
        index: 0, remainingMicroSeconds: 10000000, paused: false, ended: false);

    final intervals = published.single['intervals'] as List;
    expect(published.single['name'], 'Sets Tester');
    expect(intervals.map((i) => i['action']), [
      'Get Ready', 'Push-ups', 'Rest', 'Squats', 'Rest between sets', //
      'Push-ups', 'Rest', 'Squats',
    ]);
    expect(intervals[4]['set'], 2);
    expect(intervals[4]['kind'], 'Break');
    expect(intervals[1]['interval'], 1);
  });

  test('should mark the run inactive when it ends or is closed', () {
    final sync = buildSync();
    sync.update(index: 7, remainingMicroSeconds: 0, paused: false, ended: true);
    sync.stop();
    expect(published.map((s) => s['active']), [false, false]);
  });

  group('WearLink', () {
    setUp(WearLink.init);

    test('should start the timer the watch picks when nothing is running',
        () async {
      final started = <String>[];
      WearLink.onStart = started.add;

      await fromWatch('start:timer-1');
      expect(started, ['timer-1']);
    });

    test('should send run controls to the active run only', () async {
      final started = <String>[];
      final commands = <String>[];
      WearLink.onStart = started.add;
      final sync = buildSync()..listen(commands.add);

      await fromWatch('pause');
      await fromWatch('start:timer-2');
      expect(commands, ['pause']);
      expect(started, isEmpty, reason: 'a run is already on screen');

      sync.stop();
      await fromWatch('next');
      expect(commands, ['pause']);
    });

    test('should share the timer list only when it changes', () async {
      final timer = TimerType.empty()
        ..id = 'timer-1'
        ..name = '20/20'
        ..activeIntervals = 4
        ..totalTime = 630;
      timer.timeSettings
        ..workTime = 20
        ..restTime = 20
        ..restarts = 3;

      await WearLink.publishTimers([timer]);
      await WearLink.publishTimers([timer]);
      timer.name = '20/20 hard';
      await WearLink.publishTimers([timer]);

      expect(publishedTimers.length, 2);
      final shared = (publishedTimers.last['timers'] as List).single;
      expect(shared['name'], '20/20 hard');
      expect(shared['sets'], 4);
      expect(shared['totalTime'], 630);
    });
  });
}
