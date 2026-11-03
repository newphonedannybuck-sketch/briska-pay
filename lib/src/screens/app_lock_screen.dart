part of '../briska_app.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    required this.config,
    required this.onUnlocked,
    this.verifyPin,
    this.authenticateWithBiometrics,
    this.deviceAuthenticationAvailabilityChecker,
    super.key,
  });

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
  bool? _deviceAuthenticationAvailable;

  @override
  void initState() {
    super.initState();
    _checkDeviceAuthenticationAvailability();
  }

  Future<void> _checkDeviceAuthenticationAvailability() async {
    if (!widget.config.useBiometrics) return;
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
    if (available) await _unlockBiometric();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _unlockBiometric() async {
    setState(() => _checking = true);
    var ok = false;
    try {
      ok =
          await (widget.authenticateWithBiometrics?.call() ??
              AppLockService.authenticateWithBiometrics());
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) {
        _deviceAuthenticationFeedback =
            'Device authentication was not completed. '
            'Use your Briska Pay PIN or try again.';
      }
    });
    if (ok) widget.onUnlocked();
  }

  Future<void> _unlockPin() async {
    final pin = _pinController.text.trim();
    final ok =
        await (widget.verifyPin?.call(pin) ?? AppLockService.verifyPin(pin));
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'PIN did not match.');
    }
  }

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
                          onPressed: _checking ? null : _unlockBiometric,
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
                          onPressed: _unlockPin,
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

