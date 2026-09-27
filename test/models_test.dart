import 'package:flutter_test/flutter_test.dart';
import 'package:forever/models.dart';

void main() {
  test('prepared submission stays unfinished and keeps future reminders', () {
    final due = DateTime(2026, 9, 25, 20);
    final task = Task(id: '1', title: '报告', submission: true, due: due);
    task.prepare();
    expect(task.status, '待提交');
    expect(task.finished, false);
    expect(task.plannedReminders(DateTime(2026, 9, 24, 19)).length, 3);
    task.finish();
    expect(task.status, '已提交');
    expect(task.plannedReminders(DateTime(2026, 9, 24, 19)), isEmpty);
    task.reopen();
    expect(task.status, '待提交');
  });
  test('morning deadlines skip late daily node and duplicate nodes merge', () {
    final task = Task(id: '2', title: '早交', due: DateTime(2026, 9, 25, 8));
    final times = task.plannedReminders(DateTime(2026, 9, 24, 7));
    expect(times, [DateTime(2026, 9, 24, 8), DateTime(2026, 9, 25, 7)]);
    task.due = DateTime(2026, 9, 25, 10);
    expect(task.plannedReminders(DateTime(2026, 9, 25, 8)), [
      DateTime(2026, 9, 25, 9),
    ]);
  });
  test('ordinary completion and data round trip preserve fields', () {
    final task = Task(
      id: '3',
      title: '取件',
      note: '东门',
      due: DateTime(2026, 9, 25, 21),
    );
    task.prepare();
    expect(task.status, '待完成');
    task.finish();
    final restored = Task.fromJson(task.toJson());
    expect(restored.status, '已完成');
    expect(restored.note, '东门');
    expect(restored.due, task.due);
  });
  test('Gregorian leap birthday falls back and rolls over year', () {
    final day = ImportantDay(id: '1', title: '生日', month: 2, day: 29);
    expect(day.nextOccurrence(DateTime(2027, 1, 1)), DateTime(2027, 2, 28));
    expect(day.nextOccurrence(DateTime(2027, 3, 1)), DateTime(2028, 2, 29));
  });
  test('lunar new year uses lunar calendar across Gregorian year', () {
    final day = ImportantDay(
      id: '2',
      title: '春节',
      month: 1,
      day: 1,
      lunar: true,
    );
    expect(day.nextOccurrence(DateTime(2026, 1, 1)), DateTime(2026, 2, 17));
    expect(day.nextOccurrence(DateTime(2026, 2, 18)), DateTime(2027, 2, 6));
  });
  test('lunar leap month falls back to ordinary month when absent', () {
    final leap = ImportantDay(
      id: '3',
      title: '生日',
      month: 6,
      day: 1,
      lunar: true,
      leap: true,
    );
    expect(leap.nextOccurrence(DateTime(2025, 1, 1)), DateTime(2025, 7, 25));
    expect(leap.nextOccurrence(DateTime(2026, 1, 1)), DateTime(2026, 7, 14));
  });
}
