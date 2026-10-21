import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:openhiit/core/logs/logs.dart';
import 'package:openhiit/core/providers/timer_provider/timer_provider.dart';
import 'package:openhiit/core/utils/interval_calculation.dart';
import 'package:openhiit/features/run_timer/wear_sync.dart';
import 'package:openhiit/features/run_timer/workout.dart';
import 'package:openhiit/shared/globals.dart';
import 'package:provider/provider.dart';

/// Keeps the watch's timer list current and starts timers it picks.
///
/// Sits below the [TimerProvider] so it can follow changes to the list.
class WearTimerLink extends StatefulWidget {
  const WearTimerLink({super.key, required this.child});

  final Widget child;

  @override
  State<WearTimerLink> createState() => _WearTimerLinkState();
}

class _WearTimerLinkState extends State<WearTimerLink> {
  late final TimerProvider _timers;

  @override
  void initState() {
    super.initState();
    _timers = context.read<TimerProvider>();
    _timers.addListener(_publishTimers);
    WearLink.onStart = _start;
  }

  @override
  void dispose() {
    _timers.removeListener(_publishTimers);
    WearLink.onStart = null;
    super.dispose();
  }

  void _publishTimers() => WearLink.publishTimers(_timers.timers);

  void _start(String timerId) {
    final matches = _timers.timers.where((t) => t.id == timerId);
    final navigator = navigatorKey.currentState;
    if (matches.isEmpty || navigator == null) {
      Log.warning("watch asked to start unknown timer $timerId");
      return;
    }
    final timer = matches.first;
    final intervals = generateIntervalsFromTimer(timer);
    if (intervals.isEmpty) {
      return;
    }
    Log.info("starting timer from watch: ${timer.name}");
    navigator.push(MaterialPageRoute(
      builder: (_) => RunTimer(timer: timer, intervals: intervals),
    ));
    // The phone is usually locked, when Flutter builds no frames, so build
    // the run screen now to start the timer.
    SchedulerBinding.instance.scheduleWarmUpFrame();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
