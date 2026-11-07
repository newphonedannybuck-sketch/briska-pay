import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'csv_export_service.dart';
import 'currency.dart';
import 'display_format.dart';
import 'export_formats.dart';
import 'models.dart';
import 'work_calculator.dart';

const _briskaGreen = PdfColor.fromInt(0xFF1B8F5A);
const _briskaBrightGreen = PdfColor.fromInt(0xFF2E9D69);
const _softGreen = PdfColor.fromInt(0xFFEAF7EF);
const _rowGrey = PdfColor.fromInt(0xFFF6F8F7);
const _textDark = PdfColor.fromInt(0xFF1E2A24);

class ExportTotals {
  const ExportTotals({
    required this.workDays,
    required this.holidayDays,
    required this.unpaidDays,
    required this.paidSickDays,
    required this.unpaidSickDays,
    required this.bankHolidayDays,
    required this.paidBankHolidayDays,
    required this.unpaidBankHolidayDays,
    required this.hoursWorked,
    required this.averageHours,
    this.holidayHours = 0,
    this.bankHolidayHours = 0,
    this.totalRecordedHours = 0,
    required this.primaryPay,
    required this.secondaryPay,
    required this.allowances,
    required this.uplifts,
    required this.grossTotal,
    required this.deductions,
    required this.netTotal,
  });

  final int workDays;
  final int holidayDays;
  final int unpaidDays;
  final int paidSickDays;
  final int unpaidSickDays;
  final int bankHolidayDays;
  final int paidBankHolidayDays;
  final int unpaidBankHolidayDays;
  final double hoursWorked;
  final double averageHours;
  final double holidayHours;
  final double bankHolidayHours;
  final double totalRecordedHours;
  final double primaryPay;
  final double secondaryPay;
  double get homePay => primaryPay;
  double get awayPay => secondaryPay;
  final double allowances;
  final double uplifts;
  final double grossTotal;
  final double deductions;
  final double netTotal;
}

abstract final class PdfExportService {
  static Future<ExportFileResult> exportTimesheet(
    List<WorkEntry> entries, {
    required String fullName,
    required String companyName,
    required String periodLabel,
    required DateTime generatedAt,
    required Uint8List logoBytes,
    required Uint8List regularFontBytes,
    required Uint8List boldFontBytes,
    String? fileNameLabel,
    CurrencyConfig currency = defaultCurrency,
    String primaryRateLabel = 'Home',
    String secondaryRateLabel = 'Away',
  }) async {
    final bytes = await buildTimesheetPdf(
      entries,
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      generatedAt: generatedAt,
      logoBytes: logoBytes,
      regularFontBytes: regularFontBytes,
      boldFontBytes: boldFontBytes,
      currency: currency,
      primaryRateLabel: primaryRateLabel,
      secondaryRateLabel: secondaryRateLabel,
    );
    final file = await ExportFileNamer.createExportFile(
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      format: ExportFormat.pdfTimesheet,
      fileNameLabel: fileNameLabel,
    );
    await file.writeAsBytes(bytes, flush: true);
    return ExportFileResult(
      fileName: file.uri.pathSegments.last,
      filePath: file.path,
      fileSize: bytes.length,
    );
  }

  static Future<ExportFileResult> exportSummary(
    List<WorkEntry> entries, {
    required String fullName,
    required String companyName,
    required String periodLabel,
    required DateTime generatedAt,
    required Uint8List logoBytes,
    required Uint8List regularFontBytes,
    required Uint8List boldFontBytes,
    String? fileNameLabel,
    CurrencyConfig currency = defaultCurrency,
    String primaryRateLabel = 'Home',
    String secondaryRateLabel = 'Away',
  }) async {
    final bytes = await buildSummaryPdf(
      entries,
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      generatedAt: generatedAt,
      logoBytes: logoBytes,
      regularFontBytes: regularFontBytes,
      boldFontBytes: boldFontBytes,
      currency: currency,
      primaryRateLabel: primaryRateLabel,
      secondaryRateLabel: secondaryRateLabel,
    );
    final file = await ExportFileNamer.createExportFile(
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      format: ExportFormat.pdfSummary,
      fileNameLabel: fileNameLabel,
    );
    await file.writeAsBytes(bytes, flush: true);
    return ExportFileResult(
      fileName: file.uri.pathSegments.last,
      filePath: file.path,
      fileSize: bytes.length,
    );
  }

