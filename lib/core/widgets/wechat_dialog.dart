import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants.dart';

/// Shared dialog shell for confirmations and editable forms.
class WeChatDialog extends StatelessWidget {
  const WeChatDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.scrollable = true,
  });
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = MediaQuery.viewInsetsOf(context);
    final height = math.max(120.0, size.height - inset.bottom - 48);
    final buttons = actions.length == 2 ? actions.reversed.toList() : actions;
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
      backgroundColor: const WidgetStatePropertyAll(Color(0xFFEBEBEB)),
      foregroundColor: const WidgetStatePropertyAll(Colors.black87),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 16)),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: AppColors.navBarBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD2D2D2), width: 0.5),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: height),
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 18,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    child: title!,
                  ),
                ),
              if (content != null)
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      title == null ? 24 : 0,
                      24,
                      24,
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        height: 1.5,
                      ),
                      child: scrollable
                          ? SingleChildScrollView(child: content!)
                          : content!,
                    ),
                  ),
                ),
              if (buttons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textButtonTheme: TextButtonThemeData(style: buttonStyle),
                      filledButtonTheme: FilledButtonThemeData(
                        style: buttonStyle.copyWith(
                          backgroundColor: const WidgetStatePropertyAll(
                            AppColors.primary,
                          ),
                          foregroundColor: const WidgetStatePropertyAll(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < buttons.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 12),
                          Expanded(child: buttons[index]),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
