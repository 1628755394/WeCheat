import 'package:characters/characters.dart';

class Contact {
  final String id;
  final String name;
  final String? remark;
  final String wechatId;
  final String region;
  final bool isGroup;
  final bool isAi;
  final String? avatarAsset;

  const Contact({
    required this.id,
    required this.name,
    this.remark,
    this.wechatId = '',
    this.region = '',
    this.isGroup = false,
    this.isAi = false,
    this.avatarAsset,
  });

  String get displayName => (remark?.isNotEmpty ?? false) ? remark! : name;

  /// 头像首字符（群聊/特殊账号用图标代替，见 Avatar 组件）
  String get avatarChar => displayName.isEmpty ? '?' : displayName.characters.first;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'remark': remark,
        'wechatId': wechatId,
        'region': region,
        'isGroup': isGroup,
        'isAi': isAi,
        'avatarAsset': avatarAsset,
      };

  factory Contact.fromMap(Map<dynamic, dynamic> map) => Contact(
        id: map['id'] as String,
        name: map['name'] as String,
        remark: map['remark'] as String?,
        wechatId: (map['wechatId'] as String?) ?? '',
        region: (map['region'] as String?) ?? '',
        isGroup: (map['isGroup'] as bool?) ?? false,
        isAi: (map['isAi'] as bool?) ?? false,
        avatarAsset: map['avatarAsset'] as String?,
      );
}
