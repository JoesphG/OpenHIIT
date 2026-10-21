# OpenHIIT for Wear OS

A companion watch app that mirrors timers running on the phone app. Start a
timer on the phone and the watch shows the current interval, set, countdown,
overall elapsed / total time and live heart rate, and buzzes on each interval
change. The watch's pause, previous and next buttons control the phone.

## How it works

- The phone stays the source of truth. `lib/features/run_timer/wear_sync.dart`
  publishes a snapshot (intervals, labels, current interval, time remaining)
  as a Wearable Data Layer item whenever the interval or pause state changes.
- The watch counts down locally from the latest snapshot
  (`lib/run_snapshot.dart`), so nothing is sent on every tick.
- Watch buttons send messages back to the phone, which applies them to the
  real timer and publishes a fresh snapshot.
- While a run is active, `OngoingRun` keeps an Ongoing Activity up, so the
  OpenHIIT icon sits on the watch face and in recents to get back into the run.
- When nothing is running, the watch lists the phone's timers. Tapping one
  asks the phone to start it; the phone app must be open (it can be locked
  or in the background), as Android won't let it open itself.
- Heart rate comes from Wear OS Health Services and is only measured while
  the app is on screen.

The Data Layer only connects apps with the **same application ID and signing
key**, so this app uses `com.codepup.workout_timer` and signs release builds
with `../android/key.properties`, like the phone app. It needs Google Play
Services on both devices.

## Build

```sh
cd wear
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Requires Wear OS 3 or later (API 30+).

## Sideload onto a Pixel Watch

1. On the watch: Settings > System > About > Versions, tap **Build number**
   seven times. Then in Settings > Developer options turn on **ADB debugging**
   and **Wireless debugging**. Keep the watch on the same Wi-Fi as the computer.
2. Wireless debugging > **Pair new device** shows an IP, port and code:

   ```sh
   adb pair <ip>:<pairing-port>     # enter the code
   adb connect <ip>:<debug-port>    # port shown on the Wireless debugging screen
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

3. Open OpenHIIT on the watch once and allow the heart rate and notification
   permissions.

On WSL2, `adb` often can't reach devices on the local network. Either run the
Windows `adb.exe` from Android platform-tools, or enable mirrored networking
by adding `networkingMode=mirrored` under `[wsl2]` in `%UserProfile%\.wslconfig`.
