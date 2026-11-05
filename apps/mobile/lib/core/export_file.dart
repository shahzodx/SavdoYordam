import 'dart:convert';

import 'package:flutter/services.dart';

class ExportFile {
  static const channel = MethodChannel('uz.savdoyordam/files');
  static Future<bool> saveJson(Object data, String name) async =>
      await channel.invokeMethod<bool>('save', {
        'name': name,
        'mime': 'application/json',
        'content': const JsonEncoder.withIndent('  ').convert(data),
      }) ??
      false;
  static String csvCell(Object? value) {
    var text = value?.toString() ?? '';
    if (value is! num && RegExp(r'^[\s]*[=+\-@\t\r]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  static String csv(List<List<Object?>> rows) =>
      '\uFEFF${rows.map((row) => row.map(csvCell).join(';')).join('\r\n')}\r\n';
  static Future<bool> saveCsv(List<List<Object?>> rows, String name) async =>
      await channel.invokeMethod<bool>('save', {
        'name': name,
        'mime': 'text/csv',
        'content': csv(rows),
      }) ??
      false;
}
