part of '../briska_app.dart';

class ExportActionOverrides {
  const ExportActionOverrides({
    this.open,
    this.share,
    this.print,
    this.rename,
    this.deleteFile,
  });

  final Future<bool> Function(ExportedFileRecord record)? open;
  final Future<void> Function(ExportedFileRecord record)? share;
  final Future<void> Function(ExportedFileRecord record)? print;
  final Future<void> Function(File source, String targetPath)? rename;
  final Future<void> Function(File file)? deleteFile;
}

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
    super.key,
  });

  final List<WorkEntry> entries;
  final String fullName;
  final String companyName;
  final AppSettings settings;
  final List<ExportedFileRecord> records;
  final ValueChanged<AppSettings> onPreferencesChanged;
  final ValueChanged<ExportedFileRecord> onAdd;
  final ValueChanged<ExportedFileRecord> onDelete;
  final ValueChanged<ExportedFileRecord> onUpdate;
  final bool libraryOnly;
  final ExportActionOverrides? actionOverrides;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;
  bool isPreviewing = false;
  bool _showMoreOptions = false;
  String _librarySort = 'Newest';
  String _libraryFilter = 'All';
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
    _rangeType = _defaultRangeType(widget.settings);
    _options = ExportOptions(includeCompanyName: widget.companyName.isNotEmpty);
    _fileNameController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetFilename());
  }

  @override
  void didUpdateWidget(covariant ExportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    if (widget.libraryOnly) return _buildExportLibrary(context);
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
                      (value) => _options = _options.copyWith(
                        includeEmployeeName: value,
                      ),
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
            const _CompactEmptyExportLibrary()
          else ...[
            ...([...widget.records]
                  ..sort((a, b) => b.exportedAt.compareTo(a.exportedAt)))
                .take(5)
                .map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RecentExportCard(
                      record: record,
                      onOpen: () => _open(context, record),
                      onShare: () => _share(context, record),
                      onDelete: () => _confirmDelete(context, record),
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

  void _openExportLibrary(BuildContext context) {
    Navigator.of(context).push(
      _BriskaPageRoute(
        child: ExportScreen(
          entries: widget.entries,
          fullName: widget.fullName,
          companyName: widget.companyName,
          settings: widget.settings,
          records: widget.records,
          onPreferencesChanged: widget.onPreferencesChanged,
          onAdd: widget.onAdd,
          onDelete: widget.onDelete,
          onUpdate: widget.onUpdate,
          libraryOnly: true,
          actionOverrides: widget.actionOverrides,
        ),
      ),
    );
  }

  Widget _buildExportLibrary(BuildContext context) => Scaffold(
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
            const _CompactEmptyExportLibrary()
          else
            ..._filteredLibraryRecords.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExportedFileCard(
                  record: record,
                  onOpen: () => _open(context, record),
                  onShare: () => _share(context, record),
                  onPrint:
                      ExportFormat.fromFileType(record.fileType) ==
                              ExportFormat.pdfTimesheet ||
                          ExportFormat.fromFileType(record.fileType) ==
                              ExportFormat.pdfSummary
                      ? () => _print(context, record)
                      : null,
                  onRename: () => _rename(context, record),
                  onFavourite: () => widget.onUpdate(
                    record.copyWith(isFavourite: !record.isFavourite),
                  ),
                  onDelete: () => _confirmDelete(context, record),
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
        employeeFullName: widget.fullName,
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

  Future<void> showPreview(
    BuildContext context,
    List<WorkEntry> entries,
    String periodLabel,
  ) async {
    setState(() => isPreviewing = true);
    final summary = WorkCalculator.summarize(entries);
    if (mounted) setState(() => isPreviewing = false);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_fileFormat.label} Preview'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_reportType.label),
                Text(periodLabel),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Site/job')),
                      DataColumn(label: Text('Hours')),
                      DataColumn(label: Text('Gross pay')),
                    ],
                    rows: entries
                        .take(8)
                        .map(
                          (entry) => DataRow(
                            cells: [
                              DataCell(
                                Text(formatCompactDateWithYear(entry.date)),
                              ),
                              DataCell(Text(entry.siteName)),
                              DataCell(
                                Text(formatHoursLabel(entry.totalHours)),
                              ),
                              DataCell(Text(_money(entry.totalPay))),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(),
                Text('Total hours: ${formatHoursLabel(summary.totalHours)}'),
                Text('Gross pay: ${_money(summary.totalExpectedPay)}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close preview'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _performExport(context, entries, periodLabel);
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    List<WorkEntry> exportEntries,
    String periodLabel,
    String fileNameLabel,
    ExportFormat format,
  ) async {
    try {
      final now = DateTime.now();
      final result = await _runExport(
        format: format,
        exportEntries: exportEntries,
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        generatedAt: now,
      );
      if (!context.mounted) return;
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
        reportType: _reportType.label,
        dateRangeType: _rangeType.name,
        startDate: _range?.start,
        endDate: _range?.end,
        currencyCode: widget.settings.currency.code,
        currencySymbol: widget.settings.currency.symbol,
      );
      widget.onAdd(record);
      await _showExportCompleteActions(context, record);
    } catch (error) {
      if (!context.mounted) return;
      if (kDebugMode) debugPrint('Export failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exportCreationFailureMessage(error))),
      );
    }
  }

  Future<ExportFileResult> _runExport({
    required ExportFormat format,
    required List<WorkEntry> exportEntries,
    required String periodLabel,
    required String fileNameLabel,
    required DateTime generatedAt,
  }) async {
    return switch (format) {
      ExportFormat.excel => ExcelExportService.export(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
      ExportFormat.csv => CsvExportService.export(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
        periodLabel: periodLabel,
        fileNameLabel: fileNameLabel,
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
      ExportFormat.pdfTimesheet => PdfExportService.exportTimesheet(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
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
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
      ExportFormat.pdfSummary => PdfExportService.exportSummary(
        exportEntries,
        fullName: widget.fullName,
        companyName: widget.companyName,
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
        currency: widget.settings.currency,
        primaryRateLabel: widget.settings.labelForRate('primary'),
        secondaryRateLabel: widget.settings.labelForRate('secondary'),
      ),
    };
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
        await _open(context, record);
      case _ExportCompleteAction.share:
        await _share(context, record);
      case _ExportCompleteAction.print:
        await _print(context, record);
      case _ExportCompleteAction.done || null:
        break;
    }
  }

  Future<Uint8List> _loadAssetBytes(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List();
  }

  Future<void> _open(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export file not found.')));
      return;
    }
    try {
      record = await _providerCompatibleRecord(record);
      final override = widget.actionOverrides?.open;
      if (override != null) {
        final opened = await override(record);
        if (!context.mounted || opened) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exportFileActionFailureMessage(ExportFileAction.open),
            ),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.open)),
        ),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('open export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.open)),
        ),
      );
    }
  }

  Future<void> _share(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export file not found.')));
      return;
    }
    final format = ExportFormat.fromFileType(record.fileType);
    try {
      record = await _providerCompatibleRecord(record);
      final override = widget.actionOverrides?.share;
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.share)),
        ),
      );
    }
  }

  Future<void> _rename(BuildContext context, ExportedFileRecord record) async {
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
        record = await _providerCompatibleRecord(record);
        filePath = record.filePath;
        final separator = Platform.pathSeparator;
        final separatorIndex = record.filePath.lastIndexOf(separator);
        if (separatorIndex == -1) {
          throw FileSystemException('Could not find export folder.');
        }
        final parent = record.filePath.substring(0, separatorIndex);
        final targetPath = '$parent$separator$fileName';
        if (targetPath != record.filePath && await File(targetPath).exists()) {
          throw FileSystemException('A file with that name already exists.');
        }
        final source = File(record.filePath);
        final override = widget.actionOverrides?.rename;
        if (override != null) {
          await override(source, targetPath);
          filePath = targetPath;
        } else {
          filePath = (await source.rename(targetPath)).path;
        }
      }
      widget.onUpdate(record.copyWith(fileName: fileName, filePath: filePath));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export renamed.')));
    } catch (error) {
      if (kDebugMode) debugPrint('rename export failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            exportFileActionFailureMessage(ExportFileAction.rename),
          ),
        ),
      );
    }
  }

  Future<void> _print(BuildContext context, ExportedFileRecord record) async {
    if (!record.isAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Export file not found.')));
      return;
    }
    try {
      record = await _providerCompatibleRecord(record);
      final override = widget.actionOverrides?.print;
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exportFileActionFailureMessage(ExportFileAction.print)),
        ),
      );
    }
  }

  Future<ExportedFileRecord> _providerCompatibleRecord(
    ExportedFileRecord record,
  ) async {
    final file = await ExportFileNamer.ensureProviderCompatibleFile(
      File(record.filePath),
    );
    if (file.path == record.filePath) return record;
    final updated = record.copyWith(filePath: file.path);
    widget.onUpdate(updated);
    return updated;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ExportedFileRecord record,
  ) async {
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
          final override = widget.actionOverrides?.deleteFile;
          if (override != null) {
            await override(file);
          } else {
            await file.delete();
          }
        }
      } catch (error) {
        if (kDebugMode) debugPrint('delete export failed: $error');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exportFileActionFailureMessage(ExportFileAction.delete),
            ),
          ),
        );
        return;
      }
    }
    widget.onDelete(record);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == _DeleteChoice.fileToo
              ? 'Export deleted.'
              : 'Export removed from library.',
        ),
      ),
    );
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

