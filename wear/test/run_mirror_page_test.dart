import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhiit_wear/main.dart';
import 'package:openhiit_wear/run_snapshot.dart';
import 'package:openhiit_wear/timer_summary.dart';

final now = DateTime(2026, 10, 21, 12);

const timers = [
  TimerSummary(
    id: 'a',
    name: '20/20 · 4×4',
    color: 0xFF2196F3,
    totalTime: 630,
    activeIntervals: 4,
    sets: 4,
    workTime: 20,
    restTime: 20,
  ),
];

RunSnapshot run({DateTime? sentAt}) => RunSnapshot(
  runId: 'r',
  active: true,
  name: '20/20',
  paused: false,
  index: 0,
  remainingMs: 20000,
  sentAt: sentAt ?? now,
  intervals: const [
    WearInterval(
      action: 'Push-ups',
      seconds: 20,
      interval: 1,
      total: 4,
      set: 1,
      totalSets: 4,
      kind: 'Work',
    ),
    WearInterval(
      action: 'Rest',
      seconds: 20,
      interval: 0,
      total: 4,
      set: 1,
      totalSets: 4,
      kind: 'Rest',
    ),
    WearInterval(
      action: 'Squats',
      seconds: 20,
      interval: 2,
      total: 4,
      set: 1,
      totalSets: 4,
      kind: 'Work',
    ),
  ],
);

Future<void> pumpPage(WidgetTester tester, RunMirrorPage page) async {
  tester.view.physicalSize = const Size(228, 228);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
}

void main() {
  testWidgets('should list the phone timers when nothing is running', (
    tester,
  ) async {
    await pumpPage(
      tester,
      RunMirrorPage(initialTimers: timers, now: () => now),
    );
    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('20/20 · 4×4'), findsOneWidget);
  });

  testWidgets('should mirror a running timer', (tester) async {
    await pumpPage(
      tester,
      RunMirrorPage(
        initialSnapshot: run(),
        initialTimers: timers,
        initialBpm: 120,
        now: () => now.add(const Duration(seconds: 5)),
      ),
    );
    expect(find.text('Push-ups'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('should drop a run the phone stopped updating', (tester) async {
    await pumpPage(
      tester,
      RunMirrorPage(
        initialSnapshot: run(),
        initialTimers: timers,
        now: () => now.add(const Duration(seconds: 45)),
      ),
    );
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('should end the run from the back button', (tester) async {
    await pumpPage(
      tester,
      RunMirrorPage(
        initialSnapshot: run(),
        initialTimers: timers,
        now: () => now.add(const Duration(seconds: 5)),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    expect(find.text('Push-ups'), findsNothing);
    expect(find.text('Start a timer'), findsOneWidget);
  });

  testWidgets('should end the run on a system back', (tester) async {
    await pumpPage(
      tester,
      RunMirrorPage(
        initialSnapshot: run(),
        initialTimers: timers,
        now: () => now.add(const Duration(seconds: 5)),
      ),
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Push-ups'), findsNothing);
    expect(find.text('Start a timer'), findsOneWidget);
  });
}
