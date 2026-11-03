import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum ExportFormat {
  excel('Excel (.xlsx)', 'Excel', 'xlsx'),
  pdfTimesheet('PDF Timesheet', 'PDF Timesheet', 'pdf'),
  pdfSummary('PDF Summary', 'PDF Summary', 'pdf'),
  csv('CSV (.csv)', 'CSV', 'csv');

  const ExportFormat(this.label, this.fileType, this.extension);

  final String label;
  final String fileType;
  final String extension;

  String get mimeType {
    return switch (this) {
      ExportFormat.excel =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ExportFormat.pdfTimesheet || ExportFormat.pdfSummary => 'application/pdf',
      ExportFormat.csv => 'text/csv',
    };
  }

  String? get fileSuffix {
    return switch (this) {
      ExportFormat.pdfTimesheet => 'Timesheet',
      ExportFormat.pdfSummary => 'Summary',
      _ => null,
    };
  }

  static ExportFormat fromFileType(String value) {
    return switch (value) {
      'PDF Timesheet' || 'PDF' => ExportFormat.pdfTimesheet,
      'PDF Summary' => ExportFormat.pdfSummary,
      'CSV' => ExportFormat.csv,
      _ => ExportFormat.excel,
    };
  }

  static ExportFormat fromSettings(String value) {
    return switch (value) {
      'pdfTimesheet' => ExportFormat.pdfTimesheet,
      'pdfSummary' => ExportFormat.pdfSummary,
      'csv' => ExportFormat.csv,
      _ => ExportFormat.excel,
    };
  }

  String get settingsValue {
    return switch (this) {
      ExportFormat.excel => 'excel',
      ExportFormat.pdfTimesheet => 'pdfTimesheet',
      ExportFormat.pdfSummary => 'pdfSummary',
      ExportFormat.csv => 'csv',
    };
  }
}

class ExportFileResult {
  const ExportFileResult({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
  });

  final String fileName;
  final String filePath;
  final int fileSize;
}

abstract final class ExportFileNamer {
  static Future<Directory> exportsDirectory() async {
    final directory = await getApplicationSupportDirectory();
    final exportsDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}exports',
    );
    await exportsDirectory.create(recursive: true);
    return exportsDirectory;
  }

  static Future<File> ensureProviderCompatibleFile(File source) async {
    final exportsDirectory = await ExportFileNamer.exportsDirectory();
    if (isWithinDirectory(source.path, exportsDirectory.path)) return source;
    if (!isLegacyInternalExportPath(source.path)) return source;

    final target = File(
      '${exportsDirectory.path}${Platform.pathSeparator}${source.uri.pathSegments.last}',
    );
    if (await target.exists()) return target;
    return source.copy(target.path);
  }

  static bool isWithinDirectory(String filePath, String directoryPath) {
    final separator = Platform.pathSeparator;
    final normalizedFile = File(filePath).absolute.path;
    final normalizedDirectory = Directory(directoryPath).absolute.path;
    return normalizedFile.startsWith('$normalizedDirectory$separator');
  }

  static bool isLegacyInternalExportPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    return normalized.contains('/app_flutter/exports/') &&
        RegExp(r'\.(pdf|xlsx|csv)$', caseSensitive: false).hasMatch(normalized);
  }

  static Future<File> createExportFile({
    required String fullName,
    required String companyName,
    required String periodLabel,
    required ExportFormat format,
    String? fileNameLabel,
  }) async {
    final exportsDirectory = await ExportFileNamer.exportsDirectory();

    final baseName = buildBaseName(
      fullName: fullName,
      companyName: companyName,
      periodLabel: periodLabel,
      fileNameLabel: fileNameLabel,
      suffix: format.fileSuffix,
    );
    var fileName = '$baseName.${format.extension}';
    var file = File(
      '${exportsDirectory.path}${Platform.pathSeparator}$fileName',
    );
    var number = 2;
    while (await file.exists()) {
      fileName = '${baseName}_$number.${format.extension}';
      file = File('${exportsDirectory.path}${Platform.pathSeparator}$fileName');
      number++;
    }
    return file;
  }

  static String buildFileName({
    required String fullName,
    required String companyName,
    required String periodLabel,
    required ExportFormat format,
    String? fileNameLabel,
  }) {
    return '${buildBaseName(fullName: fullName, companyName: companyName, periodLabel: periodLabel, fileNameLabel: fileNameLabel, suffix: format.fileSuffix)}.${format.extension}';
  }

  static String buildBaseName({
    required String fullName,
    required String companyName,
    required String periodLabel,
    String? fileNameLabel,
    String? suffix,
  }) {
    if (fileNameLabel != null &&
        RegExp(
          r'\.(pdf|xlsx|csv)$',
          caseSensitive: false,
        ).hasMatch(fileNameLabel.trim())) {
      return safeName(
        fileNameLabel.trim().replaceFirst(
          RegExp(r'\.(pdf|xlsx|csv)$', caseSensitive: false),
          '',
        ),
      );
    }
    if (fileNameLabel != null &&
        fileNameLabel.trim().toLowerCase().startsWith('briska_')) {
      final withoutExtension = fileNameLabel.replaceFirst(
        RegExp(r'\.[A-Za-z0-9]+$'),
        '',
      );
      return safeName(withoutExtension);
    }
    final parts = [
      'Briska',
      if (companyName.trim().isNotEmpty) companyName,
      if (fullName.trim().isNotEmpty) fullName,
      fileNameLabel ?? periodLabel,
      ?suffix,
    ];
    return safeName(parts.join('_'));
  }

  static String safeName(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return safe.isEmpty ? 'Briska_Export' : safe;
  }
}
