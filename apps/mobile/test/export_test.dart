import 'package:flutter_test/flutter_test.dart';
import 'package:savdoyordam/core/export_file.dart';

void main() {
  test(
    'CSV protects formulas and preserves separators, quotes and line breaks',
    () {
      expect(
        ExportFile.csvCell('=HYPERLINK("url")'),
        '"\'=HYPERLINK(""url"")"',
      );
      expect(ExportFile.csvCell('+998901234567'), '"\'+998901234567"');
      expect(
        ExportFile.csvCell('Rice; "premium"\nkg'),
        '"Rice; ""premium""\nkg"',
      );
      expect(ExportFile.csvCell(-123), '"-123"');
      expect(
        ExportFile.csv([
          ['Name', 'Amount'],
          ['Rice', 100],
        ]),
        '\uFEFF"Name";"Amount"\r\n"Rice";"100"\r\n',
      );
    },
  );
}
