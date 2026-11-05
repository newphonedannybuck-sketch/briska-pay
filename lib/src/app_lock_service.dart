import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

class PinCooldownException implements Exception {
  const PinCooldownException(this.seconds);
  final int seconds;
  @override
  String toString() => 'Try again in $seconds seconds.';
}

class PinVerificationException implements Exception {
  const PinVerificationException();
  @override
  String toString() => 'Current PIN did not match.';
}

class AppLockConfigRecoveryException implements Exception {
  const AppLockConfigRecoveryException(
    this.originalError,
    this.originalStackTrace,
    this.recoveryErrors,
  );

  final Object originalError;
  final StackTrace originalStackTrace;
  final List<Object> recoveryErrors;

  @override
  String toString() => 'App Lock configuration could not be restored safely.';
}

abstract final class AppLockService {
  static const _storage = FlutterSecureStorage();
  static const _enabledKey = 'briska_lock_enabled';
  static const _biometricsKey = 'briska_lock_biometrics';
  static const _delayKey = 'briska_lock_delay';
  static const _configRecoveryKey = 'briska_lock_config_recovery_v1';
  static const _configDefaults = {
    _biometricsKey: 'false',
    _delayKey: '60',
    _enabledKey: 'false',
  };
  static Map<String, String>? _pendingConfigRecovery;
  static const _pinHashKey = 'briska_lock_pin_hash';
  static const _pinSaltKey = 'briska_lock_pin_salt';

  static final LocalAuthentication _auth = LocalAuthentication();
  static const _pinRecordKey = 'briska_lock_pin_record_v1';
  static const _cooldownKey = 'briska_lock_pin_cooldown_v1';
  static Future<void> _operations = Future<void>.value();
  static final _elapsed = Stopwatch()..start();
  static String? _observedCooldown;
  static int _observedAt = 0;
  static int _remainingAtObservation = 0;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;
  @visibleForTesting
  static int Function() monotonicMilliseconds = () =>
      _elapsed.elapsedMilliseconds;
  @visibleForTesting
  static Future<String?> Function(String key)? readOverride;
  @visibleForTesting
  static Future<void> Function(String key, String value)? writeOverride;

  static Future<String?> _read(String key) =>
      readOverride?.call(key) ?? _storage.read(key: key);
  static Future<void> _write(String key, String value) =>
      writeOverride?.call(key, value) ?? _storage.write(key: key, value: value);