enum _DeleteChoice { libraryOnly, fileToo }

enum _ExportCompleteAction { open, share, print, done }

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
        Text(_formatFileSize(record.fileSize)),
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

class _ExportedFileCard extends StatelessWidget {
  const _ExportedFileCard({
    required this.record,
    required this.onOpen,
    required this.onShare,
    required this.onPrint,
    required this.onRename,
    required this.onFavourite,
    required this.onDelete,
  });

  final ExportedFileRecord record;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback? onPrint;
  final VoidCallback onRename;
  final VoidCallback onFavourite;
  final VoidCallback onDelete;

  String get _date => formatCompactDateWithYear(record.exportedAt);

  String get _size {
    return _formatFileSize(record.fileSize);
  }

  ExportFormat get _format => ExportFormat.fromFileType(record.fileType);

  String get _icon {
    return switch (_format) {
      ExportFormat.excel => '📗',
      ExportFormat.pdfTimesheet => '📕',
      ExportFormat.pdfSummary => '📄',
      ExportFormat.csv => '📊',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(_icon, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_format.fileType} - $_date',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _money(
                    record.totalPay,
                    CurrencyCatalog.byCode(
                      record.currencyCode,
                    ).copyWith(symbol: record.currencySymbol),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                spacing: 18,
                runSpacing: 9,
                children: [
                  _LibraryDetail(label: 'Period', value: record.periodLabel),
                  _LibraryDetail(label: 'File type', value: _format.fileType),
                  _LibraryDetail(label: 'Created', value: _date),
                  _LibraryDetail(
                    label: record.workDays == 1
                        ? 'Day recorded'
                        : 'Days recorded',
                    value: record.workDays.toString(),
                  ),
                  _LibraryDetail(
                    label: 'Hours',
                    value: formatHoursLabel(record.totalHours),
                  ),
                  _LibraryDetail(label: 'File size', value: _size),
                ],
              ),
            ),
            if (!record.isAvailable) ...[
              const SizedBox(height: 10),
              const _MissingFileBadge(),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
                if (onPrint != null)
                  TextButton.icon(
                    onPressed: onPrint,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                TextButton.icon(
                  onPressed: onFavourite,
                  icon: Icon(
                    record.isFavourite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                  ),
                  label: Text(record.isFavourite ? 'Favourited' : 'Favourite'),
                ),
                TextButton.icon(
                  onPressed: onRename,
                  icon: const Icon(
                    Icons.drive_file_rename_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('Rename'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingFileBadge extends StatelessWidget {
  const _MissingFileBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'Export file not found.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _LibraryDetail extends StatelessWidget {
  const _LibraryDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: '$label  ',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
      children: [
        TextSpan(
          text: value,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class EmptyExportLibrary extends StatelessWidget {
  const EmptyExportLibrary({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              'No saved exports yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Reports saved to the Briska Pay Export Library will appear here.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CompactEmptyExportLibrary extends StatelessWidget {
  const _CompactEmptyExportLibrary();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No exports yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Reports you create will appear here for quick access.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecentExportCard extends StatelessWidget {
  const _RecentExportCard({
    required this.record,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final ExportedFileRecord record;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final format = ExportFormat.fromFileType(record.fileType);
    final created = formatCompactDateWithYear(record.exportedAt);
    final range = record.startDate != null && record.endDate != null
        ? '${formatCompactDateWithYear(record.startDate!)} – '
              '${formatCompactDateWithYear(record.endDate!)}'
        : record.periodLabel;
    final size = record.fileSize == null
        ? null
        : record.fileSize! >= 1024 * 1024
        ? '${(record.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(record.fileSize! / 1024).toStringAsFixed(0)} KB';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Icon(
              format == ExportFormat.excel
                  ? Icons.table_chart_outlined
                  : format == ExportFormat.csv
                  ? Icons.grid_on_outlined
                  : Icons.picture_as_pdf_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${record.reportType} · $range',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$created · ${format.label}${size == null ? '' : ' · $size'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Export actions',
              onSelected: (action) {
                switch (action) {
                  case 'open':
                    onOpen();
                  case 'share':
                    onShare();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
