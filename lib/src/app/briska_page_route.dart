import 'package:flutter/material.dart';

import '../../design_system/briska_theme.dart';

class BriskaPageRoute<T> extends PageRouteBuilder<T> {
  BriskaPageRoute({required Widget child})
    : super(
        transitionDuration: BriskaDurations.emphasis,
        reverseTransitionDuration: BriskaDurations.standard,
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (context, animation, _, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .018),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
}
