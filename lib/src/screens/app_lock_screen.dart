part of '../briska_app.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    required this.config,
    required this.onUnlocked,
    this.verifyPin,
    this.sessionId = 0,
    this.onDeviceAuthenticationChanged,
    this.authenticateWithBiometrics,
    this.deviceAuthenticationAvailabilityChecker,
    super.key,
  });

  final int sessionId;
  final ValueChanged<bool>? onDeviceAuthenticationChanged;
  final AppLockConfig config;
  final VoidCallback onUnlocked;
  final Future<bool> Function(String pin)? verifyPin;
  final Future<bool> Function()? authenticateWithBiometrics;
  final Future<bool> Function()? deviceAuthenticationAvailabilityChecker;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  String? _deviceAuthenticationFeedback;
  bool _checking = false;
  bool _unlocked = false;
  bool? _deviceAuthenticationAvailable;

  @override
  void initState() {
    super.initState();
    _checkDeviceAuthenticationAvailability();
  }

  Future<void> _checkDeviceAuthenticationAvailability() async {
    if (!widget.config.useBiometrics) return;
    final session = widget.sessionId;
    var available = false;
    try {
      available =
          await (widget.deviceAuthenticationAvailabilityChecker?.call() ??
              AppLockService.canUseBiometrics());
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    setState(() => _deviceAuthenticationAvailable = available);
    if (available && session == widget.sessionId) await _unlockBiometric();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppLockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _unlocked = false;
      _pinController.clear();
      _error = null;
    }
  }

  Future<void> _authenticate({required bool biometric}) async {
    if (_checking || _unlocked) return;
    final session = widget.sessionId;
    final unlock = widget.onUnlocked;
    final deviceActivity = widget.onDeviceAuthenticationChanged;
    setState(() => _checking = true);
    if (biometric) deviceActivity?.call(true);
    var ok = false;
    String? error;
    try {
      ok = biometric
          ? await (widget.authenticateWithBiometrics?.call() ??
                AppLockService.authenticateWithBiometrics())
          : await (widget.verifyPin?.call(_pinController.text) ??
                AppLockService.verifyPin(_pinController.text));
      if (!ok) {
        error = biometric
            ? 'Device authentication was not completed. Use your Briska Pay PIN or try again.'
            : 'PIN did not match.';
      }
    } on PinCooldownException catch (cooldown) {
      error = cooldown.toString();
    } catch (_) {
      error = biometric
          ? 'Device authentication was not completed. Use your Briska Pay PIN or try again.'
          : 'Could not verify authentication. Please try again.';
    } finally {
      if (biometric) deviceActivity?.call(false);
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted || session != widget.sessionId) return;
    if (ok) {
      _unlocked = true;
      unlock();
    } else {
      setState(() {
        if (biometric) {
          _deviceAuthenticationFeedback = error;
        } else {
          _error = error;
        }
      });
    }
  }

  Future<void> _unlockBiometric() => _authenticate(biometric: true);
  Future<void> _unlockPin() => _authenticate(biometric: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48)
                    .clamp(0, double.infinity)
                    .toDouble(),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BriskaLogo(size: 72),
                      const SizedBox(height: 18),
                      Text(
                        'Unlock Briska Pay',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 18),
                      if (widget.config.useBiometrics &&
                          _deviceAuthenticationAvailable == true)
                        OutlinedButton.icon(
                          onPressed: _checking || _unlocked
                              ? null
                              : _unlockBiometric,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: Text(
                            _checking
                                ? 'Checking...'
                                : 'Use device authentication',
                          ),
                        ),
                      if (_deviceAuthenticationFeedback != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _deviceAuthenticationFeedback!,
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (widget.config.useBiometrics &&
                          _deviceAuthenticationAvailable == false)
                        Text(
                          widget.config.hasPin
                              ? 'Device authentication is unavailable. '
                                    'Use your Briska Pay PIN.'
                              : 'Device authentication is unavailable '
                                    'on this device.',
                          textAlign: TextAlign.center,
                        ),
                      if (widget.config.hasPin) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pinController,
                          enabled: !_checking && !_unlocked,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Briska Pay PIN',
                            errorText: _error,
                          ),
                          onSubmitted: (_) => _unlockPin(),
                        ),
                        const SizedBox(height: 12),
                        BriskaPrimaryButton(
                          label: 'Unlock',
                          icon: Icons.lock_open_rounded,
                          onPressed: _checking || _unlocked ? null : _unlockPin,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
