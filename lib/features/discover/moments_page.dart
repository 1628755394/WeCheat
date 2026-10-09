import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../models/moment.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/moments_provider.dart';
import '../../providers/user_provider.dart';
import 'moments_publish_page.dart';


/// 朋友圈：封面 + 头像压角 + 信息流（昵称/文字/九宫格图/时间/点赞评论）
class MomentsPage extends ConsumerWidget {
  const MomentsPage({super.key});

  static const _nameBlue = Color(0xFF576B95);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moments =
        ref.watch(momentsProvider).value ?? const <Moment>[];
    final me = ref.watch(currentUserProvider);
    final overrides = ref.watch(contactOverridesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const MomentsPublishPage())),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _CoverHeader(me: me),
          for (var i = 0; i < moments.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 62),
            _MomentTile(
              moment: moments[i],
              // 我自己发的动态用实时资料；其他联系人合并自定义覆盖层
              author: moments[i].author.id == 'me'
                  ? me
                  : resolveContact(overrides, moments[i].author),
            ),
          ],
        ],
      ),
    );
  }
}

/// 封面图 + 右下角"我"的昵称和头像（压封面下缘）
class _CoverHeader extends StatelessWidget {
  final Contact me;

  const _CoverHeader({required this.me});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Image.asset(
              'assets/avatars/moments_cover.jpg',
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),
            Positioned(
              right: 12,
              bottom: -22,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    me.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppAvatar(contact: me, size: 62),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 34),
      ],
    );
  }
}

class _MomentTile extends StatelessWidget {
  final Moment moment;
  final Contact author;

  const _MomentTile({required this.moment, required this.author});

  /// 朋友圈相对时间：x分钟前 / x小时前 / 昨天 HH:mm / M月d日
  static String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 2) return '昨天';
    return '${time.month}月${time.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(contact: author, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.displayName,
                  style: const TextStyle(
                    color: MomentsPage._nameBlue,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (moment.text.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(moment.text,
                      style: const TextStyle(fontSize: 15, height: 1.4)),
                ],
                if (moment.images.isNotEmpty ||
                    moment.imageBytes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ImageGrid(
                      images: moment.images, imageBytes: moment.imageBytes),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      _relativeTime(moment.createdAt),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.searchBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.more_horiz,
                          size: 18, color: MomentsPage._nameBlue),
                    ),
                  ],
                ),
                if (moment.likes.isNotEmpty || moment.comments.isNotEmpty)
                  _InteractionBar(
                      likes: moment.likes, comments: moment.comments),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 九宫格图片：1 张显示大图，多张按 3 列正方形排列（asset 路径或内存字节）
class _ImageGrid extends StatelessWidget {
  final List<String> images;
  final List<Uint8List> imageBytes;

  const _ImageGrid({required this.images, this.imageBytes = const []});

  @override
  Widget build(BuildContext context) {
    Widget img(String asset, Uint8List? bytes,
        {required double w, required double h}) {
      final child = bytes != null
          ? Image.memory(bytes, width: w, height: h, fit: BoxFit.cover)
          : Image.asset(asset, width: w, height: h, fit: BoxFit.cover);
      return ClipRRect(borderRadius: BorderRadius.circular(4), child: child);
    }

    final total = images.length + imageBytes.length;
    if (total == 1) {
      return img(images.isNotEmpty ? images.single : '',
          imageBytes.isNotEmpty ? imageBytes.single : null,
          w: 180, h: 180);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 8) / 3;
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final a in images) img(a, null, w: cell, h: cell),
            for (final b in imageBytes) img('', b, w: cell, h: cell),
          ],
        );
      },
    );
  }
}

/// 点赞 / 评论区（灰底，昵称蓝色）
class _InteractionBar extends StatelessWidget {
  final List<String> likes;
  final List<String> comments;

  const _InteractionBar({required this.likes, required this.comments});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.searchBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (likes.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.favorite_border,
                    size: 14, color: MomentsPage._nameBlue),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    likes.join('，'),
                    style: const TextStyle(
                        fontSize: 13, color: MomentsPage._nameBlue),
                  ),
                ),
              ],
            ),
          if (likes.isNotEmpty && comments.isNotEmpty)
            const Divider(height: 10),
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(c, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
