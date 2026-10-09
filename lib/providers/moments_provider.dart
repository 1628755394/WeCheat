import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/moment.dart';
import '../repositories/mock_data.dart';
import 'user_provider.dart';

/// 朋友圈：Mock 种子 + 用户自己发的动态（Hive 持久化，box=moments）
class MomentsNotifier extends AsyncNotifier<List<Moment>> {
  static const _boxName = 'moments';
  Box? _box;

  @override
  Future<List<Moment>> build() async {
    _box ??= await Hive.openBox(_boxName);
    return _load();
  }

  List<Moment> _load() {
    final me = ref.read(currentUserProvider);
    final stored = <Moment>[
      for (final raw in _box!.values)
        Moment(
          author: me,
          text: (raw as Map)['text'] as String? ?? '',
          imageBytes: [
            for (final b in (raw['images'] as List? ?? const []))
              b is Uint8List ? b : Uint8List.fromList((b as List).cast<int>()),
          ],
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              raw['createdAt'] as int),
        ),
    ];
    return [...stored, ...MockData.seedMoments()];
  }

  /// 发布一条动态（图片存字节）
  Future<void> publish(String text, List<Uint8List> images) async {
    final entry = {
      'text': text,
      'images': images,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _box!.add(entry);
    state = AsyncData(_load());
  }
}

final momentsProvider =
    AsyncNotifierProvider<MomentsNotifier, List<Moment>>(MomentsNotifier.new);
