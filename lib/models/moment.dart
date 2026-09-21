import 'contact.dart';

/// 朋友圈动态（Mock，不持久化）
class Moment {
  final Contact author;
  final String text;
  final List<String> images;
  final DateTime createdAt;
  final List<String> likes;
  final List<String> comments;

  const Moment({
    required this.author,
    this.text = '',
    this.images = const [],
    required this.createdAt,
    this.likes = const [],
    this.comments = const [],
  });
}
