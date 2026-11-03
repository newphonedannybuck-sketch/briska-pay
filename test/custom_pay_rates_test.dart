import 'dart:convert';

import 'package:briska/src/csv_export_service.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/work_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WorkEntry entry({
    String rateType = 'primary',
    double rate = 20,
    double allowance = 0,
  }) {
    final calculation = WorkCalculator.calculate(
      startTime: '08:00',
      finishTime: '16:00',
      breakMinutes: 0,
      hourlyRate: rate,
      rateType: rateType,
      dailyAllowance: allowance,
      jobUplift: 0,
    );
    return WorkEntry(
      id: rateType,
      date: DateTime(2026, 8, 3),
      siteName: 'Site',
      startTime: '08:00',
      finishTime: '16:00',
      breakMinutes: 0,
      rateType: rateType,
      hourlyRateUsed: rate,
      dailyAllowance: allowance,
      jobUplift: 0,
      totalHours: calculation.totalHours,
      wages: calculation.wages,
      totalPay: calculation.totalPay,
      notes: '',
    );
  }

  test('new users receive editable Standard and Overtime labels', () {
    const settings = AppSettings();
    expect(settings.primaryRateLabel, 'Standard');
    expect(settings.secondaryRateLabel, 'Overtime');
    expect(
      settings
          .copyWith(primaryRateLabel: 'Weekday', secondaryRateLabel: 'Weekend')
          .toJson(),
      containsPair('secondaryRateLabel', 'Weekend'),
    );
  });

  test('legacy Home and Away settings and entries migrate safely', () {
    final settings = AppSettings.fromJson({
      'homeHourlyRate': 18.5,
      'awayHourlyRate': 27.75,
    });
    expect(settings.primaryRateLabel, 'Home');
    expect(settings.primaryRateValue, 18.5);
    expect(settings.secondaryRateLabel, 'Away');
    expect(settings.secondaryRateValue, 27.75);
    expect(
      WorkEntry.fromJson({
        ...entry().toJson(),
        'workLocation': 'Away',
        'rateType': null,
      }).rateType,
      'secondary',
    );
    expect(
      WorkEntry.fromJson({
        ...entry().toJson(),
        'workLocation': 'Away',
        'rateType': null,
        'dailyAllowance': 0,
      }).dailyAllowance,
      0,
    );
  });

  test('allowance is independent of selected generic rate', () {
    final primary = entry(allowance: 15);
    final secondary = entry(rateType: 'secondary', rate: 25);
    expect(WorkCalculator.recalculateEntry(primary).totalPay, 175);
    expect(WorkCalculator.recalculateEntry(secondary).totalPay, 200);
  });

  test('renaming labels does not change historical saved values', () {
    final historical = entry(rateType: 'secondary', rate: 27.75);
    const renamed = AppSettings(
      secondaryRateLabel: 'Weekend',
      secondaryRateValue: 40,
    );
    expect(renamed.labelForRate(historical.rateType), 'Weekend');
    expect(WorkCalculator.recalculateEntry(historical).wages, 222);
  });

  test('missing custom labels use safe display fallbacks', () {
    const settings = AppSettings(
      primaryRateLabel: '   ',
      secondaryRateLabel: '',
    );
    expect(settings.labelForRate('primary'), 'Primary Rate');
    expect(settings.labelForRate('secondary'), 'Secondary Rate');
  });

  test('CSV uses custom visible labels and stable generic data', () {
    final text = utf8.decode(
      CsvExportService.buildCsv(
        [entry(rateType: 'secondary')],
        primaryRateLabel: 'Weekday',
        secondaryRateLabel: 'Weekend',
      ),
    );
    expect(text, contains('Rate used'));
    expect(text, contains('Weekend'));
    expect(text, isNot(contains('Home / Away')));
  });
}
