import 'contact.dart';

class Conversation {
  final String id;
  final Contact contact;

  /// 群成员（仅群聊会话使用，含 AI 好友；不含"我"）
  final List<Contact> members;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool pinned;
  final bool muted;

  const Conversation({
    required this.id,
    required this.contact,
    this.members = const [],
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.pinned = false,
    this.muted = false,
  });

  Conversation copyWith({
    Contact? contact,
    List<Contact>? members,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? pinned,
    bool? muted,
  }) =>
      Conversation(
        id: id,
        contact: contact ?? this.contact,
        members: members ?? this.members,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageTime: lastMessageTime ?? this.lastMessageTime,
        unreadCount: unreadCount ?? this.unreadCount,
        pinned: pinned ?? this.pinned,
        muted: muted ?? this.muted,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'contact': contact.toMap(),
        'members': [for (final m in members) m.toMap()],
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime.millisecondsSinceEpoch,
        'unreadCount': unreadCount,
        'pinned': pinned,
        'muted': muted,
      };

  factory Conversation.fromMap(Map<dynamic, dynamic> map) => Conversation(
        id: map['id'] as String,
        contact: Contact.fromMap(map['contact'] as Map),
        members: (map['members'] as List?)
                ?.map((e) => Contact.fromMap(e as Map))
                .toList() ??
            const [],
        lastMessage: (map['lastMessage'] as String?) ?? '',
        lastMessageTime:
            DateTime.fromMillisecondsSinceEpoch(map['lastMessageTime'] as int),
        unreadCount: (map['unreadCount'] as int?) ?? 0,
        pinned: (map['pinned'] as bool?) ?? false,
        muted: (map['muted'] as bool?) ?? false,
      );
}
