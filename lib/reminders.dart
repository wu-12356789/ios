import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'models.dart';

enum ReminderPermission { unknown, enabled, quiet, disabled, unsupported }

class Reminder {
  const Reminder({
    required this.key,
    required this.title,
    required this.body,
    required this.at,
  });
  final String key;
  final String title;
  final String body;
  final DateTime at;
  String get payload =>
      'forever.v2|${jsonEncode({'key': key, 'title': title, 'body': body, 'at': at.toUtc().toIso8601String()})}';
}

class PendingReminder {
  const PendingReminder(this.id, this.payload);
  final int id;
  final String? payload;
  bool get owned => payload?.startsWith('forever.v2|') ?? false;
}

abstract class ReminderGateway {
  bool get supported;
  String? get timeZone;
  Future<void> initialize();
  Future<ReminderPermission> permission();
  Future<void> requestPermission();
  Future<List<PendingReminder>> pending();
  Future<void> schedule(int id, Reminder reminder);
  Future<void> cancel(int id);
  Future<void> openSettings();
}

class PreviewReminderGateway implements ReminderGateway {
  @override
  bool get supported => false;
  @override
  String? get timeZone => null;
  @override
  Future<void> initialize() async {}
  @override
  Future<ReminderPermission> permission() async =>
      ReminderPermission.unsupported;
  @override
  Future<void> requestPermission() async {}
  @override
  Future<List<PendingReminder>> pending() async => [];
  @override
  Future<void> schedule(int id, Reminder reminder) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> openSettings() async {}
}

List<Reminder> planReminders(
  List<Task> tasks,
  List<ImportantDay> days,
  DateTime now,
) {
  final result = <Reminder>[];
  for (final task in tasks) {
    for (final time in task.plannedReminders(now)) {
      result.add(
        Reminder(
          key: 'task/${task.id}/${time.millisecondsSinceEpoch}',
          title: task.title,
          body:
              '${dateText(task.due!)} ${clockText(task.due!)}截止，'
              '${task.submission ? '请确认提交。' : '记得完成。'}',
          at: time,
        ),
      );
    }
  }
  for (final day in days) {
    // After today's 09:00 reminder, start with the next calendar day.
    var cursor = DateTime(
      now.year,
      now.month,
      now.day + (now.hour >= 9 ? 1 : 0),
    );
    // Enumerate calendar occurrences rather than repeating a Gregorian timestamp.
    for (var year = 0; year < 3; year++) {
      final occurrence = day.nextOccurrence(cursor);
      for (final lead in [7, 1, 0]) {
        final time = DateTime(
          occurrence.year,
          occurrence.month,
          occurrence.day - lead,
          9,
        );
        if (!time.isAfter(now)) continue;
        result.add(
          Reminder(
            key: 'day/${day.id}/${time.millisecondsSinceEpoch}',
            title: day.title,
            body:
                '${occurrence.year}年${dateText(occurrence)} · '
                '${lead == 0 ? '就是今天' : '还有$lead天'}',
            at: time,
          ),
        );
      }
      cursor = DateTime(occurrence.year, occurrence.month, occurrence.day + 1);
    }
  }
  result.sort((a, b) {
    final order = a.at.compareTo(b.at);
    return order == 0 ? a.key.compareTo(b.key) : order;
  });
  return result;
}

