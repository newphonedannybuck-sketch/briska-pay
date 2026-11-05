import 'dart:async';
import 'dart:convert';

import 'package:briska/src/app_lock_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> storage;
  late DateTime now;
  var elapsed = 0;
  final originalMonotonic = AppLockService.monotonicMilliseconds;
  void advance(int seconds) {
    now = now.add(Duration(seconds: seconds));
    elapsed += seconds * 1000;
  }

  void legacy() {
    storage['briska_lock_pin_salt'] = 'legacy-salt';
    storage['briska_lock_pin_hash'] = sha256
        .convert(utf8.encode('legacy-salt:1234'))
        .toString();
  }

  setUp(() {
    AppLockService.resetOperationsForTesting();
    storage = {};
    now = DateTime.utc(2026, 11, 5);
    elapsed = 0;
    AppLockService.clock = () => now;
    AppLockService.monotonicMilliseconds = () => elapsed;
    AppLockService.readOverride = (key) async => storage[key];
    AppLockService.writeOverride = (key, value) async {
      storage[key] = value;
    };
    AppLockService.resetClockObservation();
  });
  tearDown(() {
    AppLockService.readOverride = null;
    AppLockService.writeOverride = null;
    AppLockService.clock = DateTime.now;
    AppLockService.monotonicMilliseconds = originalMonotonic;
    AppLockService.resetClockObservation();
  });
  test('legacy SHA-256 PIN verification remains compatible', () async {
    legacy();
    expect(await AppLockService.verifyPin('1234'), isTrue);
    expect((await AppLockService.loadConfig()).hasPin, isTrue);
    expect(await AppLockService.verifyPin('wrong'), isFalse);
  });
  test(
    'third incorrect PIN starts cooldown, grows and caps at fifteen minutes',
    () async {
      await AppLockService.setPin('1234');
      expect(await AppLockService.verifyPin('0000'), isFalse);
      expect(await AppLockService.verifyPin('0000'), isFalse);
      for (final duration in [30, 60, 120, 240, 480, 900, 900]) {
        await expectLater(
          AppLockService.verifyPin('0000'),
          throwsA(
            isA<PinCooldownException>().having(
              (e) => e.seconds,
              'seconds',
              duration,
            ),
          ),
        );
        expect(await AppLockService.cooldownSeconds(), duration);
        await expectLater(
          AppLockService.verifyPin('1234'),
          throwsA(isA<PinCooldownException>()),
        );
        advance(duration);
      }
      expect(await AppLockService.verifyPin('1234'), isTrue);
      expect(await AppLockService.cooldownSeconds(), 0);
      expect(await AppLockService.verifyPin('0000'), isFalse);
      expect(await AppLockService.verifyPin('0000'), isFalse);
    },
  );
  test('cooldown survives restart without storing entered PINs', () async {
    await AppLockService.setPin('1234');
    await AppLockService.verifyPin('5678');
    await AppLockService.verifyPin('5678');
    await expectLater(
      AppLockService.verifyPin('5678'),
      throwsA(isA<PinCooldownException>()),
    );
    advance(10);
    AppLockService.resetClockObservation();
    expect(await AppLockService.cooldownSeconds(), 20);
    expect(storage['briska_lock_pin_cooldown_v1'], isNot(contains('5678')));
    await expectLater(
      AppLockService.verifyPin('1234'),
      throwsA(isA<PinCooldownException>()),
    );
  });
  test('wall clock jumps do not bypass an observed cooldown', () async {
    await AppLockService.setPin('1234');
    await AppLockService.verifyPin('0');
    await AppLockService.verifyPin('0');
    await expectLater(
      AppLockService.verifyPin('0'),
      throwsA(isA<PinCooldownException>()),
    );
    now = now.add(const Duration(days: 100));
    expect(await AppLockService.cooldownSeconds(), 30);
    now = now.subtract(const Duration(days: 200));
    AppLockService.resetClockObservation();
    expect(await AppLockService.cooldownSeconds(), 30);
    advance(30);
    expect(await AppLockService.verifyPin('1234'), isTrue);
  });
  test(
    'replacement requires old PIN, and failures preserve the legacy PIN',
    () async {
      legacy();
      await expectLater(
        AppLockService.setPin('9876'),
        throwsA(isA<PinVerificationException>()),
      );
      await expectLater(
        AppLockService.setPin('9876', currentPin: '0000'),
        throwsA(isA<PinVerificationException>()),
      );
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_pin_record_v1') {
          throw StateError('write failure');
        }
        storage[key] = value;
      };
      await expectLater(
        AppLockService.setPin('9876', currentPin: '1234'),
        throwsStateError,
      );
      expect(await AppLockService.verifyPin('1234'), isTrue);
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      await AppLockService.setPin('9876', currentPin: '1234');
      expect(await AppLockService.verifyPin('9876'), isTrue);
      expect(await AppLockService.verifyPin('1234'), isFalse);
    },
  );
  test(
    'failed replacement of a new-format PIN leaves the pair intact',
    () async {
      await AppLockService.setPin('1234');
      final record = storage['briska_lock_pin_record_v1'];
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_pin_record_v1') throw StateError('write');
        storage[key] = value;
      };
      await expectLater(
        AppLockService.setPin('9876', currentPin: '1234'),
        throwsStateError,
      );
      expect(storage['briska_lock_pin_record_v1'], record);
      expect(await AppLockService.verifyPin('1234'), isTrue);
    },
  );
  for (final pin in [
    '',
    '123',
    '1234567890123',
    '12ab',
    ' 1234',
    '1234 ',
    '12.3',
  ]) {
    test(
      'rejects invalid new PIN format: length ${pin.length}, value category',
      () async {
        await expectLater(AppLockService.setPin(pin), throwsFormatException);
        expect(storage, isEmpty);
      },
    );
  }
  for (final corrupt in ['{', '{}', '{"salt":"x","hash":"bad"}']) {
    test(
      'corrupt new record fails closed without legacy fallback: $corrupt',
      () async {
        legacy();
        storage['briska_lock_pin_record_v1'] = corrupt;
        await expectLater(AppLockService.loadConfig(), throwsA(anything));
        await expectLater(AppLockService.verifyPin('1234'), throwsA(anything));
        await expectLater(AppLockService.setPin('9876'), throwsA(anything));
      },
    );
  }
  test(
    'incomplete legacy record and unavailable storage fail closed',
    () async {
      storage['briska_lock_pin_salt'] = 'salt';
      await expectLater(AppLockService.loadConfig(), throwsFormatException);
      AppLockService.readOverride = (_) async => throw StateError('storage');
      await expectLater(AppLockService.verifyPin('1234'), throwsStateError);
      await expectLater(AppLockService.setPin('1234'), throwsStateError);
    },
  );
  test(
    'disable requires current PIN, honors cooldown and preserves config on write failure',
    () async {
      await AppLockService.setPin('1234');
      await AppLockService.saveConfig(
        const AppLockConfig(enabled: true, hasPin: true),
      );
      const disabled = AppLockConfig(enabled: false);
      await expectLater(
        AppLockService.saveConfig(disabled),
        throwsA(isA<PinVerificationException>()),
      );
      await expectLater(
        AppLockService.saveConfig(disabled, currentPin: '0'),
        throwsA(isA<PinVerificationException>()),
      );
      await AppLockService.verifyPin('0');
      await expectLater(
        AppLockService.saveConfig(disabled, currentPin: '0'),
        throwsA(isA<PinCooldownException>()),
      );
      await expectLater(
        AppLockService.setPin('9876', currentPin: '1234'),
        throwsA(isA<PinCooldownException>()),
      );
      advance(30);
      final before = Map.of(storage);
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_enabled') throw StateError('storage');
        storage[key] = value;
      };
      await expectLater(
        AppLockService.saveConfig(disabled, currentPin: '1234'),
        throwsStateError,
      );
      expect(storage['briska_lock_enabled'], before['briska_lock_enabled']);
      expect((await AppLockService.loadConfig()).enabled, isTrue);
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      await AppLockService.saveConfig(disabled, currentPin: '1234');
      expect((await AppLockService.loadConfig()).enabled, isFalse);
    },
  );
  test(
    'failed configuration update restores earlier writes and keeps lock enabled',
    () async {
      await AppLockService.setPin('1234');
      await AppLockService.saveConfig(const AppLockConfig(enabled: true));
      final before = await AppLockService.loadConfig();
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_delay') throw StateError('write failed');
        storage[key] = value;
      };
      await expectLater(
        AppLockService.saveConfig(
          before.copyWith(useBiometrics: true, lockAfterSeconds: 300),
        ),
        throwsStateError,
      );
      final after = await AppLockService.loadConfig();
      expect(after.enabled, before.enabled);
      expect(after.useBiometrics, before.useBiometrics);
      expect(after.lockAfterSeconds, before.lockAfterSeconds);
      expect(after.hasPin, before.hasPin);
      expect(await AppLockService.verifyPin('1234'), isTrue);
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      await AppLockService.saveConfig(before.copyWith(useBiometrics: true));
      expect((await AppLockService.loadConfig()).useBiometrics, isTrue);
    },
  );

  test(
    'failed enabling rolls back preferences and never enables an incomplete configuration',
    () async {
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_enabled') throw StateError('write failed');
        storage[key] = value;
      };
      await expectLater(
        AppLockService.saveConfig(
          const AppLockConfig(
            enabled: true,
            useBiometrics: true,
            lockAfterSeconds: 300,
          ),
        ),
        throwsStateError,
      );
      final after = await AppLockService.loadConfig();
      expect(after.enabled, isFalse);
      expect(after.useBiometrics, isFalse);
      expect(after.lockAfterSeconds, 60);
    },
  );

  test(
    'mutate-then-throw restores the failed key first and preserves original error and PIN',
    () async {
      await AppLockService.setPin('1234');
      await AppLockService.saveConfig(const AppLockConfig(enabled: true));
      final pinRecord = storage['briska_lock_pin_record_v1'];
      final failure = StateError('original write error');
      final originalStack = StackTrace.fromString('original write stack');
      final writes = <String>[];
      AppLockService.writeOverride = (key, value) async {
        writes.add('$key=$value');
        storage[key] = value;
        if (key == 'briska_lock_delay' && value == '300') {
          Error.throwWithStackTrace(failure, originalStack);
        }
      };
      Object? caught;
      StackTrace? caughtStack;
      try {
        await AppLockService.saveConfig(
          const AppLockConfig(
            enabled: true,
            useBiometrics: true,
            lockAfterSeconds: 300,
          ),
        );
      } catch (error, stack) {
        caught = error;
        caughtStack = stack;
      }
      expect(caught, same(failure));
      expect(caughtStack.toString(), originalStack.toString());
      expect(writes, [
        'briska_lock_biometrics=true',
        'briska_lock_delay=300',
        'briska_lock_delay=60',
        'briska_lock_biometrics=false',
      ]);
      final restored = await AppLockService.loadConfig();
      expect(restored.enabled, isTrue);
      expect(restored.useBiometrics, isFalse);
      expect(restored.lockAfterSeconds, 60);
      expect(storage['briska_lock_pin_record_v1'], pinRecord);
      expect(await AppLockService.verifyPin('1234'), isTrue);
    },
  );

  test('ambiguous disable failure restores the enabled state', () async {
    legacy();
    await AppLockService.saveConfig(const AppLockConfig(enabled: true));
    final failure = StateError('disable write');
    AppLockService.writeOverride = (key, value) async {
      storage[key] = value;
      if (key == 'briska_lock_enabled' && value == 'false') throw failure;
    };
    await expectLater(
      AppLockService.saveConfig(
        const AppLockConfig(enabled: false),
        currentPin: '1234',
      ),
      throwsA(same(failure)),
    );
    expect(storage['briska_lock_enabled'], 'true');
    expect((await AppLockService.loadConfig()).enabled, isTrue);
    expect(await AppLockService.verifyPin('1234'), isTrue);
  });

  test(
    'rollback errors do not stop remaining restores; unresolved state survives restart and fails closed',
    () async {
      legacy();
      final salt = storage['briska_lock_pin_salt'];
      final hash = storage['briska_lock_pin_hash'];
      await AppLockService.saveConfig(const AppLockConfig(enabled: true));
      final original = StateError('SENSITIVE_ORIGINAL_DETAIL');
      final rollback = StateError('SENSITIVE_ROLLBACK_DETAIL');
      final originalStack = StackTrace.fromString('original save location');
      final writes = <String>[];
      AppLockService.writeOverride = (key, value) async {
        writes.add(key);
        if (key == 'briska_lock_delay' && value == '60') throw rollback;
        storage[key] = value;
        if (key == 'briska_lock_delay' && value == '300') {
          Error.throwWithStackTrace(original, originalStack);
        }
      };
      AppLockConfigRecoveryException? caught;
      try {
        await AppLockService.saveConfig(
          const AppLockConfig(
            enabled: true,
            useBiometrics: true,
            lockAfterSeconds: 300,
          ),
        );
      } on AppLockConfigRecoveryException catch (error) {
        caught = error;
      }
      expect(caught, isNotNull);
      expect(caught!.originalError, same(original));
      expect(caught.originalStackTrace.toString(), originalStack.toString());
      expect(caught.recoveryErrors, contains(same(rollback)));
      expect(caught.toString(), isNot(contains('SENSITIVE')));
      expect(writes, [
        'briska_lock_biometrics',
        'briska_lock_delay',
        'briska_lock_delay',
        'briska_lock_biometrics',
        'briska_lock_config_recovery_v1',
      ]);
      expect(storage['briska_lock_biometrics'], 'false');
      expect(storage['briska_lock_enabled'], 'true');
      expect(storage['briska_lock_pin_salt'], salt);
      expect(storage['briska_lock_pin_hash'], hash);
      AppLockService.resetOperationsForTesting();
      await expectLater(AppLockService.loadConfig(), throwsStateError);
      await expectLater(
        AppLockService.saveConfig(
          const AppLockConfig(enabled: false),
          currentPin: '1234',
        ),
        throwsStateError,
      );
      // Recovery becomes possible once storage is writable again.
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      final recovered = await AppLockService.loadConfig();
      expect(recovered.enabled, isTrue);
      expect(recovered.useBiometrics, isFalse);
      expect(recovered.lockAfterSeconds, 60);
      expect(storage['briska_lock_config_recovery_v1'], '');
      expect(storage['briska_lock_pin_salt'], salt);
      expect(storage['briska_lock_pin_hash'], hash);
      expect(await AppLockService.verifyPin('1234'), isTrue);
    },
  );

  test(
    'rollback throwing after restoration still propagates the original failure',
    () async {
      await AppLockService.saveConfig(const AppLockConfig(enabled: true));
      final original = StateError('update');
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
        if (key == 'briska_lock_delay') {
          throw value == '300' ? original : StateError('rollback');
        }
      };
      await expectLater(
        AppLockService.saveConfig(
          const AppLockConfig(
            enabled: true,
            useBiometrics: true,
            lockAfterSeconds: 300,
          ),
        ),
        throwsA(same(original)),
      );
      final restored = await AppLockService.loadConfig();
      expect(restored.enabled, isTrue);
      expect(restored.useBiometrics, isFalse);
      expect(restored.lockAfterSeconds, 60);
    },
  );

  test(
    'unrecoverable disabling cannot load as disabled after restart',
    () async {
      legacy();
      await AppLockService.saveConfig(const AppLockConfig(enabled: true));
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_enabled') {
          if (value == 'false') storage[key] = value;
          throw StateError('enabled write');
        }
        storage[key] = value;
      };
      await expectLater(
        AppLockService.saveConfig(
          const AppLockConfig(enabled: false),
          currentPin: '1234',
        ),
        throwsA(isA<AppLockConfigRecoveryException>()),
      );
      expect(storage['briska_lock_enabled'], 'false');
      AppLockService.resetOperationsForTesting();
      await expectLater(AppLockService.loadConfig(), throwsStateError);
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      expect((await AppLockService.loadConfig()).enabled, isTrue);
      expect(await AppLockService.verifyPin('1234'), isTrue);
    },
  );

  test(
    'in-process protection remains when recovery record cannot be persisted',
    () async {
      await AppLockService.saveConfig(const AppLockConfig(enabled: true));
      AppLockService.writeOverride = (key, value) async {
        if (key == 'briska_lock_delay' && value == '300') storage[key] = value;
        throw StateError('storage unavailable');
      };
      // Only the delay changes, so that write fails after mutation.
      await expectLater(
        AppLockService.saveConfig(
          const AppLockConfig(enabled: true, lockAfterSeconds: 300),
        ),
        throwsA(isA<AppLockConfigRecoveryException>()),
      );
      expect(storage['briska_lock_config_recovery_v1'], isNull);
      await expectLater(AppLockService.loadConfig(), throwsStateError);
      AppLockService.writeOverride = (key, value) async {
        storage[key] = value;
      };
      expect((await AppLockService.loadConfig()).lockAfterSeconds, 60);
    },
  );

  test(
    'corrupt recovery record fails closed without writing arbitrary keys',
    () async {
      legacy();
      storage['briska_lock_config_recovery_v1'] = jsonEncode({
        'briska_lock_pin_hash': 'replacement',
      });
      final before = Map.of(storage);
      await expectLater(AppLockService.loadConfig(), throwsStateError);
      expect(storage, before);
    },
  );

  test('concurrent incorrect checks cannot lose attempt counts', () async {
    await AppLockService.setPin('1234');
    final gate = Completer<void>();
    var reads = 0;
    AppLockService.readOverride = (key) async {
      if (key == 'briska_lock_pin_cooldown_v1' && ++reads == 1) {
        await gate.future;
      }
      return storage[key];
    };
    final first = AppLockService.verifyPin('0');
    final second = AppLockService.verifyPin('0');
    final third = expectLater(
      AppLockService.verifyPin('0'),
      throwsA(isA<PinCooldownException>()),
    );
    gate.complete();
    expect(await first, isFalse);
    expect(await second, isFalse);
    await third;
    expect(await AppLockService.cooldownSeconds(), 30);
  });
}
