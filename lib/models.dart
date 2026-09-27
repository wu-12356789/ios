import 'dart:math';
import 'package:lunar/lunar.dart';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
int daysUntil(DateTime date, DateTime now) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
String clockText(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String dateText(DateTime d) => '${d.month}月${d.day}日';
String dueText(DateTime? d, DateTime now) {
  if (d == null) return '未设截止日期';
  final days = daysUntil(d, now);
  final prefix = days == 0
      ? '今天'
      : days == 1
      ? '明天'
      : dateText(d);
  return '$prefix ${clockText(d)}';
}

enum TaskStage { todo, prepared, done }

class Task {
  Task({
    required this.id,
    required this.title,
    this.submission = false,
    this.due,
    this.stage = TaskStage.todo,
    this.note = '',
    this.reminders = const [1440, -9, 60],
  });
  final String id;
  String title;
  bool submission;
  DateTime? due;
  TaskStage stage;
  String note;
  List<int> reminders;
  bool get finished => stage == TaskStage.done;
  String get status => finished
      ? (submission ? '已提交' : '已完成')
      : submission
      ? (stage == TaskStage.prepared ? '待提交' : '待准备')
      : '待完成';
  void prepare() {
    if (submission && !finished) stage = TaskStage.prepared;
  }

  void finish() => stage = TaskStage.done;
  void reopen() => stage = submission ? TaskStage.prepared : TaskStage.todo;
  List<DateTime> plannedReminders(DateTime now) {
    if (finished || due == null) return [];
    final d = due!;
    final result =
        reminders
            .map(
              (minutes) => minutes == -9
                  ? DateTime(d.year, d.month, d.day, 9)
                  : d.subtract(Duration(minutes: minutes)),
            )
            .where((time) => time.isAfter(now) && time.isBefore(d))
            .toSet()
            .toList()
          ..sort();
    return result;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'submission': submission,
    'due': due?.toUtc().toIso8601String(),
    'stage': stage.name,
    'note': note,
    'reminders': reminders,
  };
  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'],
    title: j['title'],
    submission: j['submission'] ?? false,
    due: j['due'] == null ? null : DateTime.parse(j['due']).toLocal(),
    stage: TaskStage.values.byName(j['stage']),
    note: j['note'] ?? '',
    reminders: List<int>.from(j['reminders'] ?? [1440, -9, 60]),
  );
}

class ImportantDay {
  ImportantDay({
    required this.id,
    required this.title,
    required this.month,
    required this.day,
    this.lunar = false,
    this.leap = false,
  });
  final String id;
  String title;
  int month;
  int day;
  bool lunar;
  bool leap;
  String get rule =>
      '${lunar ? '农历${leap ? '闰' : ''}' : '公历'}$month月$day日 · 每年';
  DateTime nextOccurrence(DateTime now) {
    final today = dateOnly(now);
    final year = lunar ? Lunar.fromDate(today).getYear() : today.year;
    for (var y = year; y < year + 10; y++) {
      DateTime occurrence;
      if (lunar) {
        final selected =
            LunarMonth.fromYm(y, leap ? -month : month) ??
            LunarMonth.fromYm(y, month)!;
        final converted = Lunar.fromYmd(
          y,
          selected.getMonth(),
          min(day, selected.getDayCount()),
        ).getSolar();
        occurrence = DateTime(
          converted.getYear(),
          converted.getMonth(),
          converted.getDay(),
        );
      } else {
        occurrence = DateTime(
          y,
          month,
          min(day, DateTime(y, month + 1, 0).day),
        );
      }
      if (!occurrence.isBefore(today)) return occurrence;
    }
    throw StateError('无法计算下一次日期');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'month': month,
    'day': day,
    'lunar': lunar,
    'leap': leap,
  };
  factory ImportantDay.fromJson(Map<String, dynamic> j) => ImportantDay(
    id: j['id'],
    title: j['title'],
    month: j['month'],
    day: j['day'],
    lunar: j['lunar'] ?? false,
    leap: j['leap'] ?? false,
  );
}
