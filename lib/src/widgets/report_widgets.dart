import 'package:flutter/material.dart';

class ReportRow extends StatelessWidget {
  const ReportRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tint,
    this.monetary = false,
  });
  final IconData icon;
  final String label, value;
  final Color? tint;
  final bool monetary;
  @override
  Widget build(BuildContext context) {
    final color = tint ?? Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            MediaQuery.textScalerOf(context).scale(1) >= 1.3 ||
            value.length > 18;
        final heading = Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
          ],
        );
        final text = Text(
          value,
          maxLines: monetary ? 1 : null,
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
        final amount = monetary
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: text,
              )
            : text;
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 8), amount],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .48,
                    ),
                    child: FittedBox(fit: BoxFit.scaleDown, child: amount),
                  ),
                ],
              );
      },
    );
  }
}
