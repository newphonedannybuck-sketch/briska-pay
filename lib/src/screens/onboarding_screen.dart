part of '../briska_app.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.initialSettings,
    required this.onComplete,
    super.key,
  });

  final AppSettings initialSettings;
  final ValueChanged<AppSettings> onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _name;
  late final TextEditingController _companyName;
  late final TextEditingController _primaryRateLabel;
  late final TextEditingController _homeRate;
  late final TextEditingController _secondaryRateLabel;
  late final TextEditingController _awayRate;
  late final FocusNode _nameFocus;
  late final FocusNode _companyFocus;
  late final FocusNode _primaryLabelFocus;
  late final FocusNode _homeRateFocus;
  late final FocusNode _secondaryLabelFocus;
  late final FocusNode _awayRateFocus;
  late String _frequency;
  late String _payDay;
  late String _payPeriodAnchorDate;
  late CurrencyConfig _currency;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    _name = TextEditingController(text: settings.fullName);
    _companyName = TextEditingController(text: settings.companyName);
    _primaryRateLabel = TextEditingController(text: settings.primaryRateLabel);
    _homeRate = TextEditingController(
      text: _currencyInputValue(settings.primaryRateValue),
    );
    _awayRate = TextEditingController(
      text: _currencyInputValue(settings.secondaryRateValue),
    );
    _secondaryRateLabel = TextEditingController(
      text: settings.secondaryRateLabel,
    );
    _nameFocus = FocusNode();
    _companyFocus = FocusNode();
    _primaryLabelFocus = FocusNode();
    _homeRateFocus = FocusNode();
    _secondaryLabelFocus = FocusNode();
    _awayRateFocus = FocusNode();
    _frequency = normalisePayFrequency(settings.payFrequency);
    _payDay = settings.payDay;
    _payPeriodAnchorDate = settings.payPeriodAnchorDate;
    _currency = settings.onboardingCompleted
        ? settings.currency
        : CurrencyCatalog.fromLocale(
            WidgetsBinding.instance.platformDispatcher.locale.toString(),
          );
  }

  @override
  void dispose() {
    _name.dispose();
    _companyName.dispose();
    _primaryRateLabel.dispose();
    _homeRate.dispose();
    _awayRate.dispose();
    _secondaryRateLabel.dispose();
    _nameFocus.dispose();
    _companyFocus.dispose();
    _primaryLabelFocus.dispose();
    _homeRateFocus.dispose();
    _secondaryLabelFocus.dispose();
    _awayRateFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const BriskaLogo(),
            const SizedBox(height: 24),
            Text(
              'Welcome to Briska Pay',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Set up your pay details once. You can change them later in Settings.',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Full name'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _companyFocus.requestFocus(),
                      decoration: const InputDecoration(
                        hintText: 'Enter your full name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Employer / company'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _companyName,
                      focusNode: _companyFocus,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _primaryLabelFocus.requestFocus(),
                      decoration: const InputDecoration(
                        hintText: 'Enter employer or company name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Currency'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _currency.code,
                      items: CurrencyCatalog.supported
                          .map(
                            (currency) => DropdownMenuItem(
                              value: currency.code,
                              child: Text(
                                '${currency.displayName} · ${currency.code} · ${currency.symbol}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (code) => setState(
                        () => _currency = CurrencyCatalog.byCode(code!),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Primary rate name'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _primaryRateLabel,
                      focusNode: _primaryLabelFocus,
                      maxLength: 24,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _homeRateFocus.requestFocus(),
                      decoration: const InputDecoration(hintText: 'Standard'),
                    ),
                    const SizedBox(height: 16),
                    _CurrencyControllerField(
                      label: 'Primary hourly rate',
                      hintText: 'e.g. 20.00',
                      controller: _homeRate,
                      focusNode: _homeRateFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _secondaryLabelFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Secondary rate name'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _secondaryRateLabel,
                      focusNode: _secondaryLabelFocus,
                      maxLength: 24,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _awayRateFocus.requestFocus(),
                      decoration: const InputDecoration(hintText: 'Overtime'),
                    ),
                    const SizedBox(height: 16),
                    _CurrencyControllerField(
                      label: 'Secondary hourly rate',
                      hintText: 'e.g. 25.00',
                      controller: _awayRate,
                      focusNode: _awayRateFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _awayRateFocus.unfocus(),
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Pay period type'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _frequency,
                      items:
                          const [
                                weeklyPayFrequency,
                                fortnightlyPayFrequency,
                                fourWeeklyPayFrequency,
                                calendarMonthlyPayFrequency,
                                customMonthlyPayFrequency,
                                lastFridayPayFrequency,
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                      onChanged: (value) => setState(() => _frequency = value!),
                    ),
                    const SizedBox(height: 16),
                    if (fixedCyclePayFrequencies.contains(_frequency)) ...[
                      const FieldLabel('Known pay period start date'),
                      const SizedBox(height: 8),
                      _DatePickerTile(
                        value: _onboardingDateLabel(_payPeriodAnchorDate),
                        isMissing: _payPeriodAnchorDate.isEmpty,
                        onPressed: _choosePayPeriodAnchorDate,
                      ),
                    ] else if (_frequency == calendarMonthlyPayFrequency)
                      const Text(
                        'Period runs from the first to the last day of each month. You can set a separate payday rule in Settings.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      )
                    else if (_frequency == customMonthlyPayFrequency)
                      const Text(
                        'Custom monthly periods can be tailored in Settings after setup.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      )
                    else if (_frequency == lastFridayPayFrequency)
                      const Text(
                        'Period starts on the first Monday after the previous month\'s last Friday. Payday is the current month\'s last Friday.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            BriskaPrimaryButton(
              onPressed: _finish,
              label: 'Start Using Briska Pay',
            ),
          ],
        ),
      ),
    );
  }

  void _finish() {
    final name = _name.text.trim();
    final companyName = _companyName.text.trim();
    final primaryLabel = _primaryRateLabel.text.trim();
    final secondaryLabel = _secondaryRateLabel.text.trim();
    final home = double.tryParse(_homeRate.text);
    final away = double.tryParse(_awayRate.text);
    if (name.isEmpty ||
        primaryLabel.isEmpty ||
        secondaryLabel.isEmpty ||
        home == null ||
        away == null ||
        home < 0 ||
        away < 0) {
      setState(() => _error = 'Complete all fields with valid values.');
      return;
    }
    if (fixedCyclePayFrequencies.contains(_frequency) &&
        _payPeriodAnchorDate.isEmpty) {
      setState(
        () =>
            _error = 'Choose a known pay period start date for this schedule.',
      );
      return;
    }
    widget.onComplete(
      widget.initialSettings.copyWith(
        fullName: name,
        companyName: companyName,
        onboardingCompleted: true,
        primaryRateLabel: primaryLabel,
        primaryRateValue: home,
        secondaryRateLabel: secondaryLabel,
        secondaryRateValue: away,
        payFrequency: _frequency,
        payDay: _payDay,
        payPeriodAnchorDate: _payPeriodAnchorDate,
        payScheduleAnchorPrompted: _payPeriodAnchorDate.isNotEmpty,
        currency: _currency,
      ),
    );
  }

  Future<void> _choosePayPeriodAnchorDate() async {
    final initialDate =
        DateTime.tryParse(_payPeriodAnchorDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      String two(int value) => value.toString().padLeft(2, '0');
      _payPeriodAnchorDate =
          '${picked.year}-${two(picked.month)}-${two(picked.day)}';
    });
  }

  String _onboardingDateLabel(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return 'Choose date';
    return formatFullDate(date);
  }
}

class _CurrencyControllerField extends StatefulWidget {
  const _CurrencyControllerField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_CurrencyControllerField> createState() =>
      _CurrencyControllerFieldState();
}

class _CurrencyControllerFieldState extends State<_CurrencyControllerField> {
  bool _selectedForFocus = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _selectedForFocus = false;
      return;
    }
    if (_selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        duration: BriskaDurations.standard,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(widget.label),
      const SizedBox(height: 8),
      TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          prefixText: _currencyPrefix,
          hintText: widget.hintText,
        ),
      ),
    ],
  );
}

