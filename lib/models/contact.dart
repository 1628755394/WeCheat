import 'dart:typed_data';

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

  /// 用户自选的本地头像字节（优先于 avatarAsset）
  final Uint8List? avatarBytes;

  const Contact({
    required this.id,
    required this.name,
    this.remark,
    this.wechatId = '',
    this.region = '',
    this.isGroup = false,
    this.isAi = false,
    this.avatarAsset,
    this.avatarBytes,
  });

  Contact copyWith({
    String? name,
    String? remark,
    String? region,
    String? avatarAsset,
    Uint8List? avatarBytes,
  }) =>
      Contact(
        id: id,
        name: name ?? this.name,
        remark: remark ?? this.remark,
        wechatId: wechatId,
        region: region ?? this.region,
        isGroup: isGroup,
        isAi: isAi,
        avatarAsset: avatarAsset ?? this.avatarAsset,
        avatarBytes: avatarBytes ?? this.avatarBytes,
      );

  String get displayName => (remark?.isNotEmpty ?? false) ? remark! : name;

  /// 头像首字符（群聊/特殊账号用图标代替，见 Avatar 组件）
  String get avatarChar => displayName.isEmpty ? '?' : displayName.characters.first;

  static Uint8List? _toBytes(dynamic raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    return Uint8List.fromList((raw as List).cast<int>());
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'remark': remark,
        'wechatId': wechatId,
        'region': region,
        'isGroup': isGroup,
        'isAi': isAi,
        'avatarAsset': avatarAsset,
        'avatarBytes': avatarBytes,
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
        avatarBytes: _toBytes(map['avatarBytes']),
      );
}
