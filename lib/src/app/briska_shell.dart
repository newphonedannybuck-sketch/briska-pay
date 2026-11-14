import 'app_data_controller.dart';
import 'retained_tabs.dart';
import '../ads/advertising_startup.dart';

import '../export/export_action_overrides.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../design_system/briska_icons.dart';
import '../../design_system/briska_theme.dart';
import '../ads/ads_configuration.dart';
import '../ads/ads_consent_coordinator.dart';
import '../ads/ads_service.dart';
import '../ads/briska_banner_ad.dart';
import '../app_lock_service.dart';
import '../../design_system/briska_colors.dart';
import '../backup_service.dart';
import '../currency.dart';
import '../local_storage.dart';
import '../models.dart';
import '../work_calculator.dart';
import '../display_format.dart';
import '../presentation_format.dart';
import '../premium_home_screen.dart';
import 'briska_page_route.dart';
import 'theme_preferences.dart';
import 'settings_operation.dart';
import '../screens/app_lock_screen.dart';
import '../screens/app_lock_initialization_error_screen.dart';
import '../screens/startup_initialization_screen.dart';
import '../screens/startup_recovery_screen.dart';
import '../screens/about_screen.dart';
import '../screens/entries_screen.dart';
import '../screens/professional_reports_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/add_work_day_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/export_screen.dart';

enum AppLockInitializationState { loading, locked, unlocked, failed }

enum AdvertisingConsentGateState { waiting, checking, complete }

