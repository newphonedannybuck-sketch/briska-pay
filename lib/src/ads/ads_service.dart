import 'dart:async';

import 'ads_configuration.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum AdsCapability { unavailable, testConfigured, productionConfigured }

abstract interface class LoadedBannerAd {
  double get width;
  double get height;
  Widget buildWidget();
  Future<void> dispose();
}

abstract interface class AdsService {
  AdsConfiguration get configuration;

  Future<AdsCapability> capability();

  Future<void> initialize();

  Future<LoadedBannerAd?> loadAnchoredAdaptiveBanner(
    double width, {
    ValueChanged<double>? onSizeResolved,
  });
}

class DisabledAdsService implements AdsService {
  const DisabledAdsService(this.configuration);

  @override
  final AdsConfiguration configuration;

  @override
  Future<AdsCapability> capability() async => AdsCapability.unavailable;

  @override
  Future<void> initialize() async {}

  @override
  Future<LoadedBannerAd?> loadAnchoredAdaptiveBanner(
    double width, {
    ValueChanged<double>? onSizeResolved,
  }) async => null;
}

class GoogleMobileAdsService implements AdsService {
  GoogleMobileAdsService(this.configuration);

  @override
  final AdsConfiguration configuration;

  Future<void>? _initialization;

  @override
  Future<AdsCapability> capability() async {
    if (configuration.environment == AdsEnvironment.test) {
      return AdsCapability.testConfigured;
    }
    return configuration.isProductionConfigurationComplete
        ? AdsCapability.productionConfigured
        : AdsCapability.unavailable;
  }

  @override
  Future<void> initialize() =>
      _initialization ??= MobileAds.instance.initialize().then((_) {});

  @override
  Future<LoadedBannerAd?> loadAnchoredAdaptiveBanner(
    double width, {
    ValueChanged<double>? onSizeResolved,
  }) async {
    final validTestConfiguration =
        configuration.environment == AdsEnvironment.test &&
        configuration.bannerAdUnitIdSource ==
            BannerAdUnitIdSource.officialGoogleTest &&
        configuration.bannerAdUnitId ==
            AdsConfiguration.officialAndroidTestBannerAdUnitId;
    final validProductionConfiguration =
        configuration.environment == AdsEnvironment.production &&
        configuration.isProductionConfigurationComplete &&
        configuration.bannerAdUnitIdSource ==
            BannerAdUnitIdSource.productionConfiguration &&
        configuration.bannerAdUnitId ==
            AdsConfiguration.productionBannerAdUnitId;
    if ((!validTestConfiguration && !validProductionConfiguration) ||
        width <= 0) {
      return null;
    }
    final logicalWidth = width.floor();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
      logicalWidth,
    );
    if (size == null || size.width > logicalWidth) return null;
    onSizeResolved?.call(size.height.toDouble());

    final completer = Completer<LoadedBannerAd?>();
    late final BannerAd banner;
    banner = BannerAd(
      adUnitId: configuration.bannerAdUnitId!,
      request: const AdRequest(),
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!completer.isCompleted) {
            completer.complete(_GoogleLoadedBannerAd(banner, size));
          }
        },
        onAdFailedToLoad: (ad, error) async {
          await ad.dispose();
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    try {
      await banner.load();
    } catch (_) {
      await banner.dispose();
      rethrow;
    }
    return completer.future;
  }
}

final class _GoogleLoadedBannerAd implements LoadedBannerAd {
  const _GoogleLoadedBannerAd(this._banner, this._size);

  final BannerAd _banner;
  final AdSize _size;

  @override
  double get width => _size.width.toDouble();

  @override
  double get height => _size.height.toDouble();

  @override
  Widget buildWidget() => AdWidget(ad: _banner);

  @override
  Future<void> dispose() => _banner.dispose();
}
