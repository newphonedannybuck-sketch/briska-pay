part of '../briska_app.dart';

class EntriesScreen extends StatefulWidget {
  const EntriesScreen({
    required this.entries,
    required this.settings,
    required this.onEdit,
    required this.onAddDate,
    required this.onDelete,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;
  final ValueChanged<WorkEntry> onEdit;
  final ValueChanged<DateTime> onAddDate;
  final ValueChanged<WorkEntry> onDelete;

  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  String _query = '';
  String _rateType = 'All';
  String _entryType = 'All';
  String _month = 'All';
  bool _oldestFirst = false;

  @override
  Widget build(BuildContext context) {
    final monthOptions =
        widget.entries
            .map(
              (entry) =>
                  '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}',
            )
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (_month != 'All' && !monthOptions.contains(_month)) _month = 'All';
    final filtered =
        widget.entries.where((entry) {
          final query = _query.trim().toLowerCase();
          final searchText = [
            _entryTitle(entry),
            entry.notes,
            widget.settings.labelForRate(entry.rateType),
          ].join(' ').toLowerCase();
          final matchesQuery = query.isEmpty || searchText.contains(query);
          final matchesLocation =
              _rateType == 'All' || entry.rateType == _rateType;
          final matchesEntryType =
              _entryType == 'All' || entry.entryType == _entryType;
          final key =
              '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}';
          final matchesMonth = _month == 'All' || key == _month;
          return matchesQuery &&
              matchesLocation &&
              matchesEntryType &&
              matchesMonth;
        }).toList()..sort(
          (a, b) => _oldestFirst
              ? a.date.compareTo(b.date)
              : b.date.compareTo(a.date),
        );
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Entries',
            subtitle: 'Your recorded days and earnings.',
          ),
          const SizedBox(height: 20),
          MonthlyCalendarSection(
            entries: widget.entries,
            settings: widget.settings,
            onEditEntry: widget.onEdit,
            onAddDate: widget.onAddDate,
          ),
          const SizedBox(height: 24),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search site/job name',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'All',
                  label: const Text(
                    'All Rates',
                    key: Key('entries-filter-all'),
                  ),
                ),
                ButtonSegment(
                  value: 'primary',
                  label: Text(
                    widget.settings.labelForRate('primary'),
                    key: const Key('entries-filter-primary'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'secondary',
                  label: Text(
                    widget.settings.labelForRate('secondary'),
                    key: const Key('entries-filter-secondary'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {_rateType},
              onSelectionChanged: (value) =>
                  setState(() => _rateType = value.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _entryType,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category_outlined),
              labelText: 'Entry type',
            ),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All')),
              DropdownMenuItem(value: 'WorkDay', child: Text('Work Days')),
              DropdownMenuItem(value: 'Holiday', child: Text('Holidays')),
              DropdownMenuItem(
                value: 'bankHoliday',
                child: Text('Bank Holidays'),
              ),
              DropdownMenuItem(value: 'SickDay', child: Text('Sick Days')),
              DropdownMenuItem(
                value: 'UnpaidDayOff',
                child: Text('Unpaid Days Off'),
              ),
            ],
            onChanged: (value) => setState(() => _entryType = value!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_month),
                  isExpanded: true,
                  initialValue: _month,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text('All months'),
                    ),
                    ...monthOptions.map((key) {
                      final parts = key.split('-');
                      final year = int.parse(parts[0]);
                      final month = int.parse(parts[1]);
                      return DropdownMenuItem(
                        value: key,
                        child: Text(formatMonthYear(DateTime(year, month))),
                      );
                    }),
                  ],
                  onChanged: (value) => setState(() => _month = value!),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                onPressed: () => setState(() => _oldestFirst = !_oldestFirst),
                tooltip: _oldestFirst ? 'Oldest first' : 'Newest first',
                icon: Icon(
                  _oldestFirst
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All saved work',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${filtered.length} '
                          '${filtered.length == 1 ? 'Day recorded' : 'Days recorded'} - '
                          '${formatHours(WorkCalculator.summarize(filtered).totalHours)} hours',
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const EmptyWorkState()
          else
            ...filtered.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: WorkEntryCard(
                  entry: entry,
                  settings: widget.settings,
                  onEdit: () => widget.onEdit(entry),
                  onDelete: () => widget.onDelete(entry),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
