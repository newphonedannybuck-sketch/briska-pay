import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum ConsentFormRequirement { unknown, notRequired, required }

enum PrivacyOptionsRequirement { unknown, notRequired, required }

abstract interface class AdsConsentCoordinator {
  Future<void> updateConsentInformation();

  Future<ConsentFormRequirement> consentFormRequirement();

  Future<void> showRequiredConsentForm();

  Future<bool> canRequestAds();

  Future<PrivacyOptionsRequirement> privacyOptionsRequirement();

  Future<void> showPrivacyOptions();
}

class InactiveAdsConsentCoordinator implements AdsConsentCoordinator {
  const InactiveAdsConsentCoordinator();

  @override
  Future<bool> canRequestAds() async => false;

  @override
  Future<ConsentFormRequirement> consentFormRequirement() async =>
      ConsentFormRequirement.unknown;

  @override
  Future<PrivacyOptionsRequirement> privacyOptionsRequirement() async =>
      PrivacyOptionsRequirement.unknown;

  @override
  Future<void> showPrivacyOptions() async {}

  @override
  Future<void> showRequiredConsentForm() async {}

  @override
  Future<void> updateConsentInformation() async {}
}

enum ConsentDebugGeography { disabled, eea, regulatedUsState, other }

class AdsConsentDebugConfiguration {
  const AdsConsentDebugConfiguration._({
    required this.enabled,
    required this.testDeviceIdentifiers,
    required this.geography,
    required this.allowReset,
  });

  const AdsConsentDebugConfiguration.production()
    : this._(
        enabled: false,
        testDeviceIdentifiers: const [],
        geography: ConsentDebugGeography.disabled,
        allowReset: false,
      );

  factory AdsConsentDebugConfiguration.development({
    List<String> testDeviceIdentifiers = const [],
    ConsentDebugGeography geography = ConsentDebugGeography.disabled,
    bool allowReset = false,
  }) => AdsConsentDebugConfiguration._(
    enabled: true,
    testDeviceIdentifiers: List.unmodifiable(testDeviceIdentifiers),
    geography: geography,
    allowReset: allowReset,
  );

  factory AdsConsentDebugConfiguration.current() {
    if (kReleaseMode) return const AdsConsentDebugConfiguration.production();
    const identifiers = String.fromEnvironment('BRISKA_UMP_TEST_DEVICE_IDS');
    const geography = String.fromEnvironment('BRISKA_UMP_DEBUG_GEOGRAPHY');
    return AdsConsentDebugConfiguration.development(
      testDeviceIdentifiers: identifiers
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      geography: switch (geography.toLowerCase()) {
        'eea' => ConsentDebugGeography.eea,
        'regulated_us_state' => ConsentDebugGeography.regulatedUsState,
        'other' => ConsentDebugGeography.other,
        _ => ConsentDebugGeography.disabled,
      },
      allowReset: const bool.fromEnvironment('BRISKA_UMP_ALLOW_RESET'),
    );
  }

  final bool enabled;
  final List<String> testDeviceIdentifiers;
  final ConsentDebugGeography geography;
  final bool allowReset;
}

class GoogleAdsConsentCoordinator implements AdsConsentCoordinator {
  GoogleAdsConsentCoordinator({
    AdsConsentDebugConfiguration? debugConfiguration,
    ConsentInformation? consentInformation,
  }) : debugConfiguration =
           debugConfiguration ?? AdsConsentDebugConfiguration.current(),
       _consentInformation = consentInformation ?? ConsentInformation.instance;

  final AdsConsentDebugConfiguration debugConfiguration;
  final ConsentInformation _consentInformation;

  ConsentRequestParameters get _requestParameters => ConsentRequestParameters(
    consentDebugSettings: debugConfiguration.enabled
        ? ConsentDebugSettings(
            testIdentifiers: debugConfiguration.testDeviceIdentifiers,
            debugGeography: switch (debugConfiguration.geography) {
              ConsentDebugGeography.eea => DebugGeography.debugGeographyEea,
              ConsentDebugGeography.regulatedUsState =>
                DebugGeography.debugGeographyRegulatedUsState,
              ConsentDebugGeography.other => DebugGeography.debugGeographyOther,
              ConsentDebugGeography.disabled =>
                DebugGeography.debugGeographyDisabled,
            },
          )
        : null,
  );

  @override
  Future<void> updateConsentInformation() {
    final completer = Completer<void>();
    _consentInformation.requestConsentInfoUpdate(
      _requestParameters,
      completer.complete,
      (error) => completer.completeError(error),
    );
    return completer.future;
  }

  @override
  Future<ConsentFormRequirement> consentFormRequirement() async {
    return switch (await _consentInformation.getConsentStatus()) {
      ConsentStatus.required => ConsentFormRequirement.required,
      ConsentStatus.notRequired ||
      ConsentStatus.obtained => ConsentFormRequirement.notRequired,
      ConsentStatus.unknown => ConsentFormRequirement.unknown,
    };
  }

  @override
  Future<void> showRequiredConsentForm() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error);
      }
    });
    return completer.future;
  }

  @override
  Future<bool> canRequestAds() => _consentInformation.canRequestAds();

  @override
  Future<PrivacyOptionsRequirement> privacyOptionsRequirement() async {
    return switch (await _consentInformation
        .getPrivacyOptionsRequirementStatus()) {
      PrivacyOptionsRequirementStatus.required =>
        PrivacyOptionsRequirement.required,
      PrivacyOptionsRequirementStatus.notRequired =>
        PrivacyOptionsRequirement.notRequired,
      PrivacyOptionsRequirementStatus.unknown =>
        PrivacyOptionsRequirement.unknown,
    };
  }

  @override
  Future<void> showPrivacyOptions() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error);
      }
    });
    return completer.future;
  }

  Future<void> resetForTesting() {
    if (!debugConfiguration.enabled || !debugConfiguration.allowReset) {
      throw StateError('Consent reset is unavailable.');
    }
    return _consentInformation.reset();
  }
}
