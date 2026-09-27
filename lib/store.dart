import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'reminders.dart';

class ForeverStore extends ChangeNotifier {
  ForeverStore({
    this.preferences,
    DateTime? today,
    bool seedExamples = true,
    ReminderCoordinator? reminders,
  }) : reminders = reminders ?? ReminderCoordinator() {
    final now = today ?? DateTime.now();
    final birthday = now.add(const Duration(days: 6));
    tasks = [
      Task(
        id: 'parcel',
        title: '取快递',
        due: DateTime(now.year, now.month, now.day, 21, 30),
      ),
      Task(
        id: 'application',
        title: '实习申请',
        submission: true,
        stage: TaskStage.prepared,
        due: DateTime(now.year, now.month, now.day, 22),
        note: '内容已准备，记得在提交后确认。',
      ),
      Task(
        id: 'report',
        title: '课程报告',
        submission: true,
        due: DateTime(now.year, now.month, now.day + 1, 20),
      ),
    ];
    days = [
      ImportantDay(
        id: 'birthday',
        title: '妈妈生日',
        month: birthday.month,
        day: birthday.day,
      ),
    ];
    if (!seedExamples) {
      tasks = [];
      days = [];
    }
    final saved = preferences?.getString('forever.v1');
    if (saved != null) {
      try {
        final j = jsonDecode(saved) as Map<String, dynamic>;
        final restoredTasks = (j['tasks'] as List)
            .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final restoredDays = (j['days'] as List)
            .map((e) => ImportantDay.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        tasks = restoredTasks;
        days = restoredDays;
      } catch (_) {
        storageWarning = '本地记录读取失败，原记录未载入；保存与提醒更新已暂停。';
        readFailed = true;
      }
    }
    this.reminders.addListener(notifyListeners);
  }
  final SharedPreferences? preferences;
  final ReminderCoordinator reminders;
  late List<Task> tasks;
  late List<ImportantDay> days;
  String? storageWarning;
  bool readFailed = false;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> refreshReminders({bool requestPermission = false}) async {
    // A second edit may arrive while the first save is in flight. Wait for the
    // latest queue before using live state, including its persistence result.
    while (true) {
      final pendingWrites = _writeQueue;
      await pendingWrites;
      if (identical(pendingWrites, _writeQueue)) break;
    }
    if (readFailed || storageWarning != null) return;
    await reminders.sync(tasks, days, requestPermission: requestPermission);
  }

  @override
  void dispose() {
    reminders.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> save() async {
    notifyListeners();
    if (readFailed) return;
    final payload = jsonEncode({
      'tasks': tasks.map((e) => e.toJson()).toList(),
      'days': days.map((e) => e.toJson()).toList(),
    });
    _writeQueue = _writeQueue.then((_) async {
      try {
        final saved = await preferences?.setString('forever.v1', payload);
        if (saved == false) throw StateError('storage rejected');
        storageWarning = null;
        final snapshot = jsonDecode(payload) as Map<String, dynamic>;
        await reminders.sync(
          (snapshot['tasks'] as List)
              .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
          (snapshot['days'] as List)
              .map((e) => ImportantDay.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
        );
      } catch (_) {
        storageWarning = '本地保存失败，提醒未更新，请暂时不要关闭页面。';
        notifyListeners();
      }
    });
    await _writeQueue;
  }

  void add(Task task) {
    tasks.add(task);
    save();
  }

  void addDay(ImportantDay day) {
    days.add(day);
    save();
  }

  void prepare(Task task) {
    task.prepare();
    save();
  }

  void finish(Task task) {
    task.finish();
    save();
  }

  void reopen(Task task) {
    task.reopen();
    save();
  }

  void remove(Task task) {
    tasks.remove(task);
    save();
  }

  void removeDay(ImportantDay day) {
    days.remove(day);
    save();
  }
}
