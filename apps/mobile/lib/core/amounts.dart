/// Parse decimal text exactly. Never convert financial input through double.
int? parseScaled(String input, int decimals) {
  final text = input.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) return null;
  final parts = text.split('.');
  if (parts.length == 2 && parts[1].length > decimals) return null;
  final digits =
      parts[0] + (parts.length == 2 ? parts[1] : '').padRight(decimals, '0');
  return int.tryParse(digits);
}

String grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]} ',
);

int? parseSignedScaled(String input, int decimals) {
  final value = input.trim();
  final negative = value.startsWith('-');
  final parsed = parseScaled(negative ? value.substring(1) : value, decimals);
  return parsed == null ? null : parsed * (negative ? -1 : 1);
}

String money(int amount, String language) {
  final abs = amount.abs();
  final fraction = abs % 100;
  return '${amount < 0 ? '−' : ''}${grouped(abs ~/ 100)}${fraction == 0 ? '' : ',${fraction.toString().padLeft(2, '0')}'} ${language == 'uz' ? "so‘m" : 'сум'}';
}

String quantity(int value) {
  final whole = value.abs() ~/ 1000;
  final fraction = (value.abs() % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${value < 0 ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
}

int lineTotal(int price, int quantity) => (price * quantity + 500) ~/ 1000;
