import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/contact.dart';

/// 联系人资料覆盖层：按 contactId 存用户自定义的头像/备注等字段，
/// 渲染时合并生效（会话列表/聊天页/通话页/通讯录/朋友圈）
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

  /// 基于已有覆盖（否则 base）做字段更新，避免改备注时丢掉已设的头像
  Future<void> _update(Contact base, Contact Function(Contact) update) async {
    _box ??= await Hive.openBox(_boxName);
    final updated = update(state[base.id] ?? base);
    await _box!.put(updated.id, updated.toMap());
    state = {...state, updated.id: updated};
  }

  Future<void> setAvatarBytes(Contact base, Uint8List bytes) =>
      _update(base, (c) => c.copyWith(avatarBytes: bytes));

  /// 选内置头像：覆盖 asset 并清掉自选字节图
  Future<void> setAvatarAsset(Contact base, String asset) =>
      _update(base, (c) => Contact(
            id: c.id,
            name: c.name,
            remark: c.remark,
            wechatId: c.wechatId,
            region: c.region,
            isGroup: c.isGroup,
            isAi: c.isAi,
            avatarAsset: asset,
          ));

  /// 备注：传空字符串清除备注（显示回原名）
  Future<void> setRemark(Contact base, String remark) =>
      _update(base, (c) => Contact(
            id: c.id,
            name: c.name,
            remark: remark.isEmpty ? null : remark,
            wechatId: c.wechatId,
            region: c.region,
            isGroup: c.isGroup,
            isAi: c.isAi,
            avatarAsset: c.avatarAsset,
            avatarBytes: c.avatarBytes,
          ));
}

final contactOverridesProvider =
    NotifierProvider<ContactOverrides, Map<String, Contact>>(
        ContactOverrides.new);

/// 合并覆盖层后的联系人（有覆盖用覆盖，否则原样）
Contact resolveContact(Map<String, Contact> overrides, Contact base) =>
    overrides[base.id] ?? base;
