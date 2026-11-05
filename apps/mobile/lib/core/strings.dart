import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Strings {
  Strings(this.locale, this.values);
  final Locale locale;
  final Map<String, dynamic> values;
  String operator [](String key) =>
      values[key]?.toString() ?? values['server_error'].toString();
  static Strings of(BuildContext context) =>
      Localizations.of<Strings>(context, Strings)!;
  static const delegate = _StringsDelegate();
}

class _StringsDelegate extends LocalizationsDelegate<Strings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) => ['uz', 'ru'].contains(locale.languageCode);
  @override
  Future<Strings> load(Locale locale) async => Strings(
    locale,
    jsonDecode(
      await rootBundle.loadString('lib/l10n/app_${locale.languageCode}.arb'),
    ) as Map<String, dynamic>,
  );
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

extension LocalizedContext on BuildContext {
  Strings get text => Strings.of(this);
}
