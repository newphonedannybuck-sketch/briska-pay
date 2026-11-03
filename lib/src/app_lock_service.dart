import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockConfig {
  const AppLockConfig({
    this.enabled = false,
    this.useBiometrics = false,
    this.lockAfterSeconds = 60,
    this.hasPin = false,
  });

  final bool enabled;
  final bool useBiometrics;
  final int lockAfterSeconds;
  final bool hasPin;

  AppLockConfig copyWith({
    bool? enabled,
    bool? useBiometrics,
    int? lockAfterSeconds,
    bool? hasPin,
  }) => AppLockConfig(
    enabled: enabled ?? this.enabled,
    useBiometrics: useBiometrics ?? this.useBiometrics,
    lockAfterSeconds: lockAfterSeconds ?? this.lockAfterSeconds,
    hasPin: hasPin ?? this.hasPin,
  );
}

abstract final class AppLockService {
  static const _storage = FlutterSecureStorage();
  static const _enabledKey = 'briska_lock_enabled';
  static const _biometricsKey = 'briska_lock_biometrics';
  static const _delayKey = 'briska_lock_delay';
  static const _pinHashKey = 'briska_lock_pin_hash';
  static const _pinSaltKey = 'briska_lock_pin_salt';

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<AppLockConfig> loadConfig() async {
    final enabled = await _storage.read(key: _enabledKey) == 'true';
    final biometrics = await _storage.read(key: _biometricsKey) == 'true';
    final delay = int.tryParse(await _storage.read(key: _delayKey) ?? '') ?? 60;
    final hasPin = (await _storage.read(key: _pinHashKey)) != null;
    return AppLockConfig(
      enabled: enabled,
      useBiometrics: biometrics,
      lockAfterSeconds: delay,
      hasPin: hasPin,
    );
  }

  static Future<void> saveConfig(AppLockConfig config) async {
    await _storage.write(key: _enabledKey, value: config.enabled.toString());
    await _storage.write(
      key: _biometricsKey,
      value: config.useBiometrics.toString(),
    );
    await _storage.write(
      key: _delayKey,
      value: config.lockAfterSeconds.toString(),
    );
  }

  static Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics() async {
    try {
      return _auth.authenticate(
        localizedReason: 'Unlock Briska Pay',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    await _storage.write(key: _pinSaltKey, value: salt);
    await _storage.write(key: _pinHashKey, value: _hashPin(pin, salt));
  }

  static Future<void> clearPin() async {
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinSaltKey);
  }

  static Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _pinSaltKey);
    final expected = await _storage.read(key: _pinHashKey);
    if (salt == null || expected == null) return false;
    return _hashPin(pin, salt) == expected;
  }

  static String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