  static Future<T> _serial<T>(Future<T> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  // Only call between tests, with no active security operation.
  @visibleForTesting
  static void resetOperationsForTesting() {
    _operations = Future<void>.value();
    _observedCooldown = null;
    _pendingConfigRecovery = null;
  }

  @visibleForTesting
  static void resetClockObservation() {
    _observedCooldown = null;
  }

  static Future<({String salt, String hash})?> _pinRecord() async {
    final record = await _read(_pinRecordKey);
    String? salt;
    String? hash;
    if (record != null) {
      final data = jsonDecode(record) as Map<String, dynamic>;
      salt = data['salt'] as String?;
      hash = data['hash'] as String?;
    } else {
      salt = await _read(_pinSaltKey);
      hash = await _read(_pinHashKey);
      if (salt == null && hash == null) return null;
    }
    if (salt == null ||
        salt.isEmpty ||
        hash == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('PIN record is unavailable.');
    }
    return (salt: salt, hash: hash);
  }

  // Persist only a failure count and cooldown start/duration. Within a process,
  // elapsed time is monotonic; across restarts wall time is bounded to the
  // original duration so a backward clock change cannot cause an endless wait.
  static Future<({int failures, int remaining})> _cooldown() async {
    final raw = await _read(_cooldownKey);
    if (raw == null) return (failures: 0, remaining: 0);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final failures = data['failures'] as int;
    final start = data['start'] as int;
    final seconds = data['seconds'] as int;
    if (failures < 0 || failures > 20 || seconds < 0 || seconds > 900) {
      throw const FormatException('PIN verification is unavailable.');
    }
    if (raw != _observedCooldown) {
      _observedCooldown = raw;
      _observedAt = monotonicMilliseconds();
      _remainingAtObservation =
          (seconds * 1000 - (clock().millisecondsSinceEpoch - start)).clamp(
            0,
            seconds * 1000,
          );
    }
    final remaining =
        (_remainingAtObservation -
                (monotonicMilliseconds() - _observedAt).clamp(0, 900000))
            .clamp(0, 900000);
    return (failures: failures, remaining: (remaining / 1000).ceil());
  }

  static Future<int> cooldownSeconds() =>
      _serial(() async => (await _cooldown()).remaining);

  static Future<void> _clearFailures() async {
    await _write(
      _cooldownKey,
      jsonEncode({'failures': 0, 'start': 0, 'seconds': 0}),
    );
    _observedCooldown = null;
  }

  static Future<bool> _verifyPin(String pin) async {
    final cooldown = await _cooldown();
    if (cooldown.remaining > 0) throw PinCooldownException(cooldown.remaining);
    final record = await _pinRecord();
    if (record == null) return false;
    if (_hashPin(pin, record.salt) == record.hash) {
      await _clearFailures();
      return true;
    }
    final failures = (cooldown.failures + 1).clamp(0, 20);
    final seconds = failures < 3 ? 0 : min(900, 30 * (1 << (failures - 3)));
    await _write(
      _cooldownKey,
      jsonEncode({
        'failures': failures,
        'start': clock().millisecondsSinceEpoch,
        'seconds': seconds,
      }),
    );
    _observedCooldown = null;
    if (seconds > 0) {
      await _cooldown();
      throw PinCooldownException(seconds);
    }
    return false;
  }

  // Only these three configuration keys may be restored; PIN records and
  // cooldown state are deliberately excluded.
  static Future<bool> _restoreConfig(
    Map<String, String> previous,
    Iterable<String> affected,
    List<Object> errors,
  ) async {
    for (final key in affected.toList().reversed) {
      try {
        await _write(key, previous[key]!);
      } catch (error) {
        errors.add(error);
      }
    }
    try {
      for (final key in previous.keys) {
        if ((await _read(key) ?? _configDefaults[key]) != previous[key]) {
          return false;
        }
      }
      return true;
    } catch (error) {
      errors.add(error);
      return false;
    }
  }

  static Future<void> _recoverConfigIfNeeded() async {
    var previous = _pendingConfigRecovery;
    if (previous == null) {
      String? record;
      try {
        record = await _read(_configRecoveryKey);
      } catch (error, stackTrace) {
        throw AppLockConfigRecoveryException(error, stackTrace, const []);
      }
      if (record == null || record.isEmpty) return;
      try {
        final data = jsonDecode(record) as Map<String, dynamic>;
        if (data.length != _configDefaults.length ||
            !_configDefaults.keys.every((key) => data[key] is String) ||
            !['true', 'false'].contains(data[_enabledKey]) ||
            !['true', 'false'].contains(data[_biometricsKey]) ||
            !['0', '60', '300', '900'].contains(data[_delayKey])) {
          throw const FormatException();
        }
        previous = data.cast<String, String>();
      } catch (_) {
        throw StateError('App Lock configuration recovery is unavailable.');
      }
      _pendingConfigRecovery = previous;
    }
    final errors = <Object>[];
    if (!await _restoreConfig(previous, previous.keys, errors)) {
      throw StateError('App Lock configuration recovery is required.');
    }
    // If clearing fails, retain the in-process record and retry on the next
    // load. Restoring the original configuration again is safe.
    try {
      await _write(_configRecoveryKey, '');
    } catch (_) {
      throw StateError('App Lock configuration recovery is required.');
    }
    _pendingConfigRecovery = null;
  }

  static Future<AppLockConfig> loadConfig() => _serial(() async {
    await _recoverConfigIfNeeded();
    final enabled = await _read(_enabledKey) == 'true';
    final biometrics = await _read(_biometricsKey) == 'true';
    final delay = int.tryParse(await _read(_delayKey) ?? '') ?? 60;
    final hasPin = await _pinRecord() != null;
    return AppLockConfig(
      enabled: enabled,
      useBiometrics: biometrics,
      lockAfterSeconds: [0, 60, 300, 900].contains(delay) ? delay : 60,
      hasPin: hasPin,
    );
  });

  static Future<void> saveConfig(
    AppLockConfig config, {
    String? currentPin,
  }) => _serial(() async {
    await _recoverConfigIfNeeded();
    final enabled = await _read(_enabledKey) == 'true';
    if (enabled && !config.enabled) {
      if (currentPin == null || !await _verifyPin(currentPin)) {
        throw const PinVerificationException();
      }
    }
    final previous = <String, String>{
      _biometricsKey: await _read(_biometricsKey) ?? 'false',
      _delayKey: await _read(_delayKey) ?? '60',
      _enabledKey: enabled.toString(),
    };
    final updated = enabled && !config.enabled
        ? <String, String>{_enabledKey: 'false'}
        : <String, String>{
            _biometricsKey: config.useBiometrics.toString(),
            _delayKey: config.lockAfterSeconds.toString(),
            // Enable only after the other configuration writes succeed.
            _enabledKey: config.enabled.toString(),
          };
    final written = <String>[];
    try {
      for (final entry in updated.entries) {
        if (entry.value == previous[entry.key]) continue;
        // A write can mutate storage before throwing.
        written.add(entry.key);
        await _write(entry.key, entry.value);
      }
    } catch (error, stackTrace) {
      final recoveryErrors = <Object>[];
      if (await _restoreConfig(previous, written, recoveryErrors)) rethrow;
      _pendingConfigRecovery = Map.of(previous);
      try {
        await _write(_configRecoveryKey, jsonEncode(previous));
      } catch (recoveryError) {
        recoveryErrors.add(recoveryError);
      }
      // Keep the original cause for debugging, but never stringify storage
      // errors (which may contain sensitive platform details) in this error.
      Error.throwWithStackTrace(
        AppLockConfigRecoveryException(
          error,
          stackTrace,
          List.unmodifiable(recoveryErrors),
        ),
        stackTrace,
      );
    }
  });

  static Future<bool> canUseBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateWithBiometrics() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Briska Pay',
        biometricOnly: false,
        persistAcrossBackgrounding: false,
      );
      if (ok) await _serial(_clearFailures);
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setPin(String pin, {String? currentPin}) =>
      _serial(() async {
        if (!RegExp(r'^[0-9]{4,12}$').hasMatch(pin)) {
          throw const FormatException('Use 4-12 numerical digits.');
        }
        final existing = await _pinRecord();
        if (existing != null &&
            (currentPin == null || !await _verifyPin(currentPin))) {
          throw const PinVerificationException();
        }
        final salt = _randomSalt();
        // One secure-storage write replaces the pair. Legacy keys are read only
        // when this record is absent; a corrupt new record never falls back.
        await _write(
          _pinRecordKey,
          jsonEncode({'salt': salt, 'hash': _hashPin(pin, salt)}),
        );
      });

  static Future<bool> verifyPin(String pin) => _serial(() => _verifyPin(pin));

  static String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static String _randomSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
