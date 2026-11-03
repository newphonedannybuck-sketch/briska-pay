import 'package:intl/intl.dart';

String formatFullDate(DateTime date) => DateFormat('d MMMM yyyy').format(date);

String formatCompactDate(DateTime date) => DateFormat('d MMM').format(date);

String formatCompactDateWithYear(DateTime date) =>
    DateFormat('d MMM yyyy').format(date);

String formatMonthYear(DateTime date) => DateFormat('MMMM yyyy').format(date);

String formatWeekdayDate(DateTime date) =>
    DateFormat('EEEE, d MMMM').format(date);

String formatFullDateRange(DateTime start, DateTime end) =>
    '${formatFullDate(start)} – ${formatFullDate(end)}';

String formatHours(double hours) {
  if (!hours.isFinite) return '0';
  final normalized = hours.abs() < 0.000001 ? 0.0 : hours;
  var text = normalized.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return text.isEmpty || text == '-0' ? '0' : text;
}

String formatHoursLabel(double hours) => '${formatHours(hours)}h';

const excelWholeNumberFormat = '0';
const excelFlexibleNumberFormat = '0.##';

String? normaliseTimeInput(String value) {
  var input = value.trim().replaceAll('.', ':');
  if (RegExp(r'^\d{3,4}$').hasMatch(input)) {
    input = input.padLeft(4, '0');
    input = '${input.substring(0, 2)}:${input.substring(2)}';
  }

  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return formatTime(hour: hour, minute: minute);
}

String formatTime({required int hour, required int minute}) =>
    '${hour.toString().padLeft(2, '0')}:'
    '${minute.toString().padLeft(2, '0')}';
