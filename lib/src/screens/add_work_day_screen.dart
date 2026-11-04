part of '../briska_app.dart';

class AddWorkDayScreen extends StatefulWidget {
  const AddWorkDayScreen({
    required this.preferences,
    required this.savedEntries,
    required this.onSave,
    this.initialEntry,
    this.initialDate,
    super.key,
  });

  final AppSettings preferences;
  final List<WorkEntry> savedEntries;
  final WorkEntry? initialEntry;
  final DateTime? initialDate;
  final Future<bool> Function(WorkEntry entry) onSave;

  @override
  State<AddWorkDayScreen> createState() => _AddWorkDayScreenState();
}

class _SiteNameAutocomplete extends StatefulWidget {
  const _SiteNameAutocomplete({
    required this.controller,
    required this.entries,
    this.selectAllOnFocus = false,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<WorkEntry> entries;
  final bool selectAllOnFocus;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<_SiteNameAutocomplete> createState() => _SiteNameAutocompleteState();
}

class _SiteNameAutocompleteState extends State<_SiteNameAutocomplete> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  bool _selectedForFocus = false;

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      return;
    }
    if (widget.controller.text.trim().isEmpty) {
      setState(() {});
      return;
    }
    if (!widget.selectAllOnFocus || _selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) => recentSiteNameSuggestions(
        widget.entries,
        query: value.text,
        limit: value.text.trim().isEmpty ? 5 : 8,
      ),
      onSelected: (value) {
        widget.controller
          ..text = value
          ..selection = TextSelection.collapsed(offset: value.length);
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Where did you work?',
                prefixIcon: Icon(Icons.work_outline_rounded),
              ).copyWith(errorText: widget.errorText),
              onChanged: widget.onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onTap: () {
                if (textEditingController.text.trim().isEmpty) {
                  setState(() {});
                }
              },
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        final colorScheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 18),
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
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
  late int _breakMinutes;
  late DateTime _date;
  String? _editingEntryId;
  late final TextEditingController _siteController;
  late final TextEditingController _notesController;
  late final TextEditingController _deductionReasonController;
  String? _siteError;

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
    _breakMinutes = entry?.breakMinutes ?? preferences.defaultBreakMinutes;
    _date = entry?.date ?? widget.initialDate ?? DateTime.now();
    _siteController = TextEditingController(text: entry?.siteName ?? '');
    _notesController = TextEditingController(text: entry?.notes ?? '');
    _deductionReasonController = TextEditingController(
      text: entry?.deductionReason ?? '',
    );
    if (_entryType == 'Holiday') {
      _rateType = 'primary';
      _selectedRate = preferences.primaryRateValue;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    } else if (_entryType == 'bankHoliday') {
      _rateType = 'primary';
      _selectedRate = _isPaidBankHoliday ? preferences.primaryRateValue : 0;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    } else if (_entryType == 'UnpaidDayOff' || _entryType == 'SickDay') {
      _rateType = 'primary';
      _selectedRate = _entryType == 'SickDay' && _isPaidSickDay
          ? preferences.primaryRateValue
          : 0;
      _appliedAllowance = 0;
      _allowanceHasValue = false;
    }
  }

  @override
  void dispose() {
    _siteController.dispose();
    _notesController.dispose();
    _deductionReasonController.dispose();
    super.dispose();
  }

  WorkCalculation get _calculation => WorkCalculator.calculate(
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
  );

  void _selectEntryType(String value) {
    setState(() {
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
    if (_entryType == 'WorkDay' && _siteController.text.trim().isEmpty) {
      setState(() => _siteError = 'Enter a site/job name');
      return;
    }
    FocusScope.of(context).unfocus();
    final calculation = _calculation;
    if (!calculation.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(calculation.error!)));
      return;
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
      if (!mounted || choice == null || choice == _DuplicateChoice.cancel) {
        return;
      }
      if (choice == _DuplicateChoice.editExisting) {
        final existing = duplicate.first;
        setState(() {
          _editingEntryId = existing.id;
          _entryType = existing.entryType;
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
          _breakMinutes = existing.breakMinutes;
          _date = existing.date;
          _siteController.text = existing.siteName;
          _notesController.text = existing.notes;
        });
        return;
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
    if (!mounted) return;
    if (!saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.initialEntry == null ? 'Day saved.' : 'Day updated.',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialEntry == null ? 'Add Day' : 'Edit Day'),
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
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _EntrySectionHeading(
                      icon: Icons.event_note_outlined,
                      title: 'Entry details',
                      subtitle: 'Choose the day type and date',
                    ),
                    const SizedBox(height: 22),
                    const FieldLabel('Day Type'),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          const [
                            (EntryType.workDay, 'Work Day', Icons.work_outline),
                            (
                              EntryType.holiday,
                              'Holiday',
                              Icons.beach_access_outlined,
                            ),
                            (
                              EntryType.bankHoliday,
                              'Bank Holiday',
                              Icons.account_balance_rounded,
                            ),
                            (
                              EntryType.sickDay,
                              'Sick Day',
                              Icons.sick_outlined,
                            ),
                            (
                              EntryType.unpaidDayOff,
                              'Unpaid Day Off',
                              Icons.event_busy_outlined,
                            ),
                          ].map((option) {
                            final selected =
                                _entryType == option.$1.storageValue;
                            return ChoiceChip(
                              key: ValueKey('day-type-${option.$1.name}'),
                              selected: selected,
                              avatar: Icon(option.$3, size: 18),
                              label: Text(option.$2),
                              onSelected: (_) =>
                                  _selectEntryType(option.$1.storageValue),
                            );
                          }).toList(),
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
                        if (value != null) setState(() => _date = value);
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
                            _SiteNameAutocomplete(
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
                            Row(
                              children: [
                                Expanded(
                                  child: _TimeInputField(
                                    label: 'Start time',
                                    hint: '08:00',
                                    initialValue: _startTime,
                                    onChanged: (value) =>
                                        setState(() => _startTime = value),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _TimeInputField(
                                    label: 'Finish time',
                                    hint: '16:30',
                                    initialValue: _finishTime,
                                    onChanged: (value) =>
                                        setState(() => _finishTime = value),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _LabeledField(
                              label: 'Break minutes',
                              hint: 'Enter minutes',
                              initialValue: _breakMinutes.toString(),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                final text = value.trim();
                                setState(
                                  () => _breakMinutes = text.isEmpty
                                      ? 0
                                      : (int.tryParse(text) ?? -1),
                                );
                              },
                            ),
                            if (!_calculation.isValid) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      _calculation.error!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 26),
                            const Divider(height: 1),
                            const SizedBox(height: 24),
                            const _EntrySectionHeading(
                              icon: Icons.payments_outlined,
                              title: 'Pay details',
                              subtitle: 'Rate and extras',
                            ),
                            const SizedBox(height: 22),
                            const FieldLabel('Rate used'),
                            const SizedBox(height: 9),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<String>(
                                segments: [
                                  ButtonSegment(
                                    value: 'primary',
                                    label: Text(
                                      widget.preferences.labelForRate(
                                        'primary',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'secondary',
                                    label: Text(
                                      widget.preferences.labelForRate(
                                        'secondary',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                selected: {_rateType},
                                onSelectionChanged: (values) =>
                                    _selectRateType(values.first),
                                showSelectedIcon: false,
                              ),
                            ),
                            const SizedBox(height: 16),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const FieldLabel('Hourly rate for this day'),
                                  const SizedBox(height: 8),
                                  _SelectAllTextFormField(
                                    key: ValueKey('rate-$_rateType'),
                                    initialValue: _currencyInputValue(
                                      _selectedRate,
                                    ),
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      prefixText: _currencyPrefix,
                                      suffixText: '/ hour',
                                    ),
                                    onChanged: (value) => setState(
                                      () => _selectedRate = value.trim().isEmpty
                                          ? 0
                                          : (double.tryParse(value) ?? -1),
                                    ),
                                  ),
                                  ...[
                                    const SizedBox(height: 14),
                                    const FieldLabel('Daily allowance'),
                                    const SizedBox(height: 8),
                                    _SelectAllTextFormField(
                                      key: ValueKey(
                                        'allowance-$_editingEntryId-$_rateType',
                                      ),
                                      initialValue: _allowanceHasValue
                                          ? _currencyInputValue(
                                              _appliedAllowance,
                                            )
                                          : '',
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.done,
                                      decoration: InputDecoration(
                                        prefixText: _currencyPrefix,
                                        hintText: 'e.g. 25.00',
                                        helperText:
                                            'Optional. Leave blank for no allowance.',
                                      ),
                                      onChanged: (value) {
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],
                          if (_entryType == 'Holiday') ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  _CalculationLine(
                                    label: 'Holiday hours',
                                    value: formatHoursLabel(8),
                                    emphasize: true,
                                  ),
                                  const SizedBox(height: 8),
                                  _CalculationLine(
                                    label:
                                        '${widget.preferences.labelForRate('primary')} hourly rate',
                                    value: '${_money(_selectedRate)} / hour',
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
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Paid at Primary Rate'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Unpaid'),
                                  ),
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  _CalculationLine(
                                    label: 'Sick Day',
                                    value: _isPaidSickDay ? 'Paid' : 'Unpaid',
                                    emphasize: true,
                                  ),
                                  const SizedBox(height: 8),
                                  _CalculationLine(
                                    label: 'Hours',
                                    value: formatHoursLabel(
                                      _isPaidSickDay ? 8 : 0,
                                    ),
                                  ),
                                  if (_isPaidSickDay) ...[
                                    const SizedBox(height: 8),
                                    _CalculationLine(
                                      label: 'Paid at',
                                      value: widget.preferences.labelForRate(
                                        'primary',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_entryType == 'bankHoliday') ...[
                            const FieldLabel('Pay Status'),
                            const SizedBox(height: 9),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Paid'),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Unpaid'),
                                  ),
                                ],
                                selected: {_isPaidBankHoliday},
                                onSelectionChanged: (values) => setState(() {
                                  _isPaidBankHoliday = values.first;
                                  _rateType = 'primary';
                                  _selectedRate = _isPaidBankHoliday
                                      ? widget.preferences.primaryRateValue
                                      : 0;
                                }),
                                showSelectedIcon: false,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _CalculationLine(
                              label: 'Bank Holiday',
                              value: _isPaidBankHoliday
                                  ? 'Paid · 8 hours'
                                  : 'Unpaid · 0 hours',
                              emphasize: true,
                            ),
                            if (_isPaidBankHoliday) ...[
                              const SizedBox(height: 8),
                              _CalculationLine(
                                label: 'Paid at',
                                value:
                                    '${widget.preferences.labelForRate('primary')} · ${_money(_selectedRate)} / hour',
                              ),
                            ],
                            const SizedBox(height: 18),
                          ],
                        ],
                      ),
                    ),
                    ...[
                      const FieldLabel('Job uplift'),
                      const SizedBox(height: 8),
                      _OptionalCurrencyField(
                        key: const ValueKey('job-uplift-field'),
                        initialValue: _jobUplift,
                        onChanged: (value) =>
                            setState(() => _jobUplift = value),
                      ),
                      const SizedBox(height: 18),
                    ],
                    const _EntrySectionHeading(
                      icon: Icons.remove_circle_outline,
                      title: 'Deduction',
                      subtitle: 'Optional pay adjustment',
                    ),
                    const SizedBox(height: 12),
                    _OptionalCurrencyField(
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
                    _EarningsSummaryCard(
                      calculation: _calculation,
                      rate: _selectedRate,
                      allowance: _appliedAllowance,
                      uplift: _jobUplift,
                    ),
                    const SizedBox(height: 26),
                    const Divider(height: 1),
                    const SizedBox(height: 24),
                    const _EntrySectionHeading(
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
      bottomNavigationBar: _EntrySaveBar(
        calculation: _calculation,
        keyboardOpen: keyboardOpen,
        onSave: _save,
        label: widget.initialEntry == null ? 'Save Entry' : 'Update Entry',
      ),
    );
  }
}

class _EntrySaveBar extends StatelessWidget {
  const _EntrySaveBar({
    required this.calculation,
    required this.keyboardOpen,
    required this.onSave,
    required this.label,
  });

  final WorkCalculation calculation;
  final bool keyboardOpen;
  final VoidCallback onSave;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: .12),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            if (!keyboardOpen) ...[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated gross pay',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      calculation.isValid ? _money(calculation.totalPay) : '--',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
            SizedBox(
              width: keyboardOpen ? 176 : 170,
              child: BriskaPrimaryButton(
                onPressed: onSave,
                icon: Icons.check_rounded,
                label: label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntrySectionHeading extends StatelessWidget {
  const _EntrySectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _DuplicateChoice { cancel, editExisting, continueAnyway }

class _OptionalCurrencyField extends StatefulWidget {
  const _OptionalCurrencyField({
    required this.initialValue,
    required this.onChanged,
    super.key,
  });

  final double initialValue;
  final ValueChanged<double> onChanged;

  @override
  State<_OptionalCurrencyField> createState() => _OptionalCurrencyFieldState();
}

class _OptionalCurrencyFieldState extends State<_OptionalCurrencyField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _selectedForFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == 0
          ? ''
          : widget.initialValue.toStringAsFixed(2),
    );
    _focusNode = FocusNode()..addListener(_handleFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      _formatValue();
      return;
    }
    if (_selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        duration: BriskaDurations.standard,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _formatValue() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onChanged(0);
      return;
    }
    final value = double.tryParse(text);
    if (value == null) return;
    _controller.value = TextEditingValue(
      text: value.toStringAsFixed(2),
      selection: TextSelection.collapsed(
        offset: value.toStringAsFixed(2).length,
      ),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        prefixText: _currencyPrefix,
        hintText: 'Enter amount (optional)',
      ),
      onChanged: (text) => widget.onChanged(
        text.trim().isEmpty ? 0 : (double.tryParse(text) ?? -1),
      ),
      onEditingComplete: () {
        _formatValue();
        _focusNode.unfocus();
      },
    );
  }
}

class _CalculationLine extends StatelessWidget {
  const _CalculationLine({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.foregroundColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final color = foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: color,
              fontSize: emphasize ? 17 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _EarningsSummaryCard extends StatelessWidget {
  const _EarningsSummaryCard({
    required this.calculation,
    required this.rate,
    required this.allowance,
    required this.uplift,
  });

  final WorkCalculation calculation;
  final double rate;
  final double allowance;
  final double uplift;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, BriskaColors.dark, .3)!,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated gross pay',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          BriskaAnimatedText(
            _money(calculation.totalPay),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 24),
          _CalculationLine(
            label: 'Hours',
            value: formatHoursLabel(calculation.totalHours),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          _CalculationLine(
            label: 'Rate',
            value: '${_money(rate)} / hour',
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          _CalculationLine(
            label: 'Allowance',
            value: _money(allowance),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          _CalculationLine(
            label: 'Uplift',
            value: _money(uplift),
            foregroundColor: Colors.white,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              color: Colors.white.withValues(alpha: .2),
              height: 1,
            ),
          ),
          _CalculationLine(
            label: 'Estimated gross pay',
            value: _money(calculation.totalPay),
            emphasize: true,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _TimeInputField extends StatefulWidget {
  const _TimeInputField({
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    this.onFinished,
  });

  final String label;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFinished;

  @override
  State<_TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<_TimeInputField> {
  late final TextEditingController _controller;
  bool _normalizing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text:
          WorkCalculator.normalizeTime(widget.initialValue) ??
          widget.initialValue,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    if (_normalizing) return;
    final normalized = WorkCalculator.normalizeTime(value);
    if (normalized != null && normalized != value) {
      _normalizing = true;
      _controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      _normalizing = false;
      widget.onChanged(normalized);
      return;
    }
    widget.onChanged(value);
  }

  TimeOfDay _initialTimeOfDay() {
    final normalized =
        WorkCalculator.normalizeTime(_controller.text) ??
        WorkCalculator.normalizeTime(widget.initialValue) ??
        WorkCalculator.normalizeTime(widget.hint) ??
        '08:00';
    final parts = normalized.split(':');
    return TimeOfDay(
      hour: int.parse(parts.first),
      minute: int.parse(parts.last),
    );
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _initialTimeOfDay(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (selected == null) return;
    final value = formatTime(hour: selected.hour, minute: selected.minute);
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(widget.label),
      const SizedBox(height: 8),
      TextField(
        controller: _controller,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: IconButton(
            tooltip: 'Pick time',
            icon: const Icon(Icons.schedule_rounded, size: 20),
            onPressed: _pickTime,
          ),
        ),
        onChanged: _handleChanged,
        onEditingComplete: widget.onFinished,
      ),
    ],
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    this.initialValue,
    this.onChanged,
    this.keyboardType,
  });
  final String label, hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(label),
      const SizedBox(height: 8),
      _SelectAllTextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
        onChanged: onChanged,
      ),
    ],
  );
}
