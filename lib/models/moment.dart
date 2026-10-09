import 'dart:typed_data';

import 'contact.dart';

/// 朋友圈动态（Mock 种子 + 用户发布的持久化在 Hive）
class Moment {
  final Contact author;
  final String text;
  final List<String> images;
  final List<Uint8List> imageBytes;
  final DateTime createdAt;
  final List<String> likes;
  final List<String> comments;

  const Moment({
    required this.author,
    this.text = '',
    this.images = const [],
    this.imageBytes = const [],
    required this.createdAt,
    this.likes = const [],
    this.comments = const [],
  });
}
