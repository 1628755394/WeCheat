import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/contact.dart';

/// 联系人资料覆盖层：按 contactId 存用户自定义的头像等字段，
/// AppAvatar 读取时合并，全局生效（会话列表/聊天页/通话页/通讯录）
class ContactOverrides extends Notifier<Map<String, Contact>> {
  static const _boxName = 'contact_overrides';

  Box? _box;

  @override
  Map<String, Contact> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    _box = await Hive.openBox(_boxName);
    state = {
      for (final key in _box!.keys)
        key as String: Contact.fromMap(_box!.get(key) as Map),
    };
  }

  Future<void> _save(Contact contact) async {
    _box ??= await Hive.openBox(_boxName);
    await _box!.put(contact.id, contact.toMap());
    state = {...state, contact.id: contact};
  }

  Future<void> setAvatarBytes(Contact base, Uint8List bytes) =>
      _save(base.copyWith(avatarBytes: bytes));

  /// 选内置头像：覆盖 asset 并清掉自选字节图
  Future<void> setAvatarAsset(Contact base, String asset) => _save(Contact(
        id: base.id,
        name: base.name,
        remark: base.remark,
        wechatId: base.wechatId,
        region: base.region,
        isGroup: base.isGroup,
        isAi: base.isAi,
        avatarAsset: asset,
      ));
}

final contactOverridesProvider =
    NotifierProvider<ContactOverrides, Map<String, Contact>>(
        ContactOverrides.new);
