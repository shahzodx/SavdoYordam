import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/amounts.dart';
import '../../core/repository.dart';
import '../../core/catalog_provider.dart';
import '../../core/strings.dart';
import '../../design_system/data_view.dart';
import '../../design_system/forms.dart';
import '../../design_system/theme.dart';
import '../products/products_screen.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, this.onCredit = false});
  final bool onCredit;
  @override
  ConsumerState<PosScreen> createState() => _PosState();
}

class _PosState extends ConsumerState<PosScreen> {
  List<Map<String, dynamic>> cart = [];
  String query = '';
  bool showCart = false;
  String category = '', catalogMode = 'all';
  bool busy = false, restored = false;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final repo = ref.read(repositoryProvider);
    final value = await repo.db.cached('${repo.namespace}:cart');
    if (mounted) {
      setState(() {
        cart = value is List
            ? value.map((v) => Map<String, dynamic>.from(v as Map)).toList()
            : [];
        restored = true;
      });
    }
  }

  Future<void> saveCart() async {
    final repo = ref.read(repositoryProvider);
    await repo.db.cache('${repo.namespace}:cart', cart);
  }

  int get total => cart.fold(
    0,
    (v, p) =>
        v +
        lineTotal(p['price'] as int, p['quantity'] as int) -
        (p['discount'] as int? ?? 0),
  );
  Future<void> add(Map<String, dynamic> p) async {
    int q = 1000;
    if (p['unit'] != 'piece') {
      final value = await appForm(context, 'quantity', [
        FieldSpec(
          'quantity',
          'quantity',
          initial: '1',
          numeric: true,
          validate: (s) => (parseScaled(s, 3) ?? 0) > 0,
        ),
      ], confirm: context.text['addToCart']);
      if (value == null) return;
      q = parseScaled(value['quantity']!, 3)!;
    }
    final index = cart.indexWhere((e) => e['id'] == p['id']);
    final existing = index < 0 ? 0 : cart[index]['quantity'] as int;
    if (existing + q > (p['stock'] as int)) {
      if (mounted) message(context, 'insufficient_stock');
      return;
    }
    setState(() {
      if (index < 0) {
        cart.add({...p, 'quantity': q});
      } else {
        cart[index]['quantity'] = existing + q;
      }
    });
    await saveCart();
    HapticFeedback.selectionClick();
  }

  Future<void> checkout() async {
    final repo = ref.read(repositoryProvider);
    if (repo.saleBlocked) {
      message(context, 'pending_operations');
      return;
    }
    setState(() => busy = true);
    try {
      final customers = await repo.fetch('/customers', paginated: true) as List;
      if (!mounted) return;
      setState(() => busy = false);
      final payment = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => CheckoutSheet(
          total: total,
          customers: customers,
          onCredit: widget.onCredit,
        ),
      );
      if (payment == null || !mounted) return;
      setState(() => busy = true);
      final payload = {
        ...payment,
        'items': cart
            .map(
              (p) => {
                'product_id': p['id'],
                'quantity': p['quantity'],
                'expected_price': p['price'],
                if ((p['discount'] ?? 0) > 0) 'discount': p['discount'],
              },
            )
            .toList(),
      };
      final result = await repo.submit('/sales', payload);
      await repo.rememberProducts(payload['items'] as List);
      cart = [];
      await saveCart();
      refreshData(ref);
      HapticFeedback.mediumImpact();
      if (mounted) {
        message(
          context,
          result['queued'] == true ? 'offlineSaleQueued' : 'saleSaved',
        );
        context.pop();
      }
    } on OperationFailure catch (e) {
      if (repo.saleBlocked) {
        cart = [];
        await saveCart();
      }
      if (mounted) message(context, e.code);
    } catch (_) {
      if (mounted) message(context, 'server_error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editQuantity(Map<String, dynamic> p) async {
    final value = await appForm(
      context,
      'quantity',
      [
        FieldSpec(
          'quantity',
          'quantity',
          initial: quantity(p['quantity']),
          numeric: true,
          validate: (s) {
            final n = parseScaled(s, 3);
            return n != null &&
                n > 0 &&
                n <= p['stock'] &&
                (p['unit'] != 'piece' || n % 1000 == 0);
          },
        ),
      ],
      note:
          '${p['name']} · ${context.text['stock']}: ${quantity(p['stock'])} ${context.text[p['unit']]}',
    );
    if (value == null || !mounted) return;
    setState(() {
      p['quantity'] = parseScaled(value['quantity']!, 3)!;
      if ((p['discount'] ?? 0) >= lineTotal(p['price'], p['quantity'])) {
        p['discount'] = 0;
      }
    });
    await saveCart();
  }

  Future<void> changeQuantity(Map<String, dynamic> p, int delta) async {
    final next = (p['quantity'] as int) + delta;
    if (next > p['stock']) {
      message(context, 'insufficient_stock');
      return;
    }
    setState(() {
      if (next <= 0) {
        cart.remove(p);
      } else {
        p['quantity'] = next;
        if ((p['discount'] ?? 0) >= lineTotal(p['price'], next)) {
          p['discount'] = 0;
        }
      }
    });
    await saveCart();
  }

  Future<void> clearCart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.text['clearCart']),
        content: Text(context.text['clearCartHint']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.text['cancel']),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.text['clearCart']),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(cart.clear);
    await saveCart();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final s = context.text;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(s['newSale']),
          leading: IconButton(
            tooltip: s['close'],
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            if (cart.isNotEmpty)
              IconButton(
                tooltip: s['clearCart'],
                onPressed: busy ? null : clearCart,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (repo.saleBlocked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: NoticeCard(s['pending_operations'], warning: true),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(s['products']),
                        icon: const Icon(Icons.grid_view_rounded),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('${s['cart']} · ${cart.length}'),
                        icon: const Icon(Icons.shopping_bag_outlined),
                      ),
                    ],
                    selected: {showCart},
                    onSelectionChanged: (v) =>
                        setState(() => showCart = v.first),
                  ),
                ),
              ),
              if (!showCart)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: AppSearchField(
                    onChanged: (v) =>
                        setState(() => query = v.trim().toLowerCase()),
                  ),
                ),
              Expanded(
                child: showCart
                    ? (cart.isEmpty
                          ? SingleChildScrollView(
                              child: EmptyState(
                                icon: Icons.shopping_bag_outlined,
                                title: s['cartEmpty'],
                                hint: s['cartEmptyHint'],
                                action: AppButton(
                                  label: s['chooseProducts'],
                                  onPressed: () =>
                                      setState(() => showCart = false),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              itemCount: cart.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final p = cart[i];
                                return AppCard(
                                  padding: 16,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p['name'],
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: s['remove'],
                                            onPressed: busy
                                                ? null
                                                : () async {
                                                    setState(
                                                      () => cart.remove(p),
                                                    );
                                                    await saveCart();
                                                  },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '${money(p['price'], repo.language)} / ${s[p['unit']]}',
                                        style: const TextStyle(color: muted),
                                      ),
                                      const SizedBox(height: 14),
                                      if (repo.isOwner)
                                        TextButton.icon(
                                          icon: const Icon(
                                            Icons.percent_rounded,
                                            size: 18,
                                          ),
                                          label: Text(
                                            (p['discount'] ?? 0) > 0
                                                ? '${s['discount']}: ${money(p['discount'], repo.language)}'
                                                : s['addDiscount'],
                                          ),
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  final value = await appForm(
                                                    context,
                                                    'discount',
                                                    [
                                                      FieldSpec(
                                                        'discount',
                                                        'discountAmount',
                                                        initial:
                                                            '${(p['discount'] ?? 0) ~/ 100}',
                                                        numeric: true,
                                                        validate: (v) {
                                                          final d = parseScaled(
                                                            v,
                                                            2,
                                                          );
                                                          return d != null &&
                                                              d >= 0 &&
                                                              d <
                                                                  lineTotal(
                                                                    p['price'],
                                                                    p['quantity'],
                                                                  );
                                                        },
                                                      ),
                                                    ],
                                                  );
                                                  if (value == null ||
                                                      !mounted) {
                                                    return;
                                                  }
                                                  setState(
                                                    () => p['discount'] =
                                                        parseScaled(
                                                          value['discount']!,
                                                          2,
                                                        ),
                                                  );
                                                  await saveCart();
                                                },
                                        ),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          _QuantityControl(
                                            value: quantity(p['quantity']),
                                            onMinus: busy
                                                ? null
                                                : () => p['unit'] == 'piece'
                                                      ? changeQuantity(p, -1000)
                                                      : editQuantity(p),
                                            onPlus: busy
                                                ? null
                                                : () => p['unit'] == 'piece'
                                                      ? changeQuantity(p, 1000)
                                                      : editQuantity(p),
                                            onEdit: busy
                                                ? null
                                                : () => editQuantity(p),
                                          ),
                                          Text(
                                            money(
                                              lineTotal(
                                                    p['price'],
                                                    p['quantity'],
                                                  ) -
                                                  (p['discount'] as int? ?? 0),
                                              repo.language,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ))
                    : DataView(
                        path: '/products',
                        builder: (data) {
                          final categories =
                              (data as List)
                                  .map((p) => p['category']?.toString() ?? '')
                                  .where((c) => c.isNotEmpty)
                                  .toSet()
                                  .toList()
                                ..sort();
                          return Column(
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  12,
                                ),
                                child: Row(
                                  children: [
                                    for (final mode in [
                                      'all',
                                      'favorites',
                                      'recent',
                                    ])
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(s[mode]),
                                          selected:
                                              catalogMode == mode &&
                                              category.isEmpty,
                                          onSelected: (_) => setState(() {
                                            catalogMode = mode;
                                            category = '';
                                          }),
                                        ),
                                      ),
                                    for (final c in categories)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(c),
                                          selected: category == c,
                                          onSelected: (_) => setState(() {
                                            category = c;
                                            catalogMode = 'all';
                                          }),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _IndexedProducts(
                                  query: query,
                                  category: category,
                                  ids: catalogMode == 'favorites'
                                      ? (repo.favorites.isEmpty
                                            ? '-'
                                            : repo.favorites.join(','))
                                      : catalogMode == 'recent'
                                      ? (repo.recentProducts.isEmpty
                                            ? '-'
                                            : repo.recentProducts.join(','))
                                      : '',
                                  itemBuilder: (context, p) {
                                    final selected = cart
                                        .where((e) => e['id'] == p['id'])
                                        .firstOrNull;
                                    final enabled =
                                        !busy &&
                                        restored &&
                                        !repo.saleBlocked &&
                                        p['stock'] > 0;
                                    return ProductCard(
                                      product: p,
                                      onTap: enabled ? () => add(p) : null,
                                      trailing: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton.filledTonal(
                                            tooltip: s['addToCart'],
                                            onPressed: enabled
                                                ? () => add(p)
                                                : null,
                                            icon: const Icon(Icons.add),
                                          ),
                                          if (selected != null)
                                            Text(
                                              '${quantity(selected['quantity'])} ${s[p['unit']]}',
                                              style: const TextStyle(
                                                color: brand,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: border)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () =>
                                setState(() => showCart = !showCart),
                            icon: const Icon(Icons.shopping_bag_outlined),
                            label: Text('${s['cart']} · ${cart.length}'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                s['total'],
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                money(total, repo.language),
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AppButton(
                      label: s['checkout'],
                      busy: busy,
                      icon: Icons.arrow_forward_rounded,
                      onPressed: cart.isEmpty || repo.saleBlocked
                          ? null
                          : checkout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.value,
    this.onMinus,
    this.onPlus,
    this.onEdit,
  });
  final String value;
  final VoidCallback? onMinus, onPlus, onEdit;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: canvas,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.text['decreaseQuantity'],
          onPressed: onMinus,
          icon: const Icon(Icons.remove, size: 20),
        ),
        TextButton(
          onPressed: onEdit,
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, color: ink),
          ),
        ),
        IconButton(
          tooltip: context.text['increaseQuantity'],
          onPressed: onPlus,
          icon: const Icon(Icons.add, size: 20),
        ),
      ],
    ),
  );
}

class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({
    super.key,
    required this.total,
    required this.customers,
    this.onCredit = false,
  });
  final bool onCredit;
  final int total;
  final List customers;
  @override
  State<CheckoutSheet> createState() => _CheckoutState();
}

class _CheckoutState extends State<CheckoutSheet> {
  late final paid = TextEditingController(
    text: widget.onCredit ? '0' : _decimal(widget.total),
  );
  String method = 'cash';
  Map<String, dynamic>? customer;
  String _decimal(int value) =>
      '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
  @override
  void dispose() {
    paid.dispose();
    super.dispose();
  }

  Future<void> chooseCustomer() async {
    final value = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CustomerPicker(customers: widget.customers),
    );
    if (value == null || !mounted) return;
    setState(() => customer = value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.text;
    final amount = parseScaled(paid.text, 2);
    final validAmount = amount != null && amount <= widget.total;
    final debt = validAmount ? widget.total - amount : 0;
    final needsCustomer = debt > 0 && customer == null;
    return AppSheet(
      title: s['reviewSale'],
      subtitle: s['checkoutHint'],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (needsCustomer || !validAmount) ...[
            Text(
              s[needsCustomer ? 'customer_required' : 'paymentAmountHint'],
              style: const TextStyle(color: amber),
            ),
            const SizedBox(height: 10),
          ],
          AppButton(
            label: s['confirmSale'],
            icon: Icons.check_rounded,
            onPressed: !validAmount || needsCustomer
                ? null
                : () => Navigator.pop(context, {
                    'paid': amount,
                    'method': method,
                    'customer_id': customer?['id'],
                  }),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            color: softBrand,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['total'], style: const TextStyle(color: brand)),
                const SizedBox(height: 6),
                Text(
                  money(widget.total, s.locale.languageCode),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: brand),
                ),
              ],
            ),
          ),
          SectionHeading(s['payment']),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: Text(s['paidInFull']),
                selected: amount == widget.total,
                onSelected: (_) =>
                    setState(() => paid.text = _decimal(widget.total)),
              ),
              ChoiceChip(
                label: Text(s['onCredit']),
                selected: amount == 0,
                onSelected: (_) => setState(() => paid.text = '0'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('checkout-paid'),
            controller: paid,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: s['paid'],
              helperText: s['partialPaymentHint'],
              helperMaxLines: 3,
              errorText: amount != null && amount > widget.total
                  ? s['paymentAmountHint']
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'cash',
                label: Text(s['cash']),
                icon: const Icon(Icons.payments_outlined),
              ),
              ButtonSegment(
                value: 'card',
                label: Text(s['card']),
                icon: const Icon(Icons.credit_card),
              ),
            ],
            selected: {method},
            onSelectionChanged: (v) => setState(() => method = v.first),
          ),
          SectionHeading(s['customer']),
          AppCard(
            padding: 4,
            child: ListTile(
              key: const ValueKey('checkout-customer'),
              leading: const CircleAvatar(
                backgroundColor: softBrand,
                child: Icon(Icons.person_outline, color: brand),
              ),
              title: Text(customer?['name'] ?? s['chooseCustomer']),
              subtitle: Text(
                s[debt > 0 ? 'requiredForDebt' : 'optionalForSale'],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: chooseCustomer,
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: 16,
            child: Column(
              children: [
                SummaryRow(
                  s['received'],
                  money(validAmount ? amount : 0, s.locale.languageCode),
                ),
                const Divider(),
                SummaryRow(
                  s['debtRemaining'],
                  money(debt, s.locale.languageCode),
                  strong: true,
                  color: debt > 0 ? amber : brand,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.customers});
  final List customers;
  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final s = context.text;
    final rows = widget.customers
        .where(
          (c) =>
              '${c['name']} ${c['phone'] ?? ''}'.toLowerCase().contains(query),
        )
        .toList();
    return AppSheet(
      title: s['chooseCustomer'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            hint: s['searchCustomers'],
            onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: Text(s['anonymous']),
            onTap: () => Navigator.pop(context, <String, dynamic>{}),
          ),
          const Divider(),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(s['nothingFound'], textAlign: TextAlign.center),
            ),
          for (final c in rows)
            ListTile(
              title: Text(c['name']),
              subtitle: (c['phone'] ?? '').isEmpty ? null : Text(c['phone']),
              leading: const Icon(Icons.person_outline),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, Map<String, dynamic>.from(c)),
            ),
        ],
      ),
    );
  }
}

class _IndexedProducts extends ConsumerStatefulWidget {
  const _IndexedProducts({
    required this.query,
    required this.category,
    required this.ids,
    required this.itemBuilder,
  });
  final String query, category, ids;
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;
  @override
  ConsumerState<_IndexedProducts> createState() => _IndexedProductsState();
}

class _IndexedProductsState extends ConsumerState<_IndexedProducts> {
  int limit = 60;
  @override
  void didUpdateWidget(covariant _IndexedProducts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.category != widget.category ||
        oldWidget.ids != widget.ids) {
      limit = 60;
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(
        catalogSearchProvider((
          query: widget.query,
          category: widget.category,
          ids: widget.ids,
          limit: limit,
        )),
      )
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(context.text['error'])),
        data: (products) => products.isEmpty
            ? SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: context.text['nothingFound'],
                  hint: context.text['tryAnotherSearch'],
                ),
              )
            : ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: products.length + (products.length == limit ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => i == products.length
                    ? OutlinedButton(
                        onPressed: () => setState(() => limit += 60),
                        child: Text(context.text['loadMore']),
                      )
                    : widget.itemBuilder(context, products[i]),
              ),
      );
}
