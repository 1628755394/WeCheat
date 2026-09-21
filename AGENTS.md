# WeCheat —— Flutter 仿微信客户端

只做移动端前端，Mock 数据模拟后端。技术栈：flutter_riverpod / go_router / hive_flutter / intl / scrollable_positioned_list。

## 环境注意

- Windows 环境，shell 请用 `shell_flavor: "powershell"`（本机 WSL 未安装发行版，默认 bash 会失败）
- Flutter 3.47.2 stable / Dart 3.13.2；pub 源走 `https://storage.flutter-io.cn` 镜像
- 本机访问 github.com 走代理可能超时，但 `flutter pub` 正常
- PowerShell 的 Invoke-WebRequest/curl 别名会走代理导致 127.0.0.1 请求失败；测本地服务用 `curl.exe --noproxy "*"`
- 本机装有 Ollama 0.32.1 + `qwen3:4b`（AI 助手会话直连 `127.0.0.1:11434/api/chat` 流式接口；显存 8GB，12B 级别模型只能部分上 GPU 会很慢）

## 常用命令

```powershell
flutter pub get     # 安装依赖
flutter analyze     # 静态分析（要求 0 issue）
flutter test        # 单元测试
flutter run -d chrome --web-port=7357   # Web 调试必须固定端口！端口变=浏览器 origin 变=IndexedDB(Hive) 换库，重启后数据"丢失"
```

## 目录结构

```
lib/
├── core/            # constants.dart(配色) theme.dart utils/time_utils.dart widgets/app_avatar.dart
├── models/          # contact / conversation / message（Map 序列化，存 Hive）
├── repositories/    # mock_data.dart(Mock种子) conversation_repository.dart message_repository.dart(Hive)
├── providers/       # conversation_provider.dart chat_provider.dart(Riverpod 3：family 走构造器传参)
├── services/        # ollama_service.dart(本地大模型流式调用) tts_service.dart stt_service.dart
├── features/        # conversation(会话列表) chat contact discover mine home(home_shell)
├── router.dart      # go_router：StatefulShellRoute 四 Tab + /chat/:id
└── main.dart        # Hive.initFlutter + ProviderScope
```

## 模块进度

- [x] 骨架：底部 4 Tab + go_router
- [x] 微信页：会话列表（下拉刷新/未读角标/置顶/免打扰/点击已读/Hive 持久化）
- [x] 聊天页：消息气泡、5 分钟时间分组、输入框（Enter 发送/Shift+Enter 换行）、消息 Hive 持久化
- [x] AI 助手会话：`conv_ai` 直连本地 Ollama（默认 qwen3:4b），NDJSON 流式打字效果 + 「对方正在输入…」
- [x] 头像图片：`Contact.avatarAsset` + `AppAvatar` 图片优先/回退字母，素材在 assets/avatars
- [x] 朋友圈页 `/moments`：封面压角头像、九宫格图、点赞评论区（静态 Mock）
- [x] 音视频通话 `/call/:id?video=0|1`：聊天页 + 面板进入；AI 会话接通后 Ollama 生成→flutter_tts 播报+字幕，speech_to_text 按住说话；非 AI 响铃后无应答
- [x] 个人信息页 `/profile`：换头像（相册选图/内置头像网格）、改昵称/地区，`currentUserProvider` 存 Hive 全局生效
- [x] 聊天信息页 `/chat/:id/info`：点头像换任意联系人头像（contactOverridesProvider 存 Hive），置顶/免打扰开关，清空聊天记录
- [x] AI 设置页 `/chat/:id/ai`（AI 会话专属）：人设/知识库/聊天记录风格样本/模型切换（/api/tags 拉本机模型），`ai_profile_provider` 按 conversationId 存 Hive（每个 AI 好友一套独立配置），`ai_prompt.dart` 组装 system prompt（bigram 检索知识条目），聊天+通话共用
- [x] 添加 AI 好友：通讯录「新的朋友」/右上角 + → `add_ai_friend_page`（名字/人设/头像），创建 `conv_ai_<ts>` 会话持久化；Ollama 模型被卸载时自动回落 defaultModel
- [ ] 通讯录：A-Z 侧边索引（scrollable_positioned_list）
- [ ] 发现页/我的页：已完成静态 UI，可继续加二级页面
- [ ] 聊天页进阶：图片/语音消息、长按菜单（复制/撤回/删除）、聊天设置页
