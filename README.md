# wecheat

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## iPhone / iPad

在安装 Xcode、CocoaPods 和 Flutter 的 Mac 上运行 `flutter pub get`，然后执行 `flutter run -d ios`。真机安装还需在 Xcode 中打开 `ios/Runner.xcworkspace`，为 Runner 选择自己的 Team 与唯一 Bundle Identifier。当前仓库没有 macOS 桌面工程。

手机上的 `127.0.0.1` 指手机自身。在「AI 设置 → 模型 → 连接电脑上的 Ollama」填写电脑局域网地址，例如 `http://192.168.1.10:11434`；电脑端需监听局域网并允许防火墙访问。Voice API 和转写服务也需填写电脑局域网地址。iOS 无法直接读取电脑上的 cc-switch 数据库，可手动填写服务商 Base URL、模型名和密钥。

## 情绪调试

调试版的「AI 设置 → 情绪调试」可以查看 valence、arousal、最近事件和表达分区，拖动滑块预览好感与情绪组合。角色状态写入设备本地 Hive；Release 版隐藏调试入口。
