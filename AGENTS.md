# WeCheat —— Flutter 仿微信客户端

只做移动端前端，Mock 数据模拟后端。技术栈：flutter_riverpod / go_router / hive_flutter / intl / scrollable_positioned_list。

## 环境注意

- Windows 环境，shell 请用 `shell_flavor: "powershell"`（本机 WSL 未安装发行版，默认 bash 会失败）
- Flutter 3.47.2 stable / Dart 3.13.2；pub 源走 `https://storage.flutter-io.cn` 镜像
- 本机访问 github.com 走代理可能超时，但 `flutter pub` 正常
- PowerShell 的 Invoke-WebRequest/curl 别名会走代理导致 127.0.0.1 请求失败；测本地服务用 `curl.exe --noproxy "*"`
- 本机装有 Ollama 0.32.1 + `qwen3:4b`（AI 助手会话直连 `127.0.0.1:11434/api/chat` 流式接口；显存 8GB，12B 级别模型只能部分上 GPU 会很慢）
- 远程模型（cc-switch 服务商/手动密钥）走 `remote_llm_service.dart`（Anthropic Messages / OpenAI 兼容 SSE）；Web 端靠 `fetch_client` 才能流式，且远程接口若无 CORS 头会被浏览器拦，需在 run 命令追加 `--web-browser-flag="--disable-web-security"`（已用独立 user-data-dir，影响可控）
- cc-switch 服务商来源（`services/cc_switch*.dart` 条件导出）：桌面端直读 `~/.cc-switch/cc-switch.db`（sqlite3 命令行解析）+ 可启动 `%LOCALAPPDATA%\Programs\CC Switch\cc-switch.exe`；Web 端读 `web/ccswitch_providers.json`（`tool\export_ccswitch.ps1` 导出，含密钥已 gitignore，改配置后重跑）

## 常用命令

```powershell
flutter pub get     # 安装依赖
flutter analyze     # 静态分析（要求 0 issue）
flutter test        # 单元测试
flutter run -d chrome --web-port=7357 --web-browser-flag="--user-data-dir=$PWD\.dart_tool\chrome-profile"
# 桌面端（推荐，免 CORS、cc-switch 直读 db）：
# 需先开 Windows 开发者模式；tools\nuget.exe 供 flutter_tts 插件构建用
$env:PATH = "$PWD\tools;$env:PATH"; flutter run -d windows
# 若 INSTALL 阶段报 "cannot create directory C:/Program Files/xxx"，修 CMake 缓存：
# cmake -DCMAKE_INSTALL_PREFIX="$PWD/build/windows/x64/runner/Debug" build\windows\x64
# 两个参数缺一不可：--web-port 固定 origin（IndexedDB 按域名:端口隔离）；
# --user-data-dir 用真实 Chrome 配置目录替代临时目录，否则仅在 Chrome 正常退出时才把
# IndexedDB 拷贝到 .dart_tool/chrome-device 缓存，Ctrl+C/强杀会丢数据
```

## 目录结构

宽屏（≥760px，`AppDimens.desktopBreakpoint`）自动切 PC 三栏：`SideRail`（图标导航栏）+ `ConversationListPane`（300px 列表栏，选中行绿色高亮）+ 聊天区；窄屏保持底部 4 Tab + 全屏页。聊天路由 `/chat/:id` 进 `ResponsiveChatPage` 自适应。

