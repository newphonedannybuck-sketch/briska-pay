import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_theme.dart';
import '../src/models.dart';
import '../src/briska_app.dart';
import '../design_system/briska_theme.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    this.initialEntries = const [],
    this.initialSettings = const AppSettings(onboardingCompleted: true),
    this.initialExports = const [],
    this.useLocalStorage = true,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    super.key,
  });

  final List<WorkEntry> initialEntries;
  final AppSettings initialSettings;
  final List<ExportedFileRecord> initialExports;
  final bool useLocalStorage;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _dotController;
  late final AnimationController _logoController;
  late final Animation<double> _logoOpacity;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _logoOpacity = Tween<double>(begin: .82, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: BriskaDurations.emphasis,
          pageBuilder: (_, _, _) => BriskaShell(
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            initialEntries: widget.initialEntries,
            initialSettings: widget.initialSettings,
            initialExports: widget.initialExports,
            useLocalStorage: widget.useLocalStorage,
          ),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.background,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomPaint(
          painter: const _LoadingBackgroundPainter(),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final markWidth = (width * .52).clamp(190.0, 290.0);
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const Spacer(flex: 42),
                        FadeTransition(
                          opacity: reduceMotion
                              ? const AlwaysStoppedAnimation<double>(1)
                              : _logoOpacity,
                          child: _BriskaMark(width: markWidth),
                        ),
                        const SizedBox(height: 18),
                        const _Wordmark(),
                        const SizedBox(height: 24),
                        const _DividerRule(),
                        const SizedBox(height: 30),
                        const _Tagline(),
                        const Spacer(flex: 18),
                        _LoadingDots(
                          animation: _dotController,
                          reduceMotion: reduceMotion,
                        ),
                        const Spacer(flex: 34),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BriskaMark extends StatelessWidget {
  const _BriskaMark({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(width * .18),
      child: Image.asset(
        'assets/branding/briska-bp-splash.png',
        fit: BoxFit.contain,
      ),
    ),
  );
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: RichText(
      text: const TextSpan(
        style: TextStyle(
          color: Colors.white,
          fontSize: 58,
          fontWeight: FontWeight.w900,
          fontFamily: 'Poppins',
          letterSpacing: 0,
          height: 1,
          shadows: [
            Shadow(
              color: Color(0x88000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        children: [
          TextSpan(text: 'Bris'),
          TextSpan(
            text: 'ka',
            style: TextStyle(color: AppColors.primary),
          ),
        ],
      ),
    ),
  );
}

class _DividerRule extends StatelessWidget {
  const _DividerRule();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 132, height: 2, color: AppColors.primary),
      const SizedBox(width: 22),
      Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 22),
      Container(width: 132, height: 2, color: AppColors.primary),
    ],
  );
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text.rich(
      const TextSpan(
        children: [
          TextSpan(text: 'Work. Track. '),
          TextSpan(
            text: 'Get Paid.',
            style: TextStyle(color: AppColors.primary),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        fontFamily: 'Poppins',
        letterSpacing: 0,
      ),
    ),
  );
}

class _LoadingDots extends StatelessWidget {
  const _LoadingDots({required this.animation, required this.reduceMotion});

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(opacity: .34, scale: .9),
          SizedBox(width: 28),
          _Dot(opacity: 1, scale: 1.08),
          SizedBox(width: 28),
          _Dot(opacity: .34, scale: .9),
        ],
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          final phase = (animation.value - index / 6 + 1) % 1;
          final wave = math.exp(-math.pow(phase / .2, 2));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _Dot(opacity: .28 + wave * .72, scale: .88 + wave * .22),
          );
        }),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.opacity, required this.scale});

  final double opacity;
  final double scale;

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: scale,
    child: Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: opacity),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: opacity * .35),
            blurRadius: 18,
          ),
        ],
      ),
    ),
  );
}

class _LoadingBackgroundPainter extends CustomPainter {
  const _LoadingBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.background, AppColors.dark, Color(0xFF0D2A1E)],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    _drawRibbon(
      canvas,
      size,
      top: true,
      color: AppColors.accent.withValues(alpha: .24),
    );
    _drawRibbon(
      canvas,
      size,
      top: false,
      color: AppColors.primary.withValues(alpha: .22),
    );
  }

  void _drawRibbon(
    Canvas canvas,
    Size size, {
    required bool top,
    required Color color,
  }) {
    final path = Path();
    if (top) {
      path
        ..moveTo(0, size.height * .35)
        ..cubicTo(
          size.width * .12,
          size.height * .14,
          size.width * .35,
          size.height * .23,
          size.width * .55,
          -size.height * .05,
        )
        ..lineTo(size.width * .78, -size.height * .05)
        ..cubicTo(
          size.width * .52,
          size.height * .2,
          size.width * .56,
          size.height * .18,
          size.width * .2,
          size.height * .3,
        )
        ..cubicTo(
          size.width * .08,
          size.height * .34,
          size.width * .04,
          size.height * .45,
          0,
          size.height * .5,
        )
        ..close();
    } else {
      path
        ..moveTo(size.width * .28, size.height)
        ..cubicTo(
          size.width * .43,
          size.height * .78,
          size.width * .58,
          size.height * .84,
          size.width,
          size.height * .64,
        )
        ..lineTo(size.width, size.height * .78)
        ..cubicTo(
          size.width * .76,
          size.height * .93,
          size.width * .58,
          size.height * .88,
          size.width * .49,
          size.height,
        )
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = AppColors.primary.withValues(alpha: .36),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
