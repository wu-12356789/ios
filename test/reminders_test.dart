import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:forever/models.dart';
import 'package:forever/reminders.dart';
import 'package:forever/store.dart';

class ControlledPreferences extends InMemorySharedPreferencesStore {
  ControlledPreferences() : super.empty();
  final firstStarted = Completer<void>();
  final secondStarted = Completer<void>();
  final firstResult = Completer<bool>();
  final secondResult = Completer<bool>();
  int writes = 0;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final first = writes++ == 0;
    (first ? firstStarted : secondStarted).complete();
    final accepted = await (first ? firstResult : secondResult).future;
    return accepted ? super.setValue(valueType, key, value) : false;
  }
}

class FakeGateway implements ReminderGateway {
  final Map<int, PendingReminder> records = {};
  final List<String> calls = [];
  ReminderPermission allowed = ReminderPermission.enabled;
  bool failSchedule = false;
  bool failCancel = false;
  bool dropCancel = false;
  bool dropSchedule = false;
  Completer<void>? gate;
  @override
  bool get supported => true;
  @override
  String get timeZone => 'Asia/Shanghai';
  @override
  Future<void> initialize() async {
    await gate?.future;
  }

  @override
  Future<ReminderPermission> permission() async => allowed;
  @override
  Future<void> requestPermission() async {
    calls.add('permission');
  }

  @override
  Future<List<PendingReminder>> pending() async => records.values.toList();
  @override
  Future<void> cancel(int id) async {
    calls.add('cancel:$id');
    if (failCancel) throw StateError('cancel failed');
    if (!dropCancel) records.remove(id);
  }

  @override
  Future<void> schedule(int id, Reminder reminder) async {
    calls.add('schedule:$id');
    if (failSchedule) throw StateError('schedule failed');
    if (!dropSchedule) records[id] = PendingReminder(id, reminder.payload);
  }

  @override
  Future<void> openSettings() async {
    calls.add('settings');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 24, 8);
  Task task(String id, {int day = 25}) => Task(
    id: id,
    title: '报告$id',
    submission: true,
    due: DateTime(2026, 9, day, 20),
  );

  test(
    'prepare keeps requests; submit cancels; reopen restores with stable IDs',
    () async {
      final gateway = FakeGateway();
      final coordinator = ReminderCoordinator(
        gateway: gateway,
        clock: () => now,
      );
      final report = task('a');
      await coordinator.sync([report], []);
      final original = gateway.records.keys.toSet();
      expect(original.length, 3);
      expect(gateway.calls, isNot(contains('permission')));
      gateway.calls.clear();
      report.prepare();
      await coordinator.sync([report], []);
      expect(gateway.calls, isEmpty);
      report.finish();
      await coordinator.sync([report], []);
      expect(gateway.records, isEmpty);
      report.reopen();
      await coordinator.sync([report], []);
      expect(gateway.records.keys.toSet(), original);
    },
  );

  test(
    'editing withdraws old deadlines and deleting removes all owned requests',
    () async {
      final gateway = FakeGateway();
      final coordinator = ReminderCoordinator(
        gateway: gateway,
        clock: () => now,
      );
      final report = task('a');
      await coordinator.sync([report], []);
      final oldIds = gateway.records.keys.toSet();
      report.due = DateTime(2026, 9, 26, 21);
      report.title = '已改标题';
      gateway.calls.clear();
      await coordinator.sync([report], []);
      expect(gateway.records.keys.toSet().intersection(oldIds), isEmpty);
      expect(gateway.calls.take(3).every((c) => c.startsWith('cancel:')), true);
      expect(
        gateway.records.values.every((p) => p.payload!.contains('已改标题')),
        true,
      );
      await coordinator.sync([], []);
      expect(gateway.records, isEmpty);
    },
  );

  test(
    'denied permission cancels owned requests and only explicit action requests permission',
    () async {
      final gateway = FakeGateway();
      final coordinator = ReminderCoordinator(
        gateway: gateway,
        clock: () => now,
      );
      await coordinator.sync([task('a')], []);
      gateway.records[1] = const PendingReminder(1, 'unrelated');
      gateway.allowed = ReminderPermission.disabled;
      await coordinator.sync([task('a')], []);
      expect(gateway.records.keys, [1]);
      expect(coordinator.scheduledCount, 0);
      expect(gateway.calls, isNot(contains('permission')));
      await coordinator.sync([task('a')], [], requestPermission: true);
      expect(gateway.calls.where((c) => c == 'permission').length, 1);
    },
  );

  test(
    'capacity retains nearest requests and preserves IDs used by another producer',
    () async {
      final gateway = FakeGateway();
      final tasks = List.generate(25, (i) => task('$i', day: 25 + i));
      final all = planReminders(tasks, [], now);
      final foreignId = reminderId(all.first.key);
      gateway.records[foreignId] = PendingReminder(foreignId, 'other producer');
      final coordinator = ReminderCoordinator(
        gateway: gateway,
        clock: () => now,
      );
      await coordinator.sync(tasks, []);
      expect(gateway.records.length, 60);
      expect(gateway.records[foreignId]!.payload, 'other producer');
      expect(coordinator.deferredCount, all.length - 59);
      final installed = gateway.records.values
          .where((r) => r.owned)
          .map((r) => r.payload)
          .toSet();
      expect(installed, all.take(59).map((r) => r.payload).toSet());
    },
  );

