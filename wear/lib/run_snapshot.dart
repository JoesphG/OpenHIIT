import 'dart:convert';

/// One interval of a run, with labels precomputed by the phone.
class WearInterval {
  final String action;
  final int seconds;

  /// Position among the active intervals in a set, or 0 for rests.
  final int interval;
  final int total;
  final int set;
  final int totalSets;

  /// The phone's interval name ("Rest", "Break", "Warmup", ...), for colour.
  final String kind;

  const WearInterval({
    required this.action,
    required this.seconds,
    required this.interval,
    required this.total,
    required this.set,
    required this.totalSets,
    required this.kind,
  });

  factory WearInterval.fromJson(Map<String, dynamic> json) => WearInterval(
    action: json['action'] as String? ?? '',
    seconds: json['seconds'] as int? ?? 0,
    interval: json['interval'] as int? ?? 0,
    total: json['total'] as int? ?? 0,
    set: json['set'] as int? ?? 1,
    totalSets: json['totalSets'] as int? ?? 1,
    kind: json['kind'] as String? ?? '',
  );

  bool get isRestBetweenSets => action == "Rest between sets";

  /// "2 of 3", or empty for rests.
  String get intervalLabel => interval > 0 ? "$interval of $total" : "";

  /// "Set 2/4", "Next: Set 3/4" on the rest between sets, or empty for one set.
  String get setLabel {
    if (totalSets <= 1) {
      return "";
    }
    return isRestBetweenSets
        ? "Next: Set $set/$totalSets"
        : "Set $set/$totalSets";
  }
}

/// Where a run is at a given moment.
class RunPosition {
  final int index;
  final int remainingMs;
  final int elapsedTotalMs;
  final int totalMs;
  final bool done;

  const RunPosition({
    required this.index,
    required this.remainingMs,
    required this.elapsedTotalMs,
    required this.totalMs,
    required this.done,
  });

  /// Whole seconds left in the interval, rounded up so 0 means finished.
  int get remainingSeconds => (remainingMs / 1000).ceil();
}

/// A run published by the phone: the intervals plus where it was when sent.
///
/// The watch counts down locally from [sentAt], so the phone only needs to
/// publish when the interval or pause state changes.
class RunSnapshot {
  final String runId;
  final bool active;
  final String name;
  final bool paused;
  final int index;
  final int remainingMs;
  final DateTime sentAt;
  final List<WearInterval> intervals;

  const RunSnapshot({
    required this.runId,
    required this.active,
    required this.name,
    required this.paused,
    required this.index,
    required this.remainingMs,
    required this.sentAt,
    required this.intervals,
  });

  factory RunSnapshot.fromJson(Map<String, dynamic> json) => RunSnapshot(
    runId: json['runId'] as String? ?? '',
    active: json['active'] as bool? ?? false,
    name: json['name'] as String? ?? '',
    paused: json['paused'] as bool? ?? false,
    index: json['index'] as int? ?? 0,
    remainingMs: json['remainingMs'] as int? ?? 0,
    sentAt: DateTime.fromMillisecondsSinceEpoch(json['sentAt'] as int? ?? 0),
    intervals: (json['intervals'] as List<dynamic>? ?? [])
        .map((i) => WearInterval.fromJson(i as Map<String, dynamic>))
        .toList(),
  );

  /// Parses a published snapshot, returning null for missing or bad data.
  static RunSnapshot? tryParse(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    try {
      return RunSnapshot.fromJson(jsonDecode(source) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// A copy frozen at [position], used to pause immediately on the watch
  /// before the phone confirms.
  RunSnapshot pausedAt(RunPosition position, DateTime now) => RunSnapshot(
    runId: runId,
    active: active,
    name: name,
    paused: true,
    index: position.index,
    remainingMs: position.remainingMs,
    sentAt: now,
    intervals: intervals,
  );

  /// Whether the phone has gone quiet. It publishes on every interval
  /// change, so if the local countdown gets two intervals ahead of the last
  /// snapshot, the phone app has most likely closed mid-run.
  bool isStale(RunPosition position) =>
      !paused && !position.done && position.index >= index + 2;

  int get totalMs =>
      intervals.fold<int>(0, (sum, interval) => sum + interval.seconds * 1000);

  /// Works out the current interval and time left at [now].
  RunPosition positionAt(DateTime now) {
    final totalMs = this.totalMs;
    if (!active || intervals.isEmpty || index >= intervals.length) {
      return RunPosition(
        index: intervals.isEmpty ? 0 : intervals.length - 1,
        remainingMs: 0,
        elapsedTotalMs: totalMs,
        totalMs: totalMs,
        done: true,
      );
    }

    var current = index;
    var remaining = remainingMs;
    if (!paused) {
      final elapsed = now.difference(sentAt).inMilliseconds;
      remaining -= elapsed < 0 ? 0 : elapsed;
      while (remaining <= 0 && current < intervals.length - 1) {
        current++;
        remaining += intervals[current].seconds * 1000;
      }
    }

    final done = remaining <= 0;
    if (done) {
      remaining = 0;
    }
    final later = intervals
        .skip(current + 1)
        .fold<int>(0, (sum, interval) => sum + interval.seconds * 1000);
    return RunPosition(
      index: current,
      remainingMs: remaining,
      elapsedTotalMs: (totalMs - remaining - later).clamp(0, totalMs),
      totalMs: totalMs,
      done: done,
    );
  }
}

/// Formats milliseconds as m:ss, or h:mm:ss when an hour or longer.
String formatClock(int ms) {
  final totalSeconds = (ms / 1000).ceil();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return "$hours:${minutes.toString().padLeft(2, '0')}:$seconds";
  }
  return "$minutes:$seconds";
}

/// The big countdown: plain seconds under a minute, m:ss above.
String formatCountdown(int seconds) =>
    seconds < 60 ? "$seconds" : formatClock(seconds * 1000);
