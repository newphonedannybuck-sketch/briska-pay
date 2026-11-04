part of '../briska_app.dart';

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
