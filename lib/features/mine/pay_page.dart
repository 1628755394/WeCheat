import '../../core/widgets/wechat_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/widgets/fake_qr.dart';
import '../../providers/user_provider.dart';

/// 收付款：付款条码 + 收款二维码（伪二维码，纯 Mock）
class PayPage extends ConsumerStatefulWidget {
  const PayPage({super.key});

  @override
  ConsumerState<PayPage> createState() => _PayPageState();
}

class _PayPageState extends ConsumerState<PayPage> {
  bool _receive = false;
  double _amount = 0;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF07C160),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(_receive ? '收款' : '向商家付款'),
      ),
      body: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                me.displayName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _receive ? '扫一扫，向我付款' : '付款码',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              if (_receive && _amount > 0)
                Text(
                  '¥${_amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              FakeQr(
                seed: '${me.wechatId}-${_receive ? 'in' : 'out'}-$_amount',
              ),
              const SizedBox(height: 16),
              if (_receive)
                TextButton(
                  onPressed: _setAmount,
                  child: Text(_amount > 0 ? '修改金额' : '设置金额'),
                )
              else
                const Text(
                  '优先使用零钱支付',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => setState(() => _receive = false),
              child: Text(
                '付款码',
                style: TextStyle(
                  color: _receive ? Colors.white70 : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _receive = true),
              child: Text(
                '收款码',
                style: TextStyle(
                  color: _receive ? Colors.white : Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAmount() async {
    final ctl = TextEditingController(
      text: _amount > 0 ? _amount.toStringAsFixed(2) : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => WeChatDialog(
        title: const Text('收款金额'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '¥ '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _amount = double.tryParse(ctl.text) ?? 0);
    }
  }
}
