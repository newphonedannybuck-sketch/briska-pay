import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ads_service.dart';

class BriskaBannerAd extends StatefulWidget {
  const BriskaBannerAd({required this.adsService, super.key});

  final AdsService adsService;

  @override
  State<BriskaBannerAd> createState() => _BriskaBannerAdState();
}

class _BriskaBannerAdState extends State<BriskaBannerAd> {
  LoadedBannerAd? _banner;
  double? _reservedHeight;
  int? _requestedWidth;
  int _requestRevision = 0;

  @override
  void didUpdateWidget(BriskaBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.adsService, widget.adsService)) {
      _replaceBanner(null);
      _requestedWidth = null;
      _reservedHeight = null;
    }
  }

  void _requestForWidth(double availableWidth) {
    final width = availableWidth.floor();
    if (width <= 0 ||
        (_requestedWidth != null && (width - _requestedWidth!).abs() < 8)) {
      return;
    }
    _requestedWidth = width;
    final revision = ++_requestRevision;
    widget.adsService
        .loadAnchoredAdaptiveBanner(
          width.toDouble(),
          onSizeResolved: (height) {
            if (mounted && revision == _requestRevision) {
              setState(() => _reservedHeight = height);
            }
          },
        )
        .then((loaded) async {
          if (!mounted ||
              revision != _requestRevision ||
              _requestedWidth != width) {
            await loaded?.dispose();
            return;
          }
          if (loaded == null) _reservedHeight = null;
          await _replaceBanner(loaded);
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (kDebugMode) debugPrint('banner load failed');
          if (mounted && revision == _requestRevision) {
            _reservedHeight = null;
            _replaceBanner(null);
          }
        });
  }

  Future<void> _replaceBanner(LoadedBannerAd? replacement) async {
    final previous = _banner;
    if (mounted) {
      setState(() => _banner = replacement);
    } else {
      _banner = replacement;
    }
    if (!identical(previous, replacement)) await previous?.dispose();
  }

  @override
  void dispose() {
    _requestRevision++;
    _banner?.dispose();
    _banner = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestForWidth(constraints.maxWidth);
      });
      final banner = _banner;
      if (banner == null) {
        return SizedBox(
          key: _reservedHeight == null
              ? null
              : const ValueKey('loading-briska-banner-slot'),
          height: _reservedHeight ?? 0,
        );
      }
      return Center(
        child: SizedBox(
          key: const ValueKey('loaded-briska-banner-slot'),
          width: banner.width.clamp(0, constraints.maxWidth),
          height: banner.height,
          child: banner.buildWidget(),
        ),
      );
    },
  );
}
