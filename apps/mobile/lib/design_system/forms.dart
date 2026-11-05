import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/strings.dart';
import 'theme.dart';

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.optional = false,
    this.numeric = false,
    this.signed = false,
    this.date = false,
    this.phone = false,
    this.secret = false,
    this.section,
    this.hint,
    this.literalLabel,
    this.options,
    this.validate,
  });
  final String key, label, initial;
  final String? section, hint, literalLabel;
  final bool optional, numeric, signed, date, phone, secret;
  final List<String>? options;
  final bool Function(String)? validate;
}

Future<Map<String, String>?> appForm(
  BuildContext context,
  String title,
  List<FieldSpec> fields, {
  String? note,
  String? confirm,
}) => showModalBottomSheet<Map<String, String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: canvas,
  builder: (context) =>
      _Form(title: title, fields: fields, note: note, confirm: confirm),
);

class _Form extends StatefulWidget {
  const _Form({
    required this.title,
    required this.fields,
    this.note,
    this.confirm,
  });
  final String title;
  final List<FieldSpec> fields;
  final String? note, confirm;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final formKey = GlobalKey<FormState>();
  late final controls = {
    for (final f in widget.fields)
      f.key: TextEditingController(
        text: f.initial.isEmpty && f.options != null
            ? f.options!.first
            : f.initial,
      ),
  };
  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void submit() {
    if (formKey.currentState!.validate()) {
      formKey.currentState!.save();
      Navigator.pop(context, {
        for (final e in controls.entries) e.key: e.value.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppSheet(
    title: context.text[widget.title],
    footer: AppButton(
      label: widget.confirm ?? context.text['save'],
      onPressed: submit,
    ),
    child: Form(
      key: formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.note != null) ...[
            NoticeCard(widget.note!, icon: Icons.info_outline),
            const SizedBox(height: 20),
          ],
          for (final (index, f) in widget.fields.indexed) ...[
            if (f.section != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14, top: 4),
                child: Text(
                  context.text[f.section!],
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: f.options != null
                  ? DropdownButtonFormField<String>(
                      initialValue: controls[f.key]!.text,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: f.literalLabel ?? context.text[f.label],
                      ),
                      items: f.options!
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(context.text[v]),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => controls[f.key]!.text = v ?? '',
                    )
                  : TextFormField(
                      key: ValueKey('field-${f.key}'),
                      controller: controls[f.key],
                      decoration: InputDecoration(
                        labelText: f.literalLabel ?? context.text[f.label],
                        helperText: f.hint == null
                            ? null
                            : context.text[f.hint!],
                        helperMaxLines: 3,
                        counterText: '',
                        suffixIcon: f.date
                            ? const Icon(Icons.calendar_today_outlined)
                            : null,
                      ),
                      readOnly: f.date,
                      obscureText: f.secret,
                      enableSuggestions: !f.secret,
                      autocorrect: !f.secret,
                      onTap: !f.date
                          ? null
                          : () async {
                              final now = DateTime.now();
                              final selected = await showDatePicker(
                                context: context,
                                initialDate:
                                    DateTime.tryParse(controls[f.key]!.text) ??
                                    now,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(now.year + 1, 12, 31),
                              );
                              if (selected != null) {
                                controls[f.key]!.text = DateFormat('yyyy-MM-dd')
                                    .format(selected);
                              }
                            },
                      keyboardType: f.phone
                          ? TextInputType.phone
                          : f.numeric
                          ? TextInputType.numberWithOptions(
                              decimal: true,
                              signed: f.signed,
                            )
                          : TextInputType.text,
                      textCapitalization: f.numeric || f.phone
                          ? TextCapitalization.none
                          : TextCapitalization.sentences,
                      textInputAction: index == widget.fields.length - 1
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onFieldSubmitted: (_) {
                        if (index == widget.fields.length - 1) submit();
                      },
                      maxLength: f.numeric ? 18 : 160,
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty) {
                          return f.optional
                              ? null
                              : context.text['fieldRequired'];
                        }
                        return f.validate != null && !f.validate!(text)
                            ? context.text[f.numeric
                                  ? 'validNumber'
                                  : 'validRequired']
                            : null;
                      },
                    ),
            ),
          ],
        ],
      ),
    ),
  );
}
