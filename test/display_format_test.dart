import 'package:briska/src/display_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('date display helpers use unambiguous English textual formats', () {
    final date = DateTime(2026, 7, 22);

    expect(formatFullDate(date), '22 July 2026');
    expect(formatCompactDate(date), '22 Jul');
    expect(formatCompactDateWithYear(date), '22 Jul 2026');
    expect(formatMonthYear(date), 'July 2026');
    expect(formatWeekdayDate(date), 'Wednesday, 22 July');
  });

  test('date display helpers handle leap days and year transitions', () {
    expect(formatFullDate(DateTime(2024, 2, 29)), '29 February 2024');
    expect(
      formatFullDateRange(DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
      '31 December 2026 – 1 January 2027',
    );
  });
}
