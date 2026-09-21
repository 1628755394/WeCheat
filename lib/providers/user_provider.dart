import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/contact.dart';
import '../repositories/mock_data.dart';

/// 当前登录用户资料：Hive 持久化，修改昵称/头像/地区全局生效
class CurrentUser extends Notifier<Contact> {
  static const _boxName = 'profile';

  Box? _box;
  Future<void>? _loading;

  @override
  Contact build() {
    _loading ??= _load();
    return MockData.me;
  }

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _box = await Hive.openBox(_boxName);
    final raw = _box!.get('me');
    if (raw != null) state = Contact.fromMap(raw as Map);
  }

  Future<void> _save(Contact me) async {
    // 先等初始加载完成，否则 _load 的 state 赋值可能覆盖刚保存的值
    await ensureLoaded();
    state = me;
    await _box!.put('me', me.toMap());
  }

  Future<void> setName(String name) => _save(state.copyWith(name: name));

  Future<void> setRegion(String region) => _save(state.copyWith(region: region));

  Future<void> setAvatarBytes(Uint8List bytes) =>
      _save(state.copyWith(avatarBytes: bytes));

  /// 选内置头像：覆盖 avatarAsset 并清掉自选字节图
  Future<void> setAvatarAsset(String asset) => _save(Contact(
        id: state.id,
        name: state.name,
        remark: state.remark,
        wechatId: state.wechatId,
        region: state.region,
        isGroup: state.isGroup,
        isAi: state.isAi,
        avatarAsset: asset,
      ));
}

final currentUserProvider =
    NotifierProvider<CurrentUser, Contact>(CurrentUser.new);
