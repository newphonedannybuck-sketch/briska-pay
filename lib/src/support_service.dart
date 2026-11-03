import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'release_info.dart';

const briskaSupportEmail = 'berkzerkatron@hotmail.com';

class BriskaDiagnostics {
  const BriskaDiagnostics({
    required this.appVersion,
    required this.buildNumber,
    required this.releaseTrack,
    required this.platform,
    required this.osVersion,
    required this.deviceModel,
  });

  final String appVersion;
  final String buildNumber;
  final String releaseTrack;
  final String platform;
  final String osVersion;
  final String deviceModel;

  String get appVersionLabel => '$appVersion ($buildNumber)';

  String toSummary() => [
    'Briska Pay diagnostics',
    'App version: $appVersion',
    'Build number: $buildNumber',
    'Release track: $briskaReleaseLabel',
    'Platform: $platform',
    'OS version: $osVersion',
    'Device model: $deviceModel',
    'Mode: ${kReleaseMode ? 'release' : 'debug/profile'}',
    '',
    'No names, employer or company details, pay, rates, allowances, notes or recorded days are included.',
  ].join('\n');
}

abstract final class BriskaSupportService {
  static Future<BriskaDiagnostics> diagnostics() async {
    final packageInfo = await PackageInfo.fromPlatform();
    var platform = defaultTargetPlatform.name;
    var osVersion = 'Unknown';
    var deviceModel = 'Unknown';

    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      platform = 'Android';
      osVersion =
          'Android ${android.version.release} (SDK ${android.version.sdkInt})';
      deviceModel = '${android.manufacturer} ${android.model}'.trim();
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      platform = 'iOS';
      osVersion = ios.systemVersion;
      deviceModel = ios.utsname.machine;
    }

    return BriskaDiagnostics(
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      releaseTrack: briskaReleaseTrack,
      platform: platform,
      osVersion: osVersion,
      deviceModel: deviceModel,
    );
  }

  static Future<bool> sendFeedback({
    required String subject,
    required BriskaDiagnostics diagnostics,
  }) {
    final body = Uri.encodeComponent(
      '${diagnostics.toSummary()}\n\nFeedback:\n',
    );
    final uri = Uri.parse(
      'mailto:$briskaSupportEmail?subject=${Uri.encodeComponent(subject)}&body=$body',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
