import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/models.dart';
import '../src/app/briska_shell.dart';
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
    final theme = Theme.of(context);
    final overlays = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlays.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
      ),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final markWidth = (constraints.maxWidth * .32).clamp(96.0, 160.0);
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FadeTransition(
                          opacity: reduceMotion
                              ? const AlwaysStoppedAnimation<double>(1)
                              : _logoOpacity,
                          child: _BriskaMark(width: markWidth),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Briska Pay',
                          style: theme.textTheme.headlineLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Work. Track. Get Paid.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _LoadingDots(
                          animation: _dotController,
                          reduceMotion: reduceMotion,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    ),
  );
}
