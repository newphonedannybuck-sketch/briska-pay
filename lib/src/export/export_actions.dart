import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models.dart';
import '../app_theme.dart';
import '../export_formats.dart';
import 'export_feedback.dart';
import 'export_action_overrides.dart';

class _ExportLibraryFailure implements Exception {
  const _ExportLibraryFailure(this.message);
  final String message;
}

/// Owns file actions; the screen owns presentation eligibility and feedback.
class ExportActions {
  ExportActions({
    required this.isMounted,
    required this.canPresent,
    required this.currentUpdate,
    required this.currentDelete,
    required this.currentOverrides,
    required this.showMessage,
    required this.refresh,
  });

  final bool Function() isMounted;
  final bool Function() canPresent;
  final Future<bool> Function(ExportedFileRecord) Function() currentUpdate;
  final Future<bool> Function(ExportedFileRecord) Function() currentDelete;
  final ExportActionOverrides? Function() currentOverrides;
  final void Function(BuildContext, String) showMessage;
  final VoidCallback refresh;

  bool get mounted => isMounted();
  bool get _canPresent => canPresent();
  void _message(BuildContext context, String message) =>
      showMessage(context, message);

  // Avoid overlapping file operations or toggles based on the same stale card.
  final Set<String> _busyRecords = {};

  Future<void> run(
    ExportedFileRecord record,
    Future<void> Function() action,
  ) async {
    if (!_busyRecords.add(record.id)) return;
    try {
      await action();
    } finally {
      _busyRecords.remove(record.id);
    }
  }

  static Future<bool> persist(
    Future<bool> Function(ExportedFileRecord) callback,
    ExportedFileRecord record,
  ) async {
    try {
      return await callback(record);
    } catch (error) {
      if (kDebugMode) debugPrint('export library persistence failed: $error');
      return false;
    }
  }

  Future<void> favourite(
    BuildContext context,
    ExportedFileRecord record,
  ) async {
    if (!await persist(
      currentUpdate(),
      record.copyWith(isFavourite: !record.isFavourite),
    )) {
      if (context.mounted) {
        _message(context, 'Could not save favourite status. Please try again.');
      }
    }
  }

