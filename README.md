# forever · Cupertino 应用

Flutter 3.47.5 / Dart 3.13.4。`pubspec.lock` 固定依赖版本。界面只使用 Cupertino 控件与 Flutter 基础布局，`uses-material-design: false`。依赖中的 material_color_utilities 由 Flutter SDK 间接引入，不表示应用使用 Material 控件。

## 结构

- `lib/main.dart`：三个标签页、详情、编辑、日期选择和设置。
- `lib/models.dart`：任务状态、提醒时间、公历与农历日期规则。
- `lib/store.dart`：本地持久化、恢复、串行保存与提醒同步。
- `lib/reminders.dart`：任务与年度日期提醒规划、容量控制、调度及撤销核对。
- `lib/ios_reminders.dart`：iOS 通知权限、系统请求和设备时区接口；Web 使用不发送通知的预览实现。
- `test/`：模型与控件测试，以及通知调度、持久化、异常恢复和模拟 iOS 通道测试。
- `web/`：浏览器入口。
- `ios/`：iOS 工程，已配置通知代理，尚未在 Xcode 构建或签名。

## Windows 运行

回到项目根目录，执行 `scripts/preview.ps1 -Check`。脚本运行 flutter pub get、flutter analyze、flutter test 和 flutter build web --release --no-web-resources-cdn，然后用 Python 启动本机静态服务。

项目内 SDK：`../../work/toolchain/flutter`；依赖缓存：`../../work/pub-cache`。当前 Windows 环境的 Flutter 工具在中文绝对路径下出现过分析协议错误和 shader 编译路径错误，所以脚本临时选择 R–Z 中空闲盘符。已有盘符不会覆盖。命令完成后移除脚本自己的映射，下次会先更新包路径。

SDK 和构建产物没有作为源码提交。如果换电脑，可先从 [Flutter 官方安装文档](https://docs.flutter.dev/install/manual) 安装对应 SDK 到上述路径，并准备 Python。开发时也可使用已有 Flutter SDK，但需要在不含中文的路径别名下运行。

直接使用 SDK 的常用命令：

```text
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
```

构建可能输出 MaterialIcons 未打包提示；本项目不引用该字体或 Material 控件，CupertinoIcons 已打包，已验证页面图标显示。不要为消除这条提示开启 Material 设计。

## 当前限制

本地保存使用 SharedPreferences。Web 数据只存在当前浏览器与来源地址，换端口或浏览器不会自动同步；清除网站数据会删除记录。尚无备份恢复。

日期计算使用 lunar 1.7.8。年度农历缺少同名闰月时使用普通月，没有三十时取月末；公历 2 月 29 日在平年取 2 月 28 日。当前规则固定，创建表单可见说明。

分阶段提醒目前只能开关三项默认时间；任意提前量、重要日子自定义提醒尚待开发。iOS 本地通知代码已接入，但尚未在真实设备上验证；Web 仍只展示计划，不发送通知。每次最多使用 60 条待发送容量，重要日子预计算未来 3 次发生日期，后续计划需要重新打开应用补充。具体机制与限制见 [安装与通知验收](../../docs/iPhone安装与通知验收.md)。

用户只有免费 Apple 账号，采用 Mac 上的 Xcode Personal Team 做个人测试；当前缺少 Mac，未签名、未安装。Mac 可用 `bash ../../scripts/check-ios.sh` 先执行不签名的编译检查。通知插件方法通道测试不会调用真实 iOS。后台、锁屏、离线、签名续装和 VoiceOver 仍待真机验收。完整证据见项目根目录 design-qa.md 与 docs/评审与验证记录.md。
