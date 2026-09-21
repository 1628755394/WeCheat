import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/contact.dart';
import '../../providers/contact_override_provider.dart';
import '../constants.dart';

/// 微信风格圆角方形头像：自定义覆盖 > 字节图 > asset 图 > 图标/首字符 + 稳定底色
class AppAvatar extends ConsumerWidget {
  final Contact contact;
  final double size;
  final double radius;

  const AppAvatar({
    super.key,
    required this.contact,
    this.size = AppDimens.avatarSize,
    this.radius = AppDimens.avatarRadius,
  });

  Color _bgColor(Contact c) {
    if (c.isAi) return const Color(0xFF10A37F);
    if (c.wechatId == 'filehelper') return const Color(0xFF2F9E6E);
    if (c.isGroup) return const Color(0xFF2B7DBD);
    final hash = c.id.codeUnits.fold(0, (a, b) => a + b);
    return AppColors.avatarPalette[hash % AppColors.avatarPalette.length];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 用户自定义的头像覆盖（按 contactId）
    final c = ref.watch(contactOverridesProvider)[contact.id] ?? contact;

    Widget child;
    if (c.isAi) {
      child = Icon(Icons.smart_toy_outlined, color: Colors.white, size: size * 0.56);
    } else if (c.isGroup) {
      child = Icon(Icons.group, color: Colors.white, size: size * 0.56);
    } else if (c.wechatId == 'filehelper') {
      child = Icon(Icons.upload_file, color: Colors.white, size: size * 0.56);
    } else {
      child = Text(
        c.avatarChar,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (c.avatarBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          c.avatarBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(c, child),
        ),
      );
    }
    if (c.avatarAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          c.avatarAsset!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(c, child),
        ),
      );
    }

    return _fallback(c, child);
  }

  Widget _fallback(Contact c, Widget child) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _bgColor(c),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
