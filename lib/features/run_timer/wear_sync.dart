import 'dart:async';
import 'dart:convert';

import 'package:background_hiit_timer/models/interval_type.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:openhiit/core/logs/logs.dart';
import 'package:openhiit/core/models/timer_type.dart';
import 'package:openhiit/features/run_timer/widgets/models/timer_list_tile_model.dart';

/// App-wide link to the Wear OS app (see wear/), via MainActivity.kt.
///
/// Owns the platform channel so commands reach the right place: run controls
/// go to the active [WearSync], and `start:<timerId>` goes to [onStart].
class WearLink {
  static const _channel = MethodChannel('openhiit/wear');
  static const runPath = '/openhiit/run';
  static const timersPath = '/openhiit/timers';

  /// Starts the timer with the given id when the watch asks for it.
  static void Function(String timerId)? onStart;

  static void Function(String command)? _runCommands;
  static String? _lastTimersJson;

  /// Whether a run is on screen; the watch can't start a second one.
  static bool get runActive => _runCommands != null;

  static void init() {
    // Clear any run the watch still shows from before the app last closed,
    // e.g. after a crash or update mid-workout.
    publish(runPath, jsonEncode({'runId': 'none', 'active': false}));
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'command') {
        return;
      }
      final command = call.arguments as String;
      Log.debug("watch command: $command");
      if (command.startsWith('start:')) {
        if (!runActive) {
          onStart?.call(command.substring('start:'.length));
        }
      } else {
        _runCommands?.call(command);
      }
    });
  }

  /// Shares the timer list so the watch can offer them to start.
  static Future<void> publishTimers(List<TimerType> timers) async {
    final json = jsonEncode({
      'timers': [
        for (final timer in timers)
          {
            'id': timer.id,
            'name': timer.name,
            'color': timer.color,
            'totalTime': timer.totalTime,
            'activeIntervals': timer.activeIntervals,
            'sets': timer.timeSettings.restarts + 1,
            'workTime': timer.timeSettings.workTime,
            'restTime': timer.timeSettings.restTime,
          },
      ],
    });
    if (json == _lastTimersJson) {
      return;
    }
    _lastTimersJson = json;
    await publish(timersPath, json);
  }

  /// Lets the phone lock screen hide the app again after a watch-started run.
  static Future<void> _runEnded() async {
    try {
      await _channel.invokeMethod('runEnded');
    } on MissingPluginException {
      // No watch support on this platform (e.g. iOS).
    } on PlatformException catch (e) {
      Log.debug("Wear runEnded failed: $e");
    }
  }

  static Future<void> publish(String path, String json) async {
    try {
      await _channel.invokeMethod('publish', {'path': path, 'json': json});
    } on MissingPluginException {
      // No watch support on this platform (e.g. iOS).
    } on PlatformException catch (e) {
      Log.debug("Wear publish failed: $e");
    }
  }
}

/// Mirrors a running timer to the watch.
///
/// The phone stays the source of truth. It publishes a snapshot whenever the
/// interval or pause state changes, and the watch counts down locally from
/// it, so nothing is sent on every tick.
class WearSync {
  WearSync({
    required this.name,
    required this.intervals,
    required this.tiles,
  }) : runId = DateTime.now().microsecondsSinceEpoch.toString();

  final String runId;
  final String name;
  final List<IntervalType> intervals;

  /// Labels for every interval, in the same order as [intervals].
  final List<TimerListTileModel> tiles;

  int? _lastIndex;
  bool? _lastPaused;
  bool? _lastEnded;
  Timer? _framePump;

  /// Calls [onCommand] with "pause", "resume", "next" or "previous" when the
  /// watch's buttons are pressed.
  void listen(void Function(String command) onCommand) {
    WearLink._runCommands = onCommand;
    // Flutter stops building frames while the phone is locked, and the run
    // only publishes from its build. Keep building once a second so the
    // watch still hears about interval changes, e.g. a run started from the
    // watch with the phone in a pocket.
    _framePump = Timer.periodic(const Duration(seconds: 1), (_) {
      if (SchedulerBinding.instance.lifecycleState !=
          AppLifecycleState.resumed) {
        SchedulerBinding.instance.scheduleWarmUpFrame();
      }
    });
  }

  /// Publishes the run if the interval, pause or end state has changed.
  void update({
    required int index,
    required int remainingMicroSeconds,
    required bool paused,
    required bool ended,
  }) {
    if (index == _lastIndex && paused == _lastPaused && ended == _lastEnded) {
      return;
    }
    _lastIndex = index;
    _lastPaused = paused;
    _lastEnded = ended;
    _publish(snapshot(
      index: index,
      remainingMicroSeconds: remainingMicroSeconds,
      paused: paused,
      active: !ended,
    ));
  }

  /// Tells the watch the run is over and stops taking its commands.
  void stop() {
    _framePump?.cancel();
    WearLink._runCommands = null;
    WearLink._runEnded();
    _publish(snapshot(
        index: 0, remainingMicroSeconds: 0, paused: false, active: false));
  }

  Map<String, dynamic> snapshot({
    required int index,
    required int remainingMicroSeconds,
    required bool paused,
    required bool active,
  }) {
    return {
      'runId': runId,
      'active': active,
      'name': name,
      'paused': paused,
      'index': index,
      'remainingMs': remainingMicroSeconds ~/ 1000,
      'sentAt': DateTime.now().millisecondsSinceEpoch,
      'intervals': [
        for (var i = 0; i < intervals.length && i < tiles.length; i++)
          {
            'action': tiles[i].action,
            'seconds': intervals[i].time,
            'interval': tiles[i].interval,
            'total': tiles[i].total,
            'set': tiles[i].set,
            'totalSets': tiles[i].totalSets,
            'kind': intervals[i].name,
            // Sound names, so the watch can play the same alerts.
            'startSound': intervals[i].startSound,
            'countdownSound': intervals[i].countdownSound,
            'endSound': intervals[i].endSound,
          },
      ],
    };
  }

  Future<void> _publish(Map<String, dynamic> snapshot) =>
      WearLink.publish(WearLink.runPath, jsonEncode(snapshot));
}
