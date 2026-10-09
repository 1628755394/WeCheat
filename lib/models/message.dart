import 'dart:typed_data';

enum MessageType {
  text,
  image,
  system,
  voice,
  location,
  redPacket,
  contact,
  file,
  transfer,
  gift,
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final bool isMe;
  final MessageType type;
  final String content;
  final DateTime createdAt;

  /// 「换一换」的全部版本（含当前正文），空 = 未重新生成过
  final List<String> variants;

  /// 当前正文在 variants 里的下标
  final int variantIndex;

  /// 被用户标记为「重点记忆」，会永久注入该 AI 的 system prompt
  final bool isMemory;

  /// 语音消息的音频字节（克隆音色合成结果，type == voice 时使用）
  final Uint8List? audioBytes;
  final String audioFileName;

  /// 图片/文件消息的二进制内容（type == image/file 时使用）
  final Uint8List? mediaBytes;

  /// 已撤回（渲染成「xx 撤回了一条消息」系统提示）
  final bool recalled;

  /// 引用的原消息内容快照（微信式引用回复）
  final String quoteText;

  /// 被引用消息的发送者名
  final String quoteSender;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.isMe,
    required this.type,
    required this.content,
    required this.createdAt,
    this.variants = const [],
    this.variantIndex = 0,
    this.isMemory = false,
    this.audioBytes,
    this.audioFileName = '',
    this.mediaBytes,
    this.recalled = false,
    this.quoteText = '',
    this.quoteSender = '',
  });

  Message copyWith({
    String? content,
    List<String>? variants,
    int? variantIndex,
    bool? isMemory,
    Uint8List? audioBytes,
    String? audioFileName,
    Uint8List? mediaBytes,
    bool? recalled,
    String? quoteText,
    String? quoteSender,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        isMe: isMe,
        type: type,
        content: content ?? this.content,
        createdAt: createdAt,
        variants: variants ?? this.variants,
        variantIndex: variantIndex ?? this.variantIndex,
        isMemory: isMemory ?? this.isMemory,
        audioBytes: audioBytes ?? this.audioBytes,
        audioFileName: audioFileName ?? this.audioFileName,
        mediaBytes: mediaBytes ?? this.mediaBytes,
        recalled: recalled ?? this.recalled,
        quoteText: quoteText ?? this.quoteText,
        quoteSender: quoteSender ?? this.quoteSender,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'isMe': isMe,
        'type': type.name,
        'content': content,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'variants': variants,
        'variantIndex': variantIndex,
        'isMemory': isMemory,
        'audioBytes': audioBytes,
        'audioFileName': audioFileName,
        'mediaBytes': mediaBytes,
        'recalled': recalled,
        'quoteText': quoteText,
        'quoteSender': quoteSender,
      };

  factory Message.fromMap(Map<dynamic, dynamic> map) => Message(
        id: map['id'] as String,
        conversationId: map['conversationId'] as String,
        senderId: map['senderId'] as String,
        isMe: (map['isMe'] as bool?) ?? false,
        type: MessageType.values.byName((map['type'] as String?) ?? 'text'),
        content: (map['content'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        variants:
            (map['variants'] as List?)?.cast<String>() ?? const [],
        variantIndex: (map['variantIndex'] as int?) ?? 0,
        isMemory: (map['isMemory'] as bool?) ?? false,
        audioBytes: _toBytes(map['audioBytes']),
        audioFileName: (map['audioFileName'] as String?) ?? '',
        mediaBytes: _toBytes(map['mediaBytes']),
        recalled: (map['recalled'] as bool?) ?? false,
        quoteText: (map['quoteText'] as String?) ?? '',
        quoteSender: (map['quoteSender'] as String?) ?? '',
      );

  static Uint8List? _toBytes(dynamic raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    return Uint8List.fromList((raw as List).cast<int>());
  }
}
