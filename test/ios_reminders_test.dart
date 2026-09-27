import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forever/ios_reminders.dart';
import 'package:forever/reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezoneChannel = MethodChannel('flutter_timezone');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' ||
            'requestPermissions' ||
            'openAppNotificationSettings' => true,
            'checkPermissions' => {
              'isEnabled': true,
              'isAlertEnabled': true,
              'isSoundEnabled': true,
            },
            'pendingNotificationRequests' => <Map<String, dynamic>>[],
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          timezoneChannel,
          (_) async => 'Asia/Shanghai',
        );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezoneChannel, null);
  });

  test(
    'iOS adapter defers permission and schedules a one-shot request in device time zone',
    () async {
      final gateway = IosReminderGateway();
      await gateway.initialize();
      final init =
          calls.singleWhere((c) => c.method == 'initialize').arguments as Map;
      expect(init['requestAlertPermission'], false);
      expect(init['requestSoundPermission'], false);
      expect(calls.any((c) => c.method == 'requestPermissions'), false);
      expect(await gateway.permission(), ReminderPermission.enabled);
      final at = DateTime.now().toUtc().add(const Duration(hours: 2));
      final reminder = Reminder(
        key: 'test',
        title: '提交报告',
        body: '记得提交',
        at: at,
      );
      await gateway.schedule(42, reminder);
      final schedule =
          calls.singleWhere((c) => c.method == 'zonedSchedule').arguments
              as Map;
      expect(schedule['id'], 42);
      expect(schedule['timeZoneName'], 'Asia/Shanghai');
      expect(schedule['payload'], reminder.payload);
      expect(schedule.containsKey('matchDateTimeComponents'), false);
      expect((schedule['platformSpecifics'] as Map)['presentBadge'], false);
      await gateway.requestPermission();
      expect(calls.where((c) => c.method == 'requestPermissions').length, 1);
      await gateway.cancel(42);
      expect(calls.last.arguments, 42);
      await gateway.openSettings();
      expect(calls.last.method, 'openAppNotificationSettings');
    },
  );
}
