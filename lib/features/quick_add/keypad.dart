import 'package:flutter/material.dart';

import '../../core/haptics/app_haptics.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/quick_add/quick_add_controller.dart';

/// A large 3×4 numeric keypad: 1–9, decimal point, 0, backspace.
///
/// * Haptic selection click on every successful press (via [AppHaptics]).
/// * Long-press backspace fires [onClear] (clears the whole amount).
/// * Decimal key renders disabled when the currency has no minor units.
/// * Every key carries a semantic label for screen readers.
/// * Round, spec-coloured keys — readable in every theme.
class KeypadGrid extends StatelessWidget {
  const KeypadGrid({
    super.key,
    required this.onKey,
    this.onClear,
    this.decimalEnabled = true,
    this.semanticPrefix = '',
  });

  final ValueChanged<QuickKey> onKey;

  /// Long-press on backspace — clear the entire amount.
  final VoidCallback? onClear;
  final bool decimalEnabled;
  final String semanticPrefix;

  static const _rows = <List<QuickKey?>>[
    [QuickKey.digit1, QuickKey.digit2, QuickKey.digit3],
    [QuickKey.digit4, QuickKey.digit5, QuickKey.digit6],
    [QuickKey.digit7, QuickKey.digit8, QuickKey.digit9],
    [null, QuickKey.digit0, QuickKey.backspace],
  ];

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final row in _rows) {
      for (final k in row) {
        if (k == null) {
          children.add(const SizedBox.expand());
          continue;
        }
        children.add(_Key(
          key: ValueKey(k),
          quickKey: k,
          enabled: k != QuickKey.decimal || decimalEnabled,
          onKey: onKey,
          onClear: onClear,
          semanticPrefix: semanticPrefix,
        ));
      }
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 12,
      padding: EdgeInsets.zero,
      childAspectRatio: 1.7,
      children: children,
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.quickKey,
    required this.enabled,
    required this.onKey,
    required this.onClear,
    required this.semanticPrefix,
  });

  final QuickKey quickKey;
  final bool enabled;
  final ValueChanged<QuickKey> onKey;
  final VoidCallback? onClear;
  final String semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final label = switch (quickKey) {
      QuickKey.decimal => '.',
      QuickKey.backspace => '',
      _ => quickKey.index.toString(),
    };
    final fg = enabled ? s.textPrimary : s.textTertiary;

    Widget content;
    if (quickKey == QuickKey.backspace) {
      content = Icon(Icons.backspace_outlined, size: 23, color: fg);
    } else {
      content = Text(
        label,
        style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
              color: fg,
            ),
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: switch (quickKey) {
        QuickKey.decimal => '$semanticPrefix Decimal point',
        QuickKey.backspace => '$semanticPrefix Delete last digit. Long press to clear.',
        _ => '$semanticPrefix ${quickKey.index}',
      },
      child: GestureDetector(
        onLongPress: quickKey == QuickKey.backspace && enabled
            ? () {
                AppHaptics.tap();
                onClear?.call();
              }
            : null,
        child: Material(
          color: s.keyFill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled
                ? () {
                    AppHaptics.tap();
                    onKey(quickKey);
                  }
                : null,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
