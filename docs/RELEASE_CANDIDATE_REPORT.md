# Briska 1.0 Release Candidate Report

Version name: 1.0.0
Build number: 2
Internal label: Briska 1.0 Release Candidate
Package ID: com.berkzerker.briska

## Tests Passed

- `flutter clean`
- `flutter pub get`
- `flutter analyze`
- `flutter test` - 53 tests passed
- `flutter build apk --release`
- `flutter build appbundle --release`

Focused automated audits passed:
- Home, Away, Holiday and Unpaid Day Off calculation rules.
- Shared summary totals for documented release-candidate month.
- Weekly, fortnightly, four-weekly, monthly and last-Friday pay periods.
- Last-Friday edge cases: February, leap year, payday, after payday and month-boundary starts.
- Backup preview validation, unsupported versions, invalid JSON and legacy rebrand-era backup metadata.
- Excel whole-number, hours, currency and UK date formatting.
- Site suggestion filtering and duplicate handling.

## Tests Failed

- None in automated verification.

## Bugs Fixed In This Phase

- Updated version from `1.0.0+1` to `1.0.0+2`.
- Added internal release-candidate label for About and diagnostics.
- Removed visible unfinished support/privacy strings.
- Disabled fake support-email launching when no real address is configured.
- Prevented raw startup storage exception text from showing in release UI.
- Accepted legacy rebrand-era backup metadata during restore preview.
- Changed Excel date cell format to UK-style `dd/mm/yyyy`.
- Added release-candidate calculation, pay-period, backup and expected-month regression tests.

## Known Limitations

- No real Play upload keystore is configured yet. `android/key.properties` is absent, so release builds use the debug-key fallback.
- Physical Android phone testing could not be performed from this shell because `adb` is not available on PATH.
- Support email is configured as `berkzerkatron@hotmail.com`.
- The public privacy policy is prepared at `/privacy.html`; confirm the final
  GitHub Pages owner/repository URL and live deployment before production
  submission.

## Manual Checks Still Needed

- Install APK on a physical Android phone.
- Update APK over an existing `com.berkzerker.briska` installation and confirm data survives.
- Cold launch, warm launch, force-stop, resume and restart-phone checks.
- Open exported Excel files in Microsoft Excel, Google Sheets and an Android spreadsheet viewer.
- Test biometrics on devices with and without biometric hardware.
- Test large text scale, screen reader labels and focus order.
- Confirm launcher icon readability on physical device home screen.

## Permissions Used

- Main/release: `android.permission.USE_BIOMETRIC` for optional App Lock biometric authentication.
- Debug/profile only: `android.permission.INTERNET` for Flutter tooling, hot reload/debugging.

No location, contacts, microphone, camera or broad storage permissions are declared in the release manifest.

## Packages Used

- `shared_preferences`
- `excel`
- `path_provider`
- `open_filex`
- `share_plus`
- `intl`
- `package_info_plus`
- `local_auth`
- `flutter_secure_storage`
- `crypto`
- `file_selector`
- `device_info_plus`
- `url_launcher`

Dev/testing:
- `flutter_test`
- `flutter_lints`
- `shared_preferences_platform_interface`

## Data Safety

- Backup format version: 1
- Local data schema version: 2
- Backup restore previews data before replacement.
- Restore creates a safety backup before replacing current data.
- Existing exported-file records are not restored as available when their referenced file is missing.
- Startup storage failures show a recovery screen with Retry, Restore Backup and confirmed Reset Local Data.

## Supported Android Versions

- Android build uses Flutter's configured Android SDK values.
- Built metadata reports `minSdkVersionForDexing: 24`.

## Release Artifact Details

APK:
- Path: `C:\Briska\build\app\outputs\flutter-apk\app-release.apk`
- Size: 57,939,251 bytes

AAB:
- Path: `C:\Briska\build\app\outputs\bundle\release\app-release.aab`
- Size: 56,786,492 bytes

Signing status:
- Release signing is configured to use `android/key.properties` when present.
- `android/key.properties` was not present for this build.
- This build used the debug-key fallback and is not suitable for Play Store upload until a real upload key is configured.

## Release Readiness

No automated release blockers were found.

Do not describe Version 1.0 as ready for public release until physical-device testing, real release signing and Play Store privacy/support details are complete.
