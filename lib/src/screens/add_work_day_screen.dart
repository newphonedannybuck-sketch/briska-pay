import 'entries/entry_widgets.dart';
import 'entries/entry_form_sections.dart';
import 'entries/site_name_field.dart';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models.dart';
import '../work_calculator.dart';
import '../presentation_format.dart';
import '../display_format.dart';
import '../widgets/shared_ui.dart';

class AddWorkDayScreen extends StatefulWidget {
  const AddWorkDayScreen({
    required this.preferences,
    required this.savedEntries,
    required this.onSave,
    this.initialEntry,
    this.initialDate,
    this.securityDismissal,
    super.key,
  });

  final AppSettings preferences;
  final List<WorkEntry> savedEntries;
  final WorkEntry? initialEntry;
  final DateTime? initialDate;
  final Listenable? securityDismissal;
  final Future<bool> Function(WorkEntry entry) onSave;

  @override
  State<AddWorkDayScreen> createState() => _AddWorkDayScreenState();
}

class _AddWorkDayScreenState extends State<AddWorkDayScreen> {
  late String _entryType;
  bool _isPaidSickDay = false;
  bool _isPaidBankHoliday = true;
  late String _rateType;
  late double _selectedRate;
  late double _appliedAllowance;
  late bool _allowanceHasValue;
  double _jobUplift = 0;
  double _deductionAmount = 0;
  late String _startTime;
  late String _finishTime;
  late String _breakInput;
  int get _breakMinutes =>
      _breakInput.trim().isEmpty ? 0 : (int.tryParse(_breakInput.trim()) ?? -1);
  late DateTime _date;
  String? _editingEntryId;
  late final TextEditingController _siteController;
  late final TextEditingController _notesController;
  late final TextEditingController _deductionReasonController;
  late final TextEditingController _holidayHoursController;
  bool get _isBankHoliday =>
      _entryType == 'bankHoliday' || _entryType == 'BankHoliday';
  bool get _hasHolidayHours => _entryType == 'Holiday' || _isBankHoliday;
  double? get _holidayHours {
    final text = _holidayHoursController.text.trim();
    return text.isEmpty ? null : double.tryParse(text) ?? double.nan;
  }

  String? get _hoursError {
    final hours = _holidayHours;
    return hours != null && (!hours.isFinite || hours < 0 || hours > 24)
        ? 'Enter valid hours from 0 to 24.'
        : null;
  }

  String? _siteError;
  bool _isSaving = false;
  bool _dirty = false;
  bool _confirmingDiscard = false;
  bool _closed = false;
  bool _securityDismissed = false;
  late Object _initialFormState;

  bool get _editorActive => mounted && !_closed && !_securityDismissed;

  // Compare only form values, never focus, validation, or calculated totals.
  // Normalize values that are saved equivalently without losing invalid input.
  Object get _formState => (
    date: (_date.year, _date.month, _date.day),
    entryType: _isBankHoliday ? 'bankHoliday' : _entryType,
    site: _siteController.text.trim(),
    start: WorkCalculator.normalizeTime(_startTime) ?? _startTime,
    finish: WorkCalculator.normalizeTime(_finishTime) ?? _finishTime,
    breakMinutes: _breakInput.trim().isEmpty
        ? 0
        : int.tryParse(_breakInput.trim()) ?? _breakInput.trim(),
    rateType: _rateType,
    rate: _selectedRate,
    allowance: _appliedAllowance,
    allowanceEntered: _allowanceHasValue,
    uplift: _jobUplift,
    deduction: _deductionAmount,
    deductionReason: _deductionReasonController.text.trim(),
    holidayHours:
        double.tryParse(_holidayHoursController.text.trim())?.toString() ??
        _holidayHoursController.text.trim(),
    paidSick: _isPaidSickDay,
    paidBankHoliday: _isPaidBankHoliday,
    notes: _notesController.text.trim(),
  );

