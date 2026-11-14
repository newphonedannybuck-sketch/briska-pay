import 'package:flutter/material.dart';
import '../../models.dart';
import '../../export_formats.dart';
import '../../widgets/shared_ui.dart';
import '../../export/export_actions.dart';
import '../../export/export_action_overrides.dart';
import 'export_library_widgets.dart';

class ExportLibraryScreen extends StatefulWidget {
  const ExportLibraryScreen({
    required this.records,
    required this.onUpdate,
    required this.onDelete,
    this.actionOverrides,
    this.isActive = true,
    this.canPresent,
    super.key,
  });
  final List<ExportedFileRecord> records;
  final Future<bool> Function(ExportedFileRecord) onUpdate;
  final Future<bool> Function(ExportedFileRecord) onDelete;
  final ExportActionOverrides? actionOverrides;
  final bool isActive;
  final bool Function()? canPresent;

  @override
  State<ExportLibraryScreen> createState() => _ExportLibraryScreenState();
}

class _ExportLibraryScreenState extends State<ExportLibraryScreen> {
  String _librarySort = 'Newest';
  String _libraryFilter = 'All';
  String? _pendingMessage;
  bool get _canPresent =>
      mounted &&
      widget.isActive &&
      widget.canPresent?.call() != false &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void didUpdateWidget(covariant ExportLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_canPresent) return;
        final message = _pendingMessage;
        _pendingMessage = null;
        if (message != null) _message(context, message);
      });
    }
  }

  late final ExportActions _actions = ExportActions(
    isMounted: () => mounted,
    canPresent: () => _canPresent,
    currentUpdate: () => widget.onUpdate,
    currentDelete: () => widget.onDelete,
    currentOverrides: () => widget.actionOverrides,
    showMessage: _message,
    refresh: () {
      if (mounted) setState(() {});
    },
  );

  void _message(BuildContext context, String message) {
    if (!context.mounted) return;
    if (!_canPresent) {
      _pendingMessage = message;
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Export Library')),
    body: AppPage(
      topPadding: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButton<String>(
                value: _librarySort,
                items: const ['Newest', 'Oldest', 'Filename']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _librarySort = value!),
              ),
              ...['All', 'PDF', 'Excel', 'CSV'].map(
                (value) => FilterChip(
                  label: Text(value),
                  selected: _libraryFilter == value,
                  onSelected: (_) => setState(() => _libraryFilter = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_filteredLibraryRecords.isEmpty)
            const CompactEmptyExportLibrary()
          else
            ..._filteredLibraryRecords.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ExportedFileCard(
                  record: record,
                  onOpen: () => _actions.run(
                    record,
                    () => _actions.open(context, record),
                  ),
                  onShare: () => _actions.run(
                    record,
                    () => _actions.share(context, record),
                  ),
                  onPrint:
                      ExportFormat.fromFileType(record.fileType) ==
                              ExportFormat.pdfTimesheet ||
                          ExportFormat.fromFileType(record.fileType) ==
                              ExportFormat.pdfSummary
                      ? () => _actions.run(
                          record,
                          () => _actions.print(context, record),
                        )
                      : null,
                  onRename: () => _actions.run(
                    record,
                    () => _actions.rename(context, record),
                  ),
                  onFavourite: () => _actions.run(
                    record,
                    () => _actions.favourite(context, record),
                  ),
                  onDelete: () => _actions.run(
                    record,
                    () => _actions.confirmDelete(context, record),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  List<ExportedFileRecord> get _filteredLibraryRecords {
    final records = widget.records.where((record) {
      if (_libraryFilter == 'All') return true;
      return ExportFormat.fromFileType(
        record.fileType,
      ).fileType.toLowerCase().contains(_libraryFilter.toLowerCase());
    }).toList();
    switch (_librarySort) {
      case 'Oldest':
        records.sort((a, b) => a.exportedAt.compareTo(b.exportedAt));
      case 'Filename':
        records.sort(
          (a, b) =>
              a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
        );
      default:
        records.sort((a, b) => b.exportedAt.compareTo(a.exportedAt));
    }
    return records;
  }
}
