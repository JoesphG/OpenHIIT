import 'dart:async';

import 'package:flutter/material.dart';

import 'run_snapshot.dart';
import 'timer_summary.dart';
import 'wear_bridge.dart';

void main() {
  runApp(const OpenHiitWearApp());
}

class OpenHiitWearApp extends StatelessWidget {
  const OpenHiitWearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenHIIT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.green,
        useMaterial3: true,
      ),
      home: const RunMirrorPage(),
    );
  }
}

/// Mirrors the timer running on the phone, and lists its timers to start
/// from the watch when nothing is running.
class RunMirrorPage extends StatefulWidget {
  const RunMirrorPage({
    super.key,
    this.initialSnapshot,
    this.initialTimers,
    this.initialBpm,
    this.startingTimerId,
    this.showStartHint = false,
    this.now,
  });

  /// For previews and tests: start with this snapshot instead of asking the phone.
  final RunSnapshot? initialSnapshot;

  /// For previews and tests: the phone's timer list.
  final List<TimerSummary>? initialTimers;

  /// For previews and tests: show this timer as starting.
  final String? startingTimerId;

  /// For previews and tests: show the "open the phone app" hint.
  final bool showStartHint;

  /// For previews and tests: a heart rate to show.
  final int? initialBpm;

  /// For previews and tests: a fixed clock.
  final DateTime Function()? now;

  @override
  State<RunMirrorPage> createState() => _RunMirrorPageState();
}

class _RunMirrorPageState extends State<RunMirrorPage> {
  RunSnapshot? _snapshot;
  List<TimerSummary> _timers = [];
  Timer? _ticker;
  final _listScroll = ScrollController();

  // A start request waits this long for the phone's run before giving up.
  static const _startTimeout = Duration(seconds: 6);
  static const _hintDuration = Duration(seconds: 6);
  String? _startingId;
  DateTime? _startRequestedAt;
  DateTime? _startFailedAt;

  // Return to the timer list this long after a run finishes.
  static const _doneShownFor = Duration(seconds: 8);
  DateTime? _doneSince;

  // Hide the heart rate if the sensor stops reporting, e.g. a loose strap.
  static const _bpmStaleAfter = Duration(seconds: 10);
  int? _bpm;
  DateTime? _bpmAt;

