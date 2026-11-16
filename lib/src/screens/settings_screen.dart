import '../../design_system/briska_cards.dart';
import 'settings/settings_sections.dart';
import 'settings/app_lock_pin_dialog.dart';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../design_system/briska_spacing.dart';
import '../app/briska_page_route.dart';
import '../app/settings_operation.dart';
import '../app/theme_preferences.dart';
import '../models.dart';
import '../app_lock_service.dart';
import '../currency.dart';
import '../pay_schedule.dart';
import '../release_info.dart';
import '../widgets/shared_ui.dart';
import 'beta_checklist_screen.dart';
import 'support_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.onThemeModeChanged,
    required this.preferences,
    required this.lockConfig,
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onLockConfigChanged,
    required this.onSetLockPin,
    required this.onDisableLock,
    required this.onShowAbout,
    required this.onPreferencesChanged,
    this.deviceAuthenticationAvailabilityChecker,
    this.showTesterTools,
    this.isActive = true,
    this.canPresent,
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
  final Future<void> Function(String pin, String? currentPin) onSetLockPin;
  final Future<void> Function(String pin) onDisableLock;
  final VoidCallback onShowAbout;
  final FutureOr<void> Function(AppSettings) onPreferencesChanged;
  final bool? showTesterTools;
  final bool isActive;
  final bool Function()? canPresent;
  final Future<bool> Function()? deviceAuthenticationAvailabilityChecker;
  final bool privacyOptionsRequired;
  final Future<void> Function()? onShowAdvertisingPrivacyChoices;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool get _canPresent =>
      mounted &&
      widget.isActive &&
      widget.canPresent?.call() != false &&
      ModalRoute.of(context)?.isCurrent != false;
  bool _anchorPromptShown = false;
  bool _securityBusy = false;
  int _currencyPickerRevision = 0;
  int _formRevision = 0;
  int _saveRevision = 0;
  int _pendingSaves = 0;
  int _draftRevision = 0;
  bool _draftDirty = false;
  late AppSettings _draftPreferences;
  bool? _deviceAuthenticationAvailable;
  final _invalidRateInputs = <String>{};

  void _updateRate(String value, {required bool primary}) {
    final key = primary ? 'primary' : 'secondary';
    final parsed = value.trim().isEmpty ? 0.0 : double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      _invalidRateInputs.add(key);
    } else {
      _invalidRateInputs.remove(key);
    }
    _update(
      primary
          ? _draftPreferences.copyWith(primaryRateValue: parsed)
          : _draftPreferences.copyWith(secondaryRateValue: parsed),
    );
  }

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
    if (!_draftDirty &&
        _pendingSaves == 0 &&
        oldWidget.preferences != widget.preferences) {
      _draftPreferences = widget.preferences;
    }
  }

  void _update(AppSettings value) => setState(() {
    _draftDirty = true;
    _draftRevision++;
    _draftPreferences = value;
  });

  void _showSettingsFeedback(String message) {
    if (!_canPresent) return;
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
    if (_invalidRateInputs.isNotEmpty ||
        value.primaryRateLabel.trim().isEmpty ||
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
    _update(value);
    final draftRevision = _draftRevision;
    _pendingSaves++;
    try {
      await widget.onPreferencesChanged(value);
      if (!mounted ||
          revision != _saveRevision ||
          draftRevision != _draftRevision) {
        return true;
      }
      setState(() {
        _draftDirty = false;
        _draftPreferences = value;
      });
      if (successMessage != null) _showSettingsFeedback(successMessage);
      return true;
    } on StaleSettingsOperation {
      return false;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('settings persistence failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted ||
          revision != _saveRevision ||
          draftRevision != _draftRevision) {
        return false;
      }
      setState(() {
        _draftDirty = false;
        _draftPreferences = widget.preferences;
        _currencyPickerRevision++;
        _formRevision++;
      });
      _showSettingsFeedback(failureMessage);
      return false;
    } finally {
      _pendingSaves--;
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
    if (!_canPresent) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
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
    if (!_canPresent) return;
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
    if (_canPresent &&
        needsAnchor &&
        !_draftPreferences.payScheduleAnchorPrompted &&
        !_anchorPromptShown) {
      _anchorPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_canPresent) {
          _anchorPromptShown = false;
          return;
        }
        if (requiresPayPeriodAnchor(_draftPreferences)) {
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
          const SizedBox(height: 20),
          const SectionHeading(
            title: 'Profile',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 10),
          ProfileSettingsSection(
            readPreferences: () => _draftPreferences,
            onChanged: _update,
            onSave: _persist,
            formRevision: _formRevision,
          ),
          const SizedBox(height: 20),
          const SectionHeading(
            title: 'Pay & currency',
            icon: Icons.payments_outlined,
          ),
          const SizedBox(height: 10),
          PaySettingsSection(
            readPreferences: () => _draftPreferences,
            onChanged: _update,
            onSave: _persist,
            formRevision: _formRevision,
            currencyPickerRevision: _currencyPickerRevision,
            onCurrencyChanged: _confirmCurrencyChange,
            onRateChanged: _updateRate,
          ),
          const SizedBox(height: 20),
          const SectionHeading(
            title: 'Work defaults',
            icon: Icons.tune_rounded,
          ),
          const SizedBox(height: 10),
          WorkDefaultsSection(
            readPreferences: () => _draftPreferences,
            onChanged: _update,
            onSave: _persist,
            formRevision: _formRevision,
          ),
          const SizedBox(height: 20),
          const SectionHeading(
            title: 'Pay schedule',
            icon: Icons.event_repeat_outlined,
          ),
          const SizedBox(height: 10),
          PayScheduleSection(
            readPreferences: () => _draftPreferences,
            onChanged: _update,
            onSave: _persist,
            formRevision: _formRevision,
            onScheduleChanged: _updatePaySchedule,
            onChooseAnchorDate: _chooseAnchorDate,
          ),
          const SizedBox(height: 20),
          const SectionHeading(
            title: 'Appearance',
            icon: Icons.palette_outlined,
          ),
          const SizedBox(height: 10),
          BriskaCard(
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Theme'),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    direction: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                        ? Axis.vertical
                        : Axis.horizontal,
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
                      final previousTheme = _draftPreferences.themeMode;
                      final wasDirty = _draftDirty;
                      _update(
                        _draftPreferences.copyWith(
                          themeMode: themeModeToSettings(selection.first),
                        ),
                      );
                      final draftRevision = _draftRevision;
                      _pendingSaves++;
                      try {
                        await widget.onThemeModeChanged(selection.first);
                        if (mounted && draftRevision == _draftRevision) {
                          _draftDirty = wasDirty;
                        }
                      } on StaleSettingsOperation {
                        return;
                      } catch (error, stackTrace) {
                        if (kDebugMode) {
                          debugPrint('theme persistence failed: $error');
                          debugPrintStack(stackTrace: stackTrace);
                        }
                        if (!mounted) return;
                        if (draftRevision == _draftRevision) {
                          setState(() {
                            _draftPreferences = _draftPreferences.copyWith(
                              themeMode: previousTheme,
                            );
                            _draftDirty = wasDirty;
                            // Theme rollback must not recreate unrelated rate
                            // fields and separate their text from validation.
                          });
                        }
                        _showSettingsFeedback('Could not update theme.');
                      } finally {
                        _pendingSaves--;
                      }
                    },
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeading(title: 'Security', icon: Icons.shield_outlined),
          const SizedBox(height: 10),
          BriskaCard(
            padding: EdgeInsets.zero,
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
                    onChanged: _securityBusy
                        ? null
                        : (value) async {
                            setState(() => _securityBusy = true);
                            try {
                              if (!value) {
                                if (!await _showPinDialog(disabling: true)) {
                                  return;
                                }
                              } else {
                                if (!widget.lockConfig.hasPin &&
                                    !await _showPinDialog(disabling: false)) {
                                  return;
                                }
                                await widget.onLockConfigChanged(
                                  widget.lockConfig.copyWith(enabled: true),
                                );
                              }
                              _showSettingsFeedback(
                                value
                                    ? 'App lock enabled.'
                                    : 'App lock disabled.',
                              );
                            } catch (_) {
                              _showSettingsFeedback(
                                'Could not update app lock.',
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _securityBusy = false);
                              }
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
                        !_securityBusy &&
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
                    onChanged: widget.lockConfig.enabled && !_securityBusy
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
                    onPressed: widget.lockConfig.enabled && !_securityBusy
                        ? () async {
                            setState(() => _securityBusy = true);
                            try {
                              if (await _showPinDialog(disabling: false)) {
                                _showSettingsFeedback('PIN updated.');
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _securityBusy = false);
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
          const SizedBox(height: 20),
          const SectionHeading(
            title: 'Data & backup',
            icon: Icons.backup_outlined,
          ),
          const SizedBox(height: 10),
          BriskaCard(
            padding: EdgeInsets.zero,
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
          const SizedBox(height: 20),
          if (widget.privacyOptionsRequired) ...[
            const SectionHeading(title: 'Advertising'),
            const SizedBox(height: 10),
            BriskaCard(
              padding: EdgeInsets.zero,
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
            const SizedBox(height: 20),
          ],
          const SectionHeading(title: 'Briska Pay'),
          const SizedBox(height: 10),
          BriskaCard(
            padding: EdgeInsets.zero,
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
            const SizedBox(height: 20),
            const SectionHeading(title: 'Beta feedback'),
            const SizedBox(height: 10),
            BriskaCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Report a bug'),
                    subtitle: const Text('Opens support with app diagnostics.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(
                      context,
                    ).push(BriskaPageRoute(child: const SupportScreen())),
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
                    ).push(BriskaPageRoute(child: const SupportScreen())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('View beta checklist'),
                    subtitle: const Text('Tester release checklist.'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(
                      context,
                    ).push(BriskaPageRoute(child: const BetaChecklistScreen())),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _showPinDialog({required bool disabling}) =>
      showAppLockPinDialog(
        context,
        disabling: disabling,
        hasPin: () => widget.lockConfig.hasPin,
        onDisableLock: (pin) => widget.onDisableLock(pin),
        onSetLockPin: (pin, current) => widget.onSetLockPin(pin, current),
      );

  Future<void> _showAnchorPrompt() async {
    if (!_canPresent) return;
    final chooseNow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
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
    if (!_canPresent) return;
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
    if (!_canPresent) return;
    final current =
        _parseSettingsDate(_draftPreferences.payPeriodAnchorDate) ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !_canPresent) return;
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
}
