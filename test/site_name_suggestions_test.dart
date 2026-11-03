import 'package:flutter_test/flutter_test.dart';
import 'package:briska/src/models.dart';
import 'package:briska/src/site_name_suggestions.dart';

void main() {
  WorkEntry entry({
    required String id,
    required DateTime date,
    required String siteName,
    String entryType = 'WorkDay',
  }) => WorkEntry(
    id: id,
    entryType: entryType,
    date: date,
    siteName: siteName,
    startTime: entryType == 'WorkDay' ? '08:00' : '',
    finishTime: entryType == 'WorkDay' ? '17:00' : '',
    breakMinutes: entryType == 'WorkDay' ? 30 : 0,
    workLocation: 'Home',
    hourlyRateUsed: 20,
    dailyAllowance: 0,
    jobUplift: 0,
    totalHours: entryType == 'WorkDay' ? 8.5 : 0,
    wages: entryType == 'WorkDay' ? 170 : 0,
    totalPay: entryType == 'WorkDay' ? 170 : 0,
    notes: '',
  );

  test('suggests recent unique work day site names with contains matching', () {
    final entries = [
      entry(id: 'old', date: DateTime(2026, 7, 1), siteName: 'Station Road'),
      entry(id: 'blank', date: DateTime(2026, 7, 2), siteName: ''),
      entry(
        id: 'holiday',
        date: DateTime(2026, 7, 3),
        siteName: 'Holiday Site',
        entryType: 'Holiday',
      ),
      entry(id: 'dupe-old', date: DateTime(2026, 7, 4), siteName: 'st marys'),
      entry(id: 'joseph', date: DateTime(2026, 7, 5), siteName: 'St Josephs'),
      entry(id: 'dupe-new', date: DateTime(2026, 7, 6), siteName: 'St Marys'),
      entry(
        id: 'unpaid',
        date: DateTime(2026, 7, 7),
        siteName: 'Unpaid Site',
        entryType: 'UnpaidDayOff',
      ),
    ];

    expect(recentSiteNameSuggestions(entries, query: 'st'), [
      'St Marys',
      'St Josephs',
      'Station Road',
    ]);
    expect(recentSiteNameSuggestions(entries, query: 'road'), ['Station Road']);
    expect(recentSiteNameSuggestions(entries, query: '', limit: 2), [
      'St Marys',
      'St Josephs',
    ]);
  });
}
