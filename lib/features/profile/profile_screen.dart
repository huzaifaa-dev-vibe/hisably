import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/money/currency.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/theme_spec.dart';
import '../../core/version.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';

/// Profile: identity, appearance (themes), feedback (haptics), preferences
/// (primary currency) and local data tools (CSV export, backup/restore).
/// Everything here is offline and local — nothing leaves the device.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    final name = ref.watch(displayNameProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Profile'),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            _ProfileHeader(name: name),
            const SizedBox(height: 20),
            _SectionTitle('Appearance'),
            const _ThemePicker(),
            const SizedBox(height: 20),
            _SectionTitle('Feedback'),
            _SettingsGroup(
              children: [
                _HapticsTile(),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle('Preferences'),
            _SettingsGroup(
              children: [
                _PrimaryCurrencyTile(),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle('Data — on this device only'),
            _SettingsGroup(
              children: [
                _ActionTile(
                  icon: Icons.table_view_rounded,
                  title: 'Export transactions (CSV)',
                  subtitle: 'Open in any spreadsheet app',
                  onTap: () => _exportCsv(context, ref),
                ),
                _divider(s),
                _ActionTile(
                  icon: Icons.ios_share_rounded,
                  title: 'Backup all data (JSON)',
                  subtitle: 'Accounts, ledger, budgets, khata',
                  onTap: () => _backup(context, ref),
                ),
                _divider(s),
                _ActionTile(
                  icon: Icons.restore_rounded,
                  title: 'Restore from backup',
                  subtitle: 'Replaces everything with the backup',
                  destructive: true,
                  onTap: () => _restore(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle('Coming soon'),
            _SettingsGroup(
              children: [
                _ComingSoonTile(
                  icon: Icons.badge_outlined,
                  title: 'Account details',
                  subtitle: 'Richer profile & preferences (in progress)',
                ),
                _divider(s),
                _ComingSoonTile(
                  icon: Icons.history_rounded,
                  title: 'My activity summary',
                  subtitle: 'Your usage history at a glance (in progress)',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle('About'),
            _SettingsGroup(
              children: [
                const _StaticTile(
                  icon: Icons.verified_outlined,
                  title: 'Version',
                  value: AppVersion.string,
                ),
                _divider(s),
                const _StaticTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Private by design',
                  value: 'No account · no network · no tracking',
                ),
                _divider(s),
                const _StaticTile(
                  icon: Icons.code_rounded,
                  title: 'Open source',
                  value: 'Offline-first personal finance',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _divider(AppThemeSpec s) => Divider(
        height: 1,
        thickness: 1,
        indent: 54,
        color: s.isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
      );

  // ------------------------------------------------------------- actions

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    AppHaptics.tap();
    unawaited(_runWithBusy(context, 'Exporting CSV…', (ref) async {
      return ref.read(exportServiceProvider).exportTransactionsCsv();
    }, ref: ref));
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    AppHaptics.tap();
    unawaited(_runWithBusy(context, 'Creating backup…', (ref) async {
      return ref.read(exportServiceProvider).backup();
    }, ref: ref));
  }

  /// Runs an export job behind a modal busy dialog and shows the result
  /// (path + size) when done.
  Future<void> _runWithBusy(
    BuildContext context,
    String message,
    Future<ExportResult> Function(WidgetRef) job, {
    required WidgetRef ref,
  }) async {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));
    try {
      final result = await job(ref);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final sizeKb = (result.bytes / 1024).toStringAsFixed(1);
      unawaited(showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Saved'),
          content: Text(
            '${result.summary}\n\n$sizeKb KB\n${result.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    AppHaptics.warn();
    final pathController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This REPLACES all current data with the backup file. '
              'Paste the full path of a hisably-backup-*.json file:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration:
                  const InputDecoration(hintText: '/path/to/backup.json'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.spec.expense,
              foregroundColor: context.spec.onAccent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (pathController.text.trim().isEmpty) return;

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));
    try {
      await ref
          .read(exportServiceProvider)
          .restoreFromJsonFile(pathController.text.trim());
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored')),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $e')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.spec;
    return GlassPanel(
      blurred: false,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [s.accent, Color.lerp(s.accent, s.transfer, 0.5)!],
              ),
            ),
            child: Center(
              child: Text(
                name.isEmpty ? 'H' : name[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: s.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  'Local account · v${AppVersion.string}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit name',
            icon: Icon(Icons.edit_outlined, size: 20, color: s.textSecondary),
            onPressed: () => _editName(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: ref.read(displayNameProvider));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(displayNameProvider.notifier).set(name);
      AppHaptics.confirm();
    }
  }
}

// ---------------------------------------------------------------------------
// Theme picker
// ---------------------------------------------------------------------------

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeSettingProvider);
    final s = context.spec;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.86,
      ),
      itemCount: AppThemes.selectable.length,
      itemBuilder: (context, i) {
        final spec = AppThemes.selectable[i];
        final selected = spec.id == current;
        return _ThemeCard(
          spec: spec,
          selected: selected,
          onTap: () {
            AppHaptics.tap();
            ref.read(themeSettingProvider.notifier).set(spec.id);
          },
          s: s,
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.spec,
    required this.selected,
    required this.onTap,
    required this.s,
  });

  final AppThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;
  final AppThemeSpec s;

  @override
  Widget build(BuildContext context) {
    final isSystem = spec.id == 'system';
    // Preview swatches use the THEME'S OWN colours (for the System card we
    // preview both light and dark halves).
    final previewAccent = isSystem ? s.accent : spec.accent;
    final previewText = isSystem ? s.textPrimary : spec.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Theme ${spec.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? s.accent : s.glassBorder,
                width: selected ? 1.8 : 1,
              ),
              color: s.isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.65),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mini preview: rounded rect with bg + blobs + accent dot.
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isSystem
                            ? [AppThemes.porcelain.bgTop, AppThemes.obsidian.bgTop]
                            : [spec.bgTop, spec.bgBottom],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 5,
                          left: 5,
                          child: Container(
                            width: 18,
                            height: 10,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: previewText.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration:
                                BoxDecoration(shape: BoxShape.circle, color: previewAccent),
                          ),
                        ),
                        Positioned(
                          bottom: 5,
                          left: 5,
                          child: Container(
                            width: 26,
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: isSystem
                                  ? AppThemes.porcelain.glassFill
                                  : spec.glassFill,
                              border: Border.all(
                                color: isSystem
                                    ? AppThemes.porcelain.glassBorder
                                    : spec.glassBorder,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spec.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? s.accent : s.textPrimary,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle_rounded,
                          size: 15, color: s.accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic tiles
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 9),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      blurred: false,
      radius: 20,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: children),
    );
  }
}

class _HapticsTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(hapticsEnabledProvider);
    return SwitchListTile.adaptive(
      secondary: Icon(Icons.vibration_rounded, color: context.spec.accent),
      title: const Text('Haptic feedback'),
      subtitle: Text(
        'Vibrate on taps and saves (supported devices)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: enabled,
      onChanged: (v) {
        ref.read(hapticsEnabledProvider.notifier).set(v);
        if (v) AppHaptics.confirm();
      },
    );
  }
}

class _PrimaryCurrencyTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(primaryCurrencyProvider);
    return ListTile(
      leading: Icon(Icons.currency_exchange_rounded, color: context.spec.accent),
      title: const Text('Primary currency'),
      subtitle: Text(
        'Used for Quick Add and budgets',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Text(
        code,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () => _pickCurrency(context, ref, code),
    );
  }

  Future<void> _pickCurrency(
      BuildContext context, WidgetRef ref, String current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CurrencySheet(),
    );
    if (picked != null) {
      await ref.read(primaryCurrencyProvider.notifier).set(picked);
      AppHaptics.tap();
    }
  }
}

class _CurrencySheet extends ConsumerStatefulWidget {
  const _CurrencySheet();

  @override
  ConsumerState<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends ConsumerState<_CurrencySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final current = ref.watch(primaryCurrencyProvider);
    final all = CurrencyRegistry.all;
    final results = all
        .where((c) =>
            _query.isEmpty ||
            c.code.toLowerCase().contains(_query.toLowerCase()) ||
            (c.englishName ?? '').toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search currency or code',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final c = results[i];
                return ListTile(
                  title: Text(c.englishName ?? c.code,
                      style: TextStyle(color: s.textPrimary)),
                  trailing: Text(
                    c.code,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium!
                        .copyWith(color: s.textSecondary),
                  ),
                  selected: c.code == current,
                  onTap: () => Navigator.of(context).pop(c.code),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final color = destructive ? s.expense : s.accent;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium!
            .copyWith(color: destructive ? s.expense : s.textPrimary),
      ),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: Icon(Icons.chevron_right, color: s.textTertiary),
      onTap: onTap,
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return ListTile(
      enabled: false,
      leading: Icon(icon, color: s.textTertiary),
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium!
              .copyWith(color: s.textTertiary)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: s.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
        child: Text(
          'SOON',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: s.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _StaticTile extends StatelessWidget {
  const _StaticTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return ListTile(
      leading: Icon(icon, color: s.accent),
      title: Text(title),
      trailing: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .labelMedium!
            .copyWith(color: s.textSecondary),
      ),
    );
  }
}
