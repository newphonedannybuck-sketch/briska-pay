import 'package:flutter/services.dart';
import '../../features/export/models/export_config.dart';
import '../models.dart';
import '../export_formats.dart';
import '../csv_export_service.dart';
import '../excel_export_service.dart';
import '../pdf_export_service.dart';
import 'export_action_overrides.dart';

/// Dispatches one captured export request to the existing format renderers.
abstract final class ExportGenerationService {
  static Future<ExportFileResult> generate({
    required ExportFormat format,
    required AppSettings settings,
    required String fullName,
    required String companyName,
    ExportActionOverrides? actionOverrides,
    required List<WorkEntry> exportEntries,
    required String periodLabel,
    required String fileNameLabel,
    required DateTime generatedAt,
    required ExportOptions options,
  }) async {
    // Capture before the first await, including PDF asset loading. Retained
    // screens can receive new settings while the original file is generated.
    final create = actionOverrides?.create;
    if (create != null) return create(exportEntries, settings, format);
    return switch (format) {
      ExportFormat.excel => ExcelExportService.export(
        exportEntries,
        fullName: options.includeEmployeeName ? fullName : '',
        companyName: options.includeCompanyName ? companyName : '',
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        currency: settings.currency,
        primaryRateLabel: settings.labelForRate('primary'),
        secondaryRateLabel: settings.labelForRate('secondary'),
        includeNotes: options.includeNotes,
        includeSignatureLine: options.includeSignatureLine,
      ),
      ExportFormat.csv => CsvExportService.export(
        exportEntries,
        fullName: options.includeEmployeeName ? fullName : '',
        companyName: options.includeCompanyName ? companyName : '',
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        currency: settings.currency,
        primaryRateLabel: settings.labelForRate('primary'),
        secondaryRateLabel: settings.labelForRate('secondary'),
        includeNotes: options.includeNotes,
      ),
      ExportFormat.pdfTimesheet => PdfExportService.exportTimesheet(
        exportEntries,
        fullName: options.includeEmployeeName ? fullName : '',
        companyName: options.includeCompanyName ? companyName : '',
        periodLabel: periodLabel,
        generatedAt: generatedAt,
        logoBytes: await _loadAssetBytes(
          'assets/branding/briska-bp-in-app.png',
        ),
        regularFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-Regular.ttf',
        ),
        boldFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-SemiBold.ttf',
        ),
        fileNameLabel: fileNameLabel,
        currency: settings.currency,
        primaryRateLabel: settings.labelForRate('primary'),
        secondaryRateLabel: settings.labelForRate('secondary'),
        includeSignatureLine: options.includeSignatureLine,
      ),
      ExportFormat.pdfSummary => PdfExportService.exportSummary(
        exportEntries,
        fullName: options.includeEmployeeName ? fullName : '',
        companyName: options.includeCompanyName ? companyName : '',
        periodLabel: periodLabel,
        generatedAt: generatedAt,
        logoBytes: await _loadAssetBytes(
          'assets/branding/briska-bp-in-app.png',
        ),
        regularFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-Regular.ttf',
        ),
        boldFontBytes: await _loadAssetBytes(
          'assets/fonts/Poppins-SemiBold.ttf',
        ),
        fileNameLabel: fileNameLabel,
        currency: settings.currency,
        primaryRateLabel: settings.labelForRate('primary'),
        secondaryRateLabel: settings.labelForRate('secondary'),
        includeSignatureLine: options.includeSignatureLine,
      ),
    };
  }

  static Future<Uint8List> _loadAssetBytes(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }
}
