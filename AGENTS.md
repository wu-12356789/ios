# forever Flutter 应用

- 用户明确要求全部界面使用 Flutter Cupertino 组件，禁止 Material、React 或其他 UI 组件库。
- 使用 `package:flutter/cupertino.dart` 与 CupertinoIcons。Text、Row、Column、Padding、SafeArea 等 Flutter 基础布局组件可用于组合 Cupertino 界面；不得引入其他设计体系的控件。
- 名称固定为 `forever`，全小写。沿用已选第三张时间轴布局与米白、墨黑、浅绿配色。
- 普通任务完成与提交任务已提交必须分开；标记已准备不能结束提交任务。
- 当前先在 Windows 上开发 Flutter Web 交互预览，目标仍为 iPhone。不得将浏览器预览宣称为已验证 iOS 通知或已安装应用。
- 变更后执行 flutter analyze、业务与控件测试，以及浏览器主要流程检查。
