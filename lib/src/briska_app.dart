
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'ads/ads_configuration.dart';
import 'ads/ads_consent_coordinator.dart';
import 'ads/briska_banner_ad.dart';
import 'ads/ads_service.dart';
import 'app_lock_service.dart';
import 'app_theme.dart';
import 'backup_service.dart';
import 'csv_export_service.dart';
import 'currency.dart';
import 'display_format.dart';
import 'excel_export_service.dart';
import 'export_formats.dart';
import 'local_storage.dart';
import 'models.dart';
import 'pdf_export_service.dart';
import 'pay_schedule.dart';
import 'release_info.dart';
import 'site_name_suggestions.dart';
import 'support_service.dart';
import 'work_calculator.dart';
import 'premium_home_screen.dart';
import '../design_system/briska_colors.dart';
import '../design_system/briska_cards.dart';
import '../design_system/briska_icons.dart';
import '../design_system/briska_radius.dart';
import '../design_system/briska_spacing.dart';
import '../design_system/briska_theme.dart';
import '../features/export/models/export_config.dart';
import '../features/export/services/export_filename_service.dart';

part 'screens/about_screen.dart';
part 'screens/legal_text_screen.dart';
part 'screens/support_screen.dart';
part 'screens/beta_checklist_screen.dart';
part 'screens/startup_recovery_screen.dart';
part 'screens/startup_initialization_screen.dart';
part 'screens/app_lock_initialization_error_screen.dart';
part 'screens/app_lock_screen.dart';
part 'screens/onboarding_screen.dart';
part 'screens/reports_screen.dart';
part 'screens/professional_reports_screen.dart';
part 'screens/entries_screen.dart';

String get _currencyPrefix => '${CurrencyFormatter.current.symbol}  ';
String _money(double value, [CurrencyConfig? currency]) =>
    CurrencyFormatter.format(value, currency);
String _currencyInputValue(double value) =>
    value == 0 ? '' : value.toStringAsFixed(2);

String _formatFileSize(int? bytes) {
  if (bytes == null) return 'Size unavailable';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

enum ExportFileAction { open, share, rename, print, delete }

String exportFileActionFailureMessage(ExportFileAction action) =>
    switch (action) {
      ExportFileAction.open => 'Could not open this export.',
      ExportFileAction.share => 'Could not share this export.',
      ExportFileAction.rename => 'Could not rename this export.',
      ExportFileAction.print => 'Could not print this export.',
      ExportFileAction.delete => 'Could not delete this export.',
    };

String exportCreationFailureMessage(Object error) =>
    error is FileSystemException
    ? 'The report was generated, but the file could not be saved.'
    : 'Could not generate the report.';

ThemeMode themeModeFromSettings(String value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.light,
  };
}

String themeModeToSettings(ThemeMode value) {
  return switch (value) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'light',
  };
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _fullMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _dayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
String _weekdayName(DateTime date) => _weekdayNames[date.weekday - 1];
String _payPeriodLabel(PayPeriodRange period) => period.periodLabel;
String _dateTimeLabel(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.day} ${_monthNames[date.month - 1]} ${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

String _entryTitle(WorkEntry entry) => entry.siteName.isNotEmpty
    ? entry.siteName
    : entry.entryType == 'Holiday'
    ? 'Holiday'
    : entry.type == EntryType.bankHoliday
    ? 'Bank Holiday'
    : entry.entryType == 'UnpaidDayOff'
    ? 'Unpaid day off'
    : entry.entryType == 'SickDay'
    ? (entry.isPaidSickDay ? 'Paid Sick Day' : 'Unpaid Sick Day')
    : 'Untitled work day';
PayPeriodRange _currentWeekPeriod(DateTime date) {
  final today = DateTime(date.year, date.month, date.day);
  final start = today.subtract(Duration(days: today.weekday - 1));
  final end = start.add(const Duration(days: 6));
  return PayPeriodRange(
    start: start,
    end: end,
    payday: end,
    periodLabel: 'Current week',
  );
}

List<WorkEntry> _entriesInPeriod(
  Iterable<WorkEntry> entries,
  PayPeriodRange period,
) => entries.where((entry) => period.contains(entry.date)).toList();

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
    this.pinVerifier,
    this.biometricAuthenticator,
    this.deviceAuthenticationAvailabilityChecker,
    this.adsConsentCoordinator,
    this.adsService,
    super.key,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final List<WorkEntry> initialEntries;
  final AppSettings initialSettings;
  final List<ExportedFileRecord> initialExports;
  final bool useLocalStorage;
  final Future<AppLockConfig> Function()? appLockConfigLoader;
  final Future<bool> Function(String pin)? pinVerifier;
  final Future<bool> Function()? biometricAuthenticator;
  final Future<bool> Function()? deviceAuthenticationAvailabilityChecker;
  final AdsConsentCoordinator? adsConsentCoordinator;
  final AdsService? adsService;

  @override
  State<BriskaShell> createState() => _BriskaShellState();
}

class _BriskaShellState extends State<BriskaShell> with WidgetsBindingObserver {
  static const _consentOperationTimeout = Duration(seconds: 15);
  int _index = 0;
  late AppSettings _preferences;
  late List<WorkEntry> _entries;
  late List<ExportedFileRecord> _exportRecords;
  AppLockConfig _lockConfig = const AppLockConfig();
  AppLockInitializationState _lockState = AppLockInitializationState.loading;
  late bool _storedStateLoaded;
  DateTime? _backgroundedAt;
  String? _startupError;
  bool _startupDataIsCorrupt = false;
  bool _restoreRecoveryRequired = false;
  bool _restoreInProgress = false;
  Future<void> _preferencesSaveQueue = Future<void>.value();
  int _preferencesSaveRevision = 0;
  late final AdsConsentCoordinator _adsConsentCoordinator;
  late final AdsService _adsService;
  late final Future<bool> _adsInitializationReady;
  late final Future<bool> _consentUpdateReady;
  AdvertisingConsentGateState _consentGateState =
      AdvertisingConsentGateState.waiting;
  PrivacyOptionsRequirement _privacyOptionsRequirement =
      PrivacyOptionsRequirement.unknown;
  bool _homeBannerEligible = false;
  final Set<Timer> _optionalOperationTimers = {};

