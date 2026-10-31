import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/aurora_background.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/providers.dart';

/// Bottom navigation shell: Home / Accounts / — Quick Add — / History /
/// Profile.
///
/// The Quick Add button lives INSIDE the dock (fixed 52 dp slot, centred) —
/// it never overlaps the bar, the labels or the page content, and the page
/// body reserves its space by ending above the dock (`extendBody: false`).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _dockHeight = 62.0;

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Content ends above the dock — nothing slides underneath, so
        // list bottoms never hide behind the bar.
        extendBody: false,
        body: navigationShell,
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: GlassPanel(
              radius: 26,
              blurred: true,
              blurSigma: 22,
              child: SizedBox(
                key: const ValueKey('nav-dock'),
                height: _dockHeight,
                child: Row(
                  children: [
                    _NavItem(
                      navigationShell: navigationShell,
                      index: 0,
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home_rounded,
                      label: 'Home',
                    ),
                    _NavItem(
                      navigationShell: navigationShell,
                      index: 1,
                      icon: Icons.account_balance_wallet_outlined,
                      activeIcon: Icons.account_balance_wallet_rounded,
                      label: 'Accounts',
                    ),
                    SizedBox(
                      width: 76,
                      height: _dockHeight,
                      child: Center(
                        child: QuickAddButton(
                          onPressed: () => _openQuickAdd(context),
                        ),
                      ),
                    ),
                    _NavItem(
                      navigationShell: navigationShell,
                      index: 2,
                      icon: Icons.receipt_long_outlined,
                      activeIcon: Icons.receipt_long_rounded,
                      label: 'History',
                    ),
                    _NavItem(
                      navigationShell: navigationShell,
                      index: 3,
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openQuickAdd(BuildContext context) async {
    AppHaptics.tap();
    final id = await context.push<int?>('/quick-add');
    if (id != null && context.mounted) {
      showUndoSnackBar(context, id);
    }
  }
}

class _NavItem extends ConsumerWidget {
  const _NavItem({
    required this.navigationShell,
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final StatefulNavigationShell navigationShell;
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final shell = navigationShell;
    final selected = shell.currentIndex == index;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (!selected) AppHaptics.tap();
            shell.goBranch(index, initialLocation: selected);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.micro,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: selected
                      ? s.accent.withValues(alpha: s.isDark ? 0.20 : 0.13)
                      : Colors.transparent,
                ),
                child: Icon(
                  selected ? activeIcon : icon,
                  size: 23,
                  color: selected
                      ? s.accent
                      : s.textSecondary.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: AppMotion.fast,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? s.accent : s.textSecondary,
                  letterSpacing: 0.1,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.clip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Undo affordance after a saved transaction. Deleting the row is the
/// reversal — balances re-derive automatically from the ledger.
void showUndoSnackBar(BuildContext context, int transactionId) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Transaction saved'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            final container =
                ProviderScope.containerOf(context, listen: false);
            final repo = container.read(transactionRepositoryProvider);
            repo.deleteTransaction(transactionId).catchError((_) {});
          },
        ),
      ),
    );
}
