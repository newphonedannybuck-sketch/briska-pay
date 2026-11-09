import 'package:intl/intl.dart';

const defaultCurrencyCode = 'GBP';
const defaultCurrencySymbol = '£';
const defaultCurrency = CurrencyConfig(
  code: defaultCurrencyCode,
  symbol: defaultCurrencySymbol,
  displayName: 'British Pound',
  locale: 'en_GB',
  decimalDigits: 2,
);

class CurrencyConfig {
  const CurrencyConfig({
    required this.code,
    required this.symbol,
    required this.displayName,
    required this.locale,
    required this.decimalDigits,
  });

  final String code;
  final String symbol;
  final String displayName;
  final String locale;
  final int decimalDigits;

  Map<String, Object?> toJson() => {
    'code': code,
    'symbol': symbol,
    'displayName': displayName,
    'locale': locale,
    'decimalDigits': decimalDigits,
  };

  factory CurrencyConfig.fromJson(Map<String, dynamic> json) {
    final code = json['code'] as String? ?? 'GBP';
    return CurrencyCatalog.byCode(code).copyWith(
      symbol: CurrencyCatalog.byCode(code).symbol,
      displayName: json['displayName'] as String?,
      locale: json['locale'] as String?,
      decimalDigits: (json['decimalDigits'] as num?)?.toInt(),
    );
  }

  CurrencyConfig copyWith({
    String? code,
    String? symbol,
    String? displayName,
    String? locale,
    int? decimalDigits,
  }) => CurrencyConfig(
    code: code ?? this.code,
    symbol: symbol ?? this.symbol,
    displayName: displayName ?? this.displayName,
    locale: locale ?? this.locale,
    decimalDigits: decimalDigits ?? this.decimalDigits,
  );
}

abstract final class CurrencyCatalog {
  static const supported = [
    CurrencyConfig(
      code: 'GBP',
      symbol: '£',
      displayName: 'British Pound',
      locale: 'en_GB',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'EUR',
      symbol: '€',
      displayName: 'Euro',
      locale: 'de_DE',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'USD',
      symbol: r'$',
      displayName: 'US Dollar',
      locale: 'en_US',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'CAD',
      symbol: r'$',
      displayName: 'Canadian Dollar',
      locale: 'en_CA',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'AUD',
      symbol: r'$',
      displayName: 'Australian Dollar',
      locale: 'en_AU',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'NZD',
      symbol: r'$',
      displayName: 'New Zealand Dollar',
      locale: 'en_NZ',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'DKK',
      symbol: 'kr',
      displayName: 'Danish Krone',
      locale: 'da_DK',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'NOK',
      symbol: 'kr',
      displayName: 'Norwegian Krone',
      locale: 'nb_NO',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'SEK',
      symbol: 'kr',
      displayName: 'Swedish Krona',
      locale: 'sv_SE',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'CHF',
      symbol: 'Fr',
      displayName: 'Swiss Franc',
      locale: 'de_CH',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'PLN',
      symbol: 'zł',
      displayName: 'Polish Złoty',
      locale: 'pl_PL',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'INR',
      symbol: '₹',
      displayName: 'Indian Rupee',
      locale: 'en_IN',
      decimalDigits: 2,
    ),
    CurrencyConfig(
      code: 'JPY',
      symbol: '¥',
      displayName: 'Japanese Yen',
      locale: 'ja_JP',
      decimalDigits: 0,
    ),
  ];

  static CurrencyConfig byCode(String code) => supported.firstWhere(
    (currency) => currency.code == code.toUpperCase(),
    orElse: () => supported.first,
  );

  static CurrencyConfig fromLocale(String locale) {
    final normalized = locale.replaceAll('-', '_').toUpperCase();
    const countries = {
      'GB': 'GBP',
      'IE': 'EUR',
      'DE': 'EUR',
      'FR': 'EUR',
      'ES': 'EUR',
      'IT': 'EUR',
      'NL': 'EUR',
      'PT': 'EUR',
      'AT': 'EUR',
      'BE': 'EUR',
      'FI': 'EUR',
      'US': 'USD',
      'CA': 'CAD',
      'AU': 'AUD',
      'NZ': 'NZD',
      'DK': 'DKK',
      'NO': 'NOK',
      'SE': 'SEK',
      'CH': 'CHF',
      'PL': 'PLN',
      'IN': 'INR',
      'JP': 'JPY',
    };
    final country = normalized.split('_').last;
    return byCode(countries[country] ?? 'GBP');
  }
}

abstract final class CurrencyFormatter {
  static CurrencyConfig current = defaultCurrency;

  static String format(num amount, [CurrencyConfig? currency]) {
    final config = currency ?? current;
    return NumberFormat.currency(
      locale: config.locale,
      symbol: config.symbol,
      decimalDigits: config.decimalDigits,
    ).format(amount);
  }

  static String compact(num amount, [CurrencyConfig? currency]) {
    final config = currency ?? current;
    final value = NumberFormat.compact(locale: config.locale).format(amount);
    final separator = config.symbol.length > 1 ? ' ' : '';
    return '${config.symbol}$separator$value';
  }

  static String excelNumberFormat(CurrencyConfig currency) {
    final escapedSymbol = currency.symbol.replaceAll('"', '""');
    final decimals = currency.decimalDigits == 0
        ? ''
        : '.${List.filled(currency.decimalDigits, '0').join()}';
    return '"$escapedSymbol"${currency.symbol.length > 1 ? ' ' : ''}#,##0$decimals';
  }
}
