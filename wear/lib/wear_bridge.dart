import 'package:flutter/services.dart';

/// Talks to MainActivity.kt, which owns the Wearable Data Layer connection.
class WearBridge {
  static const _channel = MethodChannel('openhiit/wear');

  /// Calls [onState] with each snapshot JSON the phone publishes, and
  /// [onHeartRate] with live heart rate readings in beats per minute.
  static void listen({
    required void Function(String? json) onState,
    required void Function(double bpm) onHeartRate,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'state':
          onState(call.arguments as String?);
        case 'heartRate':
          onHeartRate((call.arguments as num).toDouble());
      }
    });
  }

  /// The latest snapshot JSON, or null if the phone hasn't published one.
  static Future<String?> getState() => _invoke<String>('getState', null);

  /// Sends "pause", "resume", "next" or "previous" to the phone.
  static Future<void> command(String command) => _invoke('command', command);

  /// Plays "change", "tick" or "done".
  static Future<void> vibrate(String pattern) => _invoke('vibrate', pattern);

  static Future<void> keepScreenOn(bool on) => _invoke('keepScreenOn', on);

  static Future<T?> _invoke<T>(String method, Object? arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
