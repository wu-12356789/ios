import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'store.dart';
import 'reminders.dart';
import 'ios_reminders.dart';

const paper = Color(0xFFF6F4EC);
const ink = Color(0xFF252922);
const green = Color(0xFF355642);
const sage = Color(0xFFDDE8D8);
const muted = Color(0xFF737870);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ForeverApp(
      store: ForeverStore(
        preferences: prefs,
        seedExamples: kIsWeb,
        reminders: ReminderCoordinator(gateway: createReminderGateway()),
      ),
    ),
  );
}

class ForeverApp extends StatelessWidget {
  const ForeverApp({super.key, required this.store});
  final ForeverStore store;
  @override
  Widget build(BuildContext context) => CupertinoApp(
    title: 'forever',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    theme: const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: green,
      scaffoldBackgroundColor: paper,
      barBackgroundColor: paper,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(fontSize: 16, color: ink),
      ),
    ),
    builder: (context, child) => ColoredBox(
      color: const Color(0xFFEAEAE4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: child!,
        ),
      ),
    ),
    home: HomeShell(store: store),
  );
}

void openPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));

Future<void> showMessage(BuildContext context, String title, String message) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('知道了'),
          ),
        ],
      ),
    );

Future<bool> askDelete(BuildContext context, String title) async =>
    await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text('删除$title？'),
        message: const Text('这条记录及提醒设置将被移除。'),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheetContext, true),
            child: const Text('删除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext, false),
          child: const Text('取消'),
        ),
      ),
    ) ??
    false;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final ForeverStore store;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final controller = CupertinoTabController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.store.refreshReminders();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.store.refreshReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => CupertinoTabScaffold(
      controller: controller,
      backgroundColor: paper,
      tabBar: CupertinoTabBar(
        backgroundColor: paper,
        activeColor: green,
        inactiveColor: muted,
        height: 62,
        border: const Border(),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            label: '今日',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.list_bullet),
            label: '清单',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar_today),
            label: '日子',
          ),
        ],
      ),
      tabBuilder: (context, index) => CupertinoTabView(
        builder: (context) => index == 0
            ? TodayPage(store: widget.store)
            : index == 1
            ? TaskListPage(store: widget.store)
            : DaysPage(store: widget.store),
      ),
    ),
  );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.store});
  final ForeverStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    final now = DateTime.now();
    final todayTasks =
        store.tasks
            .where(
              (t) =>
                  !t.finished && t.due != null && daysUntil(t.due!, now) <= 0,
            )
            .toList()
          ..sort((a, b) => a.due!.compareTo(b.due!));
    final upcoming =
        store.tasks
            .where(
              (t) => !t.finished && t.due != null && daysUntil(t.due!, now) > 0,
            )
            .toList()
          ..sort((a, b) => a.due!.compareTo(b.due!));
    final days = [...store.days]
      ..sort((a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)));
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: const Border(),
        backgroundColor: paper,
        leading: const Text(
          'forever',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 29,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => openPage(context, SettingsPage(store: store)),
          child: const Icon(
            CupertinoIcons.gear,
            color: ink,
            size: 26,
            semanticLabel: '设置',
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '${now.day}',
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 80,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Text(
                      '${now.month}月 · 星期${'一二三四五六日'[now.weekday - 1]}',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  now.hour >= 17 ? '今晚' : '今天',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 26),
                if (store.reminders.supported &&
                    (store.reminders.permission ==
                            ReminderPermission.disabled ||
                        store.reminders.error != null))
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        openPage(context, SettingsPage(store: store)),
                    child: Text(
                      store.reminders.error != null
                          ? '提醒安排需处理 · 查看设置'
                          : '提醒尚未开启 · 前往设置',
                    ),
                  ),
                if (store.storageWarning != null)
                  Text(
                    store.storageWarning!,
                    style: const TextStyle(color: CupertinoColors.systemRed),
                  ),
                if (todayTasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Text('今天没有待处理事项', style: TextStyle(color: muted)),
                  ),
                for (final task in todayTasks)
                  TimelineTask(task: task, store: store),
                const SizedBox(height: 18),
                if (upcoming.isNotEmpty || days.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '接下来',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final task in upcoming.take(2))
                    CupertinoListTile(
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      title: Text(
                        task.title,
                        style: const TextStyle(fontSize: 17),
                      ),
                      additionalInfo: Text(
                        dueText(task.due, now),
                        style: const TextStyle(fontSize: 14, color: muted),
                      ),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => openPage(
                        context,
                        TaskDetailPage(task: task, store: store),
                      ),
                    ),
                  for (final day in days.take(1))
                    CupertinoListTile(
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      title: Text(
                        day.title,
                        style: const TextStyle(fontSize: 17),
                      ),
                      additionalInfo: Text(
                        '还有${daysUntil(day.nextOccurrence(now), now)}天',
                        style: const TextStyle(fontSize: 14, color: muted),
                      ),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => openPage(
                        context,
                        DayDetailPage(day: day, store: store),
                      ),
                    ),
                ],
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: sage,
                    foregroundColor: green,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () =>
                        openPage(context, EditorPage(store: store)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.add, size: 25),
                        SizedBox(width: 9),
                        Text(
                          '添加事项',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TimelineTask extends StatelessWidget {
  const TimelineTask({super.key, required this.task, required this.store});
  final Task task;
  final ForeverStore store;
  @override
  Widget build(BuildContext context) {
    final overdue = task.due!.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 27),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 67,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                clockText(task.due!),
                style: const TextStyle(fontFamily: 'Georgia', fontSize: 19),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14, right: 18),
            child: Icon(
              CupertinoIcons.circle_fill,
              color: overdue
                  ? CupertinoColors.systemOrange
                  : const Color(0xFFADC6A5),
              size: 10,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                        onPressed: () => openPage(
                          context,
                          TaskDetailPage(task: task, store: store),
                        ),
                        child: Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                    if (!task.submission)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => store.finish(task),
                        child: Icon(
                          CupertinoIcons.circle,
                          size: 27,
                          color: ink,
                          semanticLabel: '完成${task.title}',
                        ),
                      ),
                  ],
                ),
                Text(
                  overdue ? '${task.status} · 已逾期' : task.status,
                  style: TextStyle(
                    fontSize: 14,
                    color: overdue
                        ? CupertinoColors.systemRed
                        : task.submission
                        ? green
                        : muted,
                  ),
                ),
                if (task.submission) ...[
                  const SizedBox(height: 9),
                  Text(
                    task.stage == TaskStage.prepared
                        ? '已准备，等待提交'
                        : '准备完成后，记得提交',
                    style: const TextStyle(fontSize: 14, color: muted),
                  ),
                  const SizedBox(height: 13),
                  CupertinoButton(
                    color: sage,
                    foregroundColor: green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    onPressed: () {
                      if (task.stage == TaskStage.prepared) {
                        store.finish(task);
                      } else {
                        store.prepare(task);
                      }
                    },
                    child: Text(
                      task.stage == TaskStage.prepared ? '确认已提交' : '标记已准备',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, required this.store});
  final ForeverStore store;
  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  int filter = 0;
  String query = '';
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('清单'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => openPage(context, EditorPage(store: widget.store)),
        child: const Icon(CupertinoIcons.add, semanticLabel: '添加事项'),
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final tasks = widget.store.tasks
              .where(
                (t) =>
                    t.title.contains(query) &&
                    (filter == 2
                        ? t.finished
                        : !t.finished && (filter != 1 || t.submission)),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              CupertinoSearchTextField(
                placeholder: '搜索事项',
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 18),
              CupertinoSlidingSegmentedControl<int>(
                groupValue: filter,
                children: const {
                  0: Text('待处理'),
                  1: Text('待提交'),
                  2: Text('已结束'),
                },
                onValueChanged: (v) => setState(() => filter = v!),
              ),
              const SizedBox(height: 20),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Text(
                    '这里暂时没有事项',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                ),
              if (tasks.isNotEmpty)
                CupertinoListSection(
                  backgroundColor: paper,
                  topMargin: 0,
                  children: [
                    for (final task in tasks)
                      CupertinoListTile(
                        title: Text(task.title),
                        subtitle: Text(
                          '${task.status} · ${dueText(task.due, DateTime.now())}',
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => openPage(
                          context,
                          TaskDetailPage(task: task, store: widget.store),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );
}

class TaskDetailPage extends StatelessWidget {
  const TaskDetailPage({super.key, required this.task, required this.store});
  final Task task;
  final ForeverStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final reminders = task.plannedReminders(DateTime.now());
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('事项详情'),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () =>
                openPage(context, EditorPage(store: store, existing: task)),
            child: const Text('编辑'),
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              CupertinoListSection.insetGrouped(
                backgroundColor: paper,
                children: [
                  CupertinoListTile(
                    title: const Text('状态'),
                    additionalInfo: Text(task.status),
                  ),
                  CupertinoListTile(
                    title: const Text('截止'),
                    additionalInfo: Text(dueText(task.due, DateTime.now())),
                  ),
                ],
              ),
              if (task.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: Text(task.note),
                ),
              CupertinoListSection.insetGrouped(
                backgroundColor: paper,
                header: const Text('计划提醒时间'),
                footer: Text(
                  store.reminders.supported
                      ? '${store.reminders.status}。可在设置中核对安排。'
                      : '当前浏览器仅预览计划，不会发送系统通知。',
                ),
                children: [
                  if (reminders.isEmpty)
                    const CupertinoListTile(title: Text('暂无未来提醒')),
                  for (final time in reminders)
                    CupertinoListTile(
                      title: Text('${dateText(time)} ${clockText(time)}'),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (task.finished)
                      CupertinoButton(
                        color: sage,
                        foregroundColor: green,
                        onPressed: () => store.reopen(task),
                        child: Text(task.submission ? '撤销已提交' : '撤销完成'),
                      )
                    else ...[
                      if (task.submission && task.stage == TaskStage.todo)
                        CupertinoButton(
                          color: sage,
                          foregroundColor: green,
                          onPressed: () => store.prepare(task),
                          child: const Text('标记已准备'),
                        ),
                      const SizedBox(height: 12),
                      CupertinoButton.filled(
                        onPressed: () => store.finish(task),
                        child: Text(task.submission ? '确认已提交' : '完成任务'),
                      ),
                    ],
                    const SizedBox(height: 22),
                    CupertinoButton(
                      onPressed: () async {
                        final confirmed = await askDelete(context, '事项');
                        if (confirmed && context.mounted) {
                          store.remove(task);
                          Navigator.pop(context);
                        }
                      },
                      child: const Text(
                        '删除事项',
                        style: TextStyle(color: CupertinoColors.systemRed),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class DaysPage extends StatelessWidget {
  const DaysPage({super.key, required this.store});
  final ForeverStore store;
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('日子'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () =>
            openPage(context, EditorPage(store: store, initialType: 2)),
        child: const Icon(CupertinoIcons.add, semanticLabel: '添加日子'),
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final now = DateTime.now();
          final days = [...store.days]
            ..sort(
              (a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)),
            );
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 25, 22, 10),
                child: Text(
                  '值得记住的日子',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
              ),
              if (days.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Text('添加一个重要日子吧', style: TextStyle(color: muted)),
                ),
              if (days.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  backgroundColor: paper,
                  children: [
                    for (final day in days)
                      CupertinoListTile(
                        title: Text(day.title),
                        subtitle: Text(day.rule),
                        additionalInfo: Text(
                          '${daysUntil(day.nextOccurrence(now), now)}天',
                          style: const TextStyle(color: green, fontSize: 20),
                        ),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => openPage(
                          context,
                          DayDetailPage(day: day, store: store),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    ),
  );
}

class DayDetailPage extends StatelessWidget {
  const DayDetailPage({super.key, required this.day, required this.store});
  final ImportantDay day;
  final ForeverStore store;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = day.nextOccurrence(now);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('重要日子')),
      child: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 25),
            Text(
              day.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            Text(
              '${daysUntil(next, now)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 80,
                fontFamily: 'Georgia',
                color: green,
              ),
            ),
            const Text(
              '天后到来',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            CupertinoListSection.insetGrouped(
              backgroundColor: paper,
              children: [
                CupertinoListTile(
                  title: const Text('日期规则'),
                  additionalInfo: Text(day.rule),
                ),
                CupertinoListTile(
                  title: const Text('下一次公历'),
                  additionalInfo: Text('${next.year}年${dateText(next)}'),
                ),
                const CupertinoListTile(
                  title: Text('提醒计划'),
                  subtitle: Text('提前7天、提前1天、当天09:00'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Text(
                '以上为默认规则，实际通知安排请在设置中查看。',
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
            if (day.lunar)
              const Padding(
                padding: EdgeInsets.all(22),
                child: Text(
                  '无对应闰月时使用普通月；没有三十的月份取月末。',
                  style: TextStyle(color: muted, fontSize: 14),
                ),
              ),
            CupertinoButton(
              onPressed: () async {
                final confirmed = await askDelete(context, '这个日子');
                if (confirmed && context.mounted) {
                  store.removeDay(day);
                  Navigator.pop(context);
                }
              },
              child: const Text(
                '删除日子',
                style: TextStyle(color: CupertinoColors.systemRed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.store,
    this.initialType = 0,
    this.existing,
  });
  final ForeverStore store;
  final int initialType;
  final Task? existing;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController title;
  late final TextEditingController note;
  late int type;
  bool hasDue = false;
  bool isLunar = false;
  bool leap = false;
  late DateTime selectedDate;
  int lunarMonth = 8;
  int lunarDay = 15;
  List<int> reminders = [1440, -9, 60];
  @override
  void initState() {
    super.initState();
    final task = widget.existing;
    title = TextEditingController(text: task?.title ?? '');
    note = TextEditingController(text: task?.note ?? '');
    type = task == null
        ? widget.initialType
        : task.submission
        ? 1
        : 0;
    hasDue = task?.due != null;
    final now = DateTime.now();
    selectedDate = task?.due ?? DateTime(now.year, now.month, now.day, 22);
    reminders = [
      ...?task?.reminders,
      if (task == null) ...[1440, -9, 60],
    ];
  }

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    FocusScope.of(context).unfocus();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoPopupSurface(
        child: ColoredBox(
          color: paper,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 300,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('完成'),
                    ),
                  ),
                  Expanded(
                    child: CupertinoDatePicker(
                      initialDateTime: selectedDate,
                      use24hFormat: true,
                      mode: type == 2
                          ? CupertinoDatePickerMode.date
                          : CupertinoDatePickerMode.dateAndTime,
                      onDateTimeChanged: (d) =>
                          setState(() => selectedDate = d),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pickLunar() async {
    FocusScope.of(context).unfocus();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoPopupSurface(
        child: ColoredBox(
          color: paper,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 290,
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: CupertinoButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('完成'),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 38,
                            scrollController: FixedExtentScrollController(
                              initialItem: lunarMonth - 1,
                            ),
                            onSelectedItemChanged: (v) =>
                                setState(() => lunarMonth = v + 1),
                            children: List.generate(
                              12,
                              (i) => Text('${i + 1}月'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: CupertinoPicker(
                            itemExtent: 38,
                            scrollController: FixedExtentScrollController(
                              initialItem: lunarDay - 1,
                            ),
                            onSelectedItemChanged: (v) =>
                                setState(() => lunarDay = v + 1),
                            children: List.generate(
                              30,
                              (i) => Text('${i + 1}日'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void save() {
    final name = title.text.trim();
    if (name.isEmpty) {
      showMessage(context, '先写个名称', '名称不能为空。');
      return;
    }
    if (type == 2) {
      widget.store.addDay(
        ImportantDay(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: name,
          month: isLunar ? lunarMonth : selectedDate.month,
          day: isLunar ? lunarDay : selectedDate.day,
          lunar: isLunar,
          leap: isLunar && leap,
        ),
      );
    } else if (widget.existing != null) {
      final task = widget.existing!;
      task.title = name;
      task.note = note.text.trim();
      task.due = hasDue ? selectedDate : null;
      task.reminders = [...reminders];
      widget.store.save();
    } else {
      widget.store.add(
        Task(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: name,
          submission: type == 1,
          due: hasDue ? selectedDate : null,
          note: note.text.trim(),
          reminders: [...reminders],
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: Text(widget.existing == null ? '添加事项' : '编辑事项'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: save,
        child: const Text('保存'),
      ),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 18),
        children: [
          if (widget.existing == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: type,
                children: const {
                  0: Text('普通任务'),
                  1: Text('需要提交'),
                  2: Text('重要日子'),
                },
                onValueChanged: (v) => setState(() => type = v!),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: CupertinoTextField(
              controller: title,
              placeholder: type == 2 ? '想记住什么日子？' : '想记下什么？',
              padding: const EdgeInsets.all(16),
              maxLength: 80,
              style: const TextStyle(fontSize: 20),
              textInputAction: TextInputAction.done,
            ),
          ),
          if (type == 2) ...[
            CupertinoFormSection.insetGrouped(
              backgroundColor: paper,
              header: const Text('日期规则'),
              children: [
                CupertinoFormRow(
                  prefix: const Text('历法'),
                  child: CupertinoSlidingSegmentedControl<bool>(
                    groupValue: isLunar,
                    children: const {false: Text('公历'), true: Text('农历')},
                    onValueChanged: (v) => setState(() => isLunar = v!),
                  ),
                ),
                CupertinoFormRow(
                  prefix: const Text('日期'),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: isLunar ? pickLunar : pickDate,
                    child: Text(
                      isLunar
                          ? '$lunarMonth月$lunarDay日'
                          : dateText(selectedDate),
                    ),
                  ),
                ),
                if (isLunar)
                  CupertinoFormRow(
                    prefix: const Text('闰月'),
                    child: Semantics(
                      label: '闰月',
                      child: CupertinoSwitch(
                        value: leap,
                        onChanged: (v) => setState(() => leap = v),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Text(
                isLunar ? '每年重复。无同名闰月用普通月；小月取月末。' : '每年重复。2月29日在平年使用2月28日。',
                style: const TextStyle(fontSize: 13, color: muted),
              ),
            ),
          ] else ...[
            CupertinoFormSection.insetGrouped(
              backgroundColor: paper,
              children: [
                CupertinoFormRow(
                  prefix: const Text('设置截止时间'),
                  child: Semantics(
                    label: '设置截止时间',
                    child: CupertinoSwitch(
                      value: hasDue,
                      onChanged: (v) => setState(() => hasDue = v),
                    ),
                  ),
                ),
                if (hasDue)
                  CupertinoFormRow(
                    prefix: const Text('截止'),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: pickDate,
                      child: Text(
                        '${dateText(selectedDate)} ${clockText(selectedDate)}',
                      ),
                    ),
                  ),
              ],
            ),
            if (hasDue)
              CupertinoFormSection.insetGrouped(
                backgroundColor: paper,
                header: const Text('分阶段提醒'),
                children: [
                  for (final r in const {
                    1440: '提前一天',
                    -9: '当天09:00',
                    60: '截止前一小时',
                  }.entries)
                    CupertinoFormRow(
                      prefix: Text(r.value),
                      child: Semantics(
                        label: r.value,
                        child: CupertinoSwitch(
                          value: reminders.contains(r.key),
                          onChanged: (v) => setState(() {
                            if (v) {
                              reminders.add(r.key);
                            } else {
                              reminders.remove(r.key);
                            }
                          }),
                        ),
                      ),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: CupertinoTextField(
                controller: note,
                placeholder: '备注（可选）',
                maxLines: 3,
                padding: const EdgeInsets.all(14),
              ),
            ),
          ],
          if (type == 1)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 25),
              child: Text(
                '做完后先标记“已准备”，真正提交后再确认。',
                style: TextStyle(fontSize: 13, color: green),
              ),
            ),
          const SizedBox(height: 25),
        ],
      ),
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});
  final ForeverStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final reminders = store.reminders;
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('设置')),
        child: SafeArea(
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 32, 24, 8),
                child: Text(
                  'forever',
                  style: TextStyle(fontFamily: 'Georgia', fontSize: 35),
                ),
              ),
              CupertinoListSection.insetGrouped(
                backgroundColor: paper,
                header: const Text('提醒'),
                footer: Text(
                  reminders.supported
                      ? '已安排的提醒由 iPhone 系统呈现；专注模式、静音与系统通知设置会影响提示。'
                      : '浏览器不会申请通知权限，也不会在后台提醒。',
                ),
                children: [
                  CupertinoListTile(
                    title: const Text('提醒状态'),
                    subtitle: Text(reminders.status, maxLines: 3),
                  ),
                  CupertinoListTile(
                    title: const Text('查看提醒计划'),
                    additionalInfo: Text('${reminders.planned.length}条'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () =>
                        openPage(context, ReminderPlanPage(store: store)),
                  ),
                  if (reminders.supported) ...[
                    if (reminders.permission != ReminderPermission.enabled &&
                        reminders.permission != ReminderPermission.quiet)
                      CupertinoListTile(
                        title: const Text('开启通知'),
                        trailing: reminders.busy
                            ? const CupertinoActivityIndicator()
                            : const CupertinoListTileChevron(),
                        onTap: reminders.busy
                            ? null
                            : () => store.refreshReminders(
                                requestPermission: true,
                              ),
                      ),
                    CupertinoListTile(
                      title: const Text('系统通知设置'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => reminders.openSettings(),
                    ),
                    CupertinoListTile(
                      title: const Text('重新核对提醒'),
                      trailing: reminders.busy
                          ? const CupertinoActivityIndicator()
                          : const CupertinoListTileChevron(),
                      onTap: reminders.busy
                          ? null
                          : () => store.refreshReminders(),
                    ),
                  ],
                  CupertinoListTile(
                    title: const Text('查看通知示例'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => showMessage(
                      context,
                      '通知示例',
                      '课程报告 · 今晚20:00截止，请确认提交。\n这是内容预览，不会安排系统通知。',
                    ),
                  ),
                ],
              ),
              if (reminders.deferredCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '还有${reminders.deferredCount}条未来提醒未安排。请定期打开应用补充。',
                    style: const TextStyle(color: CupertinoColors.systemOrange),
                  ),
                ),
              CupertinoListSection.insetGrouped(
                backgroundColor: paper,
                header: const Text('数据'),
                children: [
                  const CupertinoListTile(
                    title: Text('本地保存'),
                    subtitle: Text(
                      kIsWeb ? '保存在此浏览器；清除网站数据会丢失记录' : '保存在这台 iPhone；卸载应用会丢失记录',
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
              if (store.storageWarning != null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(store.storageWarning!),
                ),
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '重要日子计算未来3次发生日期。打开应用时重新核对；长时间未打开且计划耗尽后，不会自动续排。',
                  style: TextStyle(color: muted, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ReminderPlanPage extends StatelessWidget {
  const ReminderPlanPage({super.key, required this.store});
  final ForeverStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final reminders = store.reminders;
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('提醒计划')),
        child: SafeArea(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  reminders.status,
                  style: const TextStyle(color: green),
                ),
              ),
              if (reminders.scheduledThrough != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    '最晚已安排至 ${reminders.scheduledThrough!.year}年'
                    '${dateText(reminders.scheduledThrough!)} ${clockText(reminders.scheduledThrough!)}',
                  ),
                ),
              CupertinoListSection.insetGrouped(
                backgroundColor: paper,
                header: const Text('按时间排列的计划'),
                footer: const Text(
                  '此处显示计算结果，不等于已经收到通知。重要日子按当前设备时区计算；换时区后请重新打开应用。',
                ),
                children: [
                  if (reminders.planned.isEmpty)
                    const CupertinoListTile(title: Text('暂无未来提醒')),
                  for (final item in reminders.planned.take(60))
                    CupertinoListTile(
                      title: Text(item.title),
                      subtitle: Text(
                        '${item.at.year}年${dateText(item.at)} ${clockText(item.at)}',
                      ),
                    ),
                  if (reminders.planned.length > 60)
                    CupertinoListTile(
                      title: Text('另有${reminders.planned.length - 60}条后续计划'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
