import '../export/export_action_overrides.dart';
import '../export/export_actions.dart';
import '../export/export_generation_service.dart';
import 'export/export_library_screen.dart';
import 'export/export_library_widgets.dart';

import '../pay_schedule.dart';
import '../../design_system/briska_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../design_system/briska_cards.dart';
import '../../features/export/models/export_config.dart';
import '../../features/export/services/export_filename_service.dart';
import '../app/briska_page_route.dart';
import '../models.dart';
import '../export_formats.dart';
import '../export/export_feedback.dart';
import '../work_calculator.dart';
import '../presentation_format.dart';
import '../display_format.dart';
import '../widgets/shared_ui.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    required this.entries,
    required this.fullName,
    required this.companyName,
    required this.settings,
    required this.records,
    required this.onPreferencesChanged,
    required this.onAdd,
    required this.onDelete,
    required this.onUpdate,
    this.libraryOnly = false,
    this.actionOverrides,
    this.isActive = true,
    this.canPresent,
    super.key,
  });

  final List<WorkEntry> entries;
  final String fullName;
  final String companyName;
  final AppSettings settings;
  final List<ExportedFileRecord> records;
  final ValueChanged<AppSettings> onPreferencesChanged;
  final Future<bool> Function(ExportedFileRecord) onAdd;
  final Future<bool> Function(ExportedFileRecord) onDelete;
  final Future<bool> Function(ExportedFileRecord) onUpdate;
  final bool libraryOnly;
  final ExportActionOverrides? actionOverrides;
  final bool isActive;
  final bool Function()? canPresent;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
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

  ExportedFileRecord? _pendingCompletion;
  String? _pendingMessage;

  bool get _canPresent =>
      mounted &&
      widget.isActive &&
      widget.canPresent?.call() != false &&
      ModalRoute.of(context)?.isCurrent != false;

  void _presentPending() {
    if (!_canPresent) return;
    final message = _pendingMessage;
    _pendingMessage = null;
    if (message != null) _message(context, message);
    final record = _pendingCompletion;
    _pendingCompletion = null;
    if (record != null) _showExportCompleteActions(context, record);
  }

  late final ValueNotifier<List<ExportedFileRecord>> _libraryRecords;
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

  bool _isExporting = false;
  bool _showMoreOptions = false;
  ExportDateRangeType _rangeType = ExportDateRangeType.currentMonth;
  ExportReportType _reportType = ExportReportType.timesheet;
  ExportFileFormat _fileFormat = ExportFileFormat.pdf;
  late ExportOptions _options;
  DateTime? _customStart;
  DateTime? _customEnd;
  late final TextEditingController _fileNameController;
  bool _fileNameEdited = false;

  @override
  void initState() {
    super.initState();
    _libraryRecords = ValueNotifier(widget.records);
    _rangeType = _defaultRangeType(widget.settings);
    _options = ExportOptions(includeCompanyName: widget.companyName.isNotEmpty);
    _fileNameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetFilename());
  }

  @override
  void didUpdateWidget(covariant ExportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _presentPending());
    }
    // The library route is a sibling of this screen, so notify after this build.
    if (oldWidget.records != widget.records) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _libraryRecords.value = widget.records;
      });
    }
    if (oldWidget.settings.payFrequency != widget.settings.payFrequency ||
        oldWidget.settings.payPeriodAnchorDate !=
            widget.settings.payPeriodAnchorDate ||
        oldWidget.settings.customPeriodStartDay !=
            widget.settings.customPeriodStartDay) {
      final available = _availableRangeTypes(widget.settings);
      if (!available.contains(_rangeType)) {
        _rangeType = _defaultRangeType(widget.settings);
      }
      _updateSuggestedFilename();
    }
    if (oldWidget.fullName != widget.fullName && !_fileNameEdited) {
      _updateSuggestedFilename();
    }
  }

  static ExportDateRangeType _defaultRangeType(AppSettings settings) {
    return normalisePayFrequency(settings.payFrequency) ==
            calendarMonthlyPayFrequency
        ? ExportDateRangeType.currentMonth
        : ExportDateRangeType.currentPayPeriod;
  }

  static List<ExportDateRangeType> _availableRangeTypes(AppSettings settings) {
    final frequency = normalisePayFrequency(settings.payFrequency);
    if (frequency == calendarMonthlyPayFrequency) {
      return const [
        ExportDateRangeType.currentMonth,
        ExportDateRangeType.previousMonth,
        ExportDateRangeType.custom,
      ];
    }
    return const [
      ExportDateRangeType.currentPayPeriod,
      ExportDateRangeType.previousPayPeriod,
      ExportDateRangeType.currentMonth,
      ExportDateRangeType.custom,
    ];
  }

  String _rangeLabel(ExportDateRangeType value) {
    final frequency = normalisePayFrequency(widget.settings.payFrequency);
    return switch (value) {
      ExportDateRangeType.currentPayPeriod =>
        frequency == weeklyPayFrequency ? 'This pay week' : 'This pay period',
      ExportDateRangeType.previousPayPeriod =>
        frequency == weeklyPayFrequency ? 'Last pay week' : 'Last pay period',
      ExportDateRangeType.currentMonth => 'This month',
      ExportDateRangeType.previousMonth => 'Last month',
      ExportDateRangeType.custom => 'Custom dates',
      _ => value.label,
    };
  }

  @override
  void dispose() {
    _libraryRecords.dispose();
    _fileNameController.dispose();
    super.dispose();
  }

  ExportDateRange? get _range => ExportRangeResolver.resolve(
    type: _rangeType,
    now: DateTime.now(),
    settings: widget.settings,
    entries: widget.entries,
    customStart: _customStart,
    customEnd: _customEnd,
  );

  List<WorkEntry> get _selectedEntries {
    final range = _range;
    if (range == null || !range.isValid) return const [];
    return widget.entries.where((entry) => range.contains(entry.date)).toList();
  }

  String get _rangeError {
    if (_rangeType == ExportDateRangeType.custom &&
        (_customStart == null || _customEnd == null)) {
      return 'Choose both a From date and a To date.';
    }
    if (_range?.isValid == false) {
      return 'From date cannot be after To date.';
    }
    return '';
  }

  String get _fileNameError {
    final sanitized = ExportFilenameService.sanitize(
      _fileNameController.text,
      _fileFormat,
    );
    return sanitized.isEmpty ? 'Enter a valid file name.' : '';
  }

  bool get _canExport =>
      !_isExporting &&
      widget.entries.isNotEmpty &&
      _rangeError.isEmpty &&
      _selectedEntries.isNotEmpty &&
      _fileNameError.isEmpty &&
      (!_options.includeEmployeeName || widget.fullName.trim().isNotEmpty) &&
      (!_options.includeCompanyName || widget.companyName.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (widget.libraryOnly) {
      return ExportLibraryScreen(
        records: widget.records,
        onUpdate: widget.onUpdate,
        onDelete: widget.onDelete,
        actionOverrides: widget.actionOverrides,
        isActive: widget.isActive,
        canPresent: widget.canPresent,
      );
    }
    final range = _range;
    final periodLabel = range == null
        ? 'No date range'
        : formatFullDateRange(range.start, range.end);
    final exportEntries = _selectedEntries;
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Export',
            subtitle: 'Create a professional report from your work records.',
          ),
          const SizedBox(height: BriskaSpacing.md),
          BriskaCard(
            padding: const EdgeInsets.symmetric(
              horizontal: BriskaSpacing.md,
              vertical: BriskaSpacing.sm,
            ),
            onTap: () => _openExportLibrary(context),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: BriskaSpacing.sm),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export Library',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text('Open, share or print saved exports'),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: BriskaSpacing.md),
          _ExportSection(
            number: 1,
            title: 'Date range',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChoiceWrap<ExportDateRangeType>(
                  values: _availableRangeTypes(widget.settings),
                  selected: _rangeType,
                  label: _rangeLabel,
                  onSelected: (value) {
                    setState(() => _rangeType = value);
                    _updateSuggestedFilename();
                  },
                ),
                if (_rangeType == ExportDateRangeType.custom) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickCustomDate(true),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _customStart == null
                                ? 'From date'
                                : 'From date\n${formatFullDate(_customStart!)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickCustomDate(false),
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            _customEnd == null
                                ? 'To date'
                                : 'To date\n${formatFullDate(_customEnd!)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (range != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    periodLabel,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (_rangeError.isNotEmpty)
                  Text(
                    _rangeError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          _ExportSection(
            number: 2,
            title: 'Report type',
            child: _ChoiceWrap<ExportReportType>(
              values: const [
                ExportReportType.timesheet,
                ExportReportType.paySummary,
              ],
              selected: _reportType,
              label: (value) => value.label,
              onSelected: (value) {
                setState(() => _reportType = value);
                _updateSuggestedFilename();
              },
            ),
          ),
          _ExportSection(
            number: 3,
            title: 'File format',
            child: _ChoiceWrap<ExportFileFormat>(
              values: const [ExportFileFormat.pdf, ExportFileFormat.xlsx],
              selected: _fileFormat,
              label: (value) => value.label,
              onSelected: (value) {
                setState(() => _fileFormat = value);
                _updateSuggestedFilename();
              },
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _showMoreOptions = !_showMoreOptions),
              icon: Icon(
                _showMoreOptions
                    ? Icons.expand_less_rounded
                    : Icons.tune_rounded,
              ),
              label: Text(
                _fileFormat == ExportFileFormat.csv
                    ? 'More options · CSV selected'
                    : 'More options',
              ),
            ),
          ),
          if (_showMoreOptions)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Advanced format',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: BriskaSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ChoiceChip(
                        label: const Text('CSV (.csv)'),
                        selected: _fileFormat == ExportFileFormat.csv,
                        onSelected: (_) {
                          setState(() => _fileFormat = ExportFileFormat.csv);
                          _updateSuggestedFilename();
                        },
                      ),
                    ),
                    const Divider(height: BriskaSpacing.xl),
                    _optionSwitch(
                      'Include employer / company',
                      _options.includeCompanyName,
                      (value) => _options = _options.copyWith(
                        includeCompanyName: value,
                      ),
                    ),
                    _optionSwitch(
                      'Include employee name',
                      _options.includeEmployeeName,
                      (value) {
                        _options = _options.copyWith(
                          includeEmployeeName: value,
                        );
                        _updateSuggestedFilename();
                      },
                    ),
                    _optionSwitch(
                      'Include notes',
                      _options.includeNotes,
                      (value) =>
                          _options = _options.copyWith(includeNotes: value),
                    ),
                    _optionSwitch(
                      'Include signature line',
                      _options.includeSignatureLine,
                      (value) => _options = _options.copyWith(
                        includeSignatureLine: value,
                      ),
                      enabled: _fileFormat != ExportFileFormat.csv,
                    ),
                    if (_options.includeCompanyName &&
                        widget.companyName.trim().isEmpty)
                      const Text(
                        'Add a company name in Settings or turn this option off.',
                      ),
                    if (_options.includeEmployeeName &&
                        widget.fullName.trim().isEmpty)
                      const Text(
                        'Add an employee name in Settings or turn this option off.',
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fileNameController,
                      maxLength: 130,
                      decoration: InputDecoration(
                        labelText: 'Edit filename',
                        errorText: _fileNameError.isEmpty
                            ? null
                            : _fileNameError,
                      ),
                      onChanged: (_) => setState(() => _fileNameEdited = true),
                    ),
                    TextButton(
                      onPressed: _resetFilename,
                      child: const Text('Reset filename'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: BriskaPrimaryButton(
              icon: Icons.file_download_outlined,
              label: _isExporting ? 'Creating report…' : 'Export report',
              isLoading: _isExporting,
              onPressed: !_canExport
                  ? null
                  : () => _performExport(context, exportEntries, periodLabel),
            ),
          ),
          if (widget.entries.isEmpty) const _NoWorkRecords(),
          const SizedBox(height: 26),
          const SectionHeading(title: 'Recent exports'),
          const SizedBox(height: 10),
          if (widget.records.isEmpty)
            const CompactEmptyExportLibrary()
          else ...[
            ...([...widget.records]
                  ..sort((a, b) => b.exportedAt.compareTo(a.exportedAt)))
                .take(5)
                .map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RecentExportCard(
                      record: record,
                      onOpen: () => _actions.run(
                        record,
                        () => _actions.open(context, record),
                      ),
                      onShare: () => _actions.run(
                        record,
                        () => _actions.share(context, record),
                      ),
                      onDelete: () => _actions.run(
                        record,
                        () => _actions.confirmDelete(context, record),
                      ),
                    ),
                  ),
                ),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => _openExportLibrary(context),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('View all exports'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openExportLibrary(BuildContext context) async {
    await Navigator.of(context).push(
      BriskaPageRoute(
        child: ValueListenableBuilder<List<ExportedFileRecord>>(
          valueListenable: _libraryRecords,
          builder: (context, records, _) => ExportLibraryScreen(
            records: records,
            onDelete: widget.onDelete,
            onUpdate: widget.onUpdate,
            actionOverrides: widget.actionOverrides,
            canPresent: widget.canPresent,
          ),
        ),
      ),
    );
    _presentPending();
  }

  SwitchListTile _optionSwitch(
    String title,
    bool value,
    ValueChanged<bool> update, {
    bool enabled = true,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: !enabled ? const Text('Available for PDF and Excel only') : null,
    value: enabled && value,
    onChanged: !enabled ? null : (next) => setState(() => update(next)),
  );

  void _resetFilename() {
    final range = _range;
    if (!mounted || range == null) return;
    setState(() {
      _fileNameEdited = false;
      _fileNameController.text = _suggestedFilename(range, DateTime.now());
    });
  }

  String _suggestedFilename(ExportDateRange range, DateTime createdAt) =>
      ExportFilenameService.suggested(
        employeeFullName: _options.includeEmployeeName ? widget.fullName : '',
        rangeType: _rangeType,
        range: range,
        settings: widget.settings,
        createdAt: createdAt,
        format: _fileFormat,
      );

  void _updateSuggestedFilename() {
    if (!_fileNameEdited) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resetFilename());
    }
  }

  Future<void> _pickCustomDate(bool from) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _customStart : _customEnd) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _customStart = picked;
      } else {
        _customEnd = picked;
      }
    });
    _updateSuggestedFilename();
  }

  Future<void> _performExport(
    BuildContext context,
    List<WorkEntry> entries,
    String periodLabel,
  ) async {
    if (_isExporting || !_canPresent) return;
    final range = _range;
    if (!_fileNameEdited && range != null) {
      _fileNameController.text = _suggestedFilename(range, DateTime.now());
    }
    final sanitized = ExportFilenameService.sanitize(
      _fileNameController.text,
      _fileFormat,
    );
    setState(() => _isExporting = true);
    try {
      final format = switch (_fileFormat) {
        ExportFileFormat.xlsx => ExportFormat.excel,
        ExportFileFormat.csv => ExportFormat.csv,
        ExportFileFormat.pdf =>
          _reportType == ExportReportType.timesheet
              ? ExportFormat.pdfTimesheet
              : ExportFormat.pdfSummary,
      };
      await _export(context, entries, periodLabel, sanitized, format);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _export(
    BuildContext context,
    List<WorkEntry> exportEntries,
    String periodLabel,
    String fileNameLabel,
    ExportFormat format,
  ) async {
    final add = widget.onAdd;
    final settings = widget.settings;
    final options = _options;
    final reportType = _reportType;
    final rangeType = _rangeType;
    final range = _range;
    exportEntries = List.of(exportEntries);
    try {
      final now = DateTime.now();
      final result = await ExportGenerationService.generate(
        settings: widget.settings,
        fullName: widget.fullName,
        companyName: widget.companyName,
        actionOverrides: widget.actionOverrides,
        format: format,
        exportEntries: exportEntries,
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        generatedAt: now,
        options: options,
      );
      final summary = WorkCalculator.summarize(exportEntries);
      final record = ExportedFileRecord(
        id: now.microsecondsSinceEpoch.toString(),
        fileName: result.fileName,
        fileType: format.fileType,
        filePath: result.filePath,
        exportedAt: now,
        periodLabel: periodLabel,
        workDays: summary.totalDays,
        totalHours: summary.totalHours,
        totalPay: summary.totalExpectedPay,
        fileSize: result.fileSize,
        reportType: reportType.label,
        dateRangeType: rangeType.name,
        startDate: range?.start,
        endDate: range?.end,
        currencyCode: settings.currency.code,
        currencySymbol: settings.currency.symbol,
      );
      if (!await ExportActions.persist(add, record)) {
        if (context.mounted) {
          _message(
            context,
            'The file was created at ${record.filePath}, but could not be added to the Export Library. Keep this file or try exporting again.',
          );
        }
        return;
      }
      if (!context.mounted) return;
      _pendingCompletion = record;
      _presentPending();
    } catch (error) {
      if (!context.mounted) return;
      if (kDebugMode) debugPrint('Export failed: $error');
      _message(context, exportCreationFailureMessage(error));
    }
  }

  Future<void> _showExportCompleteActions(
    BuildContext context,
    ExportedFileRecord record,
  ) async {
    final action = await showDialog<_ExportCompleteAction>(
      context: context,
      builder: (dialogContext) => ExportCreatedDialog(
        record: record,
        onDone: () => Navigator.pop(dialogContext, _ExportCompleteAction.done),
        onShare: () =>
            Navigator.pop(dialogContext, _ExportCompleteAction.share),
        onPrint: () =>
            Navigator.pop(dialogContext, _ExportCompleteAction.print),
        onOpen: () => Navigator.pop(dialogContext, _ExportCompleteAction.open),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case _ExportCompleteAction.open:
        await _actions.open(context, record);
      case _ExportCompleteAction.share:
        await _actions.share(context, record);
      case _ExportCompleteAction.print:
        await _actions.print(context, record);
      case _ExportCompleteAction.done || null:
        break;
    }
  }
}

class _ExportSection extends StatelessWidget {
  const _ExportSection({
    required this.number,
    required this.title,
    required this.child,
  });
  final int number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: Text(
                    '$number',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: values
        .map(
          (value) => ChoiceChip(
            label: Text(label(value)),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          ),
        )
        .toList(),
  );
}

class _NoWorkRecords extends StatelessWidget {
  const _NoWorkRecords();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              Icons.work_off_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              'No days recorded to export',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text('Record a day before creating a report.'),
          ],
        ),
      ),
    ),
  );
}

enum _ExportCompleteAction { open, share, print, done }

class ExportCreatedDialog extends StatelessWidget {
  const ExportCreatedDialog({
    required this.record,
    required this.onDone,
    required this.onShare,
    required this.onPrint,
    required this.onOpen,
    super.key,
  });

  final ExportedFileRecord record;
  final VoidCallback onDone;
  final VoidCallback onShare;
  final VoidCallback onPrint;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    icon: const Icon(Icons.check_circle_outline_rounded),
    title: const Text('Export created'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(record.fileName, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Text(formatFileSize(record.fileSize)),
      ],
    ),
    actions: [
      TextButton(onPressed: onDone, child: const Text('Done')),
      TextButton(onPressed: onShare, child: const Text('Share')),
      if (ExportFormat.fromFileType(record.fileType) ==
              ExportFormat.pdfTimesheet ||
          ExportFormat.fromFileType(record.fileType) == ExportFormat.pdfSummary)
        TextButton.icon(
          onPressed: onPrint,
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print'),
        ),
      FilledButton(onPressed: onOpen, child: const Text('Open')),
    ],
  );
}
