enum MessageType { text, image, system }

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final bool isMe;
  final MessageType type;
  final String content;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.isMe,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  Message copyWith({String? content}) => Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        isMe: isMe,
        type: type,
        content: content ?? this.content,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversationId': conversationId,
        'senderId': senderId,
        'isMe': isMe,
        'type': type.name,
        'content': content,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Message.fromMap(Map<dynamic, dynamic> map) => Message(
        id: map['id'] as String,
        conversationId: map['conversationId'] as String,
        senderId: map['senderId'] as String,
        isMe: (map['isMe'] as bool?) ?? false,
        type: MessageType.values.byName((map['type'] as String?) ?? 'text'),
        content: (map['content'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      );
}