  static Future<Uint8List> buildTimesheetPdf(
    List<WorkEntry> source, {
    required String fullName,
    required String companyName,
    required String periodLabel,
    required DateTime generatedAt,
    required Uint8List logoBytes,
    required Uint8List regularFontBytes,
    required Uint8List boldFontBytes,
    CurrencyConfig currency = defaultCurrency,
    String primaryRateLabel = 'Home',
    String secondaryRateLabel = 'Away',
  }) {
    CurrencyFormatter.current = currency;
    final summary = WorkCalculator.summarize(source);
    final totals = calculateTotals(summary.entries);
    final logo = pw.MemoryImage(logoBytes);
    final document = pw.Document(
      title: 'Briska Pay Timesheet',
      author: 'Berkzerker',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        theme: _theme(
          regularFontBytes: regularFontBytes,
          boldFontBytes: boldFontBytes,
        ),
        header: (context) => _timesheetHeader(
          logo: logo,
          fullName: fullName,
          companyName: companyName,
          periodLabel: periodLabel,
          generatedAt: generatedAt,
        ),
        footer: _pageFooter,
        build: (context) => [
          pw.SizedBox(height: 14),
          _dailyTable(summary.entries),
          pw.SizedBox(height: 16),
          _totalsGrid([
            _totalItem('Days recorded', totals.workDays.toString()),
            _totalItem('Holiday Days', totals.holidayDays.toString()),
            _totalItem('Unpaid days off', totals.unpaidDays.toString()),
            _totalItem('Paid Sick Days', totals.paidSickDays.toString()),
            _totalItem('Unpaid Sick Days', totals.unpaidSickDays.toString()),
            _totalItem('Bank Holidays', totals.bankHolidayDays.toString()),
            _totalItem(
              'Paid Bank Holidays',
              totals.paidBankHolidayDays.toString(),
            ),
            _totalItem(
              'Unpaid Bank Holidays',
              totals.unpaidBankHolidayDays.toString(),
            ),
            _totalItem('Hours Worked', formatHoursLabel(totals.hoursWorked)),
            _totalItem(
              'Average Hours Worked',
              formatHoursLabel(totals.averageHours),
            ),
            _totalItem('Holiday Hours', formatHoursLabel(totals.holidayHours)),
            _totalItem(
              'Bank Holiday Hours',
              formatHoursLabel(totals.bankHolidayHours),
            ),
            _totalItem(
              'Total Recorded Hours',
              formatHoursLabel(totals.totalRecordedHours),
            ),
            _totalItem('$primaryRateLabel Pay', _money(totals.primaryPay)),
            _totalItem('$secondaryRateLabel Pay', _money(totals.secondaryPay)),
            _totalItem('Allowances', _money(totals.allowances)),
            _totalItem('Uplifts', _money(totals.uplifts)),
            _totalItem('Gross pay', _money(totals.grossTotal)),
            _totalItem('Deductions', _money(totals.deductions)),
            _totalItem('Net pay', _money(totals.netTotal)),
          ]),
        ],
      ),
    );
    return document.save();
  }

  static Future<Uint8List> buildSummaryPdf(
    List<WorkEntry> source, {
    required String fullName,
    required String companyName,
    required String periodLabel,
    required DateTime generatedAt,
    required Uint8List logoBytes,
    required Uint8List regularFontBytes,
    required Uint8List boldFontBytes,
    CurrencyConfig currency = defaultCurrency,
    String primaryRateLabel = 'Home',
    String secondaryRateLabel = 'Away',
  }) {
    CurrencyFormatter.current = currency;
    final summary = WorkCalculator.summarize(source);
    final totals = calculateTotals(summary.entries);
    final logo = pw.MemoryImage(logoBytes);
    final document = pw.Document(
      title: 'Briska Pay Summary',
      author: 'Berkzerker',
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        theme: _theme(
          regularFontBytes: regularFontBytes,
          boldFontBytes: boldFontBytes,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _summaryHeader(
              logo: logo,
              fullName: fullName,
              companyName: companyName,
              periodLabel: periodLabel,
              generatedAt: generatedAt,
            ),
            pw.SizedBox(height: 26),
            _summaryMetric('Pay period', periodLabel, wide: true),
            pw.SizedBox(height: 14),
            pw.Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _summaryMetric('Days recorded', totals.workDays.toString()),
                _summaryMetric('Holiday Days', totals.holidayDays.toString()),
                _summaryMetric('Unpaid days off', totals.unpaidDays.toString()),
                _summaryMetric(
                  'Paid Sick Days',
                  totals.paidSickDays.toString(),
                ),
                _summaryMetric(
                  'Unpaid Sick Days',
                  totals.unpaidSickDays.toString(),
                ),
                _summaryMetric(
                  'Bank Holidays',
                  totals.bankHolidayDays.toString(),
                ),
                _summaryMetric(
                  'Paid Bank Holidays',
                  totals.paidBankHolidayDays.toString(),
                ),
                _summaryMetric(
                  'Unpaid Bank Holidays',
                  totals.unpaidBankHolidayDays.toString(),
                ),
                _summaryMetric(
                  'Hours Worked',
                  formatHoursLabel(totals.hoursWorked),
                ),
                _summaryMetric(
                  'Average Hours Worked',
                  formatHoursLabel(totals.averageHours),
                ),
                _summaryMetric(
                  'Holiday Hours',
                  formatHoursLabel(totals.holidayHours),
                ),
                _summaryMetric(
                  'Bank Holiday Hours',
                  formatHoursLabel(totals.bankHolidayHours),
                ),
                _summaryMetric(
                  'Total Recorded Hours',
                  formatHoursLabel(totals.totalRecordedHours),
                ),
                _summaryMetric(
                  '$primaryRateLabel Pay',
                  _money(totals.primaryPay),
                ),
                _summaryMetric(
                  '$secondaryRateLabel Pay',
                  _money(totals.secondaryPay),
                ),
                _summaryMetric('Allowances', _money(totals.allowances)),
                _summaryMetric('Uplifts', _money(totals.uplifts)),
                _summaryMetric('Deductions', _money(totals.deductions)),
              ],
            ),
            pw.Spacer(),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                color: _briskaGreen,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Net pay',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    _money(totals.netTotal),
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  static ExportTotals calculateTotals(List<WorkEntry> entries) {
    final workEntries = entries.where((entry) => entry.entryType == 'WorkDay');
    final workDays = workEntries.length;
    final hoursWorked = workEntries.fold(
      0.0,
      (sum, entry) => sum + entry.totalHours,
    );
    final primaryPay = entries
        .where((entry) => entry.rateType == 'primary')
        .fold(0.0, (sum, entry) => sum + entry.wages);
    final secondaryPay = entries
        .where((entry) => entry.rateType == 'secondary')
        .fold(0.0, (sum, entry) => sum + entry.wages);
    return ExportTotals(
      workDays: workDays,
      holidayDays: entries
          .where((entry) => entry.entryType == 'Holiday')
          .length,
      unpaidDays: entries
          .where((entry) => entry.entryType == 'UnpaidDayOff')
          .length,
      paidSickDays: entries
          .where((entry) => entry.entryType == 'SickDay' && entry.isPaidSickDay)
          .length,
      unpaidSickDays: entries
          .where(
            (entry) => entry.entryType == 'SickDay' && !entry.isPaidSickDay,
          )
          .length,
      bankHolidayDays: entries
          .where((entry) => entry.type == EntryType.bankHoliday)
          .length,
      paidBankHolidayDays: entries
          .where(
            (entry) =>
                entry.type == EntryType.bankHoliday && entry.isPaidBankHoliday,
          )
          .length,
      unpaidBankHolidayDays: entries
          .where(
            (entry) =>
                entry.type == EntryType.bankHoliday && !entry.isPaidBankHoliday,
          )
          .length,
      holidayHours: entries
          .where((entry) => entry.entryType == 'Holiday')
          .fold(0.0, (sum, entry) => sum + entry.totalHours),
      bankHolidayHours: entries
          .where((entry) => entry.type == EntryType.bankHoliday)
          .fold(0.0, (sum, entry) => sum + entry.totalHours),
      totalRecordedHours: entries.fold(
        0.0,
        (sum, entry) => sum + entry.totalHours,
      ),
      hoursWorked: hoursWorked,
      averageHours: workDays == 0 ? 0 : hoursWorked / workDays,
      primaryPay: primaryPay,
      secondaryPay: secondaryPay,
      allowances: entries.fold(0.0, (sum, entry) => sum + entry.dailyAllowance),
      uplifts: entries.fold(0.0, (sum, entry) => sum + entry.jobUplift),
      grossTotal: entries.fold(0.0, (sum, entry) => sum + entry.totalPay),
      deductions: entries.fold(
        0.0,
        (sum, entry) => sum + entry.deductionAmount,
      ),
      netTotal: entries.fold(0.0, (sum, entry) => sum + entry.netPay),
    );
  }

  static pw.ThemeData _theme({
    required Uint8List regularFontBytes,
    required Uint8List boldFontBytes,
  }) => pw.ThemeData.withFont(
    base: pw.Font.ttf(ByteData.sublistView(regularFontBytes)),
    bold: pw.Font.ttf(ByteData.sublistView(boldFontBytes)),
  );

  static pw.Widget _timesheetHeader({
    required pw.ImageProvider logo,
    required String fullName,
    required String companyName,
    required String periodLabel,
    required DateTime generatedAt,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _briskaGreen,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _logoBox(logo),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Briska Pay',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Work. Track. Get Paid.',
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (fullName.trim().isNotEmpty)
                _headerDetail('User Name', fullName.trim()),
              if (companyName.trim().isNotEmpty)
                _headerDetail('Employer / company', companyName.trim()),
              _headerDetail('Pay period', periodLabel),
              _headerDetail('Generated Date', _dateLabel(generatedAt)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryHeader({
    required pw.ImageProvider logo,
    required String fullName,
    required String companyName,
    required String periodLabel,
    required DateTime generatedAt,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: _briskaGreen,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Row(
        children: [
          _logoBox(logo, size: 54),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Briska Pay Summary',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (fullName.trim().isNotEmpty || companyName.trim().isNotEmpty)
                  pw.Text(
                    [
                      if (fullName.trim().isNotEmpty) fullName.trim(),
                      if (companyName.trim().isNotEmpty) companyName.trim(),
                    ].join(' - '),
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 11,
                    ),
                  ),
                pw.Text(
                  'Generated ${_dateLabel(generatedAt)}',
                  style: const pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _dailyTable(List<WorkEntry> entries) {
    final headers = [
      'Date',
      'Site',
      'Type',
      'BH',
      'Hours',
      'Rate',
      'Allowance',
      'Uplift',
      'Gross',
      'Deduction',
      'Net',
    ];
    final data = entries
        .map(
          (entry) => [
            _dateLabel(entry.date),
            entry.siteName.isEmpty ? '-' : entry.siteName,
            CsvExportService.entryTypeLabel(
              entry.entryType,
              isPaidSickDay: entry.isPaidSickDay,
            ),
            entry.type == EntryType.bankHoliday
                ? (entry.isPaidBankHoliday ? 'Paid' : 'Unpaid')
                : '',
            formatHoursLabel(entry.totalHours),
            _money(entry.hourlyRateUsed),
            _money(entry.dailyAllowance),
            _money(entry.jobUplift),
            _money(entry.totalPay),
            _money(entry.deductionAmount),
            _money(entry.netPay),
          ],
        )
        .toList();
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: null,
      headerDecoration: const pw.BoxDecoration(color: _briskaGreen),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(color: _textDark, fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      rowDecoration: const pw.BoxDecoration(color: _rowGrey),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      columnWidths: {
        0: const pw.FixedColumnWidth(58),
        1: const pw.FlexColumnWidth(2.2),
        2: const pw.FixedColumnWidth(70),
        3: const pw.FixedColumnWidth(48),
        4: const pw.FixedColumnWidth(58),
        5: const pw.FixedColumnWidth(64),
        6: const pw.FixedColumnWidth(58),
        7: const pw.FixedColumnWidth(70),
      },
    );
  }

  static pw.Widget _totalsGrid(List<pw.Widget> items) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _softGreen,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Wrap(spacing: 8, runSpacing: 8, children: items),
    );
  }

  static pw.Widget _totalItem(String label, String value) {
    return pw.Container(
      width: 118,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 7),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: _textDark,
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryMetric(
    String label,
    String value, {
    bool wide = false,
  }) {
    return pw.Container(
      width: wide ? double.infinity : 160,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: pw.BoxDecoration(
        color: label == 'Pay period' ? _softGreen : _rowGrey,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: _textDark,
              fontSize: wide ? 16 : 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _logoBox(pw.ImageProvider logo, {double size = 48}) {
    return pw.Container(
      width: size,
      height: size,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Image(logo, fit: pw.BoxFit.contain),
    );
  }

  static pw.Widget _headerDetail(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          text: '$label: ',
          style: pw.TextStyle(
            color: _briskaBrightGreen,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          children: [
            pw.TextSpan(
              text: value,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pageFooter(pw.Context context) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Briska Pay · Developed by Berkzerker · Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 8),
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  static String _money(double value) => CurrencyFormatter.format(value);
}
