import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../features/accounts/account_details_screen.dart';
import '../features/accounts/accounts_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/exchange/exchange_screen.dart';
import '../features/home/home_screen.dart';
import '../features/khata/khata_detail_screen.dart';
import '../features/khata/khata_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/quick_add/quick_add_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/transactions/transactions_screen.dart';
import '../features/transfer/transfer_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// App navigation graph.
///
/// Branch routes (home/accounts/history/profile) live inside the bottom-nav
/// shell; Quick Add, transfer, exchange, reports, budgets, khata and account
/// details are full-screen pages pushed above it (root navigator) with the
/// shared fade/scale transition.
final appRouter = GoRouter(
  initialLocation: '/',
  navigatorKey: _rootKey,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/',
            name: 'home',
            builder: (context, state) => const HomeScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/accounts',
            name: 'accounts',
            builder: (context, state) => const AccountsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'account-details',
                parentNavigatorKey: _rootKey,
                builder: (context, state) => AccountDetailsScreen(
                  accountId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/transactions',
            name: 'transactions',
            builder: (context, state) => const TransactionsScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ]),
      ],
    ),
    GoRoute(
      path: '/quick-add',
      name: 'quick-add',
      parentNavigatorKey: _rootKey,
      pageBuilder: _quickAddPage,
    ),
    GoRoute(
      path: '/transfer',
      name: 'transfer',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _fadeScalePage(
        context,
        state,
        child: const TransferScreen(),
      ),
    ),
    GoRoute(
      path: '/exchange',
      name: 'exchange',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _fadeScalePage(
        context,
        state,
        child: const ExchangeScreen(),
      ),
    ),
    GoRoute(
      path: '/reports',
      name: 'reports',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _fadeScalePage(
        context,
        state,
        child: const ReportsScreen(),
      ),
    ),
    GoRoute(
      path: '/budgets',
      name: 'budgets',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _fadeScalePage(
        context,
        state,
        child: const BudgetsScreen(),
      ),
    ),
    GoRoute(
      path: '/khata',
      name: 'khata',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _fadeScalePage(
        context,
        state,
        child: const KhataScreen(),
      ),
      routes: [
        GoRoute(
          path: ':id',
          name: 'khata-person',
          parentNavigatorKey: _rootKey,
          pageBuilder: (context, state) => _fadeScalePage(
            context,
            state,
            child: KhataDetailScreen(
              personId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ),
      ],
    ),
  ],
);

/// The Quick Add entrance: slow fade + gentle scale-up, faster fade-out —
/// the app's most choreographed transition, kept restrained.
Page<void> _quickAddPage(BuildContext context, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: const QuickAddScreen(),
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.medium,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter);
      final reverse = CurvedAnimation(parent: secondary, curve: AppMotion.exit);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1.0, end: 0.0).animate(reverse),
            child: child,
          ),
        ),
      );
    },
  );
}

Page<void> _fadeScalePage(
  BuildContext context,
  GoRouterState state, {
  required Widget child,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.medium,
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
