import 'dart:async';

import 'package:flutter/material.dart';

import 'run_snapshot.dart';
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

/// Mirrors the timer running on the phone.
class RunMirrorPage extends StatefulWidget {
  const RunMirrorPage({
    super.key,
    this.initialSnapshot,
    this.initialBpm,
    this.now,
  });

  /// For previews and tests: start with this snapshot instead of asking the phone.
  final RunSnapshot? initialSnapshot;

  /// For previews and tests: a heart rate to show.
  final int? initialBpm;

  /// For previews and tests: a fixed clock.
  final DateTime Function()? now;

  @override
  State<RunMirrorPage> createState() => _RunMirrorPageState();
}

class _RunMirrorPageState extends State<RunMirrorPage> {
  RunSnapshot? _snapshot;
  Timer? _ticker;

  // Hide the heart rate if the sensor stops reporting, e.g. a loose strap.
  static const _bpmStaleAfter = Duration(seconds: 10);
  int? _bpm;
  DateTime? _bpmAt;

  // Haptics are driven by the local countdown, so remember what has buzzed.
  String? _runId;
  int? _lastIndex;
  int? _lastTickSecond;
  bool _doneBuzzed = false;
  bool? _screenOn;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot;
      _bpm = widget.initialBpm;
      _bpmAt = _now();
      return;
    }
    WearBridge.listen(onState: _onState, onHeartRate: _onHeartRate);
    WearBridge.getState().then(_onState);
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WearBridge.keepScreenOn(false);
    super.dispose();
  }

  void _onState(String? json) {
    final snapshot = RunSnapshot.tryParse(json);
    if (!mounted) {
      return;
    }
    setState(() => _snapshot = snapshot);
    _tick();
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
    final position = running ? snapshot.positionAt(_now()) : null;
    final live = position != null && !position.done;

    if (_screenOn != live) {
      _screenOn = live;
      WearBridge.keepScreenOn(live);
    }

    if (running) {
      _buzz(snapshot, position!);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _buzz(RunSnapshot snapshot, RunPosition position) {
    if (snapshot.runId != _runId) {
      // New run: start quietly at its current position.
      _runId = snapshot.runId;
      _lastIndex = position.index;
      _lastTickSecond = position.remainingSeconds;
      _doneBuzzed = position.done;
      return;
    }

    if (position.done) {
      if (!_doneBuzzed) {
        _doneBuzzed = true;
        WearBridge.vibrate('done');
      }
      return;
    }
    _doneBuzzed = false;

    if (position.index != _lastIndex) {
      _lastIndex = position.index;
      _lastTickSecond = position.remainingSeconds;
      WearBridge.vibrate('change');
      return;
    }

    final second = position.remainingSeconds;
    if (second != _lastTickSecond) {
      _lastTickSecond = second;
      if (!snapshot.paused && second >= 1 && second <= 3) {
        WearBridge.vibrate('tick');
      }
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
    if (snapshot == null || !snapshot.active) {
      return const _WaitingView();
    }
    final position = snapshot.positionAt(_now());
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