```
lib/
├── core/            # constants.dart(配色/断点) theme.dart utils/time_utils.dart widgets/app_avatar.dart
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
- [x] 微信页右上角 + 菜单：仿微信深色下拉（发起群聊/添加朋友→add_ai_friend_page/扫一扫/收付款），未实现项提示「功能开发中」
- [x] 多 agent 群聊：发起群聊→`group_create_page` 勾选 AI 好友（≥1，可现场新建）生成 `conv_group_<ts>` 会话，`Conversation.members` 存成员；群里发消息后每个 AI 按各自单聊会话的人设/知识库/模型轮流流式回复（system prompt 带群聊场景，历史里其他成员发言带「名字: 」前缀）；聊天气泡显示发送者昵称+头像，标题「xx 正在输入…」；聊天信息页成员宫格点按进该成员 AI 设置，+ 号加人/减人（updateMembers 自动重排默认群名）
- [x] 模型来源选择：`AiProfile` 加 provider/baseUrl/apiKey/providerName；通用 `model_picker`（本地 Ollama / cc-switch 服务商 / 手动密钥 OpenAI|Claude），添加 AI 好友页与 AI 设置页共用；`llm_service.dart` 网关按 provider 分发，聊天+通话统一走它；cc-switch 面板可「打开 cc-switch」启动应用（桌面端）
- [x] PC 版布局：宽屏自动切三栏——左侧图标栏（头像/四 Tab/未读角标/底部菜单）、会话列表栏（搜索 +「+」菜单、选中行绿色高亮）、右侧聊天区/空占位；点会话 `context.go` 换右侧内容不叠路由栈
- [x] 猫箱式角色体验：`AiProfile.greeting` 空会话自动发开场白；人设非空时 prompt 允许（）动作/神态描写，气泡里括号段灰色小字渲染；最后一条 AI 回复下「换一换」重新生成 + 左右切版本（`Message.variants/variantIndex` 持久化）；通讯录点 AI 好友进 `ai_friend_page.dart` 角色卡（头像/人设/开场白/发消息/AI 设置）
- [x] 内置 AI 角色（`repositories/ai_characters.dart`）：10 个角色（御姐/萝莉/病娇/假小子/少妇/邻家小妹/白月光/傲娇/弟控姐姐/雅儿贝德），各带人设+知识库+聊天样本+开场白；`AiCharacters.seed` 幂等补种单聊会话+资料+全员群 `conv_group_chars`；旧版 Mock 真人会话（conv1-12）自动清理，朋友圈种子改为 AI 角色
- [x] 重点记忆：长按消息 →「标记为记忆」写入该成员 `AiProfile.memories`（群聊写到发言成员自己的资料），prompt 全量注入永不截断；气泡右上角金星标，AI 设置页可管理删除
- [x] 克隆音色：`AiProfile.voiceBytes/voiceName/voiceEndpoint/voicePrompt`；`voice_service.dart` 走 GPT-SoVITS api_v2 兼容接口（默认 127.0.0.1:9880/tts，桌面传临时文件路径、Web 传 base64），失败回退 flutter_tts；通话播报和语音消息共用，TTS 前剥掉（）动作描写；AI 设置页可导入参考音频（file_picker 13，`FilePicker.pickFiles` 静态 API）
- [x] 语音消息：`MessageType.voice` + `audioBytes` 持久化；`+` 面板「语音消息」触发 AI 语音回复（文本先流式生成再合成）；气泡点击播放/补合成；长按 AI 消息可「朗读」
- [x] 好感度：`AiProfile.affinity`（0-100，clamp）+ `likes` 喜好/心愿清单；用户消息命中喜好（bigram 重叠 ≥2，`ai_prompt.affinityGain`）才 +6，无差别聊天不涨；满 100 prompt 注入「言听计从」指令；聊天页 AppBar 底部细进度条（单聊 AI），AI 设置页可拖滑条调整并展示喜好清单；内置角色默认拉满
- [x] 富媒体消息：`MessageType` 扩到 image/location/redPacket/contact/file + `mediaBytes`/`recalled`；`sendRich` 统一发送并给 AI 传 `[图片]` 类占位上下文；+ 面板相册/拍摄（image_picker）/位置/红包/名片/文件全接；群聊通话先选成员再打其单聊
- [x] 消息操作：长按菜单 = 复制/转发(选会话)/标记记忆/朗读/撤回(本人)/删除；撤回渲染「撤回了一条消息」居中提示
- [x] 输入栏：麦克风长按 → speech_to_text 识别文字填入输入框；表情按钮 → emoji 宫格面板插入光标处
- [x] 扫一扫 `/scan`（取景框动画→随机识别出 AI 名片）、收付款 `/pay`（FakeQr 伪二维码 CustomPaint，按 wechatId 哈希）
- [x] 查找聊天记录 `chat_search_page`（全文检索本会话）；聊天信息页 + 号对非 AI 联系人也可拉群
- [x] 通讯录：lpinyin 拼音分组 + scrollable_positioned_list 右侧 A-Z 索引栏；「群聊」列表页/「标签」分组管理页(Hive box=contact_tags)/「公众号」Mock 页
- [x] 朋友圈发动态 `moments_publish_page`（文字+≤9图，image_picker），`moments_provider` Hive box=moments 持久化用户动态，与种子合并展示
- [x] 我的页全接：二维码名片(FakeQr)/收藏(全部 isMemory 消息)/设置(清空消息+重置数据+添加入口)/服务/卡包/表情商店
- [x] 发现页二级页全接：视频号/直播/摇一摇(随机摇出 AI 角色)/看一看/搜一搜(全局搜联系人+消息+朋友圈)/附近/购物/游戏/小程序；side_rail 更多菜单接 /settings
- [x] 语音输入：record 包跨平台录音（桌面 m4a/Web opus blob，`voice_recorder*.dart` 条件导出）；输入栏麦克风切「按住 说话」模式，松手发语音消息（audioBytes，≥1秒才发）
- [x] 复读防护升级：bigram Jaccard>0.4 对比成员近 3 轮 → 提取共有片段点名禁用 + 剔除其复读历史后重试；远程请求带 temperature/presence_penalty；prompt 禁照抄 few-shot 台词
- [x] 猫箱化：①AI 主动消息（会话闲置≥30min 再打开时 TA 主动发消息，群聊随机成员冒泡）②输入栏 ✨ 智能回复建议（生成 3 条候选 chips 点选发送）③`AiProfile.userPersona` 我的人设卡（AI 设置页可编辑，注入 prompt）④好感度阶段名（陌生/初识/熟悉/心动/亲密无间/言听计从）⑤角色卡页「TA 的心声」生成内心独白
- [x] 剧情场景卡：`AiScene`(name/desc/greeting) + `AiProfile.sceneIndex`(-1=未进剧情)，AI 设置页「剧情场景」点击进场景（enterScene 发系统提示+场景开场白，无开场白则 AI 入戏生成），prompt 注入【当前剧情】；10 个内置角色各 2 场景
- [x] 角色广场 `/discover/cards`（`character_feed_page.dart`）：PageView.vertical 全屏角色卡推荐流（立绘铺满+渐变遮罩+人设摘要+开场白+开始聊天/语音通话）
- [x] AI 日记：`AiProfile.diaries`('yyyy-MM-dd HH:mm|内容')，`ai_diary_page.dart` 列表+「让 TA 写日记」（人设 prompt + 日记任务指令 + 最近12条上下文）；角色卡页入口
- [x] 「我与 TA」页（点聊天里自己头像进 `my_persona_page.dart`）：我的人设 / 我们的关系与经历(`AiProfile.relationship`) / 喜好词·厌恶词可增删；厌恶词命中 -5，好感度范围扩到 -100~100，<0 触发冷战（AI 只回一个字），<20 冷暴力敷衍，60+ 亲昵；低好感打开空会话不发预设开场白而是按当前态度生成
- [x] 转账/礼物：`MessageType.transfer`/`gift`，+ 面板入口，橙色转账卡/粉色礼物卡；好感度 <30 时红包/转账按金额(¥20≈+1，上限+15)、礼物+8 挽回，≥30 无效
- [x] 未读角标：`ChatMessages.activeConversationId` 静态标记前台会话，非前台收到的 AI 消息 `unreadCount+1`（系统消息不计）；后台流式回复本就持久化
- [x] 调试工具：`dart run tool/dump_chat.dart` dump 指定会话消息（复制 hive 文件绕锁）
