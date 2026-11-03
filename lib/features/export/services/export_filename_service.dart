import '../models/export_config.dart';
import '../../../src/models.dart';
import '../../../src/pay_schedule.dart';

abstract final class ExportFilenameService {
  static String suggested({
    required String employeeFullName,
    required ExportDateRangeType rangeType,
    required ExportDateRange range,
    required AppSettings settings,
    required DateTime createdAt,
    required ExportFileFormat format,
  }) {
    final date = resolveFilenameDate(
      rangeType: rangeType,
      range: range,
      settings: settings,
      createdAt: createdAt,
    );
    final employee = _employeeToken(employeeFullName);
    final base = '${employee}_${_date(date)}';
    return sanitize(base, format);
  }

  static DateTime resolveFilenameDate({
    required ExportDateRangeType rangeType,
    required ExportDateRange range,
    required AppSettings settings,
    required DateTime createdAt,
  }) {
    final period = getCurrentPayPeriodForSettings(
      date: range.start,
      settings: settings,
    );
    final matchesPayPeriod =
        _sameDate(period.start, range.start) &&
        _sameDate(period.end, range.end);
    if (rangeType == ExportDateRangeType.custom && !matchesPayPeriod) {
      return _dateOnly(createdAt);
    }
    return period.payday;
  }

  static String sanitize(String value, ExportFileFormat format) {
    var name = value.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '');
    name = name.replaceAll(RegExp(r'\.{2,}'), '.');
    var removedExtension = true;
    while (removedExtension) {
      removedExtension = false;
      for (final extension in ExportFileFormat.values.map((e) => e.extension)) {
        final withoutExtension = name.replaceFirst(
          RegExp('\\.$extension\$', caseSensitive: false),
          '',
        );
        if (withoutExtension != name) {
          name = withoutExtension;
          removedExtension = true;
        }
      }
    }
    name = name.trim().replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (name.length > 120) name = name.substring(0, 120).trim();
    return name.isEmpty ? '' : '$name.${format.extension}';
  }

  static String copyName(String fileName, int copyNumber) {
    final dot = fileName.lastIndexOf('.');
    final base = dot < 0 ? fileName : fileName.substring(0, dot);
    final extension = dot < 0 ? '' : fileName.substring(dot);
    return '${base}_$copyNumber$extension';
  }

  static String _date(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${date.day.toString().padLeft(2, '0')}_'
        '${months[date.month - 1]}_${date.year}';
  }

  static String _employeeToken(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final words = cleaned
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) => word.length == 1
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        );
    final token = words.join('_');
    return token.isEmpty ? 'Employee' : token;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
