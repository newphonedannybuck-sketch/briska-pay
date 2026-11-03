import 'dart:io';

import 'package:briska/src/ads/ads_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const productionEmail = 'berkzerkatron@hotmail.com';
  final obsoleteEmail = ['support', 'briskapay.app'].join('@');
  const privacySources = <String>[
    'privacy.html',
    'assets/legal/privacy_policy.md',
    'docs/PLAY_STORE_LISTING.md',
  ];

  test('production privacy sources disclose advertising and UMP choices', () {
    for (final path in privacySources) {
      final content = File(path).readAsStringSync();
      final lower = content.toLowerCase();

      expect(lower, contains('google admob'), reason: path);
      expect(lower, contains('banner'), reason: path);
      expect(lower, contains('user messaging platform'), reason: path);
      expect(lower, contains('advertising privacy choices'), reason: path);
      expect(lower, contains('locally'), reason: path);
      expect(lower, isNot(contains('no advertising')), reason: path);
      expect(lower, isNot(contains('no ads')), reason: path);
      expect(lower, isNot(contains('no internet access')), reason: path);
      expect(content, contains(productionEmail), reason: path);
      expect(content, isNot(contains(obsoleteEmail)), reason: path);
    }
  });

  test(
    'privacy policy describes local records and user-directed files safely',
    () {
      final web = File('privacy.html').readAsStringSync();
      final bundled = File('assets/legal/privacy_policy.md').readAsStringSync();
      final combined = '$web\n$bundled'.toLowerCase();

      expect(combined, contains('work/day records'));
      expect(combined, contains('cloud-sync service'));
      expect(combined, contains('automatic cloud backup'));
      expect(combined, contains('disabled'));
      expect(combined, contains('when you choose'));
      expect(
        combined,
        contains('does not intentionally send your wage/work records'),
      );
      expect(combined, contains('does not receive or store biometric data'));
      expect(combined, contains('separate briska pay pin'));
      expect(combined, contains('cannot remotely delete local records'));
    },
  );

  test('public privacy prose does not expose production advertising IDs', () {
    for (final path in privacySources) {
      final content = File(path).readAsStringSync();
      expect(
        content,
        isNot(contains(AdsConfiguration.productionAdMobAppId)),
        reason: path,
      );
      expect(
        content,
        isNot(contains(AdsConfiguration.productionBannerAdUnitId)),
        reason: path,
      );
    }
  });
}
