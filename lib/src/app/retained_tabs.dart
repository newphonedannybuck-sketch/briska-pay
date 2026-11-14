import 'package:flutter/material.dart';

// Owned by the unlocked branch: lock/recovery/onboarding disposes every tab.
// A new data generation also discards drafts after successful restore/reset.
class RetainedTabs extends StatefulWidget {
  const RetainedTabs({required this.index, required this.children, super.key});
  final int index;
  final List<Widget> children;

  @override
  State<RetainedTabs> createState() => _RetainedTabsState();
}

class _RetainedTabsState extends State<RetainedTabs> {
  final _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          TickerMode(
            enabled: i == widget.index,
            child: ExcludeFocus(
              excluding: i != widget.index,
              child: ExcludeSemantics(
                excluding: i != widget.index,
                child: _visited.contains(i)
                    ? widget.children[i]
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}
