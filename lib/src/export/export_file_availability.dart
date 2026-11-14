import 'dart:io';
import '../models/exported_file_record.dart';

/// Filesystem status is a presentation/action concern, separate from record data.
extension ExportFileAvailability on ExportedFileRecord {
  bool get isAvailable => filePath.isNotEmpty && File(filePath).existsSync();
}
