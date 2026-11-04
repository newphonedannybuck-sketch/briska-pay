part of '../briska_app.dart';

class EntranceAnimation extends StatefulWidget {
  const EntranceAnimation({
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });

  final Widget child;
  final Duration delay;

  @override
  State<EntranceAnimation> createState() => _EntranceAnimationState();
}

class _EntranceAnimationState extends State<EntranceAnimation> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: _visible || reduceMotion ? 1 : 0,
      duration: BriskaDurations.standard,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible || reduceMotion ? Offset.zero : const Offset(0, .025),
        duration: BriskaDurations.standard,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class BriskaPrimaryButton extends StatelessWidget {
  const BriskaPrimaryButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedSwitcher(
      duration: BriskaDurations.quick,
      child: isLoading
          ? const SizedBox(
              key: ValueKey('loading'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon),
                  const SizedBox(width: BriskaSpacing.xs),
                ],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        child: content,
      ),
    );
  }
}

class BriskaAnimatedText extends StatelessWidget {
  const BriskaAnimatedText(this.data, {this.style, super.key});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(data, style: style);
    }
    return AnimatedSwitcher(
      duration: BriskaDurations.standard,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .12),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(data, key: ValueKey(data), style: style),
    );
  }
}

class EmptyWorkState extends StatelessWidget {
  const EmptyWorkState({super.key});

  @override
  Widget build(BuildContext context) {
    return const BriskaEmptyState(
      icon: Icons.calendar_today_outlined,
      title: 'No days recorded yet',
      message: 'Select a date above to record your first day.',
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({
    required this.child,
    this.topPadding = BriskaSpacing.lg,
    super.key,
  });
  final Widget child;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360
        ? 16.0
        : width < 480
        ? 20.0
        : BriskaSpacing.pageHorizontal;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          BriskaSpacing.pageBottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: child,
          ),
        ),
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading({required this.title, required this.subtitle, super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    this.action,
    this.onTap,
    super.key,
  });
  final String title;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
    ],
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) =>
      Text(label, style: Theme.of(context).textTheme.titleSmall);
}

class BriskaLogo extends StatelessWidget {
  const BriskaLogo({this.size = 44, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .18),
      child: Image.asset(
        'assets/branding/briska-bp-in-app.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
