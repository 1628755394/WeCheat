import 'package:flutter/material.dart';

/// 全局常量：配色、尺寸
abstract final class AppColors {
  /// 微信绿
  static const primary = Color(0xFF07C160);

  /// 底部导航 / AppBar 背景
  static const navBarBg = Color(0xFFF7F7F7);

  /// 列表分割线
  static const divider = Color(0xFFE5E5E5);

  /// 搜索框 / 次级背景
  static const searchBg = Color(0xFFF2F2F2);

  /// 置顶会话背景
  static const pinnedBg = Color(0xFFF5F5F5);

  /// 次要文字（摘要、时间）
  static const textSecondary = Color(0xFF9B9B9B);

  /// 未读角标红
  static const badge = Color(0xFFFA5151);

  /// 聊天页背景
  static const chatBg = Color(0xFFEDEDED);

  /// 我方聊天气泡绿
  static const bubbleMe = Color(0xFF95EC69);

  /// 头像底色候选
  static const avatarPalette = [
    Color(0xFF5B6B8C),
    Color(0xFF4A7FB5),
    Color(0xFF3F9E8E),
    Color(0xFF8C6BAE),
    Color(0xFFC0785A),
    Color(0xFF5E9E5E),
    Color(0xFFB5546C),
    Color(0xFF6E7B8B),
  ];
}

abstract final class AppDimens {
  static const avatarSize = 48.0;
  static const avatarRadius = 5.0;
  static const conversationTileHeight = 72.0;
}
