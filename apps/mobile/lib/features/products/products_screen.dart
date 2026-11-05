import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/theme.dart';

Future<void> addProduct(BuildContext context, WidgetRef ref) async {
  final p = await appForm(context, 'addProduct', [
    const FieldSpec('name', 'name', section: 'productDetails'),
    FieldSpec(
      'sku',
      'sku',
      initial:
          'P-${const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase()}',
      hint: 'skuHint',
    ),
    const FieldSpec('category', 'productCategory', optional: true),
    const FieldSpec(
      'unit',
      'unit',
      initial: 'piece',
      options: ['piece', 'kg', 'liter'],
    ),
    FieldSpec(
      'price',
      'price',
      section: 'pricing',
      numeric: true,
      validate: (s) => (parseScaled(s, 2) ?? 0) > 0,
    ),
    FieldSpec(
      'cost',
      'cost',
      numeric: true,
      optional: true,
      validate: (s) => parseScaled(s, 2) != null,
    ),
    FieldSpec(
      'stock',
      'stock',
      section: 'inventory',
      initial: '0',
      numeric: true,
      validate: (s) => parseScaled(s, 3) != null,
    ),
    FieldSpec(
      'minimum',
      'minimumStock',
      initial: '0',
      numeric: true,
      validate: (s) => parseScaled(s, 3) != null,
    ),
  ]);
  if (p == null || !context.mounted) return;
  await perform(context, ref, () async {
    await ref.read(repositoryProvider).submit('/products', {
      'name': p['name'],
      'sku': p['sku'],
      'unit': p['unit'],
      'category': p['category'],
      'price': parseScaled(p['price']!, 2),
      'cost': p['cost']!.isEmpty ? null : parseScaled(p['cost']!, 2),
      'stock': parseScaled(p['stock']!, 3),
      'minimum_stock': parseScaled(p['minimum']!, 3),
    });
  });
}

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});
  @override
  ConsumerState<ProductsScreen> createState() => _ProductsState();
}

