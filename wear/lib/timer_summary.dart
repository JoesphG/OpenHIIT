import 'dart:convert';

/// A saved timer on the phone, as offered on the watch's start list.
class TimerSummary {
  final String id;
  final String name;
  final int color;
  final int totalTime;
  final int activeIntervals;
  final int sets;
  final int workTime;
  final int restTime;

  const TimerSummary({
    required this.id,
    required this.name,
    required this.color,
    required this.totalTime,
    required this.activeIntervals,
    required this.sets,
    required this.workTime,
    required this.restTime,
  });

  factory TimerSummary.fromJson(Map<String, dynamic> json) => TimerSummary(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    color: json['color'] as int? ?? 0xFF2196F3,
    totalTime: json['totalTime'] as int? ?? 0,
    activeIntervals: json['activeIntervals'] as int? ?? 0,
    sets: json['sets'] as int? ?? 1,
    workTime: json['workTime'] as int? ?? 0,
    restTime: json['restTime'] as int? ?? 0,
  );

  /// Parses the phone's published timer list, or an empty list for bad data.
  static List<TimerSummary> parseList(String? source) {
    if (source == null || source.isEmpty) {
      return [];
    }
    try {
      final timers = (jsonDecode(source) as Map<String, dynamic>)['timers'];
      return (timers as List<dynamic>)
          .map((t) => TimerSummary.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// "4 sets · 20/20s · 11 min".
  String get details {
    final parts = <String>[
      if (sets > 1) "$sets sets",
      "$workTime/${restTime}s",
      if (totalTime >= 60)
        "${(totalTime / 60).round()} min"
      else
        "${totalTime}s",
    ];
    return parts.join(" · ");
  }
}