  test('failed cancellation stops replacement; retry repairs queue', () async {
    final gateway = FakeGateway();
    final coordinator = ReminderCoordinator(gateway: gateway, clock: () => now);
    final report = task('a');
    await coordinator.sync([report], []);
    gateway.failCancel = true;
    report.finish();
    await coordinator.sync([report], []);
    expect(coordinator.error, isNotNull);
    expect(coordinator.scheduledCount, isNull);
    gateway.failCancel = false;
    await coordinator.sync([report], []);
    expect(coordinator.error, isNull);
    expect(gateway.records, isEmpty);
  });

  test(
    'silent schedule loss is detected instead of reporting success',
    () async {
      final gateway = FakeGateway()..dropSchedule = true;
      final coordinator = ReminderCoordinator(
        gateway: gateway,
        clock: () => now,
      );
      await coordinator.sync([task('a')], []);
      expect(coordinator.error, isNotNull);
      expect(coordinator.scheduledCount, isNull);
      gateway.dropSchedule = false;
      await coordinator.sync([task('a')], []);
      expect(coordinator.error, isNull);
      expect(coordinator.scheduledCount, 3);
    },
  );

  test(
    'silent cancellation failure is detected after completion or denial',
    () async {
      for (final denied in [false, true]) {
        final gateway = FakeGateway();
        final coordinator = ReminderCoordinator(
          gateway: gateway,
          clock: () => now,
        );
        final report = task('a');
        await coordinator.sync([report], []);
        gateway.dropCancel = true;
        if (denied) {
          gateway.allowed = ReminderPermission.disabled;
        } else {
          report.finish();
        }
        await coordinator.sync([report], []);
        expect(coordinator.error, isNotNull);
        expect(coordinator.scheduledCount, isNull);
        gateway.dropCancel = false;
        await coordinator.sync([report], []);
        expect(coordinator.error, isNull);
        expect(gateway.records, isEmpty);
      }
    },
  );

  test(
    'rapid edits are serialized and snapshot inputs until the final cancellation',
    () async {
      final gateway = FakeGateway()..gate = Completer<void>();
      final coordinator = ReminderCoordinator(
        gateway: gateway,
        clock: () => now,
      );
      final report = task('a');
      final first = coordinator.sync([report], []);
      report.finish();
      final second = coordinator.sync([report], []);
      gateway.gate!.complete();
      await Future.wait([first, second]);
      expect(gateway.records, isEmpty);
      expect(gateway.calls.where((c) => c.startsWith('schedule:')).length, 3);
    },
  );

  test(
    'annual lunar plan skips past morning and precomputes next three occurrences',
    () {
      final day = ImportantDay(
        id: 'newyear',
        title: '春节',
        month: 1,
        day: 1,
        lunar: true,
      );
      final plan = planReminders([], [day], DateTime(2026, 2, 17, 10));
      expect(plan.every((r) => r.at.isAfter(DateTime(2026, 2, 17, 10))), true);
      expect(plan.map((r) => r.at), contains(DateTime(2027, 2, 6, 9)));
      expect(plan.map((r) => r.at), contains(DateTime(2027, 1, 30, 9)));
      expect(plan.length, 9);
    },
  );

  test(
    'native starts empty and saved completion survives store recreation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final gateway = FakeGateway();
      final store = ForeverStore(
        preferences: preferences,
        seedExamples: false,
        reminders: ReminderCoordinator(gateway: gateway, clock: () => now),
      );
      expect(store.tasks, isEmpty);
      store.add(task('saved'));
      await store.refreshReminders();
      expect(gateway.records.length, 3);
      store.finish(store.tasks.single);
      await store.refreshReminders();
      expect(gateway.records, isEmpty);
      final restored = ForeverStore(
        preferences: preferences,
        seedExamples: false,
      );
      expect(restored.tasks.single.finished, true);
      expect(preferences.getString('forever.v1'), contains('Z'));
      expect(restored.tasks.single.due, store.tasks.single.due);
    },
  );

  test(
    'corrupt saved data must not replace the existing system notification queue',
    () async {
      SharedPreferences.setMockInitialValues({'forever.v1': 'invalid'});
      final gateway = FakeGateway();
      gateway.records[10] = const PendingReminder(10, 'forever.v2|existing');
      final store = ForeverStore(
        preferences: await SharedPreferences.getInstance(),
        seedExamples: false,
        reminders: ReminderCoordinator(gateway: gateway, clock: () => now),
      );
      await store.refreshReminders();
      await store.save();
      expect(store.readFailed, true);
      expect(gateway.records.length, 1);
      expect(gateway.calls, isEmpty);
    },
  );

  test(
    'refresh waits for a later save and preserves reminders if it fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final originalBackend = SharedPreferencesStorePlatform.instance;
      final backend = ControlledPreferences();
      SharedPreferencesStorePlatform.instance = backend;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = originalBackend,
      );
      final gateway = FakeGateway();
      final store = ForeverStore(
        preferences: preferences,
        seedExamples: false,
        reminders: ReminderCoordinator(gateway: gateway, clock: () => now),
      );
      final report = task('saving');
      store.add(report);
      await backend.firstStarted.future;
      final refresh = store.refreshReminders();
      store.finish(report);
      backend.firstResult.complete(true);
      await backend.secondStarted.future;
      await Future<void>.delayed(Duration.zero);
      final countWhileSaving = gateway.records.length;
      backend.secondResult.complete(false);
      await refresh;
      await store.refreshReminders();
      expect(countWhileSaving, 3);
      expect(store.storageWarning, isNotNull);
      expect(gateway.records.length, 3);
    },
  );
}