class _ProductsState extends ConsumerState<ProductsScreen> {
  String query = '', filter = 'all', sort = 'sortName';
  @override
  Widget build(BuildContext context) {
    final s = context.text;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeading(s['products'], subtitle: s['catalogHint']),
              AppSearchField(
                onChanged: (v) =>
                    setState(() => query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in [
                      'all',
                      'lowStock',
                      'outOfStock',
                      'archived',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(s[f]),
                          selected: filter == f,
                          onSelected: (_) => setState(() => filter = f),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.swap_vert, size: 18),
                      label: Text(s[sort]),
                      onPressed: () async {
                        final value = await appForm(context, 'sort', [
                          FieldSpec(
                            'sort',
                            'sort',
                            initial: sort,
                            options: const [
                              'sortName',
                              'sortPrice',
                              'sortStock',
                            ],
                          ),
                        ]);
                        if (value != null && mounted) {
                          setState(() => sort = value['sort']!);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        Expanded(
          child: DataView(
            path: filter == 'archived'
                ? '/products?archived=true'
                : '/products',
            builder: (data) {
              final products = (data as List)
                  .where(
                    (p) =>
                        '${p['name']} ${p['sku']}'.toLowerCase().contains(
                          query,
                        ) &&
                        (filter == 'all' ||
                            (filter == 'archived'
                                ? p['archived'] == true
                                : filter == 'outOfStock'
                                ? p['stock'] == 0
                                : p['stock'] <= p['minimum_stock'])),
                  )
                  .toList();
              products.sort(
                (a, b) => switch (sort) {
                  'sortPrice' => (a['price'] as int).compareTo(
                    b['price'] as int,
                  ),
                  'sortStock' => (a['stock'] as int).compareTo(
                    b['stock'] as int,
                  ),
                  _ => a['name'].toString().toLowerCase().compareTo(
                    b['name'].toString().toLowerCase(),
                  ),
                },
              );
              return RefreshIndicator(
                onRefresh: () async => refreshData(ref),
                child: products.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          EmptyState(
                            icon: query.isEmpty && filter == 'all'
                                ? Icons.inventory_2_outlined
                                : Icons.search_off,
                            title:
                                s[query.isEmpty && filter == 'all'
                                    ? 'empty'
                                    : 'nothingFound'],
                            hint:
                                s[query.isEmpty && filter == 'all'
                                    ? 'emptyHint'
                                    : 'tryAnotherSearch'],
                            action: query.isEmpty && filter == 'all'
                                ? AppButton(
                                    label: s['addProduct'],
                                    onPressed: () => addProduct(context, ref),
                                  )
                                : null,
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                        itemCount: products.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => ProductCard(
                          product: Map<String, dynamic>.from(products[i]),
                          onTap: () => showProduct(
                            context,
                            ref,
                            Map<String, dynamic>.from(products[i]),
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.trailing,
  });
  final Map<String, dynamic> product;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = product;
    final s = context.text;
    final low = p['stock'] <= p['minimum_stock'];
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['name'],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p['sku']} · ${s[p['unit']]}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      money(p['price'], s.locale.languageCode),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          low ? Icons.inventory_2_outlined : Icons.circle,
                          size: low ? 16 : 7,
                          color: low ? amber : brand,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${s[p['stock'] == 0 ? 'outOfStock' : 'stock']}${p['stock'] == 0 ? '' : ': ${quantity(p['stock'])} ${s[p['unit']]}'}',
                            style: TextStyle(
                              color: low ? amber : muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              trailing ??
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.chevron_right_rounded, color: muted),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showProduct(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> p,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            p['name'] as String,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          AppCard(
            color: softBrand,
            child: Column(
              children: [
                SummaryRow(
                  context.text['price'],
                  money(p['price'], context.text.locale.languageCode),
                  strong: true,
                ),
                SummaryRow(
                  context.text['stock'],
                  '${quantity(p['stock'])} ${context.text[p['unit']]}',
                  strong: true,
                ),
                SummaryRow(context.text['sku'], p['sku']),
              ],
            ),
          ),
          if (ref.read(repositoryProvider).offlineEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: NoticeCard(
                context.text['offline_store_locked'],
                warning: true,
              ),
            ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: ref.read(repositoryProvider),
            builder: (context, _) {
              final repo = ref.read(repositoryProvider);
              return OutlinedButton.icon(
                icon: Icon(
                  repo.favorites.contains(p['id'])
                      ? Icons.star
                      : Icons.star_outline_rounded,
                ),
                label: Text(
                  context.text[repo.favorites.contains(p['id'])
                      ? 'removeFavorite'
                      : 'addFavorite'],
                ),
                onPressed: () => repo.toggleFavorite(p['id']),
              );
            },
          ),
          const SizedBox(height: 12),
          if (ref.read(repositoryProvider).isOwner)
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.text['editProduct']),
              onPressed: () async {
                if (ref.read(repositoryProvider).offlineEnabled) {
                  message(context, 'offline_store_locked');
                  return;
                }
                await editProduct(context, ref, p);
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
          const SizedBox(height: 12),
          if (ref.read(repositoryProvider).isOwner)
            AppButton(
              label: context.text['adjustStock'],
              icon: Icons.swap_vert,
              onPressed: () async {
                if (ref.read(repositoryProvider).offlineEnabled) {
                  message(context, 'offline_store_locked');
                  return;
                }
                final v = await appForm(context, 'adjustStock', [
                  const FieldSpec(
                    'direction',
                    'stockDirection',
                    initial: 'stockReceive',
                    options: ['stockReceive', 'stockWriteoff'],
                  ),
                  FieldSpec(
                    'quantity',
                    'quantity',
                    numeric: true,
                    validate: (s) => (parseScaled(s, 3) ?? 0) > 0,
                  ),
                  const FieldSpec('reason', 'reason'),
                ]);
                if (v == null || !context.mounted) return;
                final q =
                    parseScaled(v['quantity']!, 3)! *
                    (v['direction'] == 'stockWriteoff' ? -1 : 1);
                await perform(context, ref, () async {
                  await ref.read(repositoryProvider).submit('/inventory', {
                    'product_id': p['id'],
                    'quantity': q,
                    'reason': v['reason'],
                    'version': p['version'],
                  });
                });
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
          if (ref.read(repositoryProvider).isOwner)
            TextButton.icon(
              icon: const Icon(Icons.archive_outlined),
              label: Text(
                context.text[p['archived'] == true
                    ? 'restoreProduct'
                    : 'archiveProduct'],
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: Text(
                      context.text[p['archived'] == true
                          ? 'restoreProduct'
                          : 'archiveProduct'],
                    ),
                    content: Text(context.text['archiveHint']),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: Text(context.text['cancel']),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: Text(context.text['confirm']),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                await perform(context, ref, () async {
                  await ref.read(repositoryProvider).submit(
                    '/products/${p['id']}',
                    {
                      'name': p['name'],
                      'sku': p['sku'],
                      'price': p['price'],
                      'cost': p['cost'],
                      'minimum_stock': p['minimum_stock'],
                      'version': p['version'],
                      'archived': p['archived'] != true,
                    },
                  );
                });
                if (sheet.mounted) Navigator.pop(sheet);
              },
            ),
          SectionHeading(context.text['inventory']),
          DataView(
            path: '/inventory/${p['id']}',
            builder: (rows) => Column(
              children: (rows as List)
                  .map(
                    (r) => ListTile(
                      title: Text(quantity(r['quantity'] as int)),
                      subtitle: Text(
                        ['opening', 'sale', 'return'].contains(r['reason'])
                            ? context.text[r['reason']]
                            : r['reason'],
                      ),
                      trailing: Text(
                        r['created_at'].toString().substring(0, 10),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> editProduct(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> product,
) async {
  String decimal(int n) =>
      '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
  final p = await appForm(context, 'editProduct', [
    FieldSpec('name', 'name', initial: product['name']),
    FieldSpec('sku', 'sku', initial: product['sku']),
    FieldSpec(
      'category',
      'productCategory',
      initial: product['category'] ?? '',
      optional: true,
    ),
    FieldSpec(
      'price',
      'price',
      initial: decimal(product['price']),
      numeric: true,
      validate: (s) => (parseScaled(s, 2) ?? 0) > 0,
    ),
    FieldSpec(
      'cost',
      'cost',
      initial: product['cost'] == null ? '' : decimal(product['cost']),
      numeric: true,
      optional: true,
      validate: (s) => parseScaled(s, 2) != null,
    ),
    FieldSpec(
      'minimum_stock',
      'minimumStock',
      initial: quantity(product['minimum_stock']),
      numeric: true,
      validate: (s) => parseScaled(s, 3) != null,
    ),
  ]);
  if (p == null || !context.mounted) return;
  await perform(context, ref, () async {
    await ref.read(repositoryProvider).submit('/products/${product['id']}', {
      'name': p['name'],
      'sku': p['sku'],
      'price': parseScaled(p['price']!, 2),
      'cost': p['cost']!.isEmpty ? null : parseScaled(p['cost']!, 2),
      'minimum_stock': parseScaled(p['minimum_stock']!, 3),
      'version': product['version'],
      'category': p['category'],
    });
  });
}
