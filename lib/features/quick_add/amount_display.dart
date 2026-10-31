import 'package:flutter/material.dart';

import '../../core/money/money_formatter.dart';
import '../../core/theme/theme_spec.dart';
import '../../data/quick_add/quick_add_controller.dart';

/// The large, centered amount display for the Quick Add amount step.
///
/// Currency symbol sits INLINE before the amount (how people read money),
/// the live-formatted amount animates with a restrained 120 ms fade/slide
/// and uses tabular figures so nothing jitters horizontally.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.state});

  final QuickAddState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.spec;
    final currency = state.currency;
    final hasDot = state.raw.contains('.');
    final grouped = AmountFormat.typing(state.raw, currency);
    final isEmpty = state.amount == null;

    return Semantics(
      liveRegion: true,
      label: 'Amount ${currency.symbol} $grouped',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            currency.symbol.isEmpty ? currency.code : currency.symbol,
            style: theme.textTheme.displaySmall!.copyWith(
              color: s.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.10),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Row(
              key: ValueKey(grouped),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    grouped.isEmpty ? '0' : grouped,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.textTheme.displayLarge!.copyWith(
                      color: isEmpty ? s.textTertiary : s.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // Soft caret: always visible, brighter while typing decimals.
                _Caret(active: hasDot),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret({required this.active});

  final bool active;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.15, end: 0.75).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        ),
        child: Container(
          width: 3.2,
          height: 44,
          decoration: BoxDecoration(
            color: context.spec.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