  @override
  void initState() {
    super.initState();
    _preferences = widget.initialSettings;
    CurrencyFormatter.current = _preferences.currency;
    _entries = widget.initialEntries
        .map(WorkCalculator.recalculateEntry)
        .toList();
    _exportRecords = List.of(widget.initialExports);
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
    _adsInitializationReady = _initializeAdsEarly();
    _consentUpdateReady = _updateConsentEarly();
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
    for (final timer in _optionalOperationTimers) {
      timer.cancel();
    }
    _optionalOperationTimers.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<T> _withOptionalOperationTimeout<T>(Future<T> operation) {
    final completer = Completer<T>();
    late final Timer timer;
    timer = Timer(_consentOperationTimeout, () {
      _optionalOperationTimers.remove(timer);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException(
            'Optional startup operation timed out.',
            _consentOperationTimeout,
          ),
        );
      }
    });
    _optionalOperationTimers.add(timer);
    operation.then(
      (value) {
        timer.cancel();
        _optionalOperationTimers.remove(timer);
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        _optionalOperationTimers.remove(timer);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  Future<bool> _initializeAdsEarly() async {
    try {
      await _withOptionalOperationTimeout(_adsService.initialize());
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('advertising SDK initialisation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return false;
    }
  }

  Future<bool> _updateConsentEarly() async {
    try {
      await _withOptionalOperationTimeout(
        _adsConsentCoordinator.updateConsentInformation(),
      );
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('advertising consent update failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lockState == AppLockInitializationState.loading ||
        _lockState == AppLockInitializationState.failed ||
        !_lockConfig.enabled) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed && _backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!).inSeconds;
      if (elapsed >= _lockConfig.lockAfterSeconds) {
        setState(() => _lockState = AppLockInitializationState.locked);
      }
      _backgroundedAt = null;
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

  Future<void> _loadStoredState() async {
    if (kDebugMode) debugPrint('storage initialisation started');
    try {
      final results = await Future.wait([
        LocalStorage.loadEntries(),
        LocalStorage.loadSettings(),
        LocalStorage.loadExportRecords(),
      ]);
      if (kDebugMode) debugPrint('storage initialisation completed');
      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<WorkEntry>;
        _preferences = results[1] as AppSettings;
        _exportRecords = results[2] as List<ExportedFileRecord>;
        _startupError = null;
        _startupDataIsCorrupt = false;
        _restoreRecoveryRequired = false;
        _storedStateLoaded = true;
        CurrencyFormatter.current = _preferences.currency;
      });
      widget.onThemeModeChanged?.call(
        themeModeFromSettings(_preferences.themeMode),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('storage initialisation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted) return;
      setState(() {
        _startupError = error.toString();
        _startupDataIsCorrupt = error is LocalDataCorruptionException;
        _storedStateLoaded = true;
      });
    }
  }

  Future<void> _resetLocalDataAfterConfirmation() async {
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
    if (!mounted) return;
    setState(() {
      _preferences = const AppSettings();
      _entries = [];
      _exportRecords = [];
      _startupError = null;
      _startupDataIsCorrupt = false;
      _restoreRecoveryRequired = false;
      _index = 0;
    });
    widget.onThemeModeChanged?.call(ThemeMode.system);
  }

  void _showAddDay([WorkEntry? entry, DateTime? initialDate]) {
    Navigator.of(context).push(
      _BriskaPageRoute(
        child: AddWorkDayScreen(
          preferences: _preferences,
          savedEntries: _entries,
          initialEntry: entry,
          initialDate: initialDate,
          onSave: _saveEntry,
        ),
      ),
    );
  }

  Future<bool> _saveEntry(WorkEntry entry) async {
    final calculatedEntry = WorkCalculator.recalculateEntry(entry);
    final updatedEntries = List<WorkEntry>.of(_entries);
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
      setState(() => _entries = updatedEntries);
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

  Future<void> _deleteEntry(WorkEntry entry) async {
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
            "This can't be undone.",
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
                  backgroundColor: AppColors.danger,
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

    final updatedEntries = List<WorkEntry>.of(_entries)
      ..removeWhere((item) => item.id == entry.id);
    try {
      await LocalStorage.saveEntries(updatedEntries);
      if (!mounted) return;
      setState(() => _entries = updatedEntries);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Day deleted.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoDeleteEntry(entry),
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

  Future<void> _undoDeleteEntry(WorkEntry entry) async {
    final restoredEntries = List<WorkEntry>.of(_entries);
    if (restoredEntries.any((item) => item.id == entry.id)) return;
    restoredEntries
      ..add(entry)
      ..sort((a, b) => b.date.compareTo(a.date));
    try {
      await LocalStorage.saveEntries(restoredEntries);
      if (!mounted) return;
      setState(() => _entries = restoredEntries);
    } catch (error, stackTrace) {
      debugPrint('entry delete undo save failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore this day.')),
      );
    }
  }

  Future<void> _savePreferences(AppSettings settings) async {
    final revision = ++_preferencesSaveRevision;
    final operation = _preferencesSaveQueue.then(
      (_) => LocalStorage.saveSettings(settings),
    );
    _preferencesSaveQueue = operation.then<void>((_) {}, onError: (_, _) {});
    await operation;
    if (!mounted || revision != _preferencesSaveRevision) return;
    setState(() => _preferences = settings);
    CurrencyFormatter.current = settings.currency;
  }

  Future<void> _savePreferencesSilently(AppSettings settings) async {
    try {
      await _savePreferences(settings);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('settings save failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _createBackup() async {
    try {
      final file = await BriskaBackupService.createBackupFile(
        settings: _preferences,
        workEntries: _entries,
        exportRecords: _exportRecords,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup saved: ${file.uri.pathSegments.last}')),
      );
      await BriskaBackupService.shareBackup(file);
    } catch (error, stackTrace) {
      debugPrint('backup failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create Briska Pay backup.')),
      );
    }
  }

  Future<void> _restoreBackup() async {
    if (_restoreInProgress) return;
    _restoreInProgress = true;
    try {
      final file = await BriskaBackupService.pickBackupFile();
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Restore cancelled.')));
        return;
      }
      final preview = await BriskaBackupService.previewFile(file);
      if (!mounted) return;
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
                value: _dateTimeLabel(preview.createdAt),
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
      if (confirmed != true) return;
      await BriskaBackupService.createBackupFile(
        settings: _preferences,
        workEntries: _entries,
        exportRecords: _exportRecords,
      );
      await LocalStorage.replaceAll(
        settings: preview.data.settings,
        entries: preview.data.workEntries,
        exportRecords: preview.data.exportRecords,
      );
      if (!mounted) return;
      setState(() {
        _preferences = preview.data.settings;
        _entries = List.of(preview.data.workEntries);
        _exportRecords = List.of(preview.data.exportRecords);
        _index = 0;
      });
      widget.onThemeModeChanged?.call(
        themeModeFromSettings(_preferences.themeMode),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Briska Pay backup restored.')),
      );
    } on LocalRestoreRollbackException catch (error) {
      if (kDebugMode) debugPrint('restore rollback failed');
      if (!mounted) return;
      setState(() {
        _startupError = error.toString();
        _startupDataIsCorrupt = false;
        _restoreRecoveryRequired = true;
      });
    } on BriskaBackupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error, stackTrace) {
      debugPrint('restore failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not restore this backup. Your existing data has been kept.',
          ),
        ),
      );
    } finally {
      _restoreInProgress = false;
    }
  }

  Future<void> _updateLockConfig(AppLockConfig config) async {
    await AppLockService.saveConfig(config);
    if (!mounted) return;
    setState(() {
      _lockConfig = config;
      _lockState =
          config.enabled && _lockState == AppLockInitializationState.locked
          ? AppLockInitializationState.locked
          : AppLockInitializationState.unlocked;
    });
  }

  Future<void> _setLockPin(String pin) async {
    await AppLockService.setPin(pin);
    final updated = (await AppLockService.loadConfig()).copyWith(hasPin: true);
    await _updateLockConfig(updated);
  }

  void _handleUnlocked() =>
      setState(() => _lockState = AppLockInitializationState.unlocked);

  void _beginConsentHandling() {
    if (_consentGateState != AdvertisingConsentGateState.waiting) return;
    _consentGateState = AdvertisingConsentGateState.checking;
    unawaited(_handleAdvertisingConsent());
  }

  Future<void> _handleAdvertisingConsent() async {
    var canRequestAds = false;
    var privacyRequirement = PrivacyOptionsRequirement.unknown;
    try {
      if (!await _consentUpdateReady) {
        throw StateError('Advertising consent information is unavailable.');
      }
      final formRequirement = await _withOptionalOperationTimeout(
        _adsConsentCoordinator.consentFormRequirement(),
      );
      if (formRequirement == ConsentFormRequirement.required) {
        await _adsConsentCoordinator.showRequiredConsentForm();
      }
      canRequestAds = await _withOptionalOperationTimeout(
        _adsConsentCoordinator.canRequestAds(),
      );
      privacyRequirement = await _withOptionalOperationTimeout(
        _adsConsentCoordinator.privacyOptionsRequirement(),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('advertising consent handling failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      canRequestAds = false;
    }

    if (canRequestAds) {
      try {
        _homeBannerEligible =
            await _adsInitializationReady &&
            await _adsService.capability() != AdsCapability.unavailable;
      } catch (error, stackTrace) {
        _homeBannerEligible = false;
        if (kDebugMode) {
          debugPrint('advertising SDK initialisation failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _privacyOptionsRequirement = privacyRequirement;
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
      return AppLockScreen(
        config: _lockConfig,
        onUnlocked: _handleUnlocked,
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
    if (!_preferences.onboardingCompleted) {
      return OnboardingScreen(
        initialSettings: _preferences,
        onComplete: (settings) {
          setState(() => _preferences = settings);
          _savePreferencesSilently(settings);
          widget.onThemeModeChanged?.call(
            themeModeFromSettings(settings.themeMode),
          );
        },
      );
    }
    if (_consentGateState == AdvertisingConsentGateState.waiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _lockState == AppLockInitializationState.unlocked &&
            _preferences.onboardingCompleted) {
          _beginConsentHandling();
        }
      });
    }
    final screens = [
      HomeScreen(
        entries: _entries,
        settings: _preferences,
        onViewEntries: () => setState(() => _index = 1),
        onAddEntry: _showAddDay,
        onOpenCalendar: () => setState(() => _index = 1),
        onOpenReports: () => setState(() => _index = 2),
        onOpenExport: () => setState(() => _index = 3),
        onConfigurePayday: () => setState(() => _index = 4),
        onEditEntry: _showAddDay,
      ),
      EntriesScreen(
        entries: _entries,
        settings: _preferences,
        onEdit: _showAddDay,
        onAddDate: (date) => _showAddDay(null, date),
        onDelete: _deleteEntry,
      ),
      ProfessionalReportsScreen(entries: _entries, settings: _preferences),
      ExportScreen(
        entries: _entries,
        fullName: _preferences.fullName,
        companyName: _preferences.companyName,
        settings: _preferences,
        records: _exportRecords,
        onPreferencesChanged: (value) {
          setState(() => _preferences = value);
          _savePreferencesSilently(value);
        },
        onAdd: (record) {
          setState(() => _exportRecords.insert(0, record));
          LocalStorage.saveExportRecords(_exportRecords);
        },
        onDelete: (record) {
          setState(() => _exportRecords.removeWhere((e) => e.id == record.id));
          LocalStorage.saveExportRecords(_exportRecords);
        },
        onUpdate: (record) => setState(() {
          final index = _exportRecords.indexWhere((e) => e.id == record.id);
          if (index != -1) _exportRecords[index] = record;
          LocalStorage.saveExportRecords(_exportRecords);
        }),
      ),
      SettingsScreen(
        preferences: _preferences,
        lockConfig: _lockConfig,
        onCreateBackup: _createBackup,
        onRestoreBackup: _restoreBackup,
        onLockConfigChanged: _updateLockConfig,
        onSetLockPin: _setLockPin,
        onShowAbout: () => Navigator.of(
          context,
        ).push(_BriskaPageRoute(child: const AboutBriskaScreen())),
        onPreferencesChanged: _savePreferences,
        onThemeModeChanged: (mode) async {
          final value = _preferences.copyWith(
            themeMode: themeModeToSettings(mode),
          );
          await _savePreferences(value);
          widget.onThemeModeChanged?.call(mode);
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
            child: AnimatedSwitcher(
              duration: BriskaDurations.emphasis,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final reduceMotion = MediaQuery.disableAnimationsOf(context);
                if (reduceMotion) return child;
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: .985,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_index),
                child: screens[_index],
              ),
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
              onDestinationSelected: (value) => setState(() => _index = value),
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
    return scaffold;
  }
}

class _BriskaPageRoute<T> extends PageRouteBuilder<T> {
  _BriskaPageRoute({required Widget child})
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

class LegacyHomeScreen extends StatelessWidget {
  const LegacyHomeScreen({
    required this.entries,
    required this.settings,
    required this.onViewEntries,
    required this.onAddEntry,
    required this.onOpenCalendar,
    required this.onOpenReports,
    required this.onOpenExport,
    required this.onConfigurePayday,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;
  final VoidCallback onViewEntries;
  final VoidCallback onAddEntry;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenExport;
  final VoidCallback onConfigurePayday;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('HomeScreen build');
    final now = DateTime.now();
    final period = getCurrentPayPeriodForSettings(
      date: now,
      settings: settings,
    );
    final periodEntries = _entriesInPeriod(entries, period);
    final periodSummary = WorkCalculator.summarize(periodEntries);
    final today = DateTime(now.year, now.month, now.day);
    final todaySummary = WorkCalculator.summarize(
      entries.where(
        (entry) =>
            entry.date.year == today.year &&
            entry.date.month == today.month &&
            entry.date.day == today.day,
      ),
    );
    final nextPayday = period.payday.isBefore(today)
        ? getCurrentPayPeriodForSettings(
            date: period.end.add(const Duration(days: 1)),
            settings: settings,
          ).payday
        : period.payday;
    final userName = settings.fullName.trim().isEmpty
        ? 'there'
        : settings.fullName.trim().split(RegExp(r'\s+')).first;
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greetingFor(now),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userName,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const BriskaLogo(size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Briska Pay',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Track your hours. Know your pay.',
                    style: TextStyle(color: Colors.transparent, fontSize: 1),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          EntranceAnimation(
            child: PayPeriodCard(entries: entries, settings: settings),
          ),
          const SizedBox(height: 16),
          EntranceAnimation(
            delay: Duration(milliseconds: 70),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  MiniSummaryCard(
                    icon: Icons.schedule_rounded,
                    label: 'Hours',
                    value: periodSummary.totalDays == 0
                        ? '0h'
                        : formatHoursLabel(periodSummary.totalHours),
                    detail: 'Pay period',
                  ),
                  MiniSummaryCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Next payday',
                    value: nextPayday.day.toString(),
                    detail: _monthNames[nextPayday.month - 1],
                  ),
                  MiniSummaryCard(
                    icon: Icons.work_history_outlined,
                    label: 'Work days',
                    value: periodSummary.entries
                        .where((entry) => entry.entryType == 'WorkDay')
                        .length
                        .toString(),
                    detail: todaySummary.totalExpectedPay == 0
                        ? 'Today'
                        : '+${_money(todaySummary.totalExpectedPay)}',
                  ),
                  MiniSummaryCard(
                    icon: Icons.sick_outlined,
                    label: 'Sick days',
                    value: periodSummary.sickDays.toString(),
                    detail:
                        '${periodSummary.paidSickDays} paid · ${periodSummary.unpaidSickDays} unpaid',
                  ),
                ];
                if (constraints.maxWidth < 520) {
                  return Row(
                    children: [
                      for (final item in cards) ...[
                        Expanded(child: item),
                        if (item != cards.last) const SizedBox(width: 8),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (final item in cards) ...[
                      Expanded(child: item),
                      if (item != cards.last) const SizedBox(width: 16),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          SectionHeading(
            title: 'Recent work',
            action: 'View all',
            onTap: onViewEntries,
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const EmptyWorkState()
          else
            ...entries
                .take(3)
                .toList()
                .asMap()
                .entries
                .map(
                  (item) => EntranceAnimation(
                    delay: Duration(milliseconds: 120 + (item.key * 55)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: WorkEntryCard(
                        entry: item.value,
                        compact: true,
                        settings: settings,
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

String _greetingFor(DateTime date) {
  if (date.hour < 12) return 'Good morning';
  if (date.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class PayPeriodCard extends StatelessWidget {
  const PayPeriodCard({
    required this.entries,
    required this.settings,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final period = getCurrentPayPeriodForSettings(
      date: now,
      settings: settings,
    );
    final periodStart = period.start;
    final periodEnd = period.end;
    final today = DateTime(now.year, now.month, now.day);
    final nextPaydayPeriod = period.payday.isBefore(today)
        ? getCurrentPayPeriodForSettings(
            date: periodEnd.add(const Duration(days: 1)),
            settings: settings,
          )
        : period;
    final nextPayday = nextPaydayPeriod.payday;
    final periodDays = periodEnd.difference(periodStart).inDays + 1;
    final elapsedDays = now.difference(periodStart).inDays + 1;
    final progress = (elapsedDays / periodDays).clamp(0.0, 1.0);
    final daysToPayday = nextPayday.difference(today).inDays;
    final periodEntries = _entriesInPeriod(entries, period);
    final summary = WorkCalculator.summarize(periodEntries);
    final todaySummary = WorkCalculator.summarize(
      entries.where(
        (entry) =>
            entry.date.year == today.year &&
            entry.date.month == today.month &&
            entry.date.day == today.day,
      ),
    );
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Card(
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Current Pay',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${periodStart.day} ${_monthNames[periodStart.month - 1]} - '
                          '${periodEnd.day} ${_monthNames[periodEnd.month - 1]}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (summary.entries.isNotEmpty) ...[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: BriskaAnimatedText(
                      _money(summary.totalExpectedPay),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: compact ? 34 : 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    todaySummary.totalExpectedPay == 0
                        ? 'No earnings recorded today'
                        : '+${_money(todaySummary.totalExpectedPay)} today',
                    style: TextStyle(
                      color: todaySummary.totalExpectedPay == 0
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Icon(
                        Icons.work_outline_rounded,
                        color: colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'No work recorded yet',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: compact ? 18 : 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Add your first work day to see hours and estimated pay.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pay Period Progress',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${elapsedDays.clamp(1, periodDays)} of $periodDays days',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.primary.withValues(alpha: .12),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(compact ? 14 : 16),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next Payday',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_weekdayName(nextPayday)}, ${nextPayday.day} '
                              '${_fullMonthNames[nextPayday.month - 1]}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          daysToPayday == 0 ? 'Today' : '$daysToPayday days',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MiniSummaryCard extends StatelessWidget {
  const MiniSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            if (value == null)
              Text('No entries', style: Theme.of(context).textTheme.titleMedium)
            else ...[
              BriskaAnimatedText(
                value!,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 18),
              ),
              Text(
                detail!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MonthlyCalendarSection extends StatefulWidget {
  const MonthlyCalendarSection({
    required this.entries,
    required this.settings,
    required this.onEditEntry,
    required this.onAddDate,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;
  final ValueChanged<WorkEntry> onEditEntry;
  final ValueChanged<DateTime> onAddDate;

  @override
  State<MonthlyCalendarSection> createState() => _MonthlyCalendarSectionState();
}

class _MonthlyCalendarSectionState extends State<MonthlyCalendarSection> {
  late DateTime _month;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _moveMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = null;
    });
  }

  void _showCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = monthStart.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final byDay = <int, List<WorkEntry>>{};
    for (final entry in widget.entries) {
      if (entry.date.year == _month.year && entry.date.month == _month.month) {
        byDay.putIfAbsent(entry.date.day, () => []).add(entry);
      }
    }
    final monthEntries = byDay.values.expand((items) => items);
    final summary = WorkCalculator.summarize(monthEntries);
    final currentPayPeriod = getCurrentPayPeriodForSettings(
      date: DateTime.now(),
      settings: widget.settings,
    );
    final selectedEntries = _selectedDay == null
        ? const <WorkEntry>[]
        : byDay[_selectedDay!.day] ?? const <WorkEntry>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final padding = compact ? 12.0 : 18.0;
        final gridGap = compact ? 3.0 : 5.0;
        const minimumDateCellExtent = 48.0;
        final minimumCalendarWidth =
            (minimumDateCellExtent * 7) + (gridGap * 6);
        final availableCalendarWidth = constraints.maxWidth - (padding * 2);
        final calendarWidth = availableCalendarWidth > minimumCalendarWidth
            ? availableCalendarWidth
            : minimumCalendarWidth;
        return Card(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatMonthYear(_month),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${byDay.length} recorded ${byDay.length == 1 ? 'day' : 'days'}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Previous month',
                      onPressed: () => _moveMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Next month',
                      onPressed: () => _moveMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 14),
                Row(
                  children: [
                    Expanded(
                      child: _CalendarMetric(
                        label: 'Hours',
                        value: formatHoursLabel(summary.totalHours),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CalendarMetric(
                        label: 'Estimated gross pay',
                        value: _money(summary.totalExpectedPay),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _showCurrentMonth,
                      child: const Text('Today'),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 14),
                SingleChildScrollView(
                  key: const ValueKey('calendar-horizontal-scroll'),
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: calendarWidth,
                    child: Column(
                      children: [
                        Row(
                          key: const ValueKey('calendar-weekday-row'),
                          children: [
                            for (final dayName in _dayNames)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    dayName.substring(0, 1),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: compact ? 10 : 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: compact ? 5 : 7),
                        GridView.builder(
                          key: const ValueKey('calendar-date-grid'),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: totalCells,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: gridGap,
                                crossAxisSpacing: gridGap,
                              ),
                          itemBuilder: (context, index) {
                            final day = index - leading + 1;
                            if (day < 1 || day > daysInMonth) {
                              return const SizedBox.shrink();
                            }
                            final date = DateTime(
                              _month.year,
                              _month.month,
                              day,
                            );
                            final entries = byDay[day] ?? const <WorkEntry>[];
                            return _CalendarDayTile(
                              key: ValueKey('calendar-day-$day'),
                              date: date,
                              entries: entries,
                              settings: widget.settings,
                              compact: compact,
                              inCurrentPayPeriod: currentPayPeriod.contains(
                                date,
                              ),
                              selected: _isSameDate(_selectedDay, date),
                              onTap: () => setState(() => _selectedDay = date),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: compact ? 10 : 12),
                Wrap(
                  key: const ValueKey('calendar-legend'),
                  spacing: compact ? 10 : 16,
                  runSpacing: 6,
                  children: [
                    _CalendarLegend(
                      status: _CalendarStatus.home,
                      label: widget.settings.labelForRate('primary'),
                    ),
                    _CalendarLegend(
                      status: _CalendarStatus.away,
                      label: widget.settings.labelForRate('secondary'),
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.holiday,
                      label: 'Holiday',
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.sick,
                      label: 'Sick Day',
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.unpaid,
                      label: 'Unpaid',
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.bankHoliday,
                      label: 'Bank Holiday',
                    ),
                    const _CalendarLegend(
                      color: BriskaColors.calendarEmpty,
                      label: 'No entry',
                    ),
                    _CalendarLegend(
                      color: BriskaColors.primary,
                      label: 'Pay period',
                      outlined: true,
                    ),
                  ],
                ),
                if (_selectedDay != null) ...[
                  SizedBox(height: compact ? 12 : 16),
                  _CalendarDaySummary(
                    date: _selectedDay!,
                    entries: selectedEntries,
                    settings: widget.settings,
                    onAdd: () => widget.onAddDate(_selectedDay!),
                    onEdit: widget.onEditEntry,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isSameDate(DateTime? left, DateTime right) {
    return left != null &&
        left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _CalendarMetric extends StatelessWidget {
  const _CalendarMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CalendarDaySummary extends StatelessWidget {
  const _CalendarDaySummary({
    required this.date,
    required this.entries,
    required this.settings,
    required this.onAdd,
    required this.onEdit,
  });

  final DateTime date;
  final List<WorkEntry> entries;
  final AppSettings settings;
  final VoidCallback onAdd;
  final ValueChanged<WorkEntry> onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dateLabel = formatWeekdayDate(date);
    return AnimatedSwitcher(
      duration: BriskaDurations.standard,
      child: Container(
        key: ValueKey(date),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.primary.withValues(alpha: .12)),
        ),
        child: entries.isEmpty
            ? _CalendarEmptyDaySummary(dateLabel: dateLabel, onAdd: onAdd)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < entries.length; index++) ...[
                    _CalendarEntrySummary(
                      entry: entries[index],
                      settings: settings,
                      onTap: () => onEdit(entries[index]),
                    ),
                    if (index < entries.length - 1) const Divider(height: 14),
                  ],
                ],
              ),
      ),
    );
  }
}

class _CalendarEmptyDaySummary extends StatelessWidget {
  const _CalendarEmptyDaySummary({
    required this.dateLabel,
    required this.onAdd,
  });

  final String dateLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.edit_calendar_outlined, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Nothing recorded yet',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
    final addButton = FilledButton.tonalIcon(
      onPressed: onAdd,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Add Day'),
    );
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5 ||
        MediaQuery.sizeOf(context).width <= 360) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          details,
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: addButton),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: details),
        const SizedBox(width: 8),
        addButton,
      ],
    );
  }
}

class _CalendarEntrySummary extends StatelessWidget {
  const _CalendarEntrySummary({
    required this.entry,
    required this.settings,
    required this.onTap,
  });

  final WorkEntry entry;
  final AppSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final calculated = WorkCalculator.recalculateEntry(entry);
    final status = _CalendarStatus.fromEntry(calculated);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 34,
              child: Center(
                child: _CalendarStatusMarker(
                  key: ValueKey('calendar-summary-marker-${status.name}'),
                  status: status,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _entryTitle(calculated),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    calculated.entryType == 'WorkDay'
                        ? '${formatHoursLabel(calculated.totalHours)} · ${settings.labelForRate(calculated.rateType)}'
                        : status.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _money(calculated.totalPay),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({
    required this.date,
    required this.entries,
    required this.settings,
    required this.compact,
    required this.inCurrentPayPeriod,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final DateTime date;
  final List<WorkEntry> entries;
  final AppSettings settings;
  final bool compact;
  final bool inCurrentPayPeriod;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final isToday =
        today.year == date.year &&
        today.month == date.month &&
        today.day == date.day;
    final statuses = entries.isEmpty
        ? const [_CalendarStatus.empty]
        : (entries.map(_CalendarStatus.fromEntry).toSet().toList()
            ..sort((left, right) => left.index.compareTo(right.index)));
    final label = entries.isEmpty
        ? 'No entry'
        : statuses
              .map(
                (status) => switch (status) {
                  _CalendarStatus.home => settings.labelForRate('primary'),
                  _CalendarStatus.away => settings.labelForRate('secondary'),
                  _ => status.label,
                },
              )
              .join(', ');
    final primaryStatus = statuses.first;
    final statusColor = primaryStatus.color;
    return Semantics(
      button: true,
      label:
          '${date.day} ${_fullMonthNames[date.month - 1]}, $label${isToday ? ', today' : ''}${selected ? ', selected' : ''}${inCurrentPayPeriod ? ', current pay period' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(BriskaRadii.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: BriskaDurations.standard,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(compact ? 4 : 6),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: .12)
                : entries.isNotEmpty
                ? statusColor.withValues(alpha: .09)
                : isToday
                ? colorScheme.primary.withValues(alpha: .045)
                : inCurrentPayPeriod
                ? colorScheme.primary.withValues(alpha: .025)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(BriskaRadii.md),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : isToday || inCurrentPayPeriod
                  ? colorScheme.primary.withValues(alpha: isToday ? .55 : .2)
                  : Theme.of(context).dividerColor.withValues(alpha: .72),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        date.day.toString(),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: isToday || selected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontSize: compact ? 10.5 : 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (isToday && !compact)
                    Container(
                      width: compact ? 4 : 5,
                      height: compact ? 4 : 5,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (entries.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final status in statuses.take(3))
                      _CalendarStatusMarker(
                        key: ValueKey(
                          'calendar-cell-marker-${status.name}-${date.day}',
                        ),
                        status: status,
                      ),
                  ],
                )
              else if (inCurrentPayPeriod)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: compact ? 8 : 10,
                    height: 2,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CalendarStatus {
  home('Primary rate', BriskaColors.secondary),
  away('Secondary rate', BriskaColors.secondary),
  holiday('Holiday', BriskaColors.calendarHoliday),
  sick('Sick Day', BriskaColors.calendarSickDay),
  unpaid('Unpaid day off', BriskaColors.warning),
  bankHoliday('Bank Holiday', BriskaColors.primary),
  empty('No entry', BriskaColors.calendarEmpty);

  const _CalendarStatus(this.label, this.color);

  final String label;
  final Color color;

  static _CalendarStatus fromEntry(WorkEntry entry) {
    return switch (entry.entryType) {
      'Holiday' => holiday,
      'bankHoliday' || 'BankHoliday' => bankHoliday,
      'SickDay' => sick,
      'UnpaidDayOff' => unpaid,
      _ => entry.rateType == 'secondary' ? away : home,
    };
  }
}

class _CalendarStatusMarker extends StatelessWidget {
  const _CalendarStatusMarker({required this.status, super.key});

  final _CalendarStatus status;

  @override
  Widget build(BuildContext context) {
    final marker = switch (status) {
      _CalendarStatus.home => Container(
        width: 12,
        height: 4,
        decoration: BoxDecoration(
          color: status.color,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      _CalendarStatus.away => Transform.rotate(
        angle: 0.7853981633974483,
        child: Container(width: 8, height: 8, color: status.color),
      ),
      _CalendarStatus.holiday => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
      ),
      _CalendarStatus.sick => Icon(
        Icons.sick_outlined,
        size: 12,
        color: status.color,
      ),
      _CalendarStatus.unpaid => Container(
        width: 8,
        height: 8,
        color: status.color,
      ),
      _CalendarStatus.bankHoliday => Icon(
        Icons.account_balance_rounded,
        size: 12,
        color: status.color,
      ),
      _CalendarStatus.empty => const SizedBox.shrink(),
    };
    return SizedBox(width: 14, height: 12, child: Center(child: marker));
  }
}

class _CalendarDot extends StatelessWidget {
  const _CalendarDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 5, height: 5),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({
    required this.label,
    this.status,
    this.color,
    this.outlined = false,
  });
  final _CalendarStatus? status;
  final Color? color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 180),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (outlined)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              border: Border.all(color: color!, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          )
        else if (status != null)
          _CalendarStatusMarker(
            key: ValueKey('calendar-legend-marker-${status!.name}'),
            status: status!,
          )
        else
          _CalendarDot(color: color!),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class WorkEntryCard extends StatelessWidget {
  const WorkEntryCard({
    required this.entry,
    this.compact = false,
    this.onEdit,
    this.onDelete,
    this.settings = const AppSettings(),
    super.key,
  });
  final WorkEntry entry;
  final bool compact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final entry = WorkCalculator.recalculateEntry(this.entry);
    return Card(
      key: ValueKey('entry-card-${entry.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _dayNames[entry.date.weekday - 1],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                      Text(
                        formatCompactDate(entry.date),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _entryTitle(entry),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.entryType == 'WorkDay'
                            ? '${WorkCalculator.normalizeTime(entry.startTime) ?? entry.startTime} - '
                                  '${WorkCalculator.normalizeTime(entry.finishTime) ?? entry.finishTime}  -  '
                                  '${settings.labelForRate(entry.rateType)}'
                            : entry.entryType == 'Holiday'
                            ? 'Paid holiday - ${settings.labelForRate('primary')}'
                            : entry.type == EntryType.bankHoliday
                            ? '${entry.isPaidBankHoliday ? 'Paid' : 'Unpaid'} Bank Holiday${entry.isPaidBankHoliday ? ' - ${settings.labelForRate('primary')}' : ''}'
                            : entry.entryType == 'SickDay'
                            ? '${entry.isPaidSickDay ? 'Paid' : 'Unpaid'} sick day${entry.isPaidSickDay ? ' - ${settings.labelForRate('primary')}' : ''}'
                            : 'Unpaid day off',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(entry.totalPay),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        formatHoursLabel(entry.totalHours),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  icon: entry.entryType == 'Holiday'
                      ? Icons.beach_access_outlined
                      : entry.type == EntryType.bankHoliday
                      ? Icons.account_balance_rounded
                      : entry.entryType == 'SickDay'
                      ? Icons.sick_outlined
                      : entry.entryType == 'UnpaidDayOff'
                      ? Icons.event_busy_outlined
                      : Icons.work_outline_rounded,
                  label: entry.entryType == 'Holiday'
                      ? 'Type: Holiday'
                      : entry.type == EntryType.bankHoliday
                      ? 'Type: Bank Holiday (${entry.isPaidBankHoliday ? 'Paid' : 'Unpaid'})'
                      : entry.entryType == 'SickDay'
                      ? 'Type: Sick Day (${entry.isPaidSickDay ? 'Paid' : 'Unpaid'})'
                      : entry.entryType == 'UnpaidDayOff'
                      ? 'Type: Unpaid'
                      : 'Type: Work day',
                ),
                _StatusPill(
                  icon: Icons.payments_outlined,
                  label: 'Rate: ${settings.labelForRate(entry.rateType)}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _EntryDetail(
                    label: 'Hours worked',
                    value: formatHoursLabel(entry.totalHours),
                  ),
                  _EntryDetail(
                    label: 'Rate',
                    value: '${_money(entry.hourlyRateUsed)}/hr',
                  ),
                  _EntryDetail(label: 'Base pay', value: _money(entry.wages)),
                  if (entry.dailyAllowance != 0)
                    _EntryDetail(
                      label: 'Daily allowance',
                      value: _money(entry.dailyAllowance),
                    ),
                  if (entry.jobUplift > 0)
                    _EntryDetail(
                      label: 'Job uplift',
                      value: _money(entry.jobUplift),
                    ),
                  _EntryDetail(
                    label: 'Estimated gross pay',
                    value: _money(entry.totalPay),
                  ),
                  if (entry.deductionAmount > 0) ...[
                    _EntryDetail(
                      label: 'Deduction',
                      value: _money(entry.deductionAmount),
                    ),
                    _EntryDetail(
                      label: 'Final pay',
                      value: _money(entry.netPay),
                    ),
                    if (entry.deductionReason.trim().isNotEmpty)
                      _EntryDetail(
                        label: 'Reason',
                        value: entry.deductionReason,
                      ),
                  ],
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 180.0;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: .18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EntryDetail extends StatelessWidget {
  const _EntryDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label  ',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ExportActionOverrides {
  const ExportActionOverrides({
    this.open,
    this.share,
    this.print,
    this.rename,
    this.deleteFile,
  });

  final Future<bool> Function(ExportedFileRecord record)? open;
  final Future<void> Function(ExportedFileRecord record)? share;
  final Future<void> Function(ExportedFileRecord record)? print;
  final Future<void> Function(File source, String targetPath)? rename;
  final Future<void> Function(File file)? deleteFile;
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    required this.entries,
    required this.fullName,
    required this.companyName,
    required this.settings,
    required this.records,
    required this.onPreferencesChanged,
    required this.onAdd,
    required this.onDelete,
    required this.onUpdate,
    this.libraryOnly = false,
    this.actionOverrides,
    super.key,
  });

  final List<WorkEntry> entries;
  final String fullName;
  final String companyName;
  final AppSettings settings;
  final List<ExportedFileRecord> records;
  final ValueChanged<AppSettings> onPreferencesChanged;
  final ValueChanged<ExportedFileRecord> onAdd;
  final ValueChanged<ExportedFileRecord> onDelete;
  final ValueChanged<ExportedFileRecord> onUpdate;
  final bool libraryOnly;
  final ExportActionOverrides? actionOverrides;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;
  bool isPreviewing = false;
  bool _showMoreOptions = false;
  String _librarySort = 'Newest';
  String _libraryFilter = 'All';
  ExportDateRangeType _rangeType = ExportDateRangeType.currentMonth;
  ExportReportType _reportType = ExportReportType.timesheet;
  ExportFileFormat _fileFormat = ExportFileFormat.pdf;
  late ExportOptions _options;
  DateTime? _customStart;
  DateTime? _customEnd;
  late final TextEditingController _fileNameController;
  bool _fileNameEdited = false;

  @override
  void initState() {
    super.initState();
    _rangeType = _defaultRangeType(widget.settings);
    _options = ExportOptions(includeCompanyName: widget.companyName.isNotEmpty);
    _fileNameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetFilename());
  }

  @override
  void didUpdateWidget(covariant ExportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.payFrequency != widget.settings.payFrequency ||
        oldWidget.settings.payPeriodAnchorDate !=
            widget.settings.payPeriodAnchorDate ||
        oldWidget.settings.customPeriodStartDay !=
            widget.settings.customPeriodStartDay) {
      final available = _availableRangeTypes(widget.settings);
      if (!available.contains(_rangeType)) {
        _rangeType = _defaultRangeType(widget.settings);
      }
      _updateSuggestedFilename();
    }
    if (oldWidget.fullName != widget.fullName && !_fileNameEdited) {
      _updateSuggestedFilename();
    }
  }

  static ExportDateRangeType _defaultRangeType(AppSettings settings) {
    return normalisePayFrequency(settings.payFrequency) ==
            calendarMonthlyPayFrequency
        ? ExportDateRangeType.currentMonth
        : ExportDateRangeType.currentPayPeriod;
  }

  static List<ExportDateRangeType> _availableRangeTypes(AppSettings settings) {
    final frequency = normalisePayFrequency(settings.payFrequency);
    if (frequency == calendarMonthlyPayFrequency) {
      return const [
        ExportDateRangeType.currentMonth,
        ExportDateRangeType.previousMonth,
        ExportDateRangeType.custom,
      ];
    }
    return const [
      ExportDateRangeType.currentPayPeriod,
      ExportDateRangeType.previousPayPeriod,
      ExportDateRangeType.currentMonth,
      ExportDateRangeType.custom,
    ];
  }

  String _rangeLabel(ExportDateRangeType value) {
    final frequency = normalisePayFrequency(widget.settings.payFrequency);
    return switch (value) {
      ExportDateRangeType.currentPayPeriod =>
        frequency == weeklyPayFrequency ? 'This pay week' : 'This pay period',
      ExportDateRangeType.previousPayPeriod =>
        frequency == weeklyPayFrequency ? 'Last pay week' : 'Last pay period',
      ExportDateRangeType.currentMonth => 'This month',
      ExportDateRangeType.previousMonth => 'Last month',
      ExportDateRangeType.custom => 'Custom dates',
      _ => value.label,
    };
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  ExportDateRange? get _range => ExportRangeResolver.resolve(
    type: _rangeType,
    now: DateTime.now(),
    settings: widget.settings,
    entries: widget.entries,
    customStart: _customStart,
    customEnd: _customEnd,
  );

  List<WorkEntry> get _selectedEntries {
    final range = _range;
    if (range == null || !range.isValid) return const [];
    return widget.entries.where((entry) => range.contains(entry.date)).toList();
  }

  String get _rangeError {
    if (_rangeType == ExportDateRangeType.custom &&
        (_customStart == null || _customEnd == null)) {
      return 'Choose both a From date and a To date.';
    }
    if (_range?.isValid == false) {
      return 'From date cannot be after To date.';
    }
    return '';
  }

  String get _fileNameError {
    final sanitized = ExportFilenameService.sanitize(
      _fileNameController.text,
      _fileFormat,
    );
    return sanitized.isEmpty ? 'Enter a valid file name.' : '';
  }

  bool get _canExport =>
      !_isExporting &&
      widget.entries.isNotEmpty &&
      _rangeError.isEmpty &&
      _selectedEntries.isNotEmpty &&
      _fileNameError.isEmpty &&
      (!_options.includeEmployeeName || widget.fullName.trim().isNotEmpty) &&
      (!_options.includeCompanyName || widget.companyName.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (widget.libraryOnly) return _buildExportLibrary(context);
    final range = _range;
    final periodLabel = range == null
        ? 'No date range'
        : formatFullDateRange(range.start, range.end);
    final exportEntries = _selectedEntries;
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Export',
            subtitle: 'Create a professional report from your work records.',
          ),
          const SizedBox(height: BriskaSpacing.md),
          BriskaCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BriskaSpacing.md,
              vertical: BriskaSpacing.sm,
            ),
            onTap: () => _openExportLibrary(context),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: BriskaSpacing.sm),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export Library',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('Open, share or print saved exports'),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: BriskaSpacing.md),
          _ExportSection(
            number: 1,
            title: 'Date range',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChoiceWrap<ExportDateRangeType>(
                  values: _availableRangeTypes(widget.settings),
                  selected: _rangeType,
                  label: _rangeLabel,
                  onSelected: (value) {
                    setState(() => _rangeType = value);
                    _updateSuggestedFilename();
                  },
                ),
                if (_rangeType == ExportDateRangeType.custom) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickCustomDate(true),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _customStart == null
                                ? 'From date'
                                : 'From date\n${formatFullDate(_customStart!)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickCustomDate(false),
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            _customEnd == null
                                ? 'To date'
                                : 'To date\n${formatFullDate(_customEnd!)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (range != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    periodLabel,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (_rangeError.isNotEmpty)
                  Text(
                    _rangeError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          _ExportSection(
            number: 2,
            title: 'Report type',
            child: _ChoiceWrap<ExportReportType>(
              values: const [
                ExportReportType.timesheet,
                ExportReportType.paySummary,
              ],
              selected: _reportType,
              label: (value) => value.label,
              onSelected: (value) {
                setState(() => _reportType = value);
                _updateSuggestedFilename();
              },
            ),
          ),
          _ExportSection(
            number: 3,
            title: 'File format',
            child: _ChoiceWrap<ExportFileFormat>(
              values: const [ExportFileFormat.pdf, ExportFileFormat.xlsx],
              selected: _fileFormat,
              label: (value) => value.label,
              onSelected: (value) {
                setState(() => _fileFormat = value);
                _updateSuggestedFilename();
              },
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _showMoreOptions = !_showMoreOptions),
              icon: Icon(
                _showMoreOptions
                    ? Icons.expand_less_rounded
                    : Icons.tune_rounded,
              ),
              label: Text(
                _fileFormat == ExportFileFormat.csv
                    ? 'More options · CSV selected'
                    : 'More options',
              ),
            ),
          ),
          if (_showMoreOptions)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Advanced format',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: BriskaSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ChoiceChip(
                        label: const Text('CSV (.csv)'),
                        selected: _fileFormat == ExportFileFormat.csv,
                        onSelected: (_) {
                          setState(() => _fileFormat = ExportFileFormat.csv);
                          _updateSuggestedFilename();
                        },
                      ),
                    ),
                    const Divider(height: BriskaSpacing.xl),
                    _optionSwitch(
                      'Include employer / company',
                      _options.includeCompanyName,
                      (value) => _options = _options.copyWith(
                        includeCompanyName: value,
                      ),
                    ),
                    _optionSwitch(
                      'Include employee name',
                      _options.includeEmployeeName,
                      (value) => _options = _options.copyWith(
                        includeEmployeeName: value,
                      ),
                    ),
                    _optionSwitch(
                      'Include notes',
                      _options.includeNotes,
                      (value) =>
                          _options = _options.copyWith(includeNotes: value),
                    ),
                    _optionSwitch(
                      'Include signature line',
                      _options.includeSignatureLine,
                      (value) => _options = _options.copyWith(
                        includeSignatureLine: value,
                      ),
                      enabled: _fileFormat != ExportFileFormat.csv,
                    ),
                    if (_options.includeCompanyName &&
                        widget.companyName.trim().isEmpty)
                      const Text(
                        'Add a company name in Settings or turn this option off.',
                      ),
                    if (_options.includeEmployeeName &&
                        widget.fullName.trim().isEmpty)
                      const Text(
                        'Add an employee name in Settings or turn this option off.',
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fileNameController,
                      maxLength: 130,
                      decoration: InputDecoration(
                        labelText: 'Edit filename',
                        errorText: _fileNameError.isEmpty
                            ? null
                            : _fileNameError,
                      ),
                      onChanged: (_) => setState(() => _fileNameEdited = true),
                    ),
                    TextButton(
                      onPressed: _resetFilename,
                      child: const Text('Reset filename'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: BriskaPrimaryButton(
              icon: Icons.file_download_outlined,
              label: _isExporting ? 'Creating report…' : 'Export report',
              isLoading: _isExporting,
              onPressed: !_canExport
                  ? null
                  : () => _performExport(context, exportEntries, periodLabel),
            ),
          ),
          if (widget.entries.isEmpty) const _NoWorkRecords(),
          const SizedBox(height: 26),
          const SectionHeading(title: 'Recent exports'),
          const SizedBox(height: 10),
          if (widget.records.isEmpty)
            const _CompactEmptyExportLibrary()
          else ...[
            ...([...widget.records]
                  ..sort((a, b) => b.exportedAt.compareTo(a.exportedAt)))
                .take(5)
                .map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RecentExportCard(
                      record: record,
                      onOpen: () => _open(context, record),
                      onShare: () => _share(context, record),
                      onDelete: () => _confirmDelete(context, record),
                    ),
                  ),
                ),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => _openExportLibrary(context),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('View all exports'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openExportLibrary(BuildContext context) {
    Navigator.of(context).push(
      _BriskaPageRoute(
        child: ExportScreen(
          entries: widget.entries,
          fullName: widget.fullName,
          companyName: widget.companyName,
          settings: widget.settings,
          records: widget.records,
          onPreferencesChanged: widget.onPreferencesChanged,
          onAdd: widget.onAdd,
          onDelete: widget.onDelete,
          onUpdate: widget.onUpdate,
          libraryOnly: true,
          actionOverrides: widget.actionOverrides,
        ),
      ),
    );
  }

  Widget _buildExportLibrary(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Export Library')),
    body: AppPage(
      topPadding: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButton<String>(
                value: _librarySort,
                items: const ['Newest', 'Oldest', 'Filename']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _librarySort = value!),
              ),
              ...['All', 'PDF', 'Excel', 'CSV'].map(
                (value) => FilterChip(
                  label: Text(value),
                  selected: _libraryFilter == value,
                  onSelected: (_) => setState(() => _libraryFilter = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_filteredLibraryRecords.isEmpty)
            const _CompactEmptyExportLibrary()
          else
            ..._filteredLibraryRecords.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExportedFileCard(
                  record: record,
                  onOpen: () => _open(context, record),
                  onShare: () => _share(context, record),
                  onPrint:
                      ExportFormat.fromFileType(record.fileType) ==
                              ExportFormat.pdfTimesheet ||
                          ExportFormat.fromFileType(record.fileType) ==
                              ExportFormat.pdfSummary
                      ? () => _print(context, record)
                      : null,
                  onRename: () => _rename(context, record),
                  onFavourite: () => widget.onUpdate(
                    record.copyWith(isFavourite: !record.isFavourite),
                  ),
                  onDelete: () => _confirmDelete(context, record),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  List<ExportedFileRecord> get _filteredLibraryRecords {
    final records = widget.records.where((record) {
      if (_libraryFilter == 'All') return true;
      return ExportFormat.fromFileType(
        record.fileType,
      ).fileType.toLowerCase().contains(_libraryFilter.toLowerCase());
    }).toList();
    switch (_librarySort) {
      case 'Oldest':
        records.sort((a, b) => a.exportedAt.compareTo(b.exportedAt));
      case 'Filename':
        records.sort(
          (a, b) =>
              a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
        );
      default:
        records.sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    }
    return records;
  }

  SwitchListTile _optionSwitch(
    String title,
    bool value,
    ValueChanged<bool> update, {
    bool enabled = true,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: !enabled ? const Text('Available for PDF and Excel only') : null,
    value: enabled && value,
    onChanged: !enabled ? null : (next) => setState(() => update(next)),
  );

  void _resetFilename() {
    final range = _range;
    if (!mounted || range == null) return;
    setState(() {
      _fileNameEdited = false;
      _fileNameController.text = _suggestedFilename(range, DateTime.now());
    });
  }

  String _suggestedFilename(ExportDateRange range, DateTime createdAt) =>
      ExportFilenameService.suggested(
        employeeFullName: widget.fullName,
        rangeType: _rangeType,
        range: range,
        settings: widget.settings,
        createdAt: createdAt,
        format: _fileFormat,
      );

  void _updateSuggestedFilename() {
    if (!_fileNameEdited) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resetFilename());
    }
  }

  Future<void> _pickCustomDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _customStart : _customEnd) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _customStart = picked;
      } else {
        _customEnd = picked;
      }
    });
    _updateSuggestedFilename();
  }

  Future<void> _performExport(
    BuildContext context,
    List<WorkEntry> entries,
    String periodLabel,
  ) async {
    final range = _range;
    if (!_fileNameEdited && range != null) {
      _fileNameController.text = _suggestedFilename(range, DateTime.now());
    }
    final sanitized = ExportFilenameService.sanitize(
      _fileNameController.text,
      _fileFormat,
    );
    setState(() => _isExporting = true);
    try {
      final format = switch (_fileFormat) {
        ExportFileFormat.xlsx => ExportFormat.excel,
        ExportFileFormat.csv => ExportFormat.csv,
        ExportFileFormat.pdf =>
          _reportType == ExportReportType.timesheet
              ? ExportFormat.pdfTimesheet
              : ExportFormat.pdfSummary,
      };
      await _export(context, entries, periodLabel, sanitized, format);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> showPreview(
    BuildContext context,
    List<WorkEntry> entries,
    String periodLabel,
  ) async {
    setState(() => isPreviewing = true);
    final summary = WorkCalculator.summarize(entries);
    if (mounted) setState(() => isPreviewing = false);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_fileFormat.label} Preview'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_reportType.label),
                Text(periodLabel),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Site/job')),
                      DataColumn(label: Text('Hours')),
                      DataColumn(label: Text('Gross pay')),
                    ],
                    rows: entries
                        .take(8)
                        .map(
                          (entry) => DataRow(
                            cells: [
                              DataCell(
                                Text(formatCompactDateWithYear(entry.date)),
                              ),
                              DataCell(Text(entry.siteName)),
                              DataCell(
                                Text(formatHoursLabel(entry.totalHours)),
                              ),
                              DataCell(Text(_money(entry.totalPay))),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(),
                Text('Total hours: ${formatHoursLabel(summary.totalHours)}'),
                Text('Gross pay: ${_money(summary.totalExpectedPay)}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close preview'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _performExport(context, entries, periodLabel);
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    List<WorkEntry> exportEntries,
    String periodLabel,
    String fileNameLabel,
    ExportFormat format,
  ) async {
    try {
      final now = DateTime.now();
      final result = await _runExport(
        format: format,
        exportEntries: exportEntries,
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        generatedAt: now,
      );
      if (!context.mounted) return;
      final summary = WorkCalculator.summarize(exportEntries);
      final record = ExportedFileRecord(
        id: now.microsecondsSinceEpoch.toString(),
        fileName: result.fileName,
        fileType: format.fileType,
        filePath: result.filePath,
        exportedAt: now,
        periodLabel: periodLabel,
        workDays: summary.totalDays,
        totalHours: summary.totalHours,
        totalPay: summary.totalExpectedPay,
        fileSize: result.fileSize,
        reportType: _reportType.label,
        dateRangeType: _rangeType.name,
        startDate: _range?.start,
        endDate: _range?.end,
        currencyCode: widget.settings.currency.code,
        currencySymbol: widget.settings.currency.symbol,
      );
      widget.onAdd(record);
      await _showExportCompleteActions(context, record);
    } catch (error) {
      if (!context.mounted) return;
      if (kDebugMode) debugPrint('Export failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exportCreationFailureMessage(error))),
      );
    }
  }

  Future<ExportFileResult> _runExport({
    required ExportFormat format,
    required List<WorkEntry> exportEntries,
    required String periodLabel,
    required String fileNameLabel,
    required DateTime generatedAt,
  }) async {
    return switch (format) {
      ExportFormat.excel => ExcelExportService.export(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
      ExportFormat.csv => CsvExportService.export(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
      ExportFormat.pdfTimesheet => PdfExportService.exportTimesheet(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
        periodLabel: periodLabel,
        generatedAt: generatedAt,
        logoBytes: await _loadAssetBytes(
          'assets/branding/briska-bp-in-app.png',
        ),
        regularFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-Regular.ttf',
        ),
        boldFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-SemiBold.ttf',
        ),
        fileNameLabel: fileNameLabel,
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
      ExportFormat.pdfSummary => PdfExportService.exportSummary(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
        periodLabel: periodLabel,
        generatedAt: generatedAt,
        logoBytes: await _loadAssetBytes(
          'assets/branding/briska-bp-in-app.png',
        ),
        regularFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-Regular.ttf',
        ),
        boldFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-SemiBold.ttf',
        ),
        fileNameLabel: fileNameLabel,
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
    };
  }

  Future<void> _showExportCompleteActions(
    BuildContext context,
    ExportedFileRecord record,
  ) async {
    final action = await showDialog<_ExportCompleteAction>(
      context: context,
      builder: (dialogContext) => ExportCreatedDialog(
        record: record,
        onDone: () => Navigator.pop(dialogContext, _ExportCompleteAction.done),
        onShare: () =>
            Navigator.pop(dialogContext, _ExportCompleteAction.share),
        onPrint: () =>
            Navigator.pop(dialogContext, _ExportCompleteAction.print),
        onOpen: () => Navigator.pop(dialogContext, _ExportCompleteAction.open),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case _ExportCompleteAction.open:
        await _open(context, record);
      case _ExportCompleteAction.share:
        await _share(context, record);
      case _ExportCompleteAction.print:
        await _print(context, record);
      case _ExportCompleteAction.done || null:
        break;
    }
  }

  Future<Uint8List> _loadAssetBytes(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }

  Future<void> _open(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export file not found.')));
      return;
    }
    try {
      record = await _providerCompatibleRecord(record);
      final override = widget.actionOverrides?.open;
      if (override != null) {
        final opened = await override(record);
        if (!context.mounted || opened) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exportFileActionFailureMessage(ExportFileAction.open),
            ),
          ),
        );
        return;
      }
      final format = ExportFormat.fromFileType(record.fileType);
      final result = await OpenFilex.open(
        record.filePath,
        type: format.mimeType,
      );
      if (!context.mounted || result.type.name == 'done') return;
      if (kDebugMode) debugPrint('open export failed: ${result.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.open)),
        ),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('open export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.open)),
        ),
      );
    }
  }

  Future<void> _share(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export file not found.')));
      return;
    }
    final format = ExportFormat.fromFileType(record.fileType);
    try {
      record = await _providerCompatibleRecord(record);
      final override = widget.actionOverrides?.share;
      if (override != null) {
        await override(record);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(record.filePath, mimeType: format.mimeType)],
            subject: record.fileName,
          ),
        );
      }
    } catch (error) {
      if (kDebugMode) debugPrint('share export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.share)),
        ),
      );
    }
  }

  Future<void> _rename(BuildContext context, ExportedFileRecord record) async {
    final format = ExportFormat.fromFileType(record.fileType);
    final initialName = record.fileName.replaceFirst(
      RegExp('\\.${RegExp.escape(format.extension)}\$'),
      '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameExportDialog(
        initialName: initialName,
        extension: format.extension,
      ),
    );
    final safeName = name == null ? '' : ExportFileNamer.safeName(name);
    if (safeName.isEmpty) return;
    final fileName = '$safeName.${format.extension}';
    try {
      var filePath = record.filePath;
      if (record.isAvailable) {
        record = await _providerCompatibleRecord(record);
        filePath = record.filePath;
        final separator = Platform.pathSeparator;
        final separatorIndex = record.filePath.lastIndexOf(separator);
        if (separatorIndex == -1) {
          throw FileSystemException('Could not find export folder.');
        }
        final parent = record.filePath.substring(0, separatorIndex);
        final targetPath = '$parent$separator$fileName';
        if (targetPath != record.filePath && await File(targetPath).exists()) {
          throw FileSystemException('A file with that name already exists.');
        }
        final source = File(record.filePath);
        final override = widget.actionOverrides?.rename;
        if (override != null) {
          await override(source, targetPath);
          filePath = targetPath;
        } else {
          filePath = (await source.rename(targetPath)).path;
        }
      }
      widget.onUpdate(record.copyWith(fileName: fileName, filePath: filePath));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export renamed.')));
    } catch (error) {
      if (kDebugMode) debugPrint('rename export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            exportFileActionFailureMessage(ExportFileAction.rename),
          ),
        ),
      );
    }
  }

  Future<void> _print(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export file not found.')));
      return;
    }
    try {
      record = await _providerCompatibleRecord(record);
      final override = widget.actionOverrides?.print;
      if (override != null) {
        await override(record);
      } else {
        await Printing.layoutPdf(
          name: record.fileName,
          onLayout: (_) => File(record.filePath).readAsBytes(),
        );
      }
    } catch (error) {
      if (kDebugMode) debugPrint('print export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.print)),
        ),
      );
    }
  }

  Future<ExportedFileRecord> _providerCompatibleRecord(
    ExportedFileRecord record,
  ) async {
    final file = await ExportFileNamer.ensureProviderCompatibleFile(
      File(record.filePath),
    );
    if (file.path == record.filePath) return record;
    final updated = record.copyWith(filePath: file.path);
    widget.onUpdate(updated);
    return updated;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ExportedFileRecord record,
  ) async {
    final result = await showDialog<_DeleteChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('Delete export?'),
        content: const Text('Choose what you want to delete.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          if (record.isAvailable)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () =>
                  Navigator.pop(dialogContext, _DeleteChoice.fileToo),
              child: const Text('Delete file and remove from library'),
            ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _DeleteChoice.libraryOnly),
            child: const Text('Remove from library'),
          ),
        ],
      ),
    );
    if (!context.mounted || result == null) return;
    if (result == _DeleteChoice.fileToo) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: const Text('Delete file from device?'),
          content: const Text(
            'This will permanently delete the exported file and remove it '
            "from the Briska Pay Export Library.\n\nThis can't be undone.",
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            Semantics(
              button: true,
              label: 'Delete export file from device',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete file'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        final file = File(record.filePath);
        if (file.existsSync()) {
          final override = widget.actionOverrides?.deleteFile;
          if (override != null) {
            await override(file);
          } else {
            await file.delete();
          }
        }
      } catch (error) {
        if (kDebugMode) debugPrint('delete export failed: $error');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exportFileActionFailureMessage(ExportFileAction.delete),
            ),
          ),
        );
        return;
      }
    }
    widget.onDelete(record);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == _DeleteChoice.fileToo
              ? 'Export deleted.'
              : 'Export removed from library.',
        ),
      ),
    );
  }
}

class _ExportSection extends StatelessWidget {
  const _ExportSection({
    required this.number,
    required this.title,
    required this.child,
  });
  final int number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: Text(
                    '$number',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: values
        .map(
          (value) => ChoiceChip(
            label: Text(label(value)),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          ),
        )
        .toList(),
  );
}

class _NoWorkRecords extends StatelessWidget {
  const _NoWorkRecords();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              Icons.work_off_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              'No days recorded to export',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Record a day before creating a report.'),
          ],
        ),
      ),
    ),
  );
}

enum _DeleteChoice { libraryOnly, fileToo }

enum _ExportCompleteAction { open, share, print, done }

class _RenameExportDialog extends StatefulWidget {
  const _RenameExportDialog({
    required this.initialName,
    required this.extension,
  });

  final String initialName;
  final String extension;

  @override
  State<_RenameExportDialog> createState() => _RenameExportDialogState();
}

class _RenameExportDialogState extends State<_RenameExportDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename export'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'File name',
      ).copyWith(suffixText: '.${widget.extension}'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Rename'),
      ),
    ],
  );
}

class ExportCreatedDialog extends StatelessWidget {
  const ExportCreatedDialog({
    required this.record,
    required this.onDone,
    required this.onShare,
    required this.onPrint,
    required this.onOpen,
    super.key,
  });

  final ExportedFileRecord record;
  final VoidCallback onDone;
  final VoidCallback onShare;
  final VoidCallback onPrint;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    icon: const Icon(Icons.check_circle_outline_rounded),
    title: const Text('Export created'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(record.fileName, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Text(_formatFileSize(record.fileSize)),
      ],
    ),
    actions: [
      TextButton(onPressed: onDone, child: const Text('Done')),
      TextButton(onPressed: onShare, child: const Text('Share')),
      if (ExportFormat.fromFileType(record.fileType) ==
              ExportFormat.pdfTimesheet ||
          ExportFormat.fromFileType(record.fileType) == ExportFormat.pdfSummary)
        TextButton.icon(
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print'),
        ),
      FilledButton(onPressed: onOpen, child: const Text('Open')),
    ],
  );
}

class _ExportedFileCard extends StatelessWidget {
  const _ExportedFileCard({
    required this.record,
    required this.onOpen,
    required this.onShare,
    required this.onPrint,
    required this.onRename,
    required this.onFavourite,
    required this.onDelete,
  });

