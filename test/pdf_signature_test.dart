import 'dart:convert';
import 'dart:io';

import 'package:briska/src/pdf_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'advanced_export_service_test.dart' show pdfText;
import 'pdf_reporting_hours_test.dart' show recorded;

void main() {
  final logo = File('assets/branding/briska-bp-in-app.png').readAsBytesSync();
  final regular = File('assets/fonts/Poppins-Regular.ttf').readAsBytesSync();
  final bold = File('assets/fonts/Poppins-SemiBold.ttf').readAsBytesSync();

  for (final summary in [false, true]) {
    for (final count in [1, 90]) {
      test(
        '${summary ? 'Summary' : 'Timesheet'} signatures with $count entries',
        () async {
          final entries = List.generate(count, (_) => recorded('WorkDay', 8));
          final build = summary
              ? PdfExportService.buildSummaryPdf
              : PdfExportService.buildTimesheetPdf;
          final defaultBytes = await build(
            entries,
            fullName: 'Employee',
            companyName: 'Employer',
            periodLabel: 'July 2026',
            generatedAt: DateTime(2026, 7, 31),
            logoBytes: logo,
            regularFontBytes: regular,
            boldFontBytes: bold,
          );
          for (final enabled in [false, true]) {
            final bytes = await build(
              entries,
              fullName: 'Employee',
              companyName: 'Employer',
              periodLabel: 'July 2026',
              generatedAt: DateTime(2026, 7, 31),
              logoBytes: logo,
              regularFontBytes: regular,
              boldFontBytes: bold,
              includeSignatureLine: enabled,
            );
            final raw = latin1.decode(bytes);
            final text = pdfText(bytes);
            expect(raw, startsWith('%PDF-'));
            expect(raw.trimRight(), endsWith('%%EOF'));
            final pages = RegExp(r'/Type\s*/Page\b').allMatches(raw).length;
            expect(
              pages,
              summary
                  ? 1
                  : (count == 90 ? greaterThan(1) : greaterThanOrEqualTo(1)),
            );
            expect(text.contains('Employeesignature'), enabled);
            expect(text.contains('Signaturedate'), enabled);
            expect(text, contains('Netpay'));
            if (!enabled) expect(text, pdfText(defaultBytes));
            // Optional local rendering artifacts, outside the repository.
            final output = Platform.environment['BRISKA_PDF_REVIEW_DIR'];
            if (output != null) {
              File(
                '$output/${summary ? 'summary' : 'timesheet'}-$count-$enabled.pdf',
              ).writeAsBytesSync(bytes);
            }
          }
        },
      );
    }
  }
}
