
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
part 'screens/monthly_calendar_section.dart';
part 'screens/export_screen.dart';
part 'screens/settings_screen.dart';
part 'screens/add_work_day_screen.dart';

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
