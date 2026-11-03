part of '../briska_app.dart';

class BetaChecklistScreen extends StatefulWidget {
  const BetaChecklistScreen({super.key});

  @override
  State<BetaChecklistScreen> createState() => _BetaChecklistScreenState();
}

class _BetaChecklistScreenState extends State<BetaChecklistScreen> {
  static const _items = [
    'Onboarding',
    'Home day',
    'Away day',
    'Holiday',
    'Unpaid day',
    'Job uplift',
    'Allowance',
    'Edit entry',
    'Delete entry',
    'Reports',
    'Calendar',
    'Statistics',
    'Excel export',
    'Export Library',
    'Currency formatting',
    'Pay-period calculations',
    'Privacy Policy',
    'Terms of Use',
    'Support page',
    'Banner ads',
    'No crashes',
  ];

  Set<String> _completed = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSelections();
  }

  Future<void> _loadSelections() async {
    final saved = await LocalStorage.loadBetaChecklist();
    if (!mounted) return;
    setState(() {
      _completed = saved.intersection(_items.toSet());
      _loading = false;
    });
  }

  Future<void> _setItem(String item, bool selected) async {
    setState(() {
      selected ? _completed.add(item) : _completed.remove(item);
    });
    await LocalStorage.saveBetaChecklist(_completed);
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _reset() async {
    if (!await _confirm(
      'Reset checklist?',
      'This will clear every completed test.',
    )) {
      return;
    }
    setState(() => _completed.clear());
    await LocalStorage.saveBetaChecklist(_completed);
  }

  Future<void> _markAllComplete() async {
    if (!await _confirm(
      'Mark all complete?',
      'This will mark every test as completed.',
    )) {
      return;
    }
    setState(() => _completed = _items.toSet());
    await LocalStorage.saveBetaChecklist(_completed);
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _completed.length;
    final allComplete = completedCount == _items.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Beta Checklist')),
      body: AppPage(
        topPadding: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$completedCount of ${_items.length} tests completed',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: BriskaSpacing.sm),
                    LinearProgressIndicator(
                      value: _loading ? null : completedCount / _items.length,
                    ),
                    if (allComplete) ...[
                      const SizedBox(height: BriskaSpacing.md),
                      Text(
                        'Briska Pay is ready for release',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: BriskaSpacing.sm,
              runSpacing: BriskaSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset checklist'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _markAllComplete,
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('Mark all complete'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._items.map(
              (item) => Card(
                child: CheckboxListTile(
                  value: _completed.contains(item),
                  onChanged: _loading
                      ? null
                      : (selected) => _setItem(item, selected ?? false),
                  title: Text(item),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

