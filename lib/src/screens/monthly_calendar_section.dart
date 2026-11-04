part of '../briska_app.dart';

class MonthlyCalendarSection extends StatefulWidget {
  const MonthlyCalendarSection({
    required this.entries,
    required this.settings,
    required this.onEditEntry,
    required this.onAddDate,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;
  final ValueChanged<WorkEntry> onEditEntry;
  final ValueChanged<DateTime> onAddDate;

  @override
  State<MonthlyCalendarSection> createState() => _MonthlyCalendarSectionState();
}

class _MonthlyCalendarSectionState extends State<MonthlyCalendarSection> {
  late DateTime _month;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _moveMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = null;
    });
  }

  void _showCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = monthStart.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final byDay = <int, List<WorkEntry>>{};
    for (final entry in widget.entries) {
      if (entry.date.year == _month.year && entry.date.month == _month.month) {
        byDay.putIfAbsent(entry.date.day, () => []).add(entry);
      }
    }
    final monthEntries = byDay.values.expand((items) => items);
    final summary = WorkCalculator.summarize(monthEntries);
    final currentPayPeriod = getCurrentPayPeriodForSettings(
      date: DateTime.now(),
      settings: widget.settings,
    );
    final selectedEntries = _selectedDay == null
        ? const <WorkEntry>[]
        : byDay[_selectedDay!.day] ?? const <WorkEntry>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final padding = compact ? 12.0 : 18.0;
        final gridGap = compact ? 3.0 : 5.0;
        const minimumDateCellExtent = 48.0;
        final minimumCalendarWidth =
            (minimumDateCellExtent * 7) + (gridGap * 6);
        final availableCalendarWidth = constraints.maxWidth - (padding * 2);
        final calendarWidth = availableCalendarWidth > minimumCalendarWidth
            ? availableCalendarWidth
            : minimumCalendarWidth;
        return Card(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatMonthYear(_month),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${byDay.length} recorded ${byDay.length == 1 ? 'day' : 'days'}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Previous month',
                      onPressed: () => _moveMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Next month',
                      onPressed: () => _moveMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 14),
                Row(
                  children: [
                    Expanded(
                      child: _CalendarMetric(
                        label: 'Hours',
                        value: formatHoursLabel(summary.totalHours),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CalendarMetric(
                        label: 'Estimated gross pay',
                        value: _money(summary.totalExpectedPay),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _showCurrentMonth,
                      child: const Text('Today'),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 14),
                SingleChildScrollView(
                  key: const ValueKey('calendar-horizontal-scroll'),
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: calendarWidth,
                    child: Column(
                      children: [
                        Row(
                          key: const ValueKey('calendar-weekday-row'),
                          children: [
                            for (final dayName in _dayNames)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    dayName.substring(0, 1),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: compact ? 10 : 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: compact ? 5 : 7),
                        GridView.builder(
                          key: const ValueKey('calendar-date-grid'),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: totalCells,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: gridGap,
                                crossAxisSpacing: gridGap,
                              ),
                          itemBuilder: (context, index) {
                            final day = index - leading + 1;
                            if (day < 1 || day > daysInMonth) {
                              return const SizedBox.shrink();
                            }
                            final date = DateTime(
                              _month.year,
                              _month.month,
                              day,
                            );
                            final entries = byDay[day] ?? const <WorkEntry>[];
                            return _CalendarDayTile(
                              key: ValueKey('calendar-day-$day'),
                              date: date,
                              entries: entries,
                              settings: widget.settings,
                              compact: compact,
                              inCurrentPayPeriod: currentPayPeriod.contains(
                                date,
                              ),
                              selected: _isSameDate(_selectedDay, date),
                              onTap: () => setState(() => _selectedDay = date),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: compact ? 10 : 12),
                Wrap(
                  key: const ValueKey('calendar-legend'),
                  spacing: compact ? 10 : 16,
                  runSpacing: 6,
                  children: [
                    _CalendarLegend(
                      status: _CalendarStatus.home,
                      label: widget.settings.labelForRate('primary'),
                    ),
                    _CalendarLegend(
                      status: _CalendarStatus.away,
                      label: widget.settings.labelForRate('secondary'),
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.holiday,
                      label: 'Holiday',
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.sick,
                      label: 'Sick Day',
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.unpaid,
                      label: 'Unpaid',
                    ),
                    const _CalendarLegend(
                      status: _CalendarStatus.bankHoliday,
                      label: 'Bank Holiday',
                    ),
                    const _CalendarLegend(
                      color: BriskaColors.calendarEmpty,
                      label: 'No entry',
                    ),
                    _CalendarLegend(
                      color: BriskaColors.primary,
                      label: 'Pay period',
                      outlined: true,
                    ),
                  ],
                ),
                if (_selectedDay != null) ...[
                  SizedBox(height: compact ? 12 : 16),
                  _CalendarDaySummary(
                    date: _selectedDay!,
                    entries: selectedEntries,
                    settings: widget.settings,
                    onAdd: () => widget.onAddDate(_selectedDay!),
                    onEdit: widget.onEditEntry,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isSameDate(DateTime? left, DateTime right) {
    return left != null &&
        left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _CalendarMetric extends StatelessWidget {
  const _CalendarMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _CalendarDaySummary extends StatelessWidget {
  const _CalendarDaySummary({
    required this.date,
    required this.entries,
    required this.settings,
    required this.onAdd,
    required this.onEdit,
  });

  final DateTime date;
  final List<WorkEntry> entries;
  final AppSettings settings;
  final VoidCallback onAdd;
  final ValueChanged<WorkEntry> onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dateLabel = formatWeekdayDate(date);
    return AnimatedSwitcher(
      duration: BriskaDurations.standard,
      child: Container(
        key: ValueKey(date),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.primary.withValues(alpha: .12)),
        ),
        child: entries.isEmpty
            ? _CalendarEmptyDaySummary(dateLabel: dateLabel, onAdd: onAdd)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < entries.length; index++) ...[
                    _CalendarEntrySummary(
                      entry: entries[index],
                      settings: settings,
                      onTap: () => onEdit(entries[index]),
                    ),
                    if (index < entries.length - 1) const Divider(height: 14),
                  ],
                ],
              ),
      ),
    );
  }
}

class _CalendarEmptyDaySummary extends StatelessWidget {
  const _CalendarEmptyDaySummary({
    required this.dateLabel,
    required this.onAdd,
  });

  final String dateLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.edit_calendar_outlined, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Nothing recorded yet',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
    final addButton = FilledButton.tonalIcon(
      onPressed: onAdd,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Add Day'),
    );
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5 ||
        MediaQuery.sizeOf(context).width <= 360) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          details,
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: addButton),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: details),
        const SizedBox(width: 8),
        addButton,
      ],
    );
  }
}

class _CalendarEntrySummary extends StatelessWidget {
  const _CalendarEntrySummary({
    required this.entry,
    required this.settings,
    required this.onTap,
  });

  final WorkEntry entry;
  final AppSettings settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final calculated = WorkCalculator.recalculateEntry(entry);
    final status = _CalendarStatus.fromEntry(calculated);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 34,
              child: Center(
                child: _CalendarStatusMarker(
                  key: ValueKey('calendar-summary-marker-${status.name}'),
                  status: status,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _entryTitle(calculated),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    calculated.entryType == 'WorkDay'
                        ? '${formatHoursLabel(calculated.totalHours)} · ${settings.labelForRate(calculated.rateType)}'
                        : status.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _money(calculated.totalPay),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({
    required this.date,
    required this.entries,
    required this.settings,
    required this.compact,
    required this.inCurrentPayPeriod,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final DateTime date;
  final List<WorkEntry> entries;
  final AppSettings settings;
  final bool compact;
  final bool inCurrentPayPeriod;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final isToday =
        today.year == date.year &&
        today.month == date.month &&
        today.day == date.day;
    final statuses = entries.isEmpty
        ? const [_CalendarStatus.empty]
        : (entries.map(_CalendarStatus.fromEntry).toSet().toList()
            ..sort((left, right) => left.index.compareTo(right.index)));
    final label = entries.isEmpty
        ? 'No entry'
        : statuses
              .map(
                (status) => switch (status) {
                  _CalendarStatus.home => settings.labelForRate('primary'),
                  _CalendarStatus.away => settings.labelForRate('secondary'),
                  _ => status.label,
                },
              )
              .join(', ');
    final primaryStatus = statuses.first;
    final statusColor = primaryStatus.color;
    return Semantics(
      button: true,
      label:
          '${date.day} ${_fullMonthNames[date.month - 1]}, $label${isToday ? ', today' : ''}${selected ? ', selected' : ''}${inCurrentPayPeriod ? ', current pay period' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(BriskaRadii.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: BriskaDurations.standard,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(compact ? 4 : 6),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: .12)
                : entries.isNotEmpty
                ? statusColor.withValues(alpha: .09)
                : isToday
                ? colorScheme.primary.withValues(alpha: .045)
                : inCurrentPayPeriod
                ? colorScheme.primary.withValues(alpha: .025)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(BriskaRadii.md),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : isToday || inCurrentPayPeriod
                  ? colorScheme.primary.withValues(alpha: isToday ? .55 : .2)
                  : Theme.of(context).dividerColor.withValues(alpha: .72),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        date.day.toString(),
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: isToday || selected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontSize: compact ? 10.5 : 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (isToday && !compact)
                    Container(
                      width: compact ? 4 : 5,
                      height: compact ? 4 : 5,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (entries.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final status in statuses.take(3))
                      _CalendarStatusMarker(
                        key: ValueKey(
                          'calendar-cell-marker-${status.name}-${date.day}',
                        ),
                        status: status,
                      ),
                  ],
                )
              else if (inCurrentPayPeriod)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: compact ? 8 : 10,
                    height: 2,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: .65),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CalendarStatus {
  home('Primary rate', BriskaColors.secondary),
  away('Secondary rate', BriskaColors.secondary),
  holiday('Holiday', BriskaColors.calendarHoliday),
  sick('Sick Day', BriskaColors.calendarSickDay),
  unpaid('Unpaid day off', BriskaColors.warning),
  bankHoliday('Bank Holiday', BriskaColors.primary),
  empty('No entry', BriskaColors.calendarEmpty);

  const _CalendarStatus(this.label, this.color);

  final String label;
  final Color color;

  static _CalendarStatus fromEntry(WorkEntry entry) {
    return switch (entry.entryType) {
      'Holiday' => holiday,
      'bankHoliday' || 'BankHoliday' => bankHoliday,
      'SickDay' => sick,
      'UnpaidDayOff' => unpaid,
      _ => entry.rateType == 'secondary' ? away : home,
    };
  }
}

class _CalendarStatusMarker extends StatelessWidget {
  const _CalendarStatusMarker({required this.status, super.key});

  final _CalendarStatus status;

  @override
  Widget build(BuildContext context) {
    final marker = switch (status) {
      _CalendarStatus.home => Container(
        width: 12,
        height: 4,
        decoration: BoxDecoration(
          color: status.color,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      _CalendarStatus.away => Transform.rotate(
        angle: 0.7853981633974483,
        child: Container(width: 8, height: 8, color: status.color),
      ),
      _CalendarStatus.holiday => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
      ),
      _CalendarStatus.sick => Icon(
        Icons.sick_outlined,
        size: 12,
        color: status.color,
      ),
      _CalendarStatus.unpaid => Container(
        width: 8,
        height: 8,
        color: status.color,
      ),
      _CalendarStatus.bankHoliday => Icon(
        Icons.account_balance_rounded,
        size: 12,
        color: status.color,
      ),
      _CalendarStatus.empty => const SizedBox.shrink(),
    };
    return SizedBox(width: 14, height: 12, child: Center(child: marker));
  }
}

class _CalendarDot extends StatelessWidget {
  const _CalendarDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox(width: 5, height: 5),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({
    required this.label,
    this.status,
    this.color,
    this.outlined = false,
  });
  final _CalendarStatus? status;
  final Color? color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 180),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (outlined)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              border: Border.all(color: color!, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
          )
        else if (status != null)
          _CalendarStatusMarker(
            key: ValueKey('calendar-legend-marker-${status!.name}'),
            status: status!,
          )
        else
          _CalendarDot(color: color!),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
