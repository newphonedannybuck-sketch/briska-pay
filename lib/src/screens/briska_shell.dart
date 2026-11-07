part of '../briska_app.dart';

class _StaleSettingsOperation implements Exception {}

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
  static const _consentOperationTimeout = Duration(seconds: 15);
  int _index = 0;
  late AppSettings _preferences;
  late List<WorkEntry> _entries;
  late List<ExportedFileRecord> _exportRecords;
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
  Future<void> _entryOperationQueue = Future<void>.value();
  int _entryDataGeneration = 0;
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
    _entries = widget.initialEntries.toList();
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
    _editorSecurityDismissal.dispose();
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

  // Include both snapshot construction and the UI commit in the queue.
  // A failed operation must not poison the queue for the next operation.
  Future<T> _queueEntryOperation<T>(Future<T> Function() operation) {
    final result = _entryOperationQueue.then((_) => operation());
    _entryOperationQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<bool> _changeExportRecord(
    ExportedFileRecord record,
    int generation, {
    bool add = false,
    bool delete = false,
  }) => _queueEntryOperation(() async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _entryDataGeneration) {
      return false;
    }
    final updated = List<ExportedFileRecord>.of(_exportRecords);
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
      setState(() => _exportRecords = updated);
      return true;
    } catch (error) {
      if (kDebugMode) debugPrint('export library save failed: $error');
      return false;
    }
  });

  Future<void> _resetLocalDataAfterConfirmation() =>
      _queueEntryOperation(_resetLocalDataInQueue);

  Future<void> _resetLocalDataInQueue() async {
    if (!mounted) return;
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
    _entryDataGeneration++;
    _preferencesSaveRevision++;
    if (!mounted) return;
    setState(() {
      _preferences = const AppSettings();
      CurrencyFormatter.current = _preferences.currency;
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
          securityDismissal: _editorSecurityDismissal,
        ),
      ),
    );
  }

  Future<bool> _saveEntry(WorkEntry entry) {
    final generation = _entryDataGeneration;
    return _queueEntryOperation(() => _saveEntryInQueue(entry, generation));
  }

  Future<bool> _saveEntryInQueue(WorkEntry entry, int generation) async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _entryDataGeneration) {
      return false;
    }
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
    final generation = _entryDataGeneration;
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
    await _queueEntryOperation(() => _deleteEntryInQueue(entry.id, generation));
  }

  Future<void> _deleteEntryInQueue(String id, int generation) async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _entryDataGeneration) {
      return;
    }
    final index = _entries.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final deletedEntry = _entries[index];
    final updatedEntries = List<WorkEntry>.of(_entries)
      ..removeWhere((item) => item.id == id);
    try {
      await LocalStorage.saveEntries(updatedEntries);
      if (!mounted) return;
      setState(() => _entries = updatedEntries);
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
      _queueEntryOperation(() => _undoDeleteEntryInQueue(entry, generation));

  Future<void> _undoDeleteEntryInQueue(WorkEntry entry, int generation) async {
    if (!mounted ||
        _restoreRecoveryRequired ||
        generation != _entryDataGeneration) {
      return;
    }
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

  Future<void> _savePreferences(
    AppSettings settings,
    int generation, {
    String? themeMode,
  }) {
    _preferencesSaveRevision++;
    return _queueEntryOperation(() async {
      if (!mounted ||
          _restoreRecoveryRequired ||
          generation != _entryDataGeneration) {
        throw _StaleSettingsOperation();
      }
      if (themeMode != null) {
        settings = _preferences.copyWith(themeMode: themeMode);
      }
      await LocalStorage.saveSettings(settings);
      if (!mounted) return;
      // Commit every successful write: backups and failed later saves must see
      // the last durable settings. Storage and UI commits share the queue.
      setState(() => _preferences = settings);
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
    final revision = _preferencesSaveRevision;
    try {
      await operation;
    } catch (error) {
      if (!mounted ||
          generation != _entryDataGeneration ||
          revision != _preferencesSaveRevision) {
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
      _foreground &&
      _lockState == AppLockInitializationState.unlocked &&
      _lockSession == session &&
      _entryDataGeneration == generation;

  Future<void> _createBackup() async {
    final session = _lockSession;
    final generation = _entryDataGeneration;
    bool isCurrent() => _backupSessionIsCurrent(session, generation);
    if (!mounted || !isCurrent()) return;
    try {
      final file = await BriskaBackupService.createBackupFile(
        settings: _preferences,
        workEntries: _entries,
        exportRecords: _exportRecords,
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
    final generation = _entryDataGeneration;
    if (_restoreInProgress || !_backupSessionIsCurrent(session, generation)) {
      return;
    }
    _restoreInProgress = true;
    try {
      await _queueEntryOperation(
        () => _restoreBackupInQueue(session, generation),
      );
    } finally {
      _restoreInProgress = false;
    }
  }

  Future<void> _restoreBackupInQueue(int session, int generation) async {
    bool isCurrent() => _backupSessionIsCurrent(session, generation);
    if (!mounted || !isCurrent()) return;
    try {
      final file = await BriskaBackupService.pickBackupFile();
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
      if (confirmed != true || !isCurrent()) return;
      await BriskaBackupService.createBackupFile(
        settings: _preferences,
        workEntries: _entries,
        exportRecords: _exportRecords,
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
      if (!mounted || !isCurrent()) return;
      _entryDataGeneration++;
      _preferencesSaveRevision++;
      setState(() {
        _preferences = preview.data.settings;
        CurrencyFormatter.current = _preferences.currency;
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
    if (!_preferences.onboardingCompleted) {
      final onboardingGeneration = _entryDataGeneration;
      return OnboardingScreen(
        initialSettings: _preferences,
        onComplete: (settings) =>
            _savePreferences(settings, onboardingGeneration),
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
    // Keep callbacks held by dialogs/file operations tied to their original data.
    final exportGeneration = _entryDataGeneration;
    final session = _lockSession;
    // Async completions can run between a navigation/security change and the
    // next build. Check live shell state as well as the child's active flag.
    bool canPresentTab(int index) =>
        mounted &&
        _lockState == AppLockInitializationState.unlocked &&
        _lockSession == session &&
        _entryDataGeneration == exportGeneration &&
        _index == index;
    final screens = [
      HomeScreen(
        entries: _entries,
        settings: _preferences,
        onViewEntries: () => _selectTab(1),
        onAddEntry: _showAddDay,
        onOpenCalendar: () => _selectTab(1),
        onOpenReports: () => _selectTab(2),
        onOpenExport: () => _selectTab(3),
        onConfigurePayday: () => _selectTab(4),
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
        isActive: _index == 3,
        canPresent: () => canPresentTab(3),
        actionOverrides: widget.exportActionOverrides,
        entries: _entries,
        fullName: _preferences.fullName,
        companyName: _preferences.companyName,
        settings: _preferences,
        records: _exportRecords,
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
        key: ValueKey(_entryDataGeneration),
        preferences: _preferences,
        lockConfig: _lockConfig,
        onCreateBackup: _createBackup,
        onRestoreBackup: _restoreBackup,
        onLockConfigChanged: _updateLockConfig,
        onSetLockPin: _setLockPin,
        onDisableLock: _disableLock,
        onShowAbout: () => Navigator.of(
          context,
        ).push(_BriskaPageRoute(child: const AboutBriskaScreen())),
        onPreferencesChanged: (value) =>
            _savePreferences(value, exportGeneration),
        onThemeModeChanged: (mode) async {
          final value = _preferences.copyWith(
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
            child: _RetainedTabs(
              key: ValueKey(_entryDataGeneration),
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

// Owned by the unlocked branch: lock/recovery/onboarding disposes every tab.
// A new data generation also discards drafts after successful restore/reset.
class _RetainedTabs extends StatefulWidget {
  const _RetainedTabs({required this.index, required this.children, super.key});
  final int index;
  final List<Widget> children;

  @override
  State<_RetainedTabs> createState() => _RetainedTabsState();
}

class _RetainedTabsState extends State<_RetainedTabs> {
  final _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          TickerMode(
            enabled: i == widget.index,
            child: ExcludeFocus(
              excluding: i != widget.index,
              child: ExcludeSemantics(
                excluding: i != widget.index,
                child: _visited.contains(i)
                    ? widget.children[i]
                    : const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
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
