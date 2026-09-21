import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/core/utils/time_utils.dart';

void main() {
  group('TimeUtils.formatConversationTime', () {
    final now = DateTime.now();

    test('今天的消息显示 HH:mm', () {
      final time = DateTime(now.year, now.month, now.day, 9, 5);
      expect(TimeUtils.formatConversationTime(time), '09:05');
    });

    test('昨天的消息显示 昨天', () {
      final time = now.subtract(const Duration(days: 1));
      expect(TimeUtils.formatConversationTime(time), '昨天');
    });

    test('一周内的消息显示 星期X', () {
      final time = now.subtract(const Duration(days: 3));
      final result = TimeUtils.formatConversationTime(time);
      expect(result, startsWith('星期'));
    });

    test('今年更早的消息显示 M月d日', () {
      final time = DateTime(now.year, 1, 1);
      // 若今天恰好是 1 月初，可能落在"一周内"分支，这里用足够早的日期规避
      if (now.difference(time).inDays >= 7) {
        expect(TimeUtils.formatConversationTime(time), '1月1日');
      }
    });

    test('跨年消息显示 yyyy/M/d', () {
      final time = DateTime(now.year - 1, 11, 20);
      expect(TimeUtils.formatConversationTime(time), '${now.year - 1}/11/20');
    });
  });
}