  bool? _screenOn;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.initialSnapshot != null || widget.initialTimers != null) {
      _snapshot = widget.initialSnapshot;
      _timers = widget.initialTimers ?? [];
      _startingId = widget.startingTimerId;
      _startFailedAt = widget.showStartHint ? _now() : null;
      _bpm = widget.initialBpm;
      _bpmAt = _now();
      return;
    }
    WearBridge.listen(
      onState: _onState,
      onTimers: _onTimers,
      onHeartRate: _onHeartRate,
      onRotary: _onRotary,
    );
    WearBridge.getState().then(_onState);
    WearBridge.getTimers().then(_onTimers);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _listScroll.dispose();
    WearBridge.keepScreenOn(false);
    super.dispose();
  }

  void _onState(String? json) {
    final snapshot = RunSnapshot.tryParse(json);
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      if (snapshot != null && snapshot.active) {
        _startingId = null;
        _startFailedAt = null;
      }
    });
    _tick();
  }

  void _onTimers(String? json) {
    final timers = TimerSummary.parseList(json);
    if (mounted) {
      setState(() => _timers = timers);
    }
  }

  void _onRotary(double pixels) {
    if (!_listScroll.hasClients) {
      return;
    }
    final position = _listScroll.position;
    _listScroll.jumpTo(
      (position.pixels + pixels).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _startTimer(TimerSummary timer) {
    if (_startingId != null) {
      return;
    }
    setState(() {
      _startingId = timer.id;
      _startRequestedAt = _now();
      _startFailedAt = null;
    });
    WearBridge.vibrate('tick');
    WearBridge.command('start:${timer.id}');
  }

  void _onHeartRate(double bpm) {
    _bpm = bpm.round();
    _bpmAt = _now();
  }

  int? get _currentBpm {
    final at = _bpmAt;
    if (_bpm == null || at == null || _now().difference(at) > _bpmStaleAfter) {
      return null;
    }
    return _bpm;
  }

  void _tick() {
    final snapshot = _snapshot;
    final running = snapshot != null && snapshot.active;
    var position = running ? snapshot.positionAt(_now()) : null;
    if (position != null && snapshot!.isStale(position)) {
      position = null;
    }
    final live = position != null && !position.done;

    if (position != null && position.done) {
      _doneSince ??= _now();
    } else {
      _doneSince = null;
    }

    // The phone app has to be open to start a timer; say so if it isn't.
    final requestedAt = _startRequestedAt;
    if (_startingId != null &&
        requestedAt != null &&
        _now().difference(requestedAt) > _startTimeout) {
      _startingId = null;
      _startFailedAt = _now();
    }

    if (_screenOn != live) {
      _screenOn = live;
      WearBridge.keepScreenOn(live);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _togglePause(RunSnapshot snapshot, RunPosition position) {
    if (snapshot.paused) {
      WearBridge.command('resume');
    } else {
      // Freeze straight away; the phone's next snapshot confirms it.
      setState(() => _snapshot = snapshot.pausedAt(position, _now()));
      WearBridge.command('pause');
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final position = snapshot?.positionAt(_now());
    final doneSince = _doneSince;
    final finishedAWhileAgo =
        doneSince != null && _now().difference(doneSince) > _doneShownFor;

    if (snapshot == null ||
        position == null ||
        !snapshot.active ||
        snapshot.isStale(position) ||
        finishedAWhileAgo) {
      if (_timers.isEmpty) {
        return const _WaitingView();
      }
      final failedAt = _startFailedAt;
      return _TimerListView(
        timers: _timers,
        controller: _listScroll,
        startingId: _startingId,
        showHint:
            failedAt != null && _now().difference(failedAt) < _hintDuration,
        onStart: _startTimer,
      );
    }
    if (position.done) {
      return _DoneView(name: snapshot.name, totalMs: position.totalMs);
    }
    return _RunView(
      snapshot: snapshot,
      position: position,
      bpm: _currentBpm,
      onTogglePause: () => _togglePause(snapshot, position),
      onNext: () => WearBridge.command('next'),
      onPrevious: () => WearBridge.command('previous'),
    );
  }
}

/// Matches the phone's run screen colours.
Color intervalColor(String kind) {
  switch (kind.toLowerCase()) {
    case 'get ready':
      return Colors.black;
    case 'warmup':
      return Colors.orange;
    case 'rest':
      return Colors.red;
    case 'cooldown':
      return Colors.blue;
    case 'break':
      return Colors.teal;
    default:
      return Colors.green;
  }
}

/// Lays out [children] inside the circle of a round watch face.
///
/// The usable square inside a circle is about 70% of its diameter, so this
/// pads by 15% on each side. On square watches the extra margin is harmless.
class _RoundSafeArea extends StatelessWidget {
  const _RoundSafeArea({required this.color, required this.builder});

  final Color color;
  final Widget Function(BuildContext context, double size) builder;

  @override
  Widget build(BuildContext context) {
    // Material gives text the app's theme (and avoids the debug underline).
    return Material(
      color: color,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          return Center(
            child: SizedBox.square(
              dimension: size * 0.82,
              child: builder(context, size),
            ),
          );
        },
      ),
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView({
    required this.snapshot,
    required this.position,
    required this.bpm,
    required this.onTogglePause,
    required this.onNext,
    required this.onPrevious,
  });

  final RunSnapshot snapshot;
  final RunPosition position;
  final int? bpm;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  Widget build(BuildContext context) {
    final interval = snapshot.intervals[position.index];
    final detail = [
      interval.intervalLabel,
      interval.setLabel,
    ].where((label) => label.isNotEmpty).join(" · ");
    final elapsed = position.elapsedTotalMs ~/ 1000 * 1000;

    return _RoundSafeArea(
      color: intervalColor(interval.kind),
      builder: (context, size) {
        final small = TextStyle(
          color: Colors.white.withValues(alpha: .9),
          fontSize: size * 0.062,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Column(
          children: [
            SizedBox(height: size * 0.03),
            // The circle is narrowest at the top, so keep the name within
            // the visible width and truncate long exercise names.
            SizedBox(
              height: size * 0.1,
              width: size * 0.66,
              child: Center(
                child: Text(
                  interval.action,
                  key: const Key('wear-action'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.08,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: size * 0.075,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  snapshot.paused ? "Paused" : detail,
                  key: const Key('wear-detail'),
                  style: small,
                ),
              ),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text(
                  formatCountdown(position.remainingSeconds),
                  key: const Key('wear-countdown'),
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: snapshot.paused ? .55 : 1,
                    ),
                    fontSize: 200,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: size * 0.075,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${formatClock(elapsed)} / ${formatClock(position.totalMs)}",
                      key: const Key('wear-total'),
                      style: small,
                    ),
                    if (bpm != null) ...[
                      SizedBox(width: size * 0.04),
                      Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: size * 0.06,
                      ),
                      SizedBox(width: size * 0.012),
                      Text("$bpm", key: const Key('wear-bpm'), style: small),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: size * 0.02),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundButton(
                  icon: Icons.skip_previous,
                  label: 'Previous',
                  diameter: size * 0.15,
                  onPressed: onPrevious,
                ),
                SizedBox(width: size * 0.04),
                _RoundButton(
                  icon: snapshot.paused ? Icons.play_arrow : Icons.pause,
                  label: snapshot.paused ? 'Resume' : 'Pause',
                  diameter: size * 0.19,
                  onPressed: onTogglePause,
                ),
                SizedBox(width: size * 0.04),
                _RoundButton(
                  icon: Icons.skip_next,
                  label: 'Next',
                  diameter: size * 0.15,
                  onPressed: onNext,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.diameter,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final double diameter;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: const Color.fromARGB(70, 0, 0, 0),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: diameter,
            child: Icon(icon, color: Colors.white, size: diameter * 0.62),
          ),
        ),
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView();

  @override
  Widget build(BuildContext context) {
    return _RoundSafeArea(
      color: Colors.black,
      builder: (context, size) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, color: Colors.green, size: size * 0.2),
          SizedBox(height: size * 0.04),
          Text(
            "Start a timer\non your phone",
            key: const Key('wear-waiting'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: size * 0.075),
          ),
          SizedBox(height: size * 0.02),
          Text(
            "It will appear here",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .7),
              fontSize: size * 0.06,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.name, required this.totalMs});

  final String name;
  final int totalMs;

  @override
  Widget build(BuildContext context) {
    return _RoundSafeArea(
      color: Colors.black,
      builder: (context, size) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: size * 0.2),
          SizedBox(height: size * 0.04),
          Text(
            "Done!",
            key: const Key('wear-done'),
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: size * 0.02),
          Text(
            "$name · ${formatClock(totalMs)}",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .7),
              fontSize: size * 0.06,
            ),
          ),
        ],
      ),
    );
  }
}

/// The phone's timers, to start one from the watch.
class _TimerListView extends StatelessWidget {
  const _TimerListView({
    required this.timers,
    required this.controller,
    required this.startingId,
    required this.showHint,
    required this.onStart,
  });

  final List<TimerSummary> timers;
  final ScrollController controller;
  final String? startingId;
  final bool showHint;
  final ValueChanged<TimerSummary> onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          // Generous top and bottom padding lets the first and last cards
          // scroll into the wide middle of the round screen.
          return ListView(
            key: const Key('wear-timer-list'),
            controller: controller,
            padding: EdgeInsets.fromLTRB(
              size * 0.09,
              size * 0.13,
              size * 0.09,
              size * 0.26,
            ),
            children: [
              Text(
                "Start a timer",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .7),
                  fontSize: size * 0.06,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showHint)
                Padding(
                  padding: EdgeInsets.only(top: size * 0.03),
                  child: Text(
                    "Open OpenHIIT on your phone, then try again",
                    key: const Key('wear-start-hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: size * 0.055,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              for (final timer in timers)
                Padding(
                  padding: EdgeInsets.only(top: size * 0.035),
                  child: _TimerCard(
                    timer: timer,
                    size: size,
                    starting: timer.id == startingId,
                    onTap: () => onStart(timer),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({
    required this.timer,
    required this.size,
    required this.starting,
    required this.onTap,
  });

  final TimerSummary timer;
  final double size;
  final bool starting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Start ${timer.name}",
      child: Material(
        color: Color(timer.color),
        borderRadius: BorderRadius.circular(size * 0.09),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: size * 0.06,
              vertical: size * 0.035,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * 0.07,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        starting ? "Starting on phone…" : timer.details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .85),
                          fontSize: size * 0.052,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: size * 0.02),
                SizedBox.square(
                  dimension: size * 0.09,
                  child: starting
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        )
                      : Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: size * 0.09,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
