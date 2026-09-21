import 'package:flutter/material.dart';

import '../../models/contact.dart';
import '../constants.dart';

/// 微信风格圆角方形头像：群聊/特殊账号显示图标，普通联系人显示首字符 + 稳定底色
class AppAvatar extends StatelessWidget {
  final Contact contact;
  final double size;
  final double radius;

  const AppAvatar({
    super.key,
    required this.contact,
    this.size = AppDimens.avatarSize,
    this.radius = AppDimens.avatarRadius,
  });

  Color _bgColor() {
    if (contact.isAi) return const Color(0xFF10A37F);
    if (contact.wechatId == 'filehelper') return const Color(0xFF2F9E6E);
    if (contact.isGroup) return const Color(0xFF2B7DBD);
    final hash = contact.id.codeUnits.fold(0, (a, b) => a + b);
    return AppColors.avatarPalette[hash % AppColors.avatarPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (contact.isAi) {
      child = Icon(Icons.smart_toy_outlined, color: Colors.white, size: size * 0.56);
    } else if (contact.isGroup) {
      child = Icon(Icons.group, color: Colors.white, size: size * 0.56);
    } else if (contact.wechatId == 'filehelper') {
      child = Icon(Icons.upload_file, color: Colors.white, size: size * 0.56);
    } else {
      child = Text(
        contact.avatarChar,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    // 有头像图直接显示图片，加载失败回退到字母/图标样式
    if (contact.avatarAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          contact.avatarAsset!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(child),
        ),
      );
    }

    return _fallback(child);
  }

  Widget _fallback(Widget child) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _bgColor(),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
