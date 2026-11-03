import 'package:flutter/material.dart';

class BriskaInputSection extends StatelessWidget {
  const BriskaInputSection({
    required this.label,
    required this.child,
    this.gap = 8,
    super.key,
  });

  final String label;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      SizedBox(height: gap),
      child,
    ],
  );
}
