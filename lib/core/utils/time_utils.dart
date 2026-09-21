import 'package:intl/intl.dart';

/// 微信风格时间格式化
abstract final class TimeUtils {
  static const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

  /// 会话列表时间：今天→HH:mm，昨天→昨天，一周内→星期X，今年→M月d日，更早→yyyy/M/d
  static String formatConversationTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(time.year, time.month, time.day);
    final diffDays = today.difference(date).inDays;

    if (diffDays <= 0) return DateFormat('HH:mm').format(time);
    if (diffDays == 1) return '昨天';
    if (diffDays < 7) return _weekdays[time.weekday - 1];
    if (time.year == now.year) return '${time.month}月${time.day}日';
    return DateFormat('yyyy/M/d').format(time);
  }

  /// 聊天页时间分组标签：今天→HH:mm，昨天→昨天 HH:mm，一周内→星期X HH:mm，更早→M月d日 HH:mm
  static String formatMessageGroupTime(DateTime time) {
    final hm = DateFormat('HH:mm').format(time);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(time.year, time.month, time.day);
    final diffDays = today.difference(date).inDays;

    if (diffDays <= 0) return hm;
    if (diffDays == 1) return '昨天 $hm';
    if (diffDays < 7) return '${_weekdays[time.weekday - 1]} $hm';
    if (time.year == now.year) return '${time.month}月${time.day}日 $hm';
    return '${DateFormat('yyyy/M/d').format(time)} $hm';
  }
}
