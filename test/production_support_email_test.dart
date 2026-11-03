import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production-facing sources use the production support email', () {
    const productionEmail = 'berkzerkatron@hotmail.com';
    final obsoleteEmail = ['support', 'briskapay.app'].join('@');
    final productionSources = <String>[
      'assets/legal/privacy_policy.md',
      'lib/src/support_service.dart',
      'index.html',
      'privacy.html',
      'terms.html',
      'support.html',
      'docs/PLAY_STORE_LISTING.md',
      'docs/RELEASE_CANDIDATE_REPORT.md',
    ];

    for (final path in productionSources) {
      final content = File(path).readAsStringSync();
      expect(content, contains(productionEmail), reason: path);
      expect(content, isNot(contains(obsoleteEmail)), reason: path);
    }
  });
}