class BriskaShell extends StatefulWidget {
  const BriskaShell({
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.initialEntries = const [],
    this.initialSettings = const AppSettings(onboardingCompleted: true),
    this.initialExports = const [],
    this.useLocalStorage = true,
    this.appLockConfigLoader,
    this.lockClock,
    this.pinVerifier,
    this.biometricAuthenticator,
    this.deviceAuthenticationAvailabilityChecker,
    this.adsConsentCoordinator,
    this.adsService,
    this.exportActionOverrides,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final List<WorkEntry> initialEntries;
  final AppSettings initialSettings;
  final List<ExportedFileRecord> initialExports;
  final bool useLocalStorage;
  final Future<AppLockConfig> Function()? appLockConfigLoader;
  final DateTime Function()? lockClock;
  final Future<bool> Function(String pin)? pinVerifier;
  final Future<bool> Function()? biometricAuthenticator;
  final Future<bool> Function()? deviceAuthenticationAvailabilityChecker;
  final AdsConsentCoordinator? adsConsentCoordinator;
  final AdsService? adsService;
  final ExportActionOverrides? exportActionOverrides;

  @override
  State<BriskaShell> createState() => _BriskaShellState();
}

class _BriskaShellState extends State<BriskaShell> with WidgetsBindingObserver {
  int _index = 0;
  late final AppDataController _data;
  late final AdvertisingStartup _advertising;
  AppLockConfig _lockConfig = const AppLockConfig();
  AppLockInitializationState _lockState = AppLockInitializationState.loading;
  late bool _storedStateLoaded;
  DateTime? _backgroundedAt;
  int _lockSession = 0;
  final _editorSecurityDismissal = ValueNotifier<int>(0);
  bool _deviceAuthenticationActive = false;
  bool _foreground = true;
  int? _pendingUnlockSession;
  String? _startupError;
  bool _startupDataIsCorrupt = false;
  bool _restoreRecoveryRequired = false;
  bool _restoreInProgress = false;
  Future<void>? _storedStateLoad;
  late final AdsConsentCoordinator _adsConsentCoordinator;
  late final AdsService _adsService;
  AdvertisingConsentGateState _consentGateState =
      AdvertisingConsentGateState.waiting;
  PrivacyOptionsRequirement _privacyOptionsRequirement =
      PrivacyOptionsRequirement.unknown;
  bool _homeBannerEligible = false;

  @override
  void initState() {
    super.initState();
    _data = AppDataController(
      settings: widget.initialSettings,
      entries: widget.initialEntries,
      exports: widget.initialExports,
    );
    CurrencyFormatter.current = _data.settings.currency;
    _storedStateLoaded = !widget.useLocalStorage;
    final adsConfiguration = AdsConfiguration.current();
    _adsConsentCoordinator =
        widget.adsConsentCoordinator ??
        (widget.useLocalStorage
            ? GoogleAdsConsentCoordinator()
            : const InactiveAdsConsentCoordinator());
    _adsService =
        widget.adsService ??
        (widget.useLocalStorage
            ? GoogleMobileAdsService(adsConfiguration)
            : DisabledAdsService(adsConfiguration));
    _advertising = AdvertisingStartup(
      service: _adsService,
      coordinator: _adsConsentCoordinator,
    );
    if (!widget.useLocalStorage && widget.adsConsentCoordinator == null) {
      _consentGateState = AdvertisingConsentGateState.complete;
    }
    final shouldLoadPersistedLock =
        widget.useLocalStorage || widget.appLockConfigLoader != null;
    if (!shouldLoadPersistedLock) {
      _lockState = AppLockInitializationState.unlocked;
    }
    WidgetsBinding.instance.addObserver(this);
    if (widget.useLocalStorage) _loadStoredState();
    if (shouldLoadPersistedLock) _loadLockConfig();
  }

  @override
  void dispose() {
    _editorSecurityDismissal.dispose();
    _advertising.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_lockState == AppLockInitializationState.loading ||
        _lockState == AppLockInitializationState.failed ||
        !_lockConfig.enabled) {
      return;
    }
    if (state == AppLifecycleState.inactive && _deviceAuthenticationActive) {
      // Native authentication may briefly make the app inactive. A real
      // background (hidden/paused) still invalidates the pending request.
      return;
    }
    final now = widget.lockClock?.call() ?? DateTime.now();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_backgroundedAt == null) {
        _backgroundedAt = now;
        _pendingUnlockSession = null;
        if (_lockState == AppLockInitializationState.locked) {
          setState(() => _lockSession++);
        }
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_backgroundedAt != null) {
        final elapsed = now.difference(_backgroundedAt!).inSeconds;
        _backgroundedAt = null;
        if (_lockState != AppLockInitializationState.locked &&
            (elapsed < 0 || elapsed >= _lockConfig.lockAfterSeconds)) {
          _dismissRoutesForAppLock();
          setState(() {
            _lockSession++;
            _lockState = AppLockInitializationState.locked;
          });
        }
      }
      final pending = _pendingUnlockSession;
      _pendingUnlockSession = null;
      if (pending != null) _handleUnlocked(pending);
    }
  }

  void _dismissRoutesForAppLock() {
    _editorSecurityDismissal.value++;
    final navigator = Navigator.of(context);
    // Remove rather than animate away: neither PopScope nor an open dialog
    // may delay security dismissal or leave sensitive content on screen.
    while (true) {
      Route<dynamic>? top;
      navigator.popUntil((route) {
        top = route;
        return true;
      });
      if (top == null || top!.isFirst) return;
      navigator.removeRoute(top!);
    }
  }

  Future<void> _loadLockConfig() async {
    if (_lockState != AppLockInitializationState.loading) {
      setState(() => _lockState = AppLockInitializationState.loading);
    }
    try {
      final config =
          await (widget.appLockConfigLoader?.call() ??
              AppLockService.loadConfig());
      if (!mounted) return;
      setState(() {
        _lockSession++;
        _lockConfig = config;
        _lockState = config.enabled
            ? AppLockInitializationState.locked
            : AppLockInitializationState.unlocked;
      });
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('app-lock initialisation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted) return;
      setState(() => _lockState = AppLockInitializationState.failed);
    }
  }

  Future<void> _loadStoredState() {
    return _storedStateLoad ??= _data
        .mutate(_reconcileStoredState)
        .whenComplete(() => _storedStateLoad = null);
  }

  Future<void> _reconcileStoredState() async {
    if (kDebugMode) debugPrint('storage initialisation started');
    try {
      // Resolve the transaction before parsing or migrating any dataset.
      await LocalStorage.recoverPendingRestore();
      final results = await Future.wait([
        LocalStorage.loadEntries(),
        LocalStorage.loadSettings(),
        LocalStorage.loadExportRecords(),
      ]);
      if (kDebugMode) debugPrint('storage initialisation completed');
      if (!mounted) return;
      setState(() {
        _data.generation++;
        _data.settingsSaveRevision++;
        _index = 0;
        _data.entries = results[0] as List<WorkEntry>;
        _data.settings = results[1] as AppSettings;
        _data.exports = results[2] as List<ExportedFileRecord>;
        _startupError = null;
        _startupDataIsCorrupt = false;
        _restoreRecoveryRequired = false;
        _storedStateLoaded = true;
        CurrencyFormatter.current = _data.settings.currency;
      });
      widget.onThemeModeChanged?.call(
        themeModeFromSettings(_data.settings.themeMode),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('storage initialisation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted) return;
      if (error is LocalRestoreRecoveryRequiredException) {
        _requireRestoreRecovery(error);
      }
      setState(() {
        _startupError = error.toString();
        _startupDataIsCorrupt = error is LocalDataCorruptionException;
        _storedStateLoaded = true;
      });
    }
  }

  void _requireRestoreRecovery(Object error) {
    if (!mounted) return;
    // Invalidate captured callbacks before the operation queue can advance.
    setState(() {
      _data.generation++;
      _data.settingsSaveRevision++;
      _restoreRecoveryRequired = true;
      _startupError = error.toString();
      _startupDataIsCorrupt = false;
    });
    _dismissRoutesForAppLock();
  }

  Future<bool> _changeExportRecord(
    ExportedFileRecord record,
    int generation, {
    bool add = false,
    bool delete = false,
  }) => _data.mutate(() async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _data.generation) {
      return false;
    }
    final updated = List<ExportedFileRecord>.of(_data.exports);
    final index = updated.indexWhere((item) => item.id == record.id);
    if (delete) {
      updated.removeWhere((item) => item.id == record.id);
    } else if (index != -1) {
      updated[index] = record;
    } else if (add) {
      updated.insert(0, record);
    } else {
      return false;
    }
    try {
      await LocalStorage.saveExportRecords(updated);
      if (!mounted) return false;
      setState(() => _data.exports = updated);
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('export library save failed: $error');
      return false;
    }
  });

  Future<void> _resetLocalDataAfterConfirmation() =>
      _data.mutate(_resetLocalDataInQueue);

  Future<void> _resetLocalDataInQueue() async {
    if (!mounted || _restoreRecoveryRequired) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset local Briska Pay data?'),
        content: const Text(
          'This removes saved entries, settings and export records from this installation. Create or restore a backup if you need to keep them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset data'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalStorage.resetLocalData();
    _data.generation++;
    _data.settingsSaveRevision++;
    if (!mounted) return;
    setState(() {
      _data.settings = const AppSettings();
      CurrencyFormatter.current = _data.settings.currency;
      _data.entries = [];
      _data.exports = [];
      _startupError = null;
      _startupDataIsCorrupt = false;
      _restoreRecoveryRequired = false;
      _index = 0;
    });
    widget.onThemeModeChanged?.call(ThemeMode.system);
  }

  void _showAddDay([WorkEntry? entry, DateTime? initialDate]) {
    if (_restoreRecoveryRequired) return;
    final generation = _data.generation;
    Navigator.of(context).push(
      BriskaPageRoute(
        child: AddWorkDayScreen(
          preferences: _data.settings,
          savedEntries: _data.entries,
          initialEntry: entry,
          initialDate: initialDate,
          onSave: (entry) => _saveEntry(entry, generation),
          securityDismissal: _editorSecurityDismissal,
        ),
      ),
    );
  }

  Future<bool> _saveEntry(WorkEntry entry, int generation) {
    return _data.mutate(() => _saveEntryInQueue(entry, generation));
  }

  Future<bool> _saveEntryInQueue(WorkEntry entry, int generation) async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _data.generation) {
      return false;
    }
    final validation = WorkCalculator.calculate(
      startTime: entry.startTime,
      finishTime: entry.finishTime,
      breakMinutes: entry.entryType == 'WorkDay' ? entry.breakMinutes : 0,
      hourlyRate: entry.hourlyRateUsed,
      rateType: entry.rateType,
      dailyAllowance: entry.dailyAllowance,
      jobUplift: entry.jobUplift,
      entryType: entry.entryType,
      isPaidSickDay: entry.isPaidSickDay,
      isPaidBankHoliday: entry.isPaidBankHoliday,
      deductionAmount: entry.deductionAmount,
      holidayHours: entry.totalHours,
    );
    if (!validation.isValid) {
      return false;
    }
    final calculatedEntry = WorkCalculator.recalculateEntry(entry);
    final updatedEntries = List<WorkEntry>.of(_data.entries);
    final index = updatedEntries.indexWhere(
      (item) => item.id == calculatedEntry.id,
    );
    if (index == -1) {
      updatedEntries.insert(0, calculatedEntry);
    } else {
      updatedEntries[index] = calculatedEntry;
    }
    updatedEntries.sort((a, b) => b.date.compareTo(a.date));
    try {
      await LocalStorage.saveEntries(updatedEntries);
      if (!mounted) return false;
      setState(() => _data.entries = updatedEntries);
      return true;
    } catch (error, stackTrace) {
      debugPrint('entries save failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not save this day.')));
      return false;
    }
  }

  Future<void> _deleteEntry(WorkEntry entry, int generation) async {
    if (_restoreRecoveryRequired || generation != _data.generation) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dayLabel = entry.entryType == 'Holiday'
            ? 'Holiday'
            : entry.type == EntryType.bankHoliday
            ? 'Bank Holiday'
            : entry.entryType == 'UnpaidDayOff'
            ? 'Unpaid day off'
            : entry.siteName.trim().isNotEmpty
            ? entry.siteName.trim()
            : 'Work day';
        final dateLabel = formatWeekdayDate(entry.date);
        return AlertDialog(
          icon: Icon(
            Icons.delete_outline_rounded,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: const Text('Delete day?'),
          content: Text(
            "Delete this recorded day?\n\n$dateLabel\n$dayLabel\n\n"
            'You can undo this briefly using the Undo action after deletion.',
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            Semantics(
              button: true,
              label: 'Delete day',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: BriskaColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _data.mutate(() => _deleteEntryInQueue(entry.id, generation));
  }

  Future<void> _deleteEntryInQueue(String id, int generation) async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _data.generation) {
      return;
    }
    final index = _data.entries.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final deletedEntry = _data.entries[index];
    final updatedEntries = List<WorkEntry>.of(_data.entries)
      ..removeWhere((item) => item.id == id);
    try {
      await LocalStorage.saveEntries(updatedEntries);
      if (!mounted) return;
      setState(() => _data.entries = updatedEntries);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Day deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoDeleteEntry(deletedEntry, generation),
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('entry delete save failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this day.')),
      );
    }
  }

  Future<void> _undoDeleteEntry(WorkEntry entry, int generation) =>
      _data.mutate(() => _undoDeleteEntryInQueue(entry, generation));

  Future<void> _undoDeleteEntryInQueue(WorkEntry entry, int generation) async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _data.generation) {
      return;
    }
    final restoredEntries = List<WorkEntry>.of(_data.entries);
    if (restoredEntries.any((item) => item.id == entry.id)) return;
    restoredEntries
      ..add(entry)
      ..sort((a, b) => b.date.compareTo(a.date));
    try {
      await LocalStorage.saveEntries(restoredEntries);
      if (!mounted) return;
      setState(() => _data.entries = restoredEntries);
    } catch (error, stackTrace) {
      debugPrint('entry delete undo save failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore this day.')),
      );
    }
  }

  Future<void> _savePreferences(
    AppSettings settings,
    int generation, {
    String? themeMode,
  }) {
    _data.settingsSaveRevision++;
    return _data.mutate(() async {
      if (!mounted ||
          _restoreRecoveryRequired ||
          generation != _data.generation) {
        throw StaleSettingsOperation();
      }
      if (themeMode != null) {
        settings = _data.settings.copyWith(themeMode: themeMode);
      }
      await LocalStorage.saveSettings(settings);
      if (!mounted) return;
      // Commit every successful write: backups and failed later saves must see
      // the last durable settings. Storage and UI commits share the queue.
      setState(() => _data.settings = settings);
      CurrencyFormatter.current = settings.currency;
      widget.onThemeModeChanged?.call(
        themeModeFromSettings(settings.themeMode),
      );
    });
  }

  Future<void> _savePreferencesWithFeedback(
    AppSettings settings,
    int generation,
  ) async {
    final operation = _savePreferences(settings, generation);
    final revision = _data.settingsSaveRevision;
    try {
      await operation;
    } catch (error) {
      if (!mounted ||
          generation != _data.generation ||
          revision != _data.settingsSaveRevision) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save settings. Please try again.'),
        ),
      );
    }
  }

  bool _backupSessionIsCurrent(int session, int generation) =>
      mounted &&
      !_restoreRecoveryRequired &&
      _foreground &&
      _lockState == AppLockInitializationState.unlocked &&
      _lockSession == session &&
      _data.generation == generation;

  Future<void> _createBackup() async {
    final session = _lockSession;
    final generation = _data.generation;
    bool isCurrent() => _backupSessionIsCurrent(session, generation);
    if (!mounted || !isCurrent()) return;
    try {
      final file = await BriskaBackupService.createBackupFile(
        settings: _data.settings,
        workEntries: _data.entries,
        exportRecords: _data.exports,
      );
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup saved: ${file.uri.pathSegments.last}')),
      );
      await BriskaBackupService.shareBackup(file);
    } catch (error, stackTrace) {
      debugPrint('backup failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create Briska Pay backup.')),
      );
    }
  }

  Future<void> _restoreBackup() async {
    final session = _lockSession;
    final generation = _data.generation;
    if (_restoreInProgress || !_backupSessionIsCurrent(session, generation)) {
      return;
    }
    _restoreInProgress = true;
    try {
      await _data.mutate(() => _restoreBackupInQueue(session, generation));
    } finally {
      _restoreInProgress = false;
    }
  }

  Future<void> _restoreBackupInQueue(int session, int generation) async {
    bool isCurrent() => _backupSessionIsCurrent(session, generation);
    if (!mounted || !isCurrent()) return;
    try {
      final file = await BriskaBackupService.pickBackupFile();
      // Android may return the selected file before Flutter resumes.
      // Wait briefly for foreground restoration, but never bypass App Lock.
      if (file != null && mounted && !_foreground) {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (mounted &&
            !_foreground &&
            !_restoreRecoveryRequired &&
            _lockState == AppLockInitializationState.unlocked &&
            _lockSession == session &&
            _data.generation == generation &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      if (!mounted || !isCurrent()) return;
      if (file == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Restore cancelled.')));
        return;
      }
      final preview = await BriskaBackupService.previewFile(file);
      if (!mounted || !isCurrent()) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore Briska Pay backup?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewLine(
                label: 'Backup date',
                value: formatDateTime(preview.createdAt),
              ),
              _PreviewLine(
                label: 'User',
                value: preview.userName.isEmpty
                    ? 'Not provided'
                    : preview.userName,
              ),
              _PreviewLine(
                label: 'Employer / company',
                value: preview.companyName.isEmpty
                    ? 'Not provided'
                    : preview.companyName,
              ),
              _PreviewLine(
                label: 'Entries',
                value: preview.entryCount.toString(),
              ),
              _PreviewLine(
                label: 'Exports',
                value: preview.exportCount.toString(),
              ),
              const SizedBox(height: 12),
              const Text(
                'This will replace current Briska Pay data. A safety backup will be created first.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !isCurrent()) return;
      await BriskaBackupService.createBackupFile(
        settings: _data.settings,
        workEntries: _data.entries,
        exportRecords: _data.exports,
      );
      if (!mounted || !isCurrent()) return;
      await LocalStorage.replaceAll(
        validateOperation: () {
          if (!isCurrent()) throw const LocalRestoreException();
        },
        settings: preview.data.settings,
        entries: preview.data.workEntries,
        exportRecords: preview.data.exportRecords,
      );
      if (!mounted) return;
      if (!isCurrent()) {
        // Commit may finish while locking. Never resume with the old datasets.
        _requireRestoreRecovery(const LocalRestoreRecoveryRequiredException());
        return;
      }
      _data.generation++;
      _data.settingsSaveRevision++;
      setState(() {
        _data.settings = preview.data.settings;
        CurrencyFormatter.current = _data.settings.currency;
        _data.entries = List.of(preview.data.workEntries);
        _data.exports = List.of(preview.data.exportRecords);
        _index = 0;
      });
      widget.onThemeModeChanged?.call(
        themeModeFromSettings(_data.settings.themeMode),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Briska Pay backup restored.')),
      );
    } on LocalRestoreRecoveryRequiredException catch (error) {
      _requireRestoreRecovery(error);
    } on LocalRestoreRollbackException catch (error) {
      if (kDebugMode) debugPrint('restore rollback failed');
      _requireRestoreRecovery(error);
    } on BriskaBackupException catch (error) {
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error, stackTrace) {
      debugPrint('restore failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not restore this backup. Your existing data has been kept.',
          ),
        ),
      );
    }
  }

  Future<void> _updateLockConfig(AppLockConfig config) async {
    await AppLockService.saveConfig(config);
    if (!mounted) return;
    setState(() {
      _lockConfig = config.copyWith(hasPin: _lockConfig.hasPin);
      _lockState =
          config.enabled && _lockState == AppLockInitializationState.locked
          ? AppLockInitializationState.locked
          : AppLockInitializationState.unlocked;
    });
  }

  Future<void> _setLockPin(String pin, String? currentPin) async {
    await AppLockService.setPin(pin, currentPin: currentPin);
    if (mounted) {
      setState(() => _lockConfig = _lockConfig.copyWith(hasPin: true));
    }
  }

  Future<void> _disableLock(String pin) async {
    final disabled = _lockConfig.copyWith(enabled: false);
    await AppLockService.saveConfig(disabled, currentPin: pin);
    if (!mounted) return;
    setState(() => _lockConfig = disabled);
  }

  void _handleUnlocked(int session) {
    if (!mounted ||
        session != _lockSession ||
        _lockState != AppLockInitializationState.locked) {
      return;
    }
    if (!_foreground) {
      _pendingUnlockSession = session;
      return;
    }
    setState(() => _lockState = AppLockInitializationState.unlocked);
  }

  void _beginConsentHandling() {
    if (_consentGateState != AdvertisingConsentGateState.waiting) return;
    _consentGateState = AdvertisingConsentGateState.checking;
    unawaited(_handleAdvertisingConsent());
  }

  Future<void> _handleAdvertisingConsent() async {
    final result = await _advertising.resolveConsent();
    if (!mounted) return;
    setState(() {
      _homeBannerEligible = result.bannerEligible;
      _privacyOptionsRequirement = result.privacyRequirement;
      _consentGateState = AdvertisingConsentGateState.complete;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('BriskaShell build');
    if (!_storedStateLoaded ||
        _lockState == AppLockInitializationState.loading) {
      return const StartupInitializationScreen();
    }
    if (_lockState == AppLockInitializationState.failed) {
      return AppLockInitializationErrorScreen(onRetry: _loadLockConfig);
    }
    if (_lockState == AppLockInitializationState.locked) {
      final session = _lockSession;
      return AppLockScreen(
        sessionId: session,
        onDeviceAuthenticationChanged: (active) =>
            _deviceAuthenticationActive = active,
        config: _lockConfig,
        onUnlocked: () => _handleUnlocked(session),
        verifyPin: widget.pinVerifier,
        authenticateWithBiometrics: widget.biometricAuthenticator,
        deviceAuthenticationAvailabilityChecker:
            widget.deviceAuthenticationAvailabilityChecker,
      );
    }
    if (_startupError != null) {
      return StartupRecoveryScreen(
        error: _startupError!,
        dataIsCorrupt: _startupDataIsCorrupt,
        restoreRecoveryRequired: _restoreRecoveryRequired,
        onRetry: _loadStoredState,
        onRestoreBackup: _restoreBackup,
        onResetLocalData: _resetLocalDataAfterConfirmation,
      );
    }
    if (!_data.settings.onboardingCompleted) {
      final onboardingGeneration = _data.generation;
      return OnboardingScreen(
        initialSettings: _data.settings,
        onComplete: (settings) =>
            _savePreferences(settings, onboardingGeneration),
      );
    }
    if (_consentGateState == AdvertisingConsentGateState.waiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _lockState == AppLockInitializationState.unlocked &&
            _data.settings.onboardingCompleted) {
          _beginConsentHandling();
        }
      });
    }
    // Keep callbacks held by dialogs/file operations tied to their original data.
    final exportGeneration = _data.generation;
    final session = _lockSession;
    // Async completions can run between a navigation/security change and the
    // next build. Check live shell state as well as the child's active flag.
    bool canPresentTab(int index) =>
        mounted &&
        _lockState == AppLockInitializationState.unlocked &&
        _lockSession == session &&
        _data.generation == exportGeneration &&
        _index == index;
    final screens = [
      HomeScreen(
        entries: _data.entries,
        settings: _data.settings,
        onViewEntries: () => _selectTab(1),
        onAddEntry: _showAddDay,
        onOpenCalendar: () => _selectTab(1),
        onOpenReports: () => _selectTab(2),
        onOpenExport: () => _selectTab(3),
        onConfigurePayday: () => _selectTab(4),
        onEditEntry: _showAddDay,
      ),
      EntriesScreen(
        entries: _data.entries,
        settings: _data.settings,
        onEdit: _showAddDay,
        onAddDate: (date) => _showAddDay(null, date),
        onDelete: (entry) => _deleteEntry(entry, exportGeneration),
      ),
      ProfessionalReportsScreen(
        entries: _data.entries,
        settings: _data.settings,
      ),
      ExportScreen(
        isActive: _index == 3,
        canPresent: () => canPresentTab(3),
        actionOverrides: widget.exportActionOverrides,
        entries: _data.entries,
        fullName: _data.settings.fullName,
        companyName: _data.settings.companyName,
        settings: _data.settings,
        records: _data.exports,
        onPreferencesChanged: (value) =>
            _savePreferencesWithFeedback(value, exportGeneration),
        onAdd: (record) =>
            _changeExportRecord(record, exportGeneration, add: true),
        onDelete: (record) =>
            _changeExportRecord(record, exportGeneration, delete: true),
        onUpdate: (record) => _changeExportRecord(record, exportGeneration),
      ),
      SettingsScreen(
        isActive: _index == 4,
        canPresent: () => canPresentTab(4),
        key: ValueKey(_data.generation),
        preferences: _data.settings,
        lockConfig: _lockConfig,
        onCreateBackup: _createBackup,
        onRestoreBackup: _restoreBackup,
        onLockConfigChanged: _updateLockConfig,
        onSetLockPin: _setLockPin,
        onDisableLock: _disableLock,
        onShowAbout: () => Navigator.of(
          context,
        ).push(BriskaPageRoute(child: const AboutBriskaScreen())),
        onPreferencesChanged: (value) =>
            _savePreferences(value, exportGeneration),
        onThemeModeChanged: (mode) async {
          final value = _data.settings.copyWith(
            themeMode: themeModeToSettings(mode),
          );
          await _savePreferences(
            value,
            exportGeneration,
            themeMode: themeModeToSettings(mode),
          );
        },
        deviceAuthenticationAvailabilityChecker:
            widget.deviceAuthenticationAvailabilityChecker,
        privacyOptionsRequired:
            _privacyOptionsRequirement == PrivacyOptionsRequirement.required,
        onShowAdvertisingPrivacyChoices:
            _adsConsentCoordinator.showPrivacyOptions,
      ),
    ];

    final scaffold = Scaffold(
      appBar: null,
      body: Column(
        children: [
          Expanded(
            child: RetainedTabs(
              key: ValueKey(_data.generation),
              index: _index,
              children: screens,
            ),
          ),
          if (_homeBannerEligible)
            BriskaBannerAd(
              key: const ValueKey('main-shell-banner'),
              adsService: _adsService,
            ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddDay,
              tooltip: 'Add Day',
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Day'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: BriskaShadows.card(
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectTab,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined, size: BriskaIcons.size),
                  selectedIcon: Icon(
                    Icons.home_rounded,
                    size: BriskaIcons.size,
                  ),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.calendar_view_day_outlined,
                    size: BriskaIcons.size,
                  ),
                  selectedIcon: Icon(
                    Icons.calendar_view_day_rounded,
                    size: BriskaIcons.size,
                  ),
                  label: 'Entries',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined, size: BriskaIcons.size),
                  selectedIcon: Icon(
                    Icons.bar_chart_rounded,
                    size: BriskaIcons.size,
                  ),
                  label: 'Reports',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.file_download_outlined,
                    size: BriskaIcons.size,
                  ),
                  selectedIcon: Icon(
                    Icons.file_download_rounded,
                    size: BriskaIcons.size,
                  ),
                  label: 'Export',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined, size: BriskaIcons.size),
                  selectedIcon: Icon(
                    Icons.settings_rounded,
                    size: BriskaIcons.size,
                  ),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return PopScope<void>(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && ModalRoute.of(context)?.isCurrent == true) {
          _selectTab(0);
        }
      },
      child: scaffold,
    );
  }

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
