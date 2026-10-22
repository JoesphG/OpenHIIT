import 'dart:async';
import 'dart:convert';

import 'package:background_hiit_timer/models/interval_type.dart';
import 'package:background_hiit_timer/models/timer_state.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
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

  /// Opens the run screen on the watch, which can't open itself.
  static Future<void> _openOnWatch() async {
    try {
      await _channel.invokeMethod('openOnWatch');
    } on MissingPluginException {
      // No watch support on this platform (e.g. iOS).
    } on PlatformException catch (e) {
      Log.debug("Wear openOnWatch failed: $e");
    }
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
    this.timerUpdates,
  }) : runId = DateTime.now().microsecondsSinceEpoch.toString();

  final String runId;
  final String name;
  final List<IntervalType> intervals;

  /// Labels for every interval, in the same order as [intervals].
  final List<TimerListTileModel> tiles;

  /// The background timer's state updates; defaults to the real service.
  final Stream<Map<String, dynamic>?>? timerUpdates;

  /// How long before an interval ends to send a fresh snapshot, so the
  /// watch's countdown cues follow the phone's actual pace.
  static const resyncBefore = 5000000;

  int? _lastIndex;
  bool? _lastPaused;
  bool? _lastEnded;
  int? _resyncedIndex;
  bool _stopped = false;
  StreamSubscription<Map<String, dynamic>?>? _updates;

  /// Calls [onCommand] with "pause", "resume", "next", "previous" or "stop"
  /// when the watch's buttons are pressed, and starts following the timer.
  void listen(void Function(String command) onCommand) {
    WearLink._runCommands = onCommand;
    // Follow the background timer's own updates rather than the run screen's
    // builds: they arrive every 100ms even while the phone is locked, so each
    // snapshot is stamped with when the timer was actually at that point.
    final updates = timerUpdates ?? FlutterBackgroundService().on('update');
    _updates = updates.listen((data) {
      if (data == null) {
        return;
      }
      final state = TimerState.fromMap(data);
      update(
        index: state.currentInterval,
        remainingMicroSeconds: state.currentMicroSeconds,
        paused: state.paused,
        ended: state.status == 'End',
      );
    });
  }

  /// Publishes the run when the interval, pause or end state changes, and
  /// once more shortly before each interval ends.
  void update({
    required int index,
    required int remainingMicroSeconds,
    required bool paused,
    required bool ended,
    DateTime? at,
  }) {
    final changed =
        index != _lastIndex || paused != _lastPaused || ended != _lastEnded;
    final resync = !changed &&
        !paused &&
        !ended &&
        _resyncedIndex != index &&
        remainingMicroSeconds <= resyncBefore;
    if (!changed && !resync) {
      return;
    }
    if (_lastIndex == null && !ended) {
      // First update of a new run: bring the watch's run screen up.
      WearLink._openOnWatch();
    }
    if (changed) {
      // An interval that starts inside the resync window needs no resync.
      _resyncedIndex = remainingMicroSeconds <= resyncBefore ? index : null;
    } else {
      _resyncedIndex = index;
    }
    _lastIndex = index;
    _lastPaused = paused;
    _lastEnded = ended;
    _publish(snapshot(
      index: index,
      remainingMicroSeconds: remainingMicroSeconds,
      paused: paused,
      active: !ended,
      at: at,
    ));
  }

  /// Tells the watch the run is over and stops taking its commands.
  ///
  /// Safe to call more than once.
  void stop() {
    if (_stopped) {
      return;
    }
    _stopped = true;
    _updates?.cancel();
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
    DateTime? at,
  }) {
    return {
      'runId': runId,
      'active': active,
      'name': name,
      'paused': paused,
      'index': index,
      'remainingMs': remainingMicroSeconds ~/ 1000,
      'sentAt': (at ?? DateTime.now()).millisecondsSinceEpoch,
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
