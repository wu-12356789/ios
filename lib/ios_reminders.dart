import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'reminders.dart';

ReminderGateway createReminderGateway() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
    ? IosReminderGateway()
    : PreviewReminderGateway();

class IosReminderGateway implements ReminderGateway {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _timeZone;
  IOSFlutterLocalNotificationsPlugin get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >()!;
  @override
  bool get supported => true;
  @override
  String? get timeZone => _timeZone;
  @override
  Future<void> initialize() async {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      final result = await _plugin.initialize(
        settings: const InitializationSettings(
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
            defaultPresentAlert: true,
            defaultPresentSound: true,
            defaultPresentBadge: false,
          ),
        ),
      );
      if (result != true)
        throw StateError('Notification initialization failed');
      _initialized = true;
    }
    // Re-read when the application resumes after the device time zone changes.
    _timeZone = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(_timeZone!));
  }

  @override
  Future<ReminderPermission> permission() async {
    final result = await _ios.checkPermissions();
    if (result == null) throw StateError('Cannot read notification permission');
    if (result.isProvisionalEnabled) return ReminderPermission.quiet;
    return result.isEnabled
        ? ReminderPermission.enabled
        : ReminderPermission.disabled;
  }

  @override
  Future<void> requestPermission() async {
    await _ios.requestPermissions(alert: true, sound: true, badge: false);
  }

  @override
  Future<List<PendingReminder>> pending() async =>
      (await _ios.pendingNotificationRequests())
          .map((p) => PendingReminder(p.id, p.payload))
          .toList();
  @override
  Future<void> schedule(int id, Reminder reminder) => _ios.zonedSchedule(
    id: id,
    title: reminder.title,
    body: reminder.body,
    scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
    payload: reminder.payload,
    notificationDetails: const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
      presentBanner: true,
      presentList: true,
    ),
  );
  @override
  Future<void> cancel(int id) => _ios.cancel(id: id);
  @override
  Future<void> openSettings() async {
    if (await _ios.openAppNotificationSettings() != true)
      throw StateError('Settings unavailable');
  }
}
