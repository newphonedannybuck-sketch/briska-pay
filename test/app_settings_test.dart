import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/models.dart';

void main() {
  test('default away allowance is not part of settings', () {
    const legacyJson = {'dailyAllowance': 25.0, 'fullName': 'Existing'};

    final restored = AppSettings.fromJson(legacyJson);

    expect(restored.toJson(), isNot(contains('dailyAllowance')));
  });

  test('persists and restores theme mode values', () {
    const settings = AppSettings(themeMode: 'dark');

    expect(AppSettings.fromJson(settings.toJson()).themeMode, 'dark');
    expect(AppSettings.fromJson({'themeMode': 'light'}).themeMode, 'light');
    expect(AppSettings.fromJson({'themeMode': 'system'}).themeMode, 'light');
    expect(
      AppSettings.fromJson({'themeMode': 'ThemeMode.dark'}).themeMode,
      'dark',
    );
    expect(AppSettings.fromJson({'themeMode': 'unknown'}).themeMode, 'light');
  });

  test('persists company name and defaults old settings to blank', () {
    const settings = AppSettings(
      fullName: 'Daniel Beckett',
      companyName: 'Example Company Ltd',
    );

    expect(
      AppSettings.fromJson(settings.toJson()).companyName,
      'Example Company Ltd',
    );
    expect(
      AppSettings.fromJson({'fullName': 'Daniel Beckett'}).companyName,
      '',
    );
    expect(
      AppSettings.fromJson({'fullName': 'Daniel Beckett'}).homeHourlyRate,
      0,
    );
    expect(
      AppSettings.fromJson({'fullName': 'Daniel Beckett'}).awayHourlyRate,
      0,
    );
  });

  test(
    'persists selected payday weekday and safely restores older settings',
    () {
      const settings = AppSettings(paydaySelectedWeekday: DateTime.tuesday);

      expect(
        AppSettings.fromJson(settings.toJson()).paydaySelectedWeekday,
        DateTime.tuesday,
      );
      expect(
        AppSettings.fromJson({'paydayWeekday': 'Monday'}).paydaySelectedWeekday,
        DateTime.monday,
      );
      expect(
        AppSettings.fromJson({
          'paydaySelectedWeekday': 99,
        }).paydaySelectedWeekday,
        DateTime.friday,
      );
    },
  );

  test('maps legacy following weekday payday rule to the new rule name', () {
    expect(
      AppSettings.fromJson({'paydayRule': 'Following weekday'}).paydayRule,
      'Next selected weekday after period end',
    );
  });

  test('persists last export format with Excel fallback', () {
    const settings = AppSettings(lastExportFormat: 'pdfSummary');

    expect(
      AppSettings.fromJson(settings.toJson()).lastExportFormat,
      'pdfSummary',
    );
    expect(
      AppSettings.fromJson({'lastExportFormat': 'unknown'}).lastExportFormat,
      'excel',
    );
  });
}
