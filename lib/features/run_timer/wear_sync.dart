import 'dart:convert';

import 'package:background_hiit_timer/models/interval_type.dart';
import 'package:flutter/services.dart';
import 'package:openhiit/core/logs/logs.dart';
import 'package:openhiit/features/run_timer/widgets/models/timer_list_tile_model.dart';

/// Mirrors a running timer to the Wear OS app (see wear/).
///
/// The phone stays the source of truth. It publishes a snapshot whenever the
/// interval or pause state changes, and the watch counts down locally from
/// it, so nothing is sent on every tick.
class WearSync {
  static const _channel = MethodChannel('openhiit/wear');

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

  /// Calls [onCommand] with "pause", "resume", "next" or "previous" when the
  /// watch's buttons are pressed.
  void listen(void Function(String command) onCommand) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'command') {
        onCommand(call.arguments as String);
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

  /// Tells the watch the run is over and stops listening for commands.
  void stop() {
    _channel.setMethodCallHandler(null);
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
          },
      ],
    };
  }

  Future<void> _publish(Map<String, dynamic> snapshot) async {
    try {
      await _channel.invokeMethod('publish', jsonEncode(snapshot));
    } on MissingPluginException {
      // No watch support on this platform (e.g. iOS).
    } on PlatformException catch (e) {
      Log.debug("Wear publish failed: $e");
    }
  }
}