int reminderId(String key) {
  var hash = 17;
  for (final code in key.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash;
}

class ReminderCoordinator extends ChangeNotifier {
  ReminderCoordinator({ReminderGateway? gateway, DateTime Function()? clock})
    : gateway = gateway ?? PreviewReminderGateway(),
      clock = clock ?? DateTime.now;
  final ReminderGateway gateway;
  final DateTime Function() clock;
  ReminderPermission permission = ReminderPermission.unknown;
  List<Reminder> planned = [];
  int? scheduledCount;
  int deferredCount = 0;
  DateTime? scheduledThrough;
  String? error;
  bool busy = false;
  Future<void> _queue = Future<void>.value();
  bool get supported => gateway.supported;
  String get status {
    if (!supported) return '浏览器预览，不发送系统通知';
    if (error != null) return error!;
    if (busy) return '正在核对提醒';
    return switch (permission) {
      ReminderPermission.enabled => '已获通知权限，已安排${scheduledCount ?? 0}条',
      ReminderPermission.quiet => '系统使用静默通知，已安排${scheduledCount ?? 0}条',
      ReminderPermission.disabled => '通知未开启，事项仍会保存',
      _ => '尚未检查通知权限',
    };
  }

  Future<void> sync(
    List<Task> tasks,
    List<ImportantDay> days, {
    bool requestPermission = false,
  }) {
    // Snapshot before queuing so rapid edits cannot mutate an in-flight plan.
    final taskSnapshot = tasks.map((t) => Task.fromJson(t.toJson())).toList();
    final daySnapshot = days
        .map((d) => ImportantDay.fromJson(d.toJson()))
        .toList();
    _queue = _queue.then(
      (_) => _sync(taskSnapshot, daySnapshot, requestPermission),
    );
    return _queue;
  }

  Future<void> _sync(
    List<Task> tasks,
    List<ImportantDay> days,
    bool request,
  ) async {
    busy = true;
    error = null;
    scheduledCount = null;
    scheduledThrough = null;
    deferredCount = 0;
    notifyListeners();
    try {
      planned = planReminders(tasks, days, clock());
      if (!supported) {
        permission = ReminderPermission.unsupported;
        return;
      }
      await gateway.initialize();
      if (request) await gateway.requestPermission();
      permission = await gateway.permission();
      final existing = await gateway.pending();
      final owned = existing.where((p) => p.owned).toList();
      if (permission != ReminderPermission.enabled &&
          permission != ReminderPermission.quiet) {
        for (final pending in owned) {
          await gateway.cancel(pending.id);
        }
        if ((await gateway.pending()).any((p) => p.owned)) {
          throw StateError('Notification cancellation verification failed');
        }
        scheduledCount = 0;
        return;
      }
      // Keep room below iOS's 64 pending limit; never evict another producer.
      final reserved = existing.where((p) => !p.owned).map((p) => p.id).toSet();
      final capacity = max(0, 60 - reserved.length);
      final future = planned.where((r) => r.at.isAfter(clock())).toList();
      final selected = future.take(capacity).toList();
      deferredCount = future.length - selected.length;
      final desired = <int, Reminder>{};
      for (final reminder in selected) {
        var id = reminderId(reminder.key);
        while (desired.containsKey(id) || reserved.contains(id)) {
          id = (id + 1) & 0x7fffffff;
        }
        desired[id] = reminder;
      }
      final unchanged = <int>{};
      for (final pending in owned) {
        if (desired[pending.id]?.payload == pending.payload) {
          unchanged.add(pending.id);
        } else {
          // Withdraw obsolete deadlines before adding their replacements.
          await gateway.cancel(pending.id);
        }
      }
      for (final entry in desired.entries) {
        if (!unchanged.contains(entry.key) && entry.value.at.isAfter(clock())) {
          await gateway.schedule(entry.key, entry.value);
        }
      }
      final confirmed = (await gateway.pending())
          .where((p) => p.owned)
          .toList();
      final expected = desired.entries
          .where((e) => e.value.at.isAfter(clock()))
          .toList();
      if (expected.any(
            (e) => !confirmed.any(
              (p) => p.id == e.key && p.payload == e.value.payload,
            ),
          ) ||
          confirmed.any((p) => desired[p.id]?.payload != p.payload)) {
        throw StateError('Notification queue verification failed');
      }
      scheduledCount = confirmed.length;
      if (expected.isNotEmpty) scheduledThrough = expected.last.value.at;
    } catch (_) {
      error = '提醒安排未完成，请重试核对；部分旧提醒可能仍在';
      scheduledCount = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> openSettings() async {
    try {
      await gateway.openSettings();
    } catch (_) {
      error = '无法打开系统设置，请在 iPhone 设置中找到 forever';
      notifyListeners();
    }
  }
}
