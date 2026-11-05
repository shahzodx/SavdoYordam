import 'package:flutter/material.dart';

import '../core/strings.dart';

const brand = Color(0xFF087F68);
const ink = Color(0xFF17231F);
const muted = Color(0xFF66756F);
const canvas = Color(0xFFF3F6F4);
const softBrand = Color(0xFFE7F3ED);
const amber = Color(0xFF835713);
const border = Color(0xFFE5ECE8);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSans',
  colorScheme: ColorScheme.fromSeed(
    seedColor: brand,
    surface: Colors.white,
    primary: brand,
    onSurface: ink,
    error: const Color(0xFFB42D2D),
  ),
  scaffoldBackgroundColor: canvas,
  visualDensity: VisualDensity.standard,
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: canvas,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    clipBehavior: Clip.antiAlias,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: Colors.white,
    selectedColor: softBrand,
    side: const BorderSide(color: border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: ink),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -.9,
      color: ink,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -.7,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 52),
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: border),
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: Color(0xFFE8F6F0),
    height: 72,
  ),
  dividerTheme: const DividerThemeData(color: border, space: 1),
);

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = 20,
  });
  final Widget child;
  final Color color;
  final double padding;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: border),
    ),
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: 20),
        if (busy || icon != null) const SizedBox(width: 10),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: 16,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: muted, size: 22),
        const SizedBox(height: 16),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: muted)),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.action,
    this.icon = Icons.inventory_2_outlined,
    this.title,
    this.hint,
  });
  final Widget? action;
  final String? title, hint;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFFE8F6F0),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 32, color: brand),
        ),
        const SizedBox(height: 20),
        Text(
          title ?? context.text['empty'],
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          hint ?? context.text['emptyHint'],
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.warning = false});
  final String label;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF3DC) : const Color(0xFFE8F6F0),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: warning ? const Color(0xFF835713) : brand,
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.label, {super.key, this.action});
  final String label;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?action,
      ],
    ),
  );
}

class AppSearchField extends StatefulWidget {
  const AppSearchField({super.key, required this.onChanged, this.hint});
  final ValueChanged<String> onChanged;
  final String? hint;
  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textInputAction: TextInputAction.search,
    onChanged: (value) {
      setState(() {});
      widget.onChanged(value);
    },
    decoration: InputDecoration(
      hintText: widget.hint ?? context.text['search'],
      prefixIcon: const Icon(Icons.search_rounded, color: muted),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: context.text['clearSearch'],
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                controller.clear();
                setState(() {});
                widget.onChanged('');
              },
            ),
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: const TextStyle(color: muted)),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    ),
  );
}

class SummaryRow extends StatelessWidget {
  const SummaryRow(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.color,
  });
  final String label, value;
  final bool strong;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final style =
            (strong
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(color: color ?? ink);
        if (constraints.maxWidth < 300 &&
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: muted)),
              const SizedBox(height: 4),
              Text(value, style: style),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: strong ? ink : muted)),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(value, textAlign: TextAlign.right, style: style),
            ),
          ],
        );
      },
    ),
  );
}

/// Keeps the primary action visible while the form scrolls above the keyboard.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * .94 -
            MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(
                color: border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: const TextStyle(color: muted)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.text['close'],
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
          if (footer != null) ...[
            const Divider(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                14 + MediaQuery.paddingOf(context).bottom,
              ),
              child: footer!,
            ),
          ],
        ],
      ),
    ),
  );
}

class NoticeCard extends StatelessWidget {
  const NoticeCard(this.text, {super.key, this.warning = false, this.icon});
  final String text;
  final bool warning;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF3DC) : softBrand,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon ?? (warning ? Icons.info_outline : Icons.check_circle_outline),
          color: warning ? amber : brand,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(color: warning ? amber : brand)),
        ),
      ],
    ),
  );
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.text['loading'],
    child: ExcludeSemantics(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    padding: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: .62,
                          child: Container(
                            height: 14,
                            decoration: BoxDecoration(
                              color: border,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FractionallySizedBox(
                          widthFactor: .38,
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: canvas,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
