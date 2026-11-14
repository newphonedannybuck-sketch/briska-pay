import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ads_service.dart';
import 'ads_consent_coordinator.dart';

class AdvertisingConsentResult {
  const AdvertisingConsentResult(this.bannerEligible, this.privacyRequirement);
  final bool bannerEligible;
  final PrivacyOptionsRequirement privacyRequirement;
}

/// Starts optional SDK work early; consent forms are requested only by the
/// unlocked shell. Disposing cancels the same optional-operation timers.
class AdvertisingStartup {
  AdvertisingStartup({required this.service, required this.coordinator}) {
    _adsInitializationReady = _initializeAdsEarly();
    _consentUpdateReady = _updateConsentEarly();
  }
  final AdsService service;
  final AdsConsentCoordinator coordinator;
  static const _consentOperationTimeout = Duration(seconds: 15);
  late final Future<bool> _adsInitializationReady;
  late final Future<bool> _consentUpdateReady;
  final Set<Timer> _optionalOperationTimers = {};

  void dispose() {
    for (final timer in _optionalOperationTimers) {
      timer.cancel();
    }
    _optionalOperationTimers.clear();
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
      await _withOptionalOperationTimeout(service.initialize());
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
        coordinator.updateConsentInformation(),
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

  Future<AdvertisingConsentResult> resolveConsent() async {
    var canRequestAds = false;
    var bannerEligible = false;
    var privacyRequirement = PrivacyOptionsRequirement.unknown;
    try {
      if (!await _consentUpdateReady) {
        throw StateError('Advertising consent information is unavailable.');
      }
      final formRequirement = await _withOptionalOperationTimeout(
        coordinator.consentFormRequirement(),
      );
      if (formRequirement == ConsentFormRequirement.required) {
        await coordinator.showRequiredConsentForm();
      }
      canRequestAds = await _withOptionalOperationTimeout(
        coordinator.canRequestAds(),
      );
      privacyRequirement = await _withOptionalOperationTimeout(
        coordinator.privacyOptionsRequirement(),
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
        bannerEligible =
            await _adsInitializationReady &&
            await service.capability() != AdsCapability.unavailable;
      } catch (error, stackTrace) {
        bannerEligible = false;
        if (kDebugMode) {
          debugPrint('advertising SDK initialisation failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    }
    return AdvertisingConsentResult(bannerEligible, privacyRequirement);
  }
}