  Future<void> open(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      _message(context, 'Export file not found.');
      return;
    }
    try {
      record = await _providerCompatibleRecord(record);
      if (!_canPresent) return;
      final override = currentOverrides()?.open;
      if (override != null) {
        final opened = await override(record);
        if (!context.mounted || opened) return;
        _message(
          context,
          exportFileActionFailureMessage(ExportFileAction.open),
        );
        return;
      }
      final format = ExportFormat.fromFileType(record.fileType);
      final result = await OpenFilex.open(
        record.filePath,
        type: format.mimeType,
      );
      if (!context.mounted || result.type.name == 'done') return;
      if (kDebugMode) debugPrint('open export failed: ${result.message}');
      _message(context, exportFileActionFailureMessage(ExportFileAction.open));
    } catch (error) {
      if (kDebugMode) debugPrint('open export failed: $error');
      if (error is _ExportLibraryFailure) {
        if (context.mounted) {
          _message(context, error.message);
        }
        return;
      }
      if (!context.mounted) return;
      _message(context, exportFileActionFailureMessage(ExportFileAction.open));
    }
  }

  Future<void> share(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      _message(context, 'Export file not found.');
      return;
    }
    final format = ExportFormat.fromFileType(record.fileType);
    try {
      record = await _providerCompatibleRecord(record);
      if (!_canPresent) return;
      final override = currentOverrides()?.share;
      if (override != null) {
        await override(record);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(record.filePath, mimeType: format.mimeType)],
            subject: record.fileName,
          ),
        );
      }
    } catch (error) {
      if (kDebugMode) debugPrint('share export failed: $error');
      if (error is _ExportLibraryFailure) {
        if (context.mounted) {
          _message(context, error.message);
        }
        return;
      }
      if (!context.mounted) return;
      _message(context, exportFileActionFailureMessage(ExportFileAction.share));
    }
  }

  Future<void> rename(BuildContext context, ExportedFileRecord record) async {
    final update = currentUpdate();
    final format = ExportFormat.fromFileType(record.fileType);
    final initialName = record.fileName.replaceFirst(
      RegExp('\\.${RegExp.escape(format.extension)}\$'),
      '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameExportDialog(
        initialName: initialName,
        extension: format.extension,
      ),
    );
    final safeName = name == null ? '' : ExportFileNamer.safeName(name);
    if (safeName.isEmpty) return;
    final fileName = '$safeName.${format.extension}';
    try {
      var filePath = record.filePath;
      if (record.isAvailable) {
        record = await _providerCompatibleRecord(record, onUpdate: update);
        filePath = record.filePath;
        final separator = Platform.pathSeparator;
        final parent = File(record.filePath).parent.path;
        final targetPath = '$parent$separator$fileName';
        if (targetPath != record.filePath && await File(targetPath).exists()) {
          throw FileSystemException('A file with that name already exists.');
        }
        final source = File(record.filePath);
        final override = currentOverrides()?.rename;
        if (override != null) {
          await override(source, targetPath);
          filePath = targetPath;
        } else {
          filePath = (await source.rename(targetPath)).path;
        }
      }
      if (!await persist(
        update,
        record.copyWith(fileName: fileName, filePath: filePath),
      )) {
        if (filePath != record.filePath) {
          try {
            final original = File(record.filePath);
            if (await original.exists()) {
              throw const FileSystemException(
                'Original filename is now occupied.',
              );
            }
            await File(filePath).rename(record.filePath);
          } catch (_) {
            if (mounted) refresh();
            if (context.mounted) {
              _message(
                context,
                'The file was renamed to $filePath, but the Export Library could not be updated and the original name could not be restored. Keep the renamed file; remove the old library record or export again.',
              );
            }
            return;
          }
        }
        if (context.mounted) {
          _message(
            context,
            'Could not save the new name. The original filename has been kept. Please try again.',
          );
        }
        return;
      }
      if (!context.mounted) return;
      _message(context, 'Export renamed.');
    } catch (error) {
      if (kDebugMode) debugPrint('rename export failed: $error');
      if (error is _ExportLibraryFailure) {
        if (context.mounted) {
          _message(context, error.message);
        }
        return;
      }
      if (!context.mounted) return;
      _message(
        context,
        exportFileActionFailureMessage(ExportFileAction.rename),
      );
    }
  }

  Future<void> print(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      _message(context, 'Export file not found.');
      return;
    }
    try {
      record = await _providerCompatibleRecord(record);
      if (!_canPresent) return;
      final override = currentOverrides()?.print;
      if (override != null) {
        await override(record);
      } else {
        await Printing.layoutPdf(
          name: record.fileName,
          onLayout: (_) => File(record.filePath).readAsBytes(),
        );
      }
    } catch (error) {
      if (kDebugMode) debugPrint('print export failed: $error');
      if (error is _ExportLibraryFailure) {
        if (context.mounted) {
          _message(context, error.message);
        }
        return;
      }
      if (!context.mounted) return;
      _message(context, exportFileActionFailureMessage(ExportFileAction.print));
    }
  }

  Future<ExportedFileRecord> _providerCompatibleRecord(
    ExportedFileRecord record, {
    Future<bool> Function(ExportedFileRecord)? onUpdate,
  }) async {
    final update = onUpdate ?? currentUpdate();
    final file = await ExportFileNamer.ensureProviderCompatibleFile(
      File(record.filePath),
    );
    if (file.path == record.filePath) return record;
    final updated = record.copyWith(filePath: file.path);
    if (!await persist(update, updated)) {
      throw const _ExportLibraryFailure(
        'Could not save the updated export path. The original file is still available. Please try again.',
      );
    }
    return updated;
  }

  Future<void> confirmDelete(
    BuildContext context,
    ExportedFileRecord record,
  ) async {
    final delete = currentDelete();
    final result = await showDialog<_DeleteChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('Delete export?'),
        content: const Text('Choose what you want to delete.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          if (record.isAvailable)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () =>
                  Navigator.pop(dialogContext, _DeleteChoice.fileToo),
              child: const Text('Delete file and remove from library'),
            ),
          OutlinedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _DeleteChoice.libraryOnly),
            child: const Text('Remove from library'),
          ),
        ],
      ),
    );
    if (!context.mounted || result == null) return;
    if (result == _DeleteChoice.fileToo) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(dialogContext).colorScheme.error,
          ),
          title: const Text('Delete file from device?'),
          content: const Text(
            'This will permanently delete the exported file and remove it '
            "from the Briska Pay Export Library.\n\nThis can't be undone.",
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            Semantics(
              button: true,
              label: 'Delete export file from device',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete file'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        final file = File(record.filePath);
        if (file.existsSync()) {
          final override = currentOverrides()?.deleteFile;
          if (override != null) {
            await override(file);
          } else {
            await file.delete();
          }
        }
      } catch (error) {
        if (kDebugMode) debugPrint('delete export failed: $error');
        if (!context.mounted) return;
        _message(
          context,
          exportFileActionFailureMessage(ExportFileAction.delete),
        );
        return;
      }
    }
    if (!await persist(delete, record)) {
      if (mounted) refresh();
      if (context.mounted) {
        _message(
          context,
          result == _DeleteChoice.fileToo
              ? 'The file was deleted, but its library record could not be removed. Try Remove from library again.'
              : 'Could not remove this export from the library. Please try again.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    _message(
      context,
      result == _DeleteChoice.fileToo
          ? 'Export deleted.'
          : 'Export removed from library.',
    );
  }
}

enum _DeleteChoice { libraryOnly, fileToo }

class _RenameExportDialog extends StatefulWidget {
  const _RenameExportDialog({
    required this.initialName,
    required this.extension,
  });

  final String initialName;
  final String extension;

  @override
  State<_RenameExportDialog> createState() => _RenameExportDialogState();
}

class _RenameExportDialogState extends State<_RenameExportDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename export'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'File name',
      ).copyWith(suffixText: '.${widget.extension}'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Rename'),
      ),
    ],
  );
}
