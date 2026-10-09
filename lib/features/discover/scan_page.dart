import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/conversation_provider.dart';
import '../../repositories/ai_characters.dart';

/// 扫一扫：深色取景框 + 扫描线动画，Mock 识别出一张 AI 名片
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    // 模拟识别延迟
    _timer = Timer(const Duration(milliseconds: 2600), _mockResult);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _mockResult() async {
    if (_scanned || !mounted) return;
    _scanned = true;
    // 随机扫出一个 AI 角色的名片
    final chars = AiCharacters.all;
    final contact = chars[Random().nextInt(chars.length)].contact;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('识别结果'),
        content: Text('扫到一张名片：${contact.displayName}（AI）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 找到该角色的单聊会话跳过去
              for (final c
                  in ref.read(conversationListProvider).value ?? const []) {
                if (!c.contact.isGroup && c.contact.id == contact.id) {
                  context.push('/chat/${c.id}');
                  return;
                }
              }
            },
            child: const Text('进入聊天'),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _scanned = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('扫一扫'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                children: [
                  // 四角边框
                  for (final pos in [
                    Alignment.topLeft,
                    Alignment.topRight,
                    Alignment.bottomLeft,
                    Alignment.bottomRight,
                  ])
                    Align(alignment: pos, child: const _Corner()),
                  // 扫描线
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Positioned(
                      top: _controller.value * 220,
                      left: 10,
                      right: 10,
                      child: Container(
                        height: 2,
                        color: const Color(0xFF07C160),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('将二维码放入框内，即可自动扫描',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// 取景框四角
class _Corner extends StatelessWidget {
  const _Corner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF07C160), width: 3),
      ),
    );
  }
}
