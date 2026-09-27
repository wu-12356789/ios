import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forever/main.dart';
import 'package:forever/models.dart';
import 'package:forever/store.dart';

void main() {
  testWidgets(
    'add submission, prepare, submit and reopen using Cupertino controls',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ForeverStore();
      await tester.pumpWidget(ForeverApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoApp), findsOneWidget);
      await tester.tap(find.text('添加事项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('需要提交'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).first, '验收报告');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final task = store.tasks.singleWhere((e) => e.title == '验收报告');
      expect(task.submission, true);
      await tester.tap(find.text('清单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('验收报告'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标记已准备'));
      await tester.pumpAndSettle();
      expect(task.stage, TaskStage.prepared);
      expect(task.finished, false);
      expect(find.text('待提交'), findsWidgets);
      await tester.tap(find.text('确认已提交'));
      await tester.pumpAndSettle();
      expect(task.finished, true);
      await tester.tap(find.text('撤销已提交'));
      await tester.pumpAndSettle();
      expect(task.finished, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'home completion immediately removes task, no submission checkbox',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = ForeverStore();
      await tester.pumpWidget(ForeverApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.circle), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.circle));
      await tester.pumpAndSettle();
      expect(find.text('取快递'), findsNothing);
      expect(find.text('实习申请'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