  final ExportedFileRecord record;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback? onPrint;
  final VoidCallback onRename;
  final VoidCallback onFavourite;
  final VoidCallback onDelete;

  String get _date => formatCompactDateWithYear(record.exportedAt);

  String get _size {
    return _formatFileSize(record.fileSize);
  }

  ExportFormat get _format => ExportFormat.fromFileType(record.fileType);

  String get _icon {
    return switch (_format) {
      ExportFormat.excel => '📗',
      ExportFormat.pdfTimesheet => '📕',
      ExportFormat.pdfSummary => '📄',
      ExportFormat.csv => '📊',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(_icon, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_format.fileType} - $_date',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _money(
                    record.totalPay,
                    CurrencyCatalog.byCode(
                      record.currencyCode,
                    ).copyWith(symbol: record.currencySymbol),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                spacing: 18,
                runSpacing: 9,
                children: [
                  _LibraryDetail(label: 'Period', value: record.periodLabel),
                  _LibraryDetail(label: 'File type', value: _format.fileType),
                  _LibraryDetail(label: 'Created', value: _date),
                  _LibraryDetail(
                    label: record.workDays == 1
                        ? 'Day recorded'
                        : 'Days recorded',
                    value: record.workDays.toString(),
                  ),
                  _LibraryDetail(
                    label: 'Hours',
                    value: formatHoursLabel(record.totalHours),
                  ),
                  _LibraryDetail(label: 'File size', value: _size),
                ],
              ),
            ),
            if (!record.isAvailable) ...[
              const SizedBox(height: 10),
              const _MissingFileBadge(),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
                if (onPrint != null)
                  TextButton.icon(
                    onPressed: onPrint,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                TextButton.icon(
                  onPressed: onFavourite,
                  icon: Icon(
                    record.isFavourite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                  ),
                  label: Text(record.isFavourite ? 'Favourited' : 'Favourite'),
                ),
                TextButton.icon(
                  onPressed: onRename,
                  icon: const Icon(
                    Icons.drive_file_rename_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('Rename'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingFileBadge extends StatelessWidget {
  const _MissingFileBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'Export file not found.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _LibraryDetail extends StatelessWidget {
  const _LibraryDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '$label  ',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
      children: [
        TextSpan(
          text: value,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class EmptyExportLibrary extends StatelessWidget {
  const EmptyExportLibrary({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              'No saved exports yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Reports saved to the Briska Pay Export Library will appear here.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CompactEmptyExportLibrary extends StatelessWidget {
  const _CompactEmptyExportLibrary();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No exports yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Reports you create will appear here for quick access.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecentExportCard extends StatelessWidget {
  const _RecentExportCard({
    required this.record,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final ExportedFileRecord record;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final format = ExportFormat.fromFileType(record.fileType);
    final created = formatCompactDateWithYear(record.exportedAt);
    final range = record.startDate != null && record.endDate != null
        ? '${formatCompactDateWithYear(record.startDate!)} – '
              '${formatCompactDateWithYear(record.endDate!)}'
        : record.periodLabel;
    final size = record.fileSize == null
        ? null
        : record.fileSize! >= 1024 * 1024
        ? '${(record.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(record.fileSize! / 1024).toStringAsFixed(0)} KB';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Icon(
              format == ExportFormat.excel
                  ? Icons.table_chart_outlined
                  : format == ExportFormat.csv
                  ? Icons.grid_on_outlined
                  : Icons.picture_as_pdf_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${record.reportType} · $range',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$created · ${format.label}${size == null ? '' : ' · $size'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Export actions',
              onSelected: (action) {
                switch (action) {
                  case 'open':
                    onOpen();
                  case 'share':
                    onShare();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.onThemeModeChanged,
    required this.preferences,
    required this.lockConfig,
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onLockConfigChanged,
    required this.onSetLockPin,
    required this.onShowAbout,
    required this.onPreferencesChanged,
    this.deviceAuthenticationAvailabilityChecker,
    this.showTesterTools,
    this.privacyOptionsRequired = false,
    this.onShowAdvertisingPrivacyChoices,
    super.key,
  });
  final FutureOr<void> Function(ThemeMode) onThemeModeChanged;
  final AppSettings preferences;
  final AppLockConfig lockConfig;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function(AppLockConfig config) onLockConfigChanged;
  final Future<void> Function(String pin) onSetLockPin;
  final VoidCallback onShowAbout;
  final FutureOr<void> Function(AppSettings) onPreferencesChanged;
  final bool? showTesterTools;
  final Future<bool> Function()? deviceAuthenticationAvailabilityChecker;
  final bool privacyOptionsRequired;
  final Future<void> Function()? onShowAdvertisingPrivacyChoices;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _anchorPromptShown = false;
  int _currencyPickerRevision = 0;
  int _formRevision = 0;
  int _saveRevision = 0;
  late AppSettings _draftPreferences;
  bool? _deviceAuthenticationAvailable;

  @override
  void initState() {
    super.initState();
    _draftPreferences = widget.preferences;
    _loadDeviceAuthenticationAvailability();
  }

  Future<void> _loadDeviceAuthenticationAvailability() async {
    var available = false;
    try {
      available =
          await (widget.deviceAuthenticationAvailabilityChecker?.call() ??
              AppLockService.canUseBiometrics());
    } catch (_) {
      available = false;
    }
    if (mounted) {
      setState(() => _deviceAuthenticationAvailable = available);
    }
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      _draftPreferences = widget.preferences;
    }
  }

  void _update(AppSettings value) => setState(() => _draftPreferences = value);

  void _showSettingsFeedback(String message) {
    if (!mounted) return;
    if (Scaffold.maybeOf(context) == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _persist(
    AppSettings value, {
    String? successMessage,
    required String failureMessage,
  }) async {
    if (value.primaryRateLabel.trim().isEmpty ||
        value.secondaryRateLabel.trim().isEmpty ||
        value.primaryRateLabel.trim().length > 24 ||
        value.secondaryRateLabel.trim().length > 24 ||
        value.primaryRateValue < 0 ||
        value.secondaryRateValue < 0) {
      _showSettingsFeedback(failureMessage);
      return false;
    }
    value = value.copyWith(
      primaryRateLabel: value.primaryRateLabel.trim(),
      secondaryRateLabel: value.secondaryRateLabel.trim(),
    );
    final revision = ++_saveRevision;
    try {
      await widget.onPreferencesChanged(value);
      if (!mounted || revision != _saveRevision) return true;
      setState(() => _draftPreferences = value);
      if (successMessage != null) _showSettingsFeedback(successMessage);
      return true;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('settings persistence failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted || revision != _saveRevision) return false;
      setState(() {
        _draftPreferences = widget.preferences;
        _currencyPickerRevision++;
        _formRevision++;
      });
      _showSettingsFeedback(failureMessage);
      return false;
    }
  }

  Future<void> _updatePaySchedule(AppSettings value) async {
    await _persist(
      value,
      successMessage: 'Pay schedule updated.',
      failureMessage: 'Could not update pay schedule.',
    );
  }

  Future<void> _confirmCurrencyChange(CurrencyConfig currency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change currency?'),
        content: const Text(
          'This changes how money is displayed throughout Briska Pay. It does not convert existing wage values using an exchange rate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Change currency'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _persist(
        _draftPreferences.copyWith(currency: currency),
        successMessage: 'Currency updated.',
        failureMessage: 'Could not update currency.',
      );
    } else if (mounted) {
      setState(() => _currencyPickerRevision++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsAnchor = requiresPayPeriodAnchor(_draftPreferences);
    if (needsAnchor &&
        !_draftPreferences.payScheduleAnchorPrompted &&
        !_anchorPromptShown) {
      _anchorPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && requiresPayPeriodAnchor(_draftPreferences)) {
          _showAnchorPrompt();
        }
      });
    }

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Settings',
            subtitle: 'Make Briska Pay work your way.',
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Profile'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Full name'),
                  const SizedBox(height: 8),
                  _SettingsFinishedTextField(
                    key: ValueKey('fullName-$_formRevision'),
                    initialValue: _draftPreferences.fullName,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    hintText: 'Enter your full name',
                    onChanged: (value) => _update(
                      _draftPreferences.copyWith(fullName: value.trim()),
                    ),
                    onFinished: () => _persist(
                      _draftPreferences,
                      successMessage: 'Personal details updated.',
                      failureMessage: 'Could not save personal details.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Employer / company'),
                  const SizedBox(height: 8),
                  _SettingsFinishedTextField(
                    key: ValueKey('companyName-$_formRevision'),
                    initialValue: _draftPreferences.companyName,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    hintText: 'Enter employer or company name',
                    onChanged: (value) => _update(
                      _draftPreferences.copyWith(companyName: value.trim()),
                    ),
                    onFinished: () => _persist(
                      _draftPreferences,
                      successMessage: 'Personal details updated.',
                      failureMessage: 'Could not save personal details.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Pay & currency'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Currency'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      '${_draftPreferences.currency.code}-'
                      '$_currencyPickerRevision',
                    ),
                    isExpanded: true,
                    initialValue: _draftPreferences.currency.code,
                    items: CurrencyCatalog.supported
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency.code,
                            child: Text(
                              '${currency.displayName} · ${currency.symbol}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (code) {
                      if (code != null &&
                          code != _draftPreferences.currency.code) {
                        _confirmCurrencyChange(CurrencyCatalog.byCode(code));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Primary rate'),
                  const SizedBox(height: 12),
                  _SettingsTextField(
                    key: ValueKey('primaryRateLabel-$_formRevision'),
                    label: 'Name',
                    value: _draftPreferences.primaryRateLabel,
                    hint: 'Standard',
                    maxLength: 24,
                    onChanged: (value) => _update(
                      _draftPreferences.copyWith(
                        primaryRateLabel: value.trim(),
                      ),
                    ),
                    onFinished: () => _persist(
                      _draftPreferences,
                      successMessage: 'Pay rates updated.',
                      failureMessage: 'Rate names cannot be blank.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Hourly rate'),
                  const SizedBox(height: 8),
                  _SelectAllTextFormField(
                    key: ValueKey('homeRate-$_formRevision'),
                    initialValue: _currencyInputValue(
                      _draftPreferences.primaryRateValue,
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      prefixText: _currencyPrefix,
                      hintText: 'e.g. 20.00',
                    ),
                    onChanged: (value) => _update(
                      _draftPreferences.copyWith(
                        primaryRateValue: value.trim().isEmpty
                            ? 0
                            : double.tryParse(value),
                      ),
                    ),
                    onFinished: () => _persist(
                      _draftPreferences,
                      successMessage: 'Pay rates updated.',
                      failureMessage: 'Could not save pay rates.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 32),
                  const FieldLabel('Secondary rate'),
                  const SizedBox(height: 12),
                  _SettingsTextField(
                    key: ValueKey('secondaryRateLabel-$_formRevision'),
                    label: 'Name',
                    value: _draftPreferences.secondaryRateLabel,
                    hint: 'Overtime',
                    maxLength: 24,
                    onChanged: (value) => _update(
                      _draftPreferences.copyWith(
                        secondaryRateLabel: value.trim(),
                      ),
                    ),
                    onFinished: () => _persist(
                      _draftPreferences,
                      successMessage: 'Pay rates updated.',
                      failureMessage: 'Rate names cannot be blank.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Hourly rate'),
                  const SizedBox(height: 8),
                  _SelectAllTextFormField(
                    key: ValueKey('awayRate-$_formRevision'),
                    initialValue: _currencyInputValue(
                      _draftPreferences.secondaryRateValue,
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      prefixText: _currencyPrefix,
                      hintText: 'e.g. 25.00',
                    ),
                    onChanged: (value) => _update(
                      _draftPreferences.copyWith(
                        secondaryRateValue: value.trim().isEmpty
                            ? 0
                            : double.tryParse(value),
                      ),
                    ),
                    onFinished: () => _persist(
                      _draftPreferences,
                      successMessage: 'Pay rates updated.',
                      failureMessage: 'Could not save pay rates.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Work defaults'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SettingsTextField(
                          key: ValueKey('defaultStart-$_formRevision'),
                          label: 'Default start time',
                          value: _draftPreferences.defaultStartTime,
                          hint: '08:00',
                          normalizeTime: true,
                          onChanged: (value) => _update(
                            _draftPreferences.copyWith(defaultStartTime: value),
                          ),
                          onFinished: () => _persist(
                            _draftPreferences,
                            failureMessage: 'Could not save work defaults.',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SettingsTextField(
                          key: ValueKey('defaultFinish-$_formRevision'),
                          label: 'Default finish time',
                          value: _draftPreferences.defaultFinishTime,
                          hint: '16:30',
                          normalizeTime: true,
                          onChanged: (value) => _update(
                            _draftPreferences.copyWith(
                              defaultFinishTime: value,
                            ),
                          ),
                          onFinished: () => _persist(
                            _draftPreferences,
                            failureMessage: 'Could not save work defaults.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsTextField(
                    key: ValueKey('defaultBreak-$_formRevision'),
                    label: 'Default break minutes',
                    value: _draftPreferences.defaultBreakMinutes.toString(),
                    hint: '30',
                    keyboardType: TextInputType.number,
                    onChanged: (value) => _update(
                      _draftPreferences.copyWith(
                        defaultBreakMinutes: int.tryParse(value),
                      ),
                    ),
                    onFinished: () => _persist(
                      _draftPreferences,
                      failureMessage: 'Could not save work defaults.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const FieldLabel('Default rate'),
                  const SizedBox(height: 9),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'primary',
                          label: Text(
                            _draftPreferences.labelForRate('primary'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ButtonSegment(
                          value: 'secondary',
                          label: Text(
                            _draftPreferences.labelForRate('secondary'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      selected: {_draftPreferences.defaultRateType},
                      onSelectionChanged: (values) => _persist(
                        _draftPreferences.copyWith(
                          defaultRateType: values.first,
                        ),
                        failureMessage: 'Could not save work defaults.',
                      ),
                      showSelectedIcon: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Pay schedule'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Pay period type'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('payFrequency-$_formRevision'),
                    isExpanded: true,
                    initialValue: normalisePayFrequency(
                      _draftPreferences.payFrequency,
                    ),
                    items:
                        const [
                              weeklyPayFrequency,
                              fortnightlyPayFrequency,
                              fourWeeklyPayFrequency,
                              calendarMonthlyPayFrequency,
                              customMonthlyPayFrequency,
                              lastFridayPayFrequency,
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final allowedRules = _paydayRulesFor(value);
                      final currentRule =
                          _draftPreferences.paydayRule == paydayFollowingWeekday
                          ? paydayNextSelectedWeekdayAfterPeriodEnd
                          : _draftPreferences.paydayRule;
                      _updatePaySchedule(
                        _draftPreferences.copyWith(
                          payFrequency: value,
                          paydayRule: allowedRules.contains(currentRule)
                              ? currentRule
                              : paydayOnPeriodEnd,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  ..._payScheduleControls(context),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Appearance'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Theme'),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {
                      themeModeFromSettings(_draftPreferences.themeMode),
                    },
                    onSelectionChanged: (selection) async {
                      try {
                        await widget.onThemeModeChanged(selection.first);
                      } catch (error, stackTrace) {
                        if (kDebugMode) {
                          debugPrint('theme persistence failed: $error');
                          debugPrintStack(stackTrace: stackTrace);
                        }
                        if (!mounted) return;
                        setState(() => _formRevision++);
                        _showSettingsFeedback('Could not update theme.');
                      }
                    },
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Security'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('App lock'),
                    subtitle: const Text(
                      'Disabled by default. Forgotten PIN recovery may require reinstalling.',
                    ),
                    value: widget.lockConfig.enabled,
                    onChanged: (value) async {
                      try {
                        if (value && !widget.lockConfig.hasPin) {
                          final pin = await _promptForPin(context);
                          if (pin == null) return;
                          await widget.onSetLockPin(pin);
                        }
                        await widget.onLockConfigChanged(
                          widget.lockConfig.copyWith(enabled: value),
                        );
                        _showSettingsFeedback(
                          value ? 'App lock enabled.' : 'App lock disabled.',
                        );
                      } catch (error, stackTrace) {
                        if (kDebugMode) {
                          debugPrint('app-lock persistence failed: $error');
                          debugPrintStack(stackTrace: stackTrace);
                        }
                        if (!mounted) return;
                        _showSettingsFeedback('Could not update app lock.');
                      }
                    },
                  ),
                  SwitchListTile(
                    key: const ValueKey('device-authentication-setting'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use device authentication'),
                    subtitle: const Text(
                      'Unlock Briska Pay using your fingerprint, face, '
                      'or device screen lock. This is separate from your '
                      'Briska Pay PIN.',
                    ),
                    value: widget.lockConfig.useBiometrics,
                    onChanged:
                        widget.lockConfig.enabled &&
                            _deviceAuthenticationAvailable == true
                        ? (value) async {
                            try {
                              await widget.onLockConfigChanged(
                                widget.lockConfig.copyWith(
                                  useBiometrics: value,
                                ),
                              );
                            } catch (error, stackTrace) {
                              if (kDebugMode) {
                                debugPrint(
                                  'device authentication preference '
                                  'persistence failed: '
                                  '$error',
                                );
                                debugPrintStack(stackTrace: stackTrace);
                              }
                              if (!mounted) return;
                              _showSettingsFeedback(
                                'Could not update device authentication.',
                              );
                            }
                          }
                        : null,
                  ),
                  if (_deviceAuthenticationAvailable == false)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Device authentication is unavailable on this device. '
                        'Your Briska Pay PIN remains available.',
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: widget.lockConfig.lockAfterSeconds,
                    decoration: const InputDecoration(
                      labelText: 'Lock when backgrounded',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Immediately')),
                      DropdownMenuItem(
                        value: 60,
                        child: Text('After 1 minute'),
                      ),
                      DropdownMenuItem(
                        value: 300,
                        child: Text('After 5 minutes'),
                      ),
                      DropdownMenuItem(
                        value: 900,
                        child: Text('After 15 minutes'),
                      ),
                    ],
                    onChanged: widget.lockConfig.enabled
                        ? (value) async {
                            try {
                              await widget.onLockConfigChanged(
                                widget.lockConfig.copyWith(
                                  lockAfterSeconds: value ?? 60,
                                ),
                              );
                            } catch (error, stackTrace) {
                              if (kDebugMode) {
                                debugPrint(
                                  'lock timeout persistence failed: $error',
                                );
                                debugPrintStack(stackTrace: stackTrace);
                              }
                              if (!mounted) return;
                              _showSettingsFeedback(
                                'Could not update lock timeout.',
                              );
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.lockConfig.enabled
                        ? () async {
                            final pin = await _promptForPin(context);
                            if (pin != null) {
                              try {
                                await widget.onSetLockPin(pin);
                                _showSettingsFeedback('PIN updated.');
                              } catch (error, stackTrace) {
                                if (kDebugMode) {
                                  debugPrint('PIN persistence failed: $error');
                                  debugPrintStack(stackTrace: stackTrace);
                                }
                                if (!mounted) return;
                                _showSettingsFeedback('Could not update PIN.');
                              }
                            }
                          }
                        : null,
                    icon: const Icon(Icons.pin_outlined),
                    label: const Text('Set PIN fallback'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading(title: 'Data & backup'),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                children: [
                  BriskaPrimaryButton(
                    icon: Icons.backup_outlined,
                    label: 'Create Briska Pay Backup',
                    onPressed: widget.onCreateBackup,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onRestoreBackup,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Restore Briska Pay Backup'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (widget.privacyOptionsRequired) ...[
            const SectionHeading(title: 'Advertising'),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Advertising privacy choices'),
                subtitle: const Text(
                  'Review or change your advertising privacy choices.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  try {
                    await widget.onShowAdvertisingPrivacyChoices?.call();
                  } catch (error, stackTrace) {
                    if (kDebugMode) {
                      debugPrint('advertising privacy options failed: $error');
                      debugPrintStack(stackTrace: stackTrace);
                    }
                    _showSettingsFeedback(
                      'Could not open advertising privacy choices.',
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 22),
          ],
          const SectionHeading(title: 'Briska Pay'),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const BriskaLogo(size: 40),
              title: const Text('About Briska Pay'),
              subtitle: const Text(
                'Version, support, privacy and legal information.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: widget.onShowAbout,
            ),
          ),
          if (widget.showTesterTools ?? showBetaTools) ...[
            const SizedBox(height: 22),
            const SectionHeading(title: 'Beta feedback'),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Report a bug'),
                    subtitle: const Text('Opens support with app diagnostics.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(
                      context,
                    ).push(_BriskaPageRoute(child: const SupportScreen())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lightbulb_outline_rounded),
                    title: const Text('Suggest an improvement'),
                    subtitle: const Text(
                      'No separate app analytics service included.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(
                      context,
                    ).push(_BriskaPageRoute(child: const SupportScreen())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('View beta checklist'),
                    subtitle: const Text('Tester release checklist.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      _BriskaPageRoute(child: const BetaChecklistScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<String?> _promptForPin(BuildContext context) async {
    var enteredPin = '';
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set Briska Pay PIN'),
        content: TextField(
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 12,
          onChanged: (value) => enteredPin = value,
          decoration: const InputDecoration(
            labelText: 'PIN',
            helperText:
                'Use at least 4 digits. Forgotten PINs cannot be recovered securely.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = enteredPin.trim();
              if (value.length < 4) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
    return pin;
  }

  List<Widget> _payScheduleControls(BuildContext context) {
    final type = normalisePayFrequency(_draftPreferences.payFrequency);
    if (fixedCyclePayFrequencies.contains(type)) {
      return [
        Text(
          'Periods repeat every ${type == weeklyPayFrequency
              ? 7
              : type == fortnightlyPayFrequency
              ? 14
              : 28} days from a known pay period start date.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Known pay period start date'),
        const SizedBox(height: 8),
        _DatePickerTile(
          value: _dateLabel(
            _parseSettingsDate(_draftPreferences.payPeriodAnchorDate),
          ),
          isMissing: requiresPayPeriodAnchor(_draftPreferences),
          onPressed: _chooseAnchorDate,
        ),
        if (requiresPayPeriodAnchor(_draftPreferences)) ...[
          const SizedBox(height: 10),
          Text(
            'Choose an anchor date so Briska Pay can calculate periods forwards and backwards accurately.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        ..._paydayRuleControls(type),
      ];
    }
    if (type == calendarMonthlyPayFrequency) {
      return [
        Text(
          'Period runs from the first to the last day of each month.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ..._paydayRuleControls(type),
      ];
    }
    if (type == customMonthlyPayFrequency) {
      return [
        const FieldLabel('Period start day'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _draftPreferences.customPeriodStartDay.clamp(1, 31),
          items: List.generate(
            31,
            (index) =>
                DropdownMenuItem(value: index + 1, child: Text('${index + 1}')),
          ),
          onChanged: (value) => _updatePaySchedule(
            _draftPreferences.copyWith(customPeriodStartDay: value),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The period ends on the day before the next period begins.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ..._paydayRuleControls(type),
      ];
    }
    return [
      Text(
        'Period starts on the first Monday after the previous month\'s last Friday, ends on the current month\'s last Friday, and payday is the current month\'s last Friday.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  List<Widget> _paydayRuleControls(String type) {
    final allowedRules = _paydayRulesFor(type);
    final storedRule = _draftPreferences.paydayRule == paydayFollowingWeekday
        ? paydayNextSelectedWeekdayAfterPeriodEnd
        : _draftPreferences.paydayRule;
    final rule = allowedRules.contains(storedRule)
        ? storedRule
        : paydayOnPeriodEnd;
    final widgets = <Widget>[
      const FieldLabel('Payday rule'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: rule,
        items: allowedRules
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) =>
            _updatePaySchedule(_draftPreferences.copyWith(paydayRule: value)),
      ),
    ];
    if (rule == paydayDaysAfterPeriodEnd) {
      widgets.addAll([
        const SizedBox(height: 16),
        _SettingsTextField(
          label: 'Days after period end',
          value: _draftPreferences.paydayOffsetDays.toString(),
          hint: '0',
          keyboardType: TextInputType.number,
          onChanged: (value) => _update(
            _draftPreferences.copyWith(paydayOffsetDays: int.tryParse(value)),
          ),
          onFinished: () => _persist(
            _draftPreferences,
            successMessage: 'Pay schedule updated.',
            failureMessage: 'Could not update pay schedule.',
          ),
        ),
      ]);
    }
    if (rule == paydayNextSelectedWeekdayAfterPeriodEnd) {
      widgets.addAll([
        const SizedBox(height: 16),
        const FieldLabel('Payday weekday'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: _draftPreferences.paydaySelectedWeekday.clamp(
            DateTime.monday,
            DateTime.sunday,
          ),
          items: List.generate(
            DateTime.daysPerWeek,
            (index) => DropdownMenuItem(
              value: index + DateTime.monday,
              child: Text(_weekdayNames[index]),
            ),
          ),
          onChanged: (value) => _updatePaySchedule(
            _draftPreferences.copyWith(
              paydaySelectedWeekday: value,
              paydayWeekday: value == null ? null : _weekdayNames[value - 1],
              payDay: value == null ? null : _weekdayNames[value - 1],
            ),
          ),
        ),
      ]);
    }
    if (rule == paydayFixedDaySameMonth ||
        rule == paydayFixedDayFollowingMonth) {
      widgets.addAll([
        const SizedBox(height: 16),
        const FieldLabel('Fixed calendar day'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _draftPreferences.paydayFixedDay.clamp(1, 31),
          items: List.generate(
            31,
            (index) =>
                DropdownMenuItem(value: index + 1, child: Text('${index + 1}')),
          ),
          onChanged: (value) => _updatePaySchedule(
            _draftPreferences.copyWith(paydayFixedDay: value),
          ),
        ),
      ]);
    }
    return widgets;
  }

  List<String> _paydayRulesFor(String type) {
    final normalised = normalisePayFrequency(type);
    if (fixedCyclePayFrequencies.contains(normalised)) {
      return const [
        paydayOnPeriodEnd,
        paydayDaysAfterPeriodEnd,
        paydayNextSelectedWeekdayAfterPeriodEnd,
      ];
    }
    if (normalised == lastFridayPayFrequency) {
      return const [paydayOnPeriodEnd];
    }
    return const [
      paydayOnPeriodEnd,
      paydayDaysAfterPeriodEnd,
      paydayNextSelectedWeekdayAfterPeriodEnd,
      paydayFixedDaySameMonth,
      paydayFixedDayFollowingMonth,
      paydayLastWorkingDaySameMonth,
      paydayLastFridayOfMonth,
    ];
  }

  Future<void> _showAnchorPrompt() async {
    final chooseNow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose pay period start'),
        content: const Text(
          'Weekly, fortnightly and four-weekly schedules need a known pay period start date before Briska Pay can calculate your periods accurately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Choose date'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (chooseNow == true) {
      await _chooseAnchorDate();
    } else {
      await _persist(
        _draftPreferences.copyWith(payScheduleAnchorPrompted: true),
        failureMessage: 'Could not update pay schedule.',
      );
    }
  }

  Future<void> _chooseAnchorDate() async {
    final current =
        _parseSettingsDate(_draftPreferences.payPeriodAnchorDate) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _updatePaySchedule(
      _draftPreferences.copyWith(
        payPeriodAnchorDate: _settingsDateValue(picked),
        payScheduleAnchorPrompted: true,
      ),
    );
  }

  DateTime? _parseSettingsDate(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _settingsDateValue(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Choose date';
    return formatFullDate(date);
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.value,
    required this.isMissing,
    required this.onPressed,
  });

  final String value;
  final bool isMissing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        isMissing ? Icons.event_busy_outlined : Icons.event_available_outlined,
      ),
      label: Align(alignment: Alignment.centerLeft, child: Text(value)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: isMissing ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.keyboardType,
    this.normalizeTime = false,
    this.onFinished,
    this.maxLength,
  });

  final String label;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool normalizeTime;
  final VoidCallback? onFinished;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    if (normalizeTime) {
      return _TimeInputField(
        label: label,
        hint: hint,
        initialValue: value,
        onChanged: onChanged,
        onFinished: onFinished,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: 8),
        _SelectAllTextFormField(
          initialValue: value,
          keyboardType: keyboardType,
          maxLength: maxLength,
          decoration: InputDecoration(hintText: hint),
          onChanged: onChanged,
          onFinished: onFinished,
        ),
      ],
    );
  }
}

class _SettingsFinishedTextField extends StatefulWidget {
  const _SettingsFinishedTextField({
    super.key,
    required this.initialValue,
    required this.hintText,
    required this.onChanged,
    required this.onFinished,
    required this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
  });

  final String initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onFinished;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;

  @override
  State<_SettingsFinishedTextField> createState() =>
      _SettingsFinishedTextFieldState();
}

class _SettingsFinishedTextFieldState
    extends State<_SettingsFinishedTextField> {
  late final FocusNode _focusNode;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  void _finishIfEdited() {
    if (!_edited) return;
    _edited = false;
    widget.onFinished();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _finishIfEdited();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: widget.initialValue,
      focusNode: _focusNode,
      textCapitalization: widget.textCapitalization,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(hintText: widget.hintText),
      onChanged: (value) {
        _edited = true;
        widget.onChanged(value);
      },
      onFieldSubmitted: (_) => _finishIfEdited(),
    );
  }
}

class _SelectAllTextFormField extends StatefulWidget {
  const _SelectAllTextFormField({
    super.key,
    this.initialValue,
    this.keyboardType,
    this.decoration,
    this.textInputAction,
    this.onChanged,
    this.onFinished,
    this.maxLength,
  });

  final String? initialValue;
  final TextInputType? keyboardType;
  final InputDecoration? decoration;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFinished;
  final int? maxLength;

  @override
  State<_SelectAllTextFormField> createState() =>
      _SelectAllTextFormFieldState();
}

class _SelectAllTextFormFieldState extends State<_SelectAllTextFormField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _selectedForFocus = false;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(_SelectAllTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _finishIfEdited() {
    if (!_edited) return;
    _edited = false;
    widget.onFinished?.call();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      _finishIfEdited();
      return;
    }
    if (_selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        duration: BriskaDurations.standard,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      decoration: widget.decoration,
      onChanged: (value) {
        _edited = true;
        widget.onChanged?.call(value);
      },
      onFieldSubmitted: (_) => _finishIfEdited(),
    );
  }
}

class AddWorkDayScreen extends StatefulWidget {
  const AddWorkDayScreen({
    required this.preferences,
    required this.savedEntries,
    required this.onSave,
    this.initialEntry,
    this.initialDate,
    super.key,
  });

  final AppSettings preferences;
  final List<WorkEntry> savedEntries;
  final WorkEntry? initialEntry;
  final DateTime? initialDate;
  final Future<bool> Function(WorkEntry entry) onSave;

  @override
  State<AddWorkDayScreen> createState() => _AddWorkDayScreenState();
}

class _SiteNameAutocomplete extends StatefulWidget {
  const _SiteNameAutocomplete({
    required this.controller,
    required this.entries,
    this.selectAllOnFocus = false,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<WorkEntry> entries;
  final bool selectAllOnFocus;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<_SiteNameAutocomplete> createState() => _SiteNameAutocompleteState();
}

class _SiteNameAutocompleteState extends State<_SiteNameAutocomplete> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  bool _selectedForFocus = false;

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      return;
    }
    if (widget.controller.text.trim().isEmpty) {
      setState(() {});
      return;
    }
    if (!widget.selectAllOnFocus || _selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) => recentSiteNameSuggestions(
        widget.entries,
        query: value.text,
        limit: value.text.trim().isEmpty ? 5 : 8,
      ),
      onSelected: (value) {
        widget.controller
          ..text = value
          ..selection = TextSelection.collapsed(offset: value.length);
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Where did you work?',
                prefixIcon: Icon(Icons.work_outline_rounded),
              ).copyWith(errorText: widget.errorText),
              onChanged: widget.onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onTap: () {
                if (textEditingController.text.trim().isEmpty) {
                  setState(() {});
                }
              },
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        final colorScheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 18),
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AddWorkDayScreenState extends State<AddWorkDayScreen> {
  late String _entryType;
  bool _isPaidSickDay = false;
  bool _isPaidBankHoliday = true;
  late String _rateType;
  late double _selectedRate;
  late double _appliedAllowance;
  late bool _allowanceHasValue;
  double _jobUplift = 0;
  double _deductionAmount = 0;
  late String _startTime;
  late String _finishTime;
  late int _breakMinutes;
  late DateTime _date;
  String? _editingEntryId;
  late final TextEditingController _siteController;
  late final TextEditingController _notesController;
  late final TextEditingController _deductionReasonController;
  String? _siteError;

  @override
  void initState() {
    super.initState();
    final preferences = widget.preferences;
    final entry = widget.initialEntry;
    _editingEntryId = entry?.id;
    _entryType = entry?.entryType ?? 'WorkDay';
    _isPaidSickDay = entry?.isPaidSickDay ?? false;
    _isPaidBankHoliday = entry?.isPaidBankHoliday ?? true;
    _rateType = entry?.rateType ?? preferences.defaultRateType;
    _selectedRate =
        entry?.hourlyRateUsed ??
        (_rateType == 'primary'
            ? preferences.primaryRateValue
            : preferences.secondaryRateValue);
    _appliedAllowance = entry?.dailyAllowance ?? 0;
    _allowanceHasValue = entry != null && entry.dailyAllowance != 0;
    _jobUplift = entry?.jobUplift ?? 0;
    _deductionAmount = entry?.deductionAmount ?? 0;
    _startTime = entry?.startTime ?? preferences.defaultStartTime;
    _finishTime = entry?.finishTime ?? preferences.defaultFinishTime;
    _breakMinutes = entry?.breakMinutes ?? preferences.defaultBreakMinutes;
    _date = entry?.date ?? widget.initialDate ?? DateTime.now();
    _siteController = TextEditingController(text: entry?.siteName ?? '');
    _notesController = TextEditingController(text: entry?.notes ?? '');
    _deductionReasonController = TextEditingController(
      text: entry?.deductionReason ?? '',
    );
    if (_entryType == 'Holiday') {
      _rateType = 'primary';
      _selectedRate = preferences.primaryRateValue;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    } else if (_entryType == 'bankHoliday') {
      _rateType = 'primary';
      _selectedRate = _isPaidBankHoliday ? preferences.primaryRateValue : 0;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    } else if (_entryType == 'UnpaidDayOff' || _entryType == 'SickDay') {
      _rateType = 'primary';
      _selectedRate = _entryType == 'SickDay' && _isPaidSickDay
          ? preferences.primaryRateValue
          : 0;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    }
  }

  @override
  void dispose() {
    _siteController.dispose();
    _notesController.dispose();
    _deductionReasonController.dispose();
    super.dispose();
  }

  WorkCalculation get _calculation => WorkCalculator.calculate(
    startTime: _startTime,
    finishTime: _finishTime,
    breakMinutes: _breakMinutes,
    hourlyRate: _selectedRate,
    rateType: _rateType,
    dailyAllowance: _appliedAllowance,
    jobUplift: _jobUplift,
    entryType: _entryType,
    isPaidSickDay: _isPaidSickDay,
    isPaidBankHoliday: _isPaidBankHoliday,
    deductionAmount: _deductionAmount,
  );

  void _selectEntryType(String value) {
    setState(() {
      _entryType = value;
      if (value == 'Holiday') {
        _rateType = 'primary';
        _selectedRate = widget.preferences.primaryRateValue;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else if (value == 'bankHoliday') {
        _isPaidBankHoliday = true;
        _rateType = 'primary';
        _selectedRate = widget.preferences.primaryRateValue;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else if (value == 'UnpaidDayOff') {
        _rateType = 'primary';
        _selectedRate = 0;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else if (value == 'SickDay') {
        _isPaidSickDay = false;
        _rateType = 'primary';
        _selectedRate = 0;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else {
        _rateType = widget.preferences.defaultRateType;
        _selectedRate = _rateType == 'primary'
            ? widget.preferences.primaryRateValue
            : widget.preferences.secondaryRateValue;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      }
    });
  }

  void _selectRateType(String rateType) {
    setState(() {
      _rateType = rateType;
      _selectedRate = rateType == 'primary'
          ? widget.preferences.primaryRateValue
          : widget.preferences.secondaryRateValue;
    });
  }

  Future<void> _save() async {
    if (_entryType == 'WorkDay' && _siteController.text.trim().isEmpty) {
      setState(() => _siteError = 'Enter a site/job name');
      return;
    }
    FocusScope.of(context).unfocus();
    final calculation = _calculation;
    if (!calculation.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(calculation.error!)));
      return;
    }
    final duplicate = widget.savedEntries.where((entry) {
      final sameDate =
          entry.date.year == _date.year &&
          entry.date.month == _date.month &&
          entry.date.day == _date.day;
      return sameDate && entry.id != _editingEntryId;
    }).toList();
    if (duplicate.isNotEmpty) {
      final choice = await showDialog<_DuplicateChoice>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Entry already exists'),
          content: Text(
            'There is already ${duplicate.length == 1 ? 'an entry' : '${duplicate.length} entries'} for this date.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateChoice.editExisting),
              child: const Text('Edit existing'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateChoice.continueAnyway),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == _DuplicateChoice.cancel) {
        return;
      }
      if (choice == _DuplicateChoice.editExisting) {
        final existing = duplicate.first;
        setState(() {
          _editingEntryId = existing.id;
          _entryType = existing.entryType;
          _isPaidSickDay = existing.isPaidSickDay;
          _isPaidBankHoliday = existing.isPaidBankHoliday;
          _rateType = existing.rateType;
          _selectedRate = existing.hourlyRateUsed;
          _appliedAllowance = existing.dailyAllowance;
          _allowanceHasValue = existing.dailyAllowance != 0;
          _jobUplift = existing.jobUplift;
          _deductionAmount = existing.deductionAmount;
          _deductionReasonController.text = existing.deductionReason;
          _startTime = existing.startTime;
          _finishTime = existing.finishTime;
          _breakMinutes = existing.breakMinutes;
          _date = existing.date;
          _siteController.text = existing.siteName;
          _notesController.text = existing.notes;
        });
        return;
      }
    }
    final entry = WorkEntry(
      id: _editingEntryId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      entryType: _entryType,
      date: _date,
      siteName: _entryType == 'WorkDay' ? _siteController.text.trim() : '',
      startTime: _entryType == 'WorkDay'
          ? WorkCalculator.normalizeTime(_startTime)!
          : '',
      finishTime: _entryType == 'WorkDay'
          ? WorkCalculator.normalizeTime(_finishTime)!
          : '',
      breakMinutes: _entryType == 'WorkDay' ? _breakMinutes : 0,
      rateType: _entryType == 'WorkDay' ? _rateType : 'primary',
      hourlyRateUsed: _selectedRate,
      dailyAllowance: _entryType == 'WorkDay' ? _appliedAllowance : 0,
      jobUplift: _jobUplift,
      totalHours: calculation.totalHours,
      wages: calculation.wages,
      totalPay: calculation.totalPay,
      notes: _notesController.text.trim(),
      isPaidSickDay: _isPaidSickDay,
      isPaidBankHoliday: _isPaidBankHoliday,
      deductionAmount: _deductionAmount,
      deductionReason: _deductionReasonController.text.trim(),
    );
    final saved = await widget.onSave(entry);
    if (!mounted) return;
    if (!saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.initialEntry == null ? 'Day saved.' : 'Day updated.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialEntry == null ? 'Add Day' : 'Edit Day'),
        centerTitle: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: AppPage(
        topPadding: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record your day',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Everything you need for an accurate record.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _EntrySectionHeading(
                      icon: Icons.event_note_outlined,
                      title: 'Entry details',
                      subtitle: 'Choose the day type and date',
                    ),
                    const SizedBox(height: 22),
                    const FieldLabel('Day Type'),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          const [
                            (EntryType.workDay, 'Work Day', Icons.work_outline),
                            (
                              EntryType.holiday,
                              'Holiday',
                              Icons.beach_access_outlined,
                            ),
                            (
                              EntryType.bankHoliday,
                              'Bank Holiday',
                              Icons.account_balance_rounded,
                            ),
                            (
                              EntryType.sickDay,
                              'Sick Day',
                              Icons.sick_outlined,
                            ),
                            (
                              EntryType.unpaidDayOff,
                              'Unpaid Day Off',
                              Icons.event_busy_outlined,
                            ),
                          ].map((option) {
                            final selected =
                                _entryType == option.$1.storageValue;
                            return ChoiceChip(
                              key: ValueKey('day-type-${option.$1.name}'),
                              selected: selected,
                              avatar: Icon(option.$3, size: 18),
                              label: Text(option.$2),
                              onSelected: (_) =>
                                  _selectEntryType(option.$1.storageValue),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Date'),
                    const SizedBox(height: 8),
                    TextField(
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: formatFullDate(_date),
                        suffixIcon: const Icon(Icons.calendar_today_outlined),
                      ),
                      onTap: () async {
                        final value = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (value != null) setState(() => _date = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_entryType == 'WorkDay') ...[
                            const FieldLabel('Site/job name'),
                            const SizedBox(height: 8),
                            _SiteNameAutocomplete(
                              controller: _siteController,
                              entries: widget.savedEntries,
                              selectAllOnFocus: widget.initialEntry != null,
                              errorText: _siteError,
                              onChanged: (_) {
                                if (_siteError != null) {
                                  setState(() => _siteError = null);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_entryType == 'WorkDay') ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _TimeInputField(
                                    label: 'Start time',
                                    hint: '08:00',
                                    initialValue: _startTime,
                                    onChanged: (value) =>
                                        setState(() => _startTime = value),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TimeInputField(
                                    label: 'Finish time',
                                    hint: '16:30',
                                    initialValue: _finishTime,
                                    onChanged: (value) =>
                                        setState(() => _finishTime = value),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _LabeledField(
                              label: 'Break minutes',
                              hint: 'Enter minutes',
                              initialValue: _breakMinutes.toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final text = value.trim();
                                setState(
                                  () => _breakMinutes = text.isEmpty
                                      ? 0
                                      : (int.tryParse(text) ?? -1),
                                );
                              },
                            ),
                            if (!_calculation.isValid) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      _calculation.error!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 26),
                            const Divider(height: 1),
                            const SizedBox(height: 24),
                            const _EntrySectionHeading(
                              icon: Icons.payments_outlined,
                              title: 'Pay details',
                              subtitle: 'Rate and extras',
                            ),
                            const SizedBox(height: 22),
                            const FieldLabel('Rate used'),
                            const SizedBox(height: 9),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<String>(
                                segments: [
                                  ButtonSegment(
                                    value: 'primary',
                                    label: Text(
                                      widget.preferences.labelForRate(
                                        'primary',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'secondary',
                                    label: Text(
                                      widget.preferences.labelForRate(
                                        'secondary',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                selected: {_rateType},
                                onSelectionChanged: (values) =>
                                    _selectRateType(values.first),
                                showSelectedIcon: false,
                              ),
                            ),
                            const SizedBox(height: 16),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const FieldLabel('Hourly rate for this day'),
                                  const SizedBox(height: 8),
                                  _SelectAllTextFormField(
                                    key: ValueKey('rate-$_rateType'),
                                    initialValue: _currencyInputValue(
                                      _selectedRate,
                                    ),
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      prefixText: _currencyPrefix,
                                      suffixText: '/ hour',
                                    ),
                                    onChanged: (value) => setState(
                                      () => _selectedRate = value.trim().isEmpty
                                          ? 0
                                          : (double.tryParse(value) ?? -1),
                                    ),
                                  ),
                                  ...[
                                    const SizedBox(height: 14),
                                    const FieldLabel('Daily allowance'),
                                    const SizedBox(height: 8),
                                    _SelectAllTextFormField(
                                      key: ValueKey(
                                        'allowance-$_editingEntryId-$_rateType',
                                      ),
                                      initialValue: _allowanceHasValue
                                          ? _currencyInputValue(
                                              _appliedAllowance,
                                            )
                                          : '',
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.done,
                                      decoration: InputDecoration(
                                        prefixText: _currencyPrefix,
                                        hintText: 'e.g. 25.00',
                                        helperText:
                                            'Optional. Leave blank for no allowance.',
                                      ),
                                      onChanged: (value) {
                                        final text = value.trim();
                                        setState(() {
                                          _allowanceHasValue = text.isNotEmpty;
                                          _appliedAllowance = text.isEmpty
                                              ? 0
                                              : (double.tryParse(text) ?? -1);
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],
                          if (_entryType == 'Holiday') ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  _CalculationLine(
                                    label: 'Holiday hours',
                                    value: formatHoursLabel(8),
                                    emphasize: true,
                                  ),
                                  const SizedBox(height: 8),
                                  _CalculationLine(
                                    label:
                                        '${widget.preferences.labelForRate('primary')} hourly rate',
                                    value: '${_money(_selectedRate)} / hour',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_entryType == 'SickDay') ...[
                            const FieldLabel('Sick Pay'),
                            const SizedBox(height: 9),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Paid at Primary Rate'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Unpaid'),
                                  ),
                                ],
                                selected: {_isPaidSickDay},
                                onSelectionChanged: (values) => setState(() {
                                  _isPaidSickDay = values.first;
                                  _rateType = 'primary';
                                  _selectedRate = _isPaidSickDay
                                      ? widget.preferences.primaryRateValue
                                      : 0;
                                }),
                                showSelectedIcon: false,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  _CalculationLine(
                                    label: 'Sick Day',
                                    value: _isPaidSickDay ? 'Paid' : 'Unpaid',
                                    emphasize: true,
                                  ),
                                  const SizedBox(height: 8),
                                  _CalculationLine(
                                    label: 'Hours',
                                    value: formatHoursLabel(
                                      _isPaidSickDay ? 8 : 0,
                                    ),
                                  ),
                                  if (_isPaidSickDay) ...[
                                    const SizedBox(height: 8),
                                    _CalculationLine(
                                      label: 'Paid at',
                                      value: widget.preferences.labelForRate(
                                        'primary',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_entryType == 'bankHoliday') ...[
                            const FieldLabel('Pay Status'),
                            const SizedBox(height: 9),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Paid'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Unpaid'),
                                  ),
                                ],
                                selected: {_isPaidBankHoliday},
                                onSelectionChanged: (values) => setState(() {
                                  _isPaidBankHoliday = values.first;
                                  _rateType = 'primary';
                                  _selectedRate = _isPaidBankHoliday
                                      ? widget.preferences.primaryRateValue
                                      : 0;
                                }),
                                showSelectedIcon: false,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _CalculationLine(
                              label: 'Bank Holiday',
                              value: _isPaidBankHoliday
                                  ? 'Paid · 8 hours'
                                  : 'Unpaid · 0 hours',
                              emphasize: true,
                            ),
                            if (_isPaidBankHoliday) ...[
                              const SizedBox(height: 8),
                              _CalculationLine(
                                label: 'Paid at',
                                value:
                                    '${widget.preferences.labelForRate('primary')} · ${_money(_selectedRate)} / hour',
                              ),
                            ],
                            const SizedBox(height: 18),
                          ],
                        ],
                      ),
                    ),
                    ...[
                      const FieldLabel('Job uplift'),
                      const SizedBox(height: 8),
                      _OptionalCurrencyField(
                        key: const ValueKey('job-uplift-field'),
                        initialValue: _jobUplift,
                        onChanged: (value) =>
                            setState(() => _jobUplift = value),
                      ),
                      const SizedBox(height: 18),
                    ],
                    const _EntrySectionHeading(
                      icon: Icons.remove_circle_outline,
                      title: 'Deduction',
                      subtitle: 'Optional pay adjustment',
                    ),
                    const SizedBox(height: 12),
                    _OptionalCurrencyField(
                      key: const ValueKey('deduction-amount-field'),
                      initialValue: _deductionAmount,
                      onChanged: (value) =>
                          setState(() => _deductionAmount = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _deductionReasonController,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Deduction reason',
                        hintText: 'Advance, Loan Repayment, Uniform or Other',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _EarningsSummaryCard(
                      calculation: _calculation,
                      rate: _selectedRate,
                      allowance: _appliedAllowance,
                      uplift: _jobUplift,
                    ),
                    const SizedBox(height: 26),
                    const Divider(height: 1),
                    const SizedBox(height: 24),
                    const _EntrySectionHeading(
                      icon: Icons.notes_rounded,
                      title: 'Notes',
                      subtitle: 'Optional details for later',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Anything useful to remember...',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 96),
          ],
        ),
      ),
      bottomNavigationBar: _EntrySaveBar(
        calculation: _calculation,
        keyboardOpen: keyboardOpen,
        onSave: _save,
        label: widget.initialEntry == null ? 'Save Entry' : 'Update Entry',
      ),
    );
  }
}

class _EntrySaveBar extends StatelessWidget {
  const _EntrySaveBar({
    required this.calculation,
    required this.keyboardOpen,
    required this.onSave,
    required this.label,
  });

  final WorkCalculation calculation;
  final bool keyboardOpen;
  final VoidCallback onSave;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: .12),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            if (!keyboardOpen) ...[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated gross pay',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      calculation.isValid ? _money(calculation.totalPay) : '--',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
            SizedBox(
              width: keyboardOpen ? 176 : 170,
              child: BriskaPrimaryButton(
                onPressed: onSave,
                icon: Icons.check_rounded,
                label: label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntrySectionHeading extends StatelessWidget {
  const _EntrySectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _DuplicateChoice { cancel, editExisting, continueAnyway }

class _OptionalCurrencyField extends StatefulWidget {
  const _OptionalCurrencyField({
    required this.initialValue,
    required this.onChanged,
    super.key,
  });

  final double initialValue;
  final ValueChanged<double> onChanged;

  @override
  State<_OptionalCurrencyField> createState() => _OptionalCurrencyFieldState();
}

class _OptionalCurrencyFieldState extends State<_OptionalCurrencyField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _selectedForFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == 0
          ? ''
          : widget.initialValue.toStringAsFixed(2),
    );
    _focusNode = FocusNode()..addListener(_handleFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      _formatValue();
      return;
    }
    if (_selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        duration: BriskaDurations.standard,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _formatValue() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onChanged(0);
      return;
    }
    final value = double.tryParse(text);
    if (value == null) return;
    _controller.value = TextEditingValue(
      text: value.toStringAsFixed(2),
      selection: TextSelection.collapsed(
        offset: value.toStringAsFixed(2).length,
      ),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        prefixText: _currencyPrefix,
        hintText: 'Enter amount (optional)',
      ),
      onChanged: (text) => widget.onChanged(
        text.trim().isEmpty ? 0 : (double.tryParse(text) ?? -1),
      ),
      onEditingComplete: () {
        _formatValue();
        _focusNode.unfocus();
      },
    );
  }
}

class _CalculationLine extends StatelessWidget {
  const _CalculationLine({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.foregroundColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final color = foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: color,
              fontSize: emphasize ? 17 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _EarningsSummaryCard extends StatelessWidget {
  const _EarningsSummaryCard({
    required this.calculation,
    required this.rate,
    required this.allowance,
    required this.uplift,
  });

  final WorkCalculation calculation;
  final double rate;
  final double allowance;
  final double uplift;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, BriskaColors.dark, .3)!,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated gross pay',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          BriskaAnimatedText(
            _money(calculation.totalPay),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 24),
          _CalculationLine(
            label: 'Hours',
            value: formatHoursLabel(calculation.totalHours),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          _CalculationLine(
            label: 'Rate',
            value: '${_money(rate)} / hour',
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          _CalculationLine(
            label: 'Allowance',
            value: _money(allowance),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          _CalculationLine(
            label: 'Uplift',
            value: _money(uplift),
            foregroundColor: Colors.white,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              color: Colors.white.withValues(alpha: .2),
              height: 1,
            ),
          ),
          _CalculationLine(
            label: 'Estimated gross pay',
            value: _money(calculation.totalPay),
            emphasize: true,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _TimeInputField extends StatefulWidget {
  const _TimeInputField({
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    this.onFinished,
  });

  final String label;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFinished;

  @override
  State<_TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<_TimeInputField> {
  late final TextEditingController _controller;
  bool _normalizing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text:
          WorkCalculator.normalizeTime(widget.initialValue) ??
          widget.initialValue,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    if (_normalizing) return;
    final normalized = WorkCalculator.normalizeTime(value);
    if (normalized != null && normalized != value) {
      _normalizing = true;
      _controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      _normalizing = false;
      widget.onChanged(normalized);
      return;
    }
    widget.onChanged(value);
  }

  TimeOfDay _initialTimeOfDay() {
    final normalized =
        WorkCalculator.normalizeTime(_controller.text) ??
        WorkCalculator.normalizeTime(widget.initialValue) ??
        WorkCalculator.normalizeTime(widget.hint) ??
        '08:00';
    final parts = normalized.split(':');
    return TimeOfDay(
      hour: int.parse(parts.first),
      minute: int.parse(parts.last),
    );
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _initialTimeOfDay(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (selected == null) return;
    final value = formatTime(hour: selected.hour, minute: selected.minute);
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(widget.label),
      const SizedBox(height: 8),
      TextField(
        controller: _controller,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: IconButton(
            tooltip: 'Pick time',
            icon: const Icon(Icons.schedule_rounded, size: 20),
            onPressed: _pickTime,
          ),
        ),
        onChanged: _handleChanged,
        onEditingComplete: widget.onFinished,
      ),
    ],
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    this.initialValue,
    this.onChanged,
    this.keyboardType,
  });
  final String label, hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(label),
      const SizedBox(height: 8),
      _SelectAllTextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
        onChanged: onChanged,
      ),
    ],
  );
}

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
