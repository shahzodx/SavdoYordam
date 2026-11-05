import 'package:flutter/material.dart';

import '../core/strings.dart';
import 'theme.dart';

Future<Map<String, dynamic>?> chooseRecord(
  BuildContext context,
  String title,
  List records, {
  String nameKey = 'name',
}) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) =>
      _RecordPicker(title: title, records: records, nameKey: nameKey),
);

class _RecordPicker extends StatefulWidget {
  const _RecordPicker({
    required this.title,
    required this.records,
    required this.nameKey,
  });
  final String title, nameKey;
  final List records;
  @override
  State<_RecordPicker> createState() => _RecordPickerState();
}

class _RecordPickerState extends State<_RecordPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.records
        .where(
          (r) => r[widget.nameKey].toString().toLowerCase().contains(query),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.text[widget.title],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.text['close'],
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: AppSearchField(
                hint: context.text['search'],
                onChanged: (v) =>
                    setState(() => query = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(context.text['nothingFound']))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(rows[i][widget.nameKey]),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(
                          context,
                          Map<String, dynamic>.from(rows[i]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
