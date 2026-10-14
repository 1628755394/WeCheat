# WeCheat

WeCheat 是一个以微信交互为基础的 Flutter AI 角色聊天客户端。会话、通讯录、朋友圈和个人资料使用本地 Mock 数据与 Hive 持久化；AI 角色可接入本地 Ollama 或兼容 OpenAI / Anthropic 的远程模型。项目以移动端体验为主，宽屏下提供三栏布局。

## 功能概览

- 单聊与多角色群聊：流式回复、未读计数、消息搜索、转发、撤回、语音和图片等富媒体消息。
- AI 角色：独立人设、知识条目、记忆、关系与好感度、剧情场景、日记、主动消息和回复重生成。
- 模型接入：本地 Ollama、cc-switch 服务商与手动配置的远程 API；聊天和通话共用模型网关。
- 语音与虚拟形象：语音录制和播放、TTS、语音克隆服务接入、Live2D 通话形象；绑定音色后可使用实时语音会话。
- 常用页面：四 Tab 导航、角色广场、朋友圈、通讯录、个人设置及微信风格的辅助页面。

本仓库是前端演示项目，社交内容和部分页面由 Mock 数据驱动。模型推理、语音克隆及实时语音需要自行提供可访问的服务；实时语音协议和真机音频仍需与服务端联调。

## 技术栈

Flutter 3.47 / Dart 3.13，使用 `flutter_riverpod` 管理状态、`go_router` 管理导航、`hive_flutter` 持久化本地数据；音频使用 `record`、`audioplayers`、`flutter_tts` 和 `speech_to_text`，实时通话使用 `web_socket_channel`。Live2D Flutter 插件位于 `third_party/live2d_flutter`。

## 快速运行

```powershell
flutter pub get
flutter run -d windows
# 或在 Android 设备上运行：flutter run -d <device-id>
```

运行 AI 聊天前，请在角色设置中选择本地 Ollama 模型或填写远程模型配置。Windows 构建需要开启开发者模式；语音功能依赖对应平台的录音权限和可访问的服务地址。

## iPhone / iPad

在安装 Xcode、CocoaPods 和 Flutter 的 Mac 上运行 `flutter pub get`，然后执行 `flutter run -d ios`。真机安装还需在 Xcode 中打开 `ios/Runner.xcworkspace`，为 Runner 选择自己的 Team 与唯一 Bundle Identifier。当前仓库没有 macOS 桌面工程。

手机上的 `127.0.0.1` 指手机自身。在「AI 设置 → 模型 → 连接电脑上的 Ollama」填写电脑局域网地址，例如 `http://192.168.1.10:11434`；电脑端需监听局域网并允许防火墙访问。Voice API 和转写服务也需填写电脑局域网地址。iOS 无法直接读取电脑上的 cc-switch 数据库，可手动填写服务商 Base URL、模型名和密钥。

## 局域网语音克隆服务

SoulNexus Voice API 当前部署在 `http://192.168.3.15:7072`。手机和服务端须处于同一局域网；地址变化时填写新的局域网 IP。先在手机浏览器打开 `/health`，应返回 `status: ok` 和 `voiceCloneEnabled: true`。

在角色的「AI 设置 → 语音服务与音色档案」中填写服务根地址与 Bearer Token，点击「连接并刷新音色」，选择状态为 `success` 的音色。Token 只在应用当前进程内保存，重新打开应用后需要再填。可以开启「自动发语音消息」，或在通话中验证克隆音色。聊天语音使用 `POST /api/v1/voice-clones/{id}/synthesize`；通话页面已有 `voice-sessions` WebSocket 接入代码，需与服务端文本帧协议和真机音频播放联调。

绑定音色后的 AI 音视频通话在实时会话连接成功时自动开麦，麦克风持续发送 16 kHz 单声道 PCM；静音按钮发送静音帧，服务端负责语音活动检测与华语识别。录音端会请求系统的自动增益、回声消除和噪声抑制，效果取决于手机硬件。连接失败时页面会提示并回退到按住说话模式。

Android 正式包需要 `INTERNET` 权限和局域网 HTTP 明文访问能力；两项已在主 Manifest 中配置。网页端还需要语音服务允许网页来源跨域访问。服务端的火山引擎凭证只放在服务端，不填入客户端。

正式环境可使用 [nginx 配置模板](deploy/nginx/voice-api.conf.example)：Nginx 对外提供 HTTPS，把 `/api/v1/` 原样转发到 `127.0.0.1:7072`，同时转发 `Upgrade`/`Connection` 头以支持实时语音 WebSocket。客户端地址只填写 `https://你的域名`，不要填写 `/api/clone` 或把路径写进 `server_name`。实测音色列表在不带 Token 时返回 401；仍需在服务端逐一确认上传、合成、会话创建和 WebSocket 票据的鉴权。Nginx 配置会透传 `Authorization` 请求头；不要把真实 Token 写进 Nginx 配置或仓库。

## 情绪参数

调试运行时，「AI 设置 → 情绪参数」可查看 valence、arousal、最近事件和表达分区，并拖动滑块预览好感与情绪组合。Release 包保留自动情绪规则，不显示参数面板；角色状态写入设备本地 Hive。
