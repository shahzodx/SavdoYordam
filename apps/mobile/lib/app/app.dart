import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/strings.dart';
import '../design_system/theme.dart';
import '../features/auth/auth_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/products/products_screen.dart';
import '../features/pos/pos_screen.dart';
import '../features/sales/sales_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/sync_screen.dart';
import '../features/team/team_screen.dart';
import '../features/security/security_screen.dart';
import '../features/export/export_screen.dart';
import '../features/audit/audit_screen.dart';
import '../features/purchases/purchases_screen.dart';
import 'providers.dart';

class SavdoApp extends ConsumerStatefulWidget {
  const SavdoApp({super.key});
  @override
  ConsumerState<SavdoApp> createState() => _SavdoAppState();
}

class _SavdoAppState extends ConsumerState<SavdoApp>
    with WidgetsBindingObserver {
  late final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: ref.read(repositoryProvider),
    redirect: (context, state) {
      final repo = ref.read(repositoryProvider);
      final path = state.uri.path;
      if (!repo.authenticated) return path == '/login' ? null : '/login';
      if (!repo.hasStore && path != '/login' && path != '/onboarding') {
        return '/onboarding';
      }
      if (repo.hasStore && path == '/onboarding') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/sales', builder: (_, _) => const SalesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/products',
                builder: (_, _) => const ProductsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/customers',
                builder: (_, _) => const CustomersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (_, _) => const ReportsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/audit', builder: (_, _) => const AuditScreen()),
      GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
      GoRoute(path: '/security', builder: (_, _) => const SecurityScreen()),
      GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
      GoRoute(path: '/team', builder: (_, _) => const TeamScreen()),
      GoRoute(path: '/purchases', builder: (_, _) => const PurchasesScreen()),
      GoRoute(
        path: '/pos',
        builder: (_, state) =>
            PosScreen(onCredit: state.uri.queryParameters['credit'] == 'true'),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/expenses', builder: (_, _) => const ExpensesScreen()),
    ],
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = ref.read(repositoryProvider);
      if (repo.authenticated && repo.hasStore) repo.resumeSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      ref.read(repositoryProvider).pauseSync();
    }
    if (state == AppLifecycleState.resumed) {
      final repo = ref.read(repositoryProvider);
      if (repo.authenticated && repo.hasStore) {
        repo.resumeSync().then((_) {
          if (mounted) ref.invalidate(dataProvider);
          repo.notifyLowStock();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'SavdoYordam',
        theme: appTheme(),
        locale: Locale(repo.language),
        supportedLocales: const [Locale('uz'), Locale('ru')],
        localizationsDelegates: const [
          Strings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    );
  }
}

class _Shell extends ConsumerWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final s = context.text;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.storefront_outlined, color: brand),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s['appName'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (shell.currentIndex == 2 || shell.currentIndex == 3)
            IconButton(
              tooltip: s['newSale'],
              onPressed: () => context.push('/pos'),
              icon: const Icon(Icons.point_of_sale_outlined),
            ),
          IconButton(
            tooltip: s['sync'],
            onPressed: () => context.push('/sync'),
            icon: Icon(
              repo.queue.isEmpty
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_upload_outlined,
              color: repo.queue.isEmpty ? muted : const Color(0xFF835713),
            ),
          ),
          IconButton(
            tooltip: s['settings'],
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (repo.offline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                color: const Color(0xFFFFF3DC),
                child: Text(s['offline']),
              ),
            Expanded(child: shell),
          ],
        ),
      ),
      floatingActionButton: shell.currentIndex == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () => switch (shell.currentIndex) {
                2 =>
                  repo.isOwner
                      ? addProduct(context, ref)
                      : context.push('/pos'),
                3 => addCustomer(context, ref),
                _ => context.push('/pos'),
              },
              backgroundColor: brand,
              foregroundColor: Colors.white,
              icon: Icon(
                shell.currentIndex == 3 ? Icons.person_add_outlined : Icons.add,
              ),
              label: Text(
                s[shell.currentIndex == 2 && repo.isOwner
                    ? 'addProduct'
                    : shell.currentIndex == 3
                    ? 'addCustomer'
                    : 'newSale'],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.space_dashboard_outlined),
            selectedIcon: const Icon(Icons.space_dashboard),
            label: s['home'],
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            label: s['sales'],
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            label: s['products'],
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            label: s['customers'],
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            label: s['reports'],
          ),
        ],
      ),
    );
  }
}
