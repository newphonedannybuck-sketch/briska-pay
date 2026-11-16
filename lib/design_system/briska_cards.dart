import 'package:flutter/material.dart';

import 'briska_spacing.dart';
import 'briska_surfaces.dart';

class BriskaCard extends StatelessWidget {
  const BriskaCard({
    required this.child,
    this.padding = const EdgeInsets.all(BriskaSpacing.cardPadding),
    this.onTap,
    this.tint,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    final decoration = BriskaSurfaces.panel(context, tint: tint);
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: decoration.boxShadow,
        borderRadius: decoration.borderRadius,
      ),
      child: Card(
        color: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: decoration.copyWith(boxShadow: []),
          child: onTap == null
              ? content
              : InkWell(onTap: onTap, child: content),
        ),
      ),
    );
  }
}

class BriskaEmptyState extends StatelessWidget {
  const BriskaEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return BriskaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: BriskaSpacing.cardPadding,
        vertical: BriskaSpacing.xl,
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 28, color: colors.primary),
            ),
            const SizedBox(height: BriskaSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: BriskaSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: BriskaSpacing.md),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
