import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/loading_screen.dart';
import 'src/ads/ads_consent_coordinator.dart';
import 'src/ads/ads_service.dart';
import 'src/app_lock_service.dart';
import 'src/app_theme.dart';
import 'src/briska_app.dart';
import 'src/models.dart';

void main() {
  if (kDebugMode) debugPrint('main() started');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BriskaApp(useLocalStorage: true));
}

class BriskaApp extends StatefulWidget {
  const BriskaApp({
    this.initialEntries = const [],
    this.initialSettings = const AppSettings(onboardingCompleted: true),
    this.initialExports = const [],
    this.showLoadingScreen = false,
    this.useLocalStorage = false,
    this.appLockConfigLoader,
    this.pinVerifier,
    this.biometricAuthenticator,
    this.deviceAuthenticationAvailabilityChecker,
    this.adsConsentCoordinator,
    this.adsService,
    super.key,
  });

  final List<WorkEntry> initialEntries;
  final AppSettings initialSettings;
  final List<ExportedFileRecord> initialExports;
  final bool showLoadingScreen;
  final bool useLocalStorage;
  final Future<AppLockConfig> Function()? appLockConfigLoader;
  final Future<bool> Function(String pin)? pinVerifier;
  final Future<bool> Function()? biometricAuthenticator;
  final Future<bool> Function()? deviceAuthenticationAvailabilityChecker;
  final AdsConsentCoordinator? adsConsentCoordinator;
  final AdsService? adsService;

  @override
  State<BriskaApp> createState() => _BriskaAppState();
}

class _BriskaAppState extends State<BriskaApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = themeModeFromSettings(widget.initialSettings.themeMode);
  }

  void _handleThemeModeChanged(ThemeMode themeMode) {
    if (_themeMode == themeMode) return;
    setState(() => _themeMode = themeMode);
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('BriskaApp build');
    return MaterialApp(
      title: 'Briska Pay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: widget.showLoadingScreen
          ? LoadingScreen(
              initialEntries: widget.initialEntries,
              initialSettings: widget.initialSettings,
              initialExports: widget.initialExports,
              useLocalStorage: widget.useLocalStorage,
              themeMode: _themeMode,
              onThemeModeChanged: _handleThemeModeChanged,
            )
          : BriskaShell(
              themeMode: _themeMode,
              onThemeModeChanged: _handleThemeModeChanged,
              initialEntries: widget.initialEntries,
              initialSettings: widget.initialSettings,
              initialExports: widget.initialExports,
              useLocalStorage: widget.useLocalStorage,
              appLockConfigLoader: widget.appLockConfigLoader,
              pinVerifier: widget.pinVerifier,
              biometricAuthenticator: widget.biometricAuthenticator,
              deviceAuthenticationAvailabilityChecker:
                  widget.deviceAuthenticationAvailabilityChecker,
              adsConsentCoordinator: widget.adsConsentCoordinator,
              adsService: widget.adsService,
            ),
    );
  }
}