  void _textChanged() {
    // Controller listeners also run for selection/focus changes. Only rebuild
    // when the navigation permission actually changes.
    if (!_editorActive) return;
    final dirty = _formState != _initialFormState;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  void _dismissForSecurity() {
    if (!mounted) return;
    setState(() => _securityDismissed = true);
  }

  Future<void> _confirmDiscard() async {
    if (!_editorActive || _isSaving || _confirmingDiscard) return;
    _confirmingDiscard = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('Your changes to this day have not been saved.'),
          actions: [
            TextButton(
              onPressed: () {
                if (_editorActive &&
                    ModalRoute.of(dialogContext)?.isCurrent == true) {
                  Navigator.pop(dialogContext, false);
                }
              },
              child: const Text('Keep Editing'),
            ),
            FilledButton(
              onPressed: () {
                if (_editorActive &&
                    ModalRoute.of(dialogContext)?.isCurrent == true) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Discard Changes'),
            ),
          ],
        ),
      );
      if (!_editorActive || _isSaving || discard != true) return;
      _closeEditor();
    } finally {
      _confirmingDiscard = false;
    }
  }

  void _closeEditor() {
    if (!_editorActive || ModalRoute.of(context)?.isCurrent != true) return;
    _closed = true;
    // Explicit programmatic completion; ordinary Back uses maybePop/PopScope.
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    final preferences = widget.preferences;
    final entry = widget.initialEntry;
    _editingEntryId = entry?.id;
    _entryType = entry?.entryType ?? 'WorkDay';
    _isPaidSickDay = entry?.isPaidSickDay ?? false;
    _isPaidBankHoliday = entry?.isPaidBankHoliday ?? true;
    _rateType = entry?.rateType ?? preferences.defaultRateType;
    _selectedRate =
        entry?.hourlyRateUsed ??
        (_rateType == 'primary'
            ? preferences.primaryRateValue
            : preferences.secondaryRateValue);
    _appliedAllowance = entry?.dailyAllowance ?? 0;
    _allowanceHasValue = entry != null && entry.dailyAllowance != 0;
    _jobUplift = entry?.jobUplift ?? 0;
    _deductionAmount = entry?.deductionAmount ?? 0;
    _startTime = entry?.startTime ?? preferences.defaultStartTime;
    _finishTime = entry?.finishTime ?? preferences.defaultFinishTime;
    _breakInput = (entry?.breakMinutes ?? preferences.defaultBreakMinutes)
        .toString();
    _date = entry?.date ?? widget.initialDate ?? DateTime.now();
    _siteController = TextEditingController(text: entry?.siteName ?? '');
    _notesController = TextEditingController(text: entry?.notes ?? '');
    _deductionReasonController = TextEditingController(
      text: entry?.deductionReason ?? '',
    );
    _holidayHoursController = TextEditingController(
      text: entry != null && _hasHolidayHours && entry.totalHours != 0
          ? entry.totalHours.toString()
          : '',
    );
    if (_entryType == 'Holiday') {
      _rateType = 'primary';
      _selectedRate = entry?.hourlyRateUsed ?? preferences.primaryRateValue;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    } else if (_isBankHoliday) {
      _rateType = 'primary';
      _selectedRate = entry?.hourlyRateUsed ?? preferences.primaryRateValue;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    } else if (_entryType == 'UnpaidDayOff' || _entryType == 'SickDay') {
      _rateType = 'primary';
      _selectedRate = _entryType == 'SickDay' && _isPaidSickDay
          ? (entry?.hourlyRateUsed ?? preferences.primaryRateValue)
          : 0;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    }
    _initialFormState = _formState;
    for (final controller in [
      _siteController,
      _notesController,
      _deductionReasonController,
      _holidayHoursController,
    ]) {
      controller.addListener(_textChanged);
    }
    widget.securityDismissal?.addListener(_dismissForSecurity);
  }

  @override
  void didUpdateWidget(AddWorkDayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.securityDismissal != widget.securityDismissal) {
      oldWidget.securityDismissal?.removeListener(_dismissForSecurity);
      widget.securityDismissal?.addListener(_dismissForSecurity);
    }
  }

  @override
  void dispose() {
    widget.securityDismissal?.removeListener(_dismissForSecurity);
    _holidayHoursController.dispose();
    _siteController.dispose();
    _notesController.dispose();
    _deductionReasonController.dispose();
    super.dispose();
  }

  WorkCalculation get _calculation =>
      _entryType == 'WorkDay' &&
          _breakInput.trim().isNotEmpty &&
          int.tryParse(_breakInput.trim()) == null
      ? const WorkCalculation(
          totalHours: 0,
          wages: 0,
          totalPay: 0,
          error: 'Enter break duration in whole minutes.',
        )
      : WorkCalculator.calculate(
          startTime: _startTime,
          finishTime: _finishTime,
          breakMinutes: _breakMinutes,
          hourlyRate: _selectedRate,
          rateType: _rateType,
          dailyAllowance: _appliedAllowance,
          jobUplift: _jobUplift,
          entryType: _entryType,
          isPaidSickDay: _isPaidSickDay,
          isPaidBankHoliday: _isPaidBankHoliday,
          deductionAmount: _deductionAmount,
          holidayHours: _hasHolidayHours ? _holidayHours : null,
        );

  void _selectEntryType(String value) {
    if (_entryType == value || (_isBankHoliday && value == 'bankHoliday')) {
      return;
    }
    setState(() {
      if (!_hasHolidayHours || (value != 'Holiday' && value != 'bankHoliday')) {
        _holidayHoursController.clear();
      }
      _entryType = value;
      if (value == 'Holiday') {
        _rateType = 'primary';
        _selectedRate = widget.preferences.primaryRateValue;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else if (value == 'bankHoliday') {
        _isPaidBankHoliday = true;
        _rateType = 'primary';
        _selectedRate = widget.preferences.primaryRateValue;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else if (value == 'UnpaidDayOff') {
        _rateType = 'primary';
        _selectedRate = 0;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else if (value == 'SickDay') {
        _isPaidSickDay = false;
        _rateType = 'primary';
        _selectedRate = 0;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      } else {
        _rateType = widget.preferences.defaultRateType;
        _selectedRate = _rateType == 'primary'
            ? widget.preferences.primaryRateValue
            : widget.preferences.secondaryRateValue;
        _appliedAllowance = 0;
        _allowanceHasValue = false;
      }
    });
  }

  void _selectRateType(String rateType) {
    setState(() {
      _rateType = rateType;
      _selectedRate = rateType == 'primary'
          ? widget.preferences.primaryRateValue
          : widget.preferences.secondaryRateValue;
    });
  }

  Future<void> _save() async {
    if (!_editorActive || _isSaving || _confirmingDiscard) return;
    setState(() => _isSaving = true);
    var saved = false;
    try {
      saved = await _submit();
    } catch (error, stackTrace) {
      debugPrint('entry submission failed: $error');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (mounted && _editorActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this day.')),
        );
      }
    } finally {
      if (_editorActive && !saved) setState(() => _isSaving = false);
    }
  }

  Future<bool> _submit() async {
    if (_entryType == 'WorkDay' && _siteController.text.trim().isEmpty) {
      setState(() => _siteError = 'Enter a site/job name');
      return false;
    }
    FocusScope.of(context).unfocus();
    final calculation = _calculation;
    if (!calculation.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(calculation.error!)));
      return false;
    }
    final duplicate = widget.savedEntries.where((entry) {
      final sameDate =
          entry.date.year == _date.year &&
          entry.date.month == _date.month &&
          entry.date.day == _date.day;
      return sameDate && entry.id != _editingEntryId;
    }).toList();
    if (duplicate.isNotEmpty) {
      final choice = await showDialog<_DuplicateChoice>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Entry already exists'),
          content: Text(
            'There is already ${duplicate.length == 1 ? 'an entry' : '${duplicate.length} entries'} for this date.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateChoice.editExisting),
              child: const Text('Edit existing'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _DuplicateChoice.continueAnyway),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!_editorActive ||
          choice == null ||
          choice == _DuplicateChoice.cancel) {
        return false;
      }
      if (choice == _DuplicateChoice.editExisting) {
        final existing = duplicate.first;
        setState(() {
          _editingEntryId = existing.id;
          _entryType = existing.entryType;
          _holidayHoursController.text =
              _hasHolidayHours && existing.totalHours != 0
              ? existing.totalHours.toString()
              : '';
          _isPaidSickDay = existing.isPaidSickDay;
          _isPaidBankHoliday = existing.isPaidBankHoliday;
          _rateType = existing.rateType;
          _selectedRate = existing.hourlyRateUsed;
          _appliedAllowance = existing.dailyAllowance;
          _allowanceHasValue = existing.dailyAllowance != 0;
          _jobUplift = existing.jobUplift;
          _deductionAmount = existing.deductionAmount;
          _deductionReasonController.text = existing.deductionReason;
          _startTime = existing.startTime;
          _finishTime = existing.finishTime;
          _breakInput = existing.breakMinutes.toString();
          _date = existing.date;
          _siteController.text = existing.siteName;
          _notesController.text = existing.notes;
          _initialFormState = _formState;
        });
        return false;
      }
    }
    final entry = WorkEntry(
      id: _editingEntryId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      entryType: _entryType,
      date: _date,
      siteName: _entryType == 'WorkDay' ? _siteController.text.trim() : '',
      startTime: _entryType == 'WorkDay'
          ? WorkCalculator.normalizeTime(_startTime)!
          : '',
      finishTime: _entryType == 'WorkDay'
          ? WorkCalculator.normalizeTime(_finishTime)!
          : '',
      breakMinutes: _entryType == 'WorkDay' ? _breakMinutes : 0,
      rateType: _entryType == 'WorkDay' ? _rateType : 'primary',
      hourlyRateUsed: _selectedRate,
      dailyAllowance: _entryType == 'WorkDay' ? _appliedAllowance : 0,
      jobUplift: _jobUplift,
      totalHours: calculation.totalHours,
      wages: calculation.wages,
      totalPay: calculation.totalPay,
      notes: _notesController.text.trim(),
      isPaidSickDay: _isPaidSickDay,
      isPaidBankHoliday: _isPaidBankHoliday,
      deductionAmount: _deductionAmount,
      deductionReason: _deductionReasonController.text.trim(),
    );
    final saved = await widget.onSave(entry);
    if (!mounted || !_editorActive || !saved) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_editingEntryId == null ? 'Day saved.' : 'Day updated.'),
      ),
    );
    _closeEditor();
    return true;
  }

  List<Widget> _absenceInputs() => [
    if (_hasHolidayHours) ...[
      const FieldLabel('Hours (optional)'),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('holiday-hours-field'),
        controller: _holidayHoursController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: 'Enter hours (optional)',
          errorText: _hoursError,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
    ],
    if (_entryType == 'Holiday') ...[
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            CalculationLine(
              label: 'Holiday hours',
              value: formatHoursLabel(_calculation.totalHours),
              emphasize: true,
            ),
            const SizedBox(height: 8),
            CalculationLine(
              label:
                  '${widget.preferences.labelForRate('primary')} hourly rate',
              value: '${formatMoney(_selectedRate)} / hour',
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
    ],
    if (_entryType == 'SickDay') ...[
      const FieldLabel('Sick Pay'),
      const SizedBox(height: 9),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Paid at Primary Rate')),
            ButtonSegment(value: false, label: Text('Unpaid')),
          ],
          selected: {_isPaidSickDay},
          onSelectionChanged: (values) => setState(() {
            _isPaidSickDay = values.first;
            _rateType = 'primary';
            _selectedRate = _isPaidSickDay
                ? widget.preferences.primaryRateValue
                : 0;
          }),
          showSelectedIcon: false,
        ),
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            CalculationLine(
              label: 'Sick Day',
              value: _isPaidSickDay ? 'Paid' : 'Unpaid',
              emphasize: true,
            ),
            const SizedBox(height: 8),
            CalculationLine(
              label: 'Hours',
              value: formatHoursLabel(_isPaidSickDay ? 8 : 0),
            ),
            if (_isPaidSickDay) ...[
              const SizedBox(height: 8),
              CalculationLine(
                label: 'Paid at',
                value: widget.preferences.labelForRate('primary'),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
    ],
    if (_isBankHoliday) ...[
      const FieldLabel('Pay Status'),
      const SizedBox(height: 9),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Paid')),
            ButtonSegment(value: false, label: Text('Unpaid')),
          ],
          selected: {_isPaidBankHoliday},
          onSelectionChanged: (values) => setState(() {
            _isPaidBankHoliday = values.first;
            _rateType = 'primary';
          }),
          showSelectedIcon: false,
        ),
      ),
      const SizedBox(height: 16),
      CalculationLine(
        label: 'Bank Holiday',
        value: _isPaidBankHoliday ? 'Paid' : 'Unpaid',
        emphasize: true,
      ),
      if (_isPaidBankHoliday) ...[
        const SizedBox(height: 8),
        CalculationLine(
          label: 'Paid at',
          value:
              '${widget.preferences.labelForRate('primary')} · ${formatMoney(_selectedRate)} / hour',
        ),
      ],
      const SizedBox(height: 18),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    if (_securityDismissed) return const SizedBox.shrink();
    _dirty = _formState != _initialFormState;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(_editingEntryId == null ? 'Add Day' : 'Edit Day'),
        centerTitle: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: AppPage(
        topPadding: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record your day',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Everything you need for an accurate record.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EntrySectionHeading(
                      icon: Icons.event_note_outlined,
                      title: 'Entry details',
                      subtitle: 'Choose the day type and date',
                    ),
                    const SizedBox(height: 22),
                    const FieldLabel('Day Type'),
                    const SizedBox(height: 9),
                    EntryDayTypeSelector(
                      entryType: _entryType,
                      isBankHoliday: _isBankHoliday,
                      onSelected: _selectEntryType,
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Date'),
                    const SizedBox(height: 8),
                    TextField(
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: formatFullDate(_date),
                        suffixIcon: const Icon(Icons.calendar_today_outlined),
                      ),
                      onTap: () async {
                        final value = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (_editorActive && value != null) {
                          setState(() => _date = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_entryType == 'WorkDay') ...[
                            const FieldLabel('Site/job name'),
                            const SizedBox(height: 8),
                            SiteNameAutocomplete(
                              controller: _siteController,
                              entries: widget.savedEntries,
                              selectAllOnFocus: widget.initialEntry != null,
                              errorText: _siteError,
                              onChanged: (_) {
                                if (_siteError != null) {
                                  setState(() => _siteError = null);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_entryType == 'WorkDay') ...[
                            WorkTimeSection(
                              startTime: _startTime,
                              finishTime: _finishTime,
                              breakInput: _breakInput,
                              calculation: _calculation,
                              onStartChanged: (value) =>
                                  setState(() => _startTime = value),
                              onFinishChanged: (value) =>
                                  setState(() => _finishTime = value),
                              onBreakChanged: (value) =>
                                  setState(() => _breakInput = value),
                            ),
                            const SizedBox(height: 26),
                            const Divider(height: 1),
                            const SizedBox(height: 24),
                            WorkPaySection(
                              preferences: widget.preferences,
                              rateType: _rateType,
                              editingEntryId: _editingEntryId,
                              selectedRate: _selectedRate,
                              allowanceHasValue: _allowanceHasValue,
                              appliedAllowance: _appliedAllowance,
                              onRateTypeChanged: _selectRateType,
                              onRateChanged: (value) => setState(
                                () => _selectedRate = value.trim().isEmpty
                                    ? 0
                                    : (double.tryParse(value) ?? -1),
                              ),
                              onAllowanceChanged: (value) {
                                final text = value.trim();
                                setState(() {
                                  _allowanceHasValue = text.isNotEmpty;
                                  _appliedAllowance = text.isEmpty
                                      ? 0
                                      : (double.tryParse(text) ?? -1);
                                });
                              },
                            ),
                          ],
                          ..._absenceInputs(),
                        ],
                      ),
                    ),
                    ...[
                      const FieldLabel('Job uplift'),
                      const SizedBox(height: 8),
                      OptionalCurrencyField(
                        key: const ValueKey('job-uplift-field'),
                        initialValue: _jobUplift,
                        onChanged: (value) =>
                            setState(() => _jobUplift = value),
                      ),
                      const SizedBox(height: 18),
                    ],
                    const EntrySectionHeading(
                      icon: Icons.remove_circle_outline,
                      title: 'Deduction',
                      subtitle: 'Optional pay adjustment',
                    ),
                    const SizedBox(height: 12),
                    OptionalCurrencyField(
                      key: const ValueKey('deduction-amount-field'),
                      initialValue: _deductionAmount,
                      onChanged: (value) =>
                          setState(() => _deductionAmount = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _deductionReasonController,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Deduction reason',
                        hintText: 'Advance, Loan Repayment, Uniform or Other',
                      ),
                    ),
                    const SizedBox(height: 10),
                    EarningsSummaryCard(
                      calculation: _calculation,
                      rate: _selectedRate,
                      allowance: _appliedAllowance,
                      uplift: _jobUplift,
                    ),
                    const SizedBox(height: 26),
                    const Divider(height: 1),
                    const SizedBox(height: 24),
                    const EntrySectionHeading(
                      icon: Icons.notes_rounded,
                      title: 'Notes',
                      subtitle: 'Optional details for later',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Anything useful to remember...',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 96),
          ],
        ),
      ),
      bottomNavigationBar: EntrySaveBar(
        calculation: _calculation,
        keyboardOpen: keyboardOpen,
        onSave: _isSaving ? null : _save,
        label: _editingEntryId == null ? 'Save Entry' : 'Update Entry',
      ),
    );
    return PopScope<void>(
      canPop: !_isSaving && !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _closed = true;
          return;
        }
        unawaited(_confirmDiscard());
      },
      child: AbsorbPointer(
        absorbing: _isSaving,
        child: ExcludeFocus(excluding: _isSaving, child: scaffold),
      ),
    );
  }
}

enum _DuplicateChoice { cancel, editExisting, continueAnyway }
