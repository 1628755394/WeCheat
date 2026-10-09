import 'dart:math';

import 'package:flutter/material.dart';

/// 伪二维码：由 seed 字符串哈希生成确定性网格图案（非真实 QR 编码，纯视觉 Mock）
class FakeQr extends StatelessWidget {
  final String seed;
  final double size;

  const FakeQr({super.key, required this.seed, this.size = 220});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _FakeQrPainter(seed),
    );
  }
}

class _FakeQrPainter extends CustomPainter {
  final String seed;

  _FakeQrPainter(this.seed);

  static const _n = 25; // 网格边长

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _n;
    final rnd = Random(seed.hashCode);
    final paint = Paint()..color = Colors.black;

    // 白底
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    bool inFinder(int x, int y) =>
        (x < 7 && y < 7) ||
        (x >= _n - 7 && y < 7) ||
        (x < 7 && y >= _n - 7);

    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        if (inFinder(x, y)) continue;
        if (rnd.nextBool()) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            paint,
          );
        }
      }
    }

    // 三个定位角
    void finder(double dx, double dy) {
      canvas.drawRect(
          Rect.fromLTWH(dx, dy, cell * 7, cell * 7), paint);
      canvas.drawRect(
          Rect.fromLTWH(dx + cell, dy + cell, cell * 5, cell * 5),
          Paint()..color = Colors.white);
      canvas.drawRect(
          Rect.fromLTWH(dx + cell * 2, dy + cell * 2, cell * 3, cell * 3),
          paint);
    }

    finder(0, 0);
    finder(size.width - cell * 7, 0);
    finder(0, size.height - cell * 7);
  }

  @override
  bool shouldRepaint(_FakeQrPainter old) => old.seed != seed;
}
