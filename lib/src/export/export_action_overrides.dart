import 'dart:io';
import '../models.dart';
import '../export_formats.dart';

class ExportActionOverrides {
  const ExportActionOverrides({
    this.open,
    this.share,
    this.print,
    this.rename,
    this.deleteFile,
    this.create,
  });

  final Future<bool> Function(ExportedFileRecord record)? open;
  final Future<void> Function(ExportedFileRecord record)? share;
  final Future<void> Function(ExportedFileRecord record)? print;
  final Future<void> Function(File source, String targetPath)? rename;
  final Future<void> Function(File file)? deleteFile;
  final Future<ExportFileResult> Function(
    List<WorkEntry> entries,
    AppSettings settings,
    ExportFormat format,
  )?
  create;
}
