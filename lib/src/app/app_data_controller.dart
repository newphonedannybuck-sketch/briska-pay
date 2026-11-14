import '../models.dart';

/// The shell's durable data snapshots and single serialized mutation boundary.
///
/// A mutation includes validation, snapshot construction, persistence and the UI
/// commit. Generation changes invalidate callbacks from replaced datasets.
/// The shell still owns Flutter notifications and security/session eligibility.
class AppDataController {
  AppDataController({
    required this.settings,
    required List<WorkEntry> entries,
    required List<ExportedFileRecord> exports,
  }) : entries = List.of(entries),
       exports = List.of(exports);

  AppSettings settings;
  List<WorkEntry> entries;
  List<ExportedFileRecord> exports;
  int generation = 0;
  int settingsSaveRevision = 0;
  Future<void> _operations = Future<void>.value();

  // Include both snapshot construction and the UI commit in the queue.
  // A failed operation must not poison the queue for the next operation.
  Future<T> mutate<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
