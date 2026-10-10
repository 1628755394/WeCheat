import 'package:flutter/material.dart';

import '../constants.dart';

/// Keep forms and secondary lists readable on large desktop windows.
class AppPageBody extends StatelessWidget {
  const AppPageBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= AppDimens.desktopBreakpoint;
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 0),
            child: child,
          ),
        ),
      );
    },
  );
}
