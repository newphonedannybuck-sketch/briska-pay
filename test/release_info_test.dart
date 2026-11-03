import 'package:briska/src/release_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release track defaults to production-safe tester visibility', () {
    expect(briskaReleaseTrack, 'production');
    expect(showBetaTools, isFalse);
    expect(briskaReleaseLabel, 'Production');
  });

  test('only explicit beta and development tracks expose tester tools', () {
    expect(isTesterReleaseTrack('beta'), isTrue);
    expect(isTesterReleaseTrack('development'), isTrue);
    expect(isTesterReleaseTrack('dev'), isTrue);
    expect(isTesterReleaseTrack('production'), isFalse);
    expect(isTesterReleaseTrack('release'), isFalse);
    expect(isTesterReleaseTrack('release-candidate'), isFalse);
    expect(isTesterReleaseTrack('rc'), isFalse);
    expect(isTesterReleaseTrack(''), isFalse);
    expect(isTesterReleaseTrack('unexpected-value'), isFalse);
  });
}
