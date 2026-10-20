import 'package:background_hiit_timer/models/interval_type.dart';
import 'package:openhiit/core/models/timer_type.dart';
import 'package:openhiit/features/run_timer/widgets/models/timer_list_tile_model.dart';

/// Generates a list of [ListTileModel] objects representing the workout intervals
/// based on the provided list of [exercises] and the [Workout] argument.
///
/// Parameters:
///   - [exercises]: The list of exercises to be included in the workout intervals.
///   - [workoutArgument]: The 'Workout' object containing workout configuration.
///
/// Returns:
///   - A list of [ListTileModel] objects representing each interval in the workout.
///
List<TimerListTileModel> listItems(
    TimerType timer, List<IntervalType> intervals) {
  List<TimerListTileModel> listItems = [];

  const nonActiveNames = {"Rest", "Get Ready", "Warmup", "Cooldown", "Break"};
  final totalSets =
      (timer.timeSettings.restarts > 0 ? timer.timeSettings.restarts + 1 : 1);

  int workIntervalIndex = 0;
  int currentSet = 1;
  bool setIncrementPending = false;

  for (var interval in intervals) {
    final isActive = !nonActiveNames.contains(interval.name);
    final isBetweenSets = setIncrementPending && !isActive;

    if (setIncrementPending) {
      if (!isActive || workIntervalIndex >= timer.activeIntervals) {
        if (currentSet < totalSets) {
          currentSet += 1;
        }
        workIntervalIndex = 0;
        setIncrementPending = false;
      }
    }

    if (isActive) {
      workIntervalIndex += 1;
      if (workIntervalIndex == timer.activeIntervals &&
          currentSet < totalSets) {
        setIncrementPending = true;
      }
    }

    listItems.add(
      TimerListTileModel(
        action: interval.name == "Break" || isBetweenSets
            ? "Rest between sets"
            : interval.name,
        showMinutes: timer.showMinutes,
        interval: isActive ? workIntervalIndex : 0,
        total: timer.activeIntervals,
        seconds: interval.time,
        set: currentSet,
        totalSets: totalSets,
      ),
    );
  }

  return listItems;
}
