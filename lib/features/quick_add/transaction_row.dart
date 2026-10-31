import 'package:flutter/material.dart';

import '../../core/db/app_database.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/theme/icon_registry.dart';
import '../../core/theme/theme_spec.dart';
import '../../core/utils/date_formats.dart';
import '../../data/repositories/transaction_repository.dart';

/// One ledger row as displayed in lists: icon bubble, title (category or
/// type label), subtitle (account + note), signed amount in its own
/// currency. Transfers/exchanges show both legs. Colours always come from
/// the active theme spec — legible in every theme by construction.
class TransactionRow extends StatelessWidget {
  const TransactionRow({super.key, required this.item, this.showDate = false});

  final TxWithRefs item;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    final tx = item.tx;
    final color = _colorFor(s, tx.type);
    final title = _titleFor(item);
    final subtitle = _subtitleFor(item);
    final amountStr = _amountFor(item);
    final amountColor = switch (tx.type) {
      TransactionType.income => s.income,
      TransactionType.expense => s.expense,
      _ => s.textPrimary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(_iconFor(item), size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    showDate
                        ? '$subtitle · ${DateFormats.shortDate(tx.occurredAt)}'
                        : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            amountStr,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  color: amountColor,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
          ),
          if (tx.type == TransactionType.exchange && item.toAccount != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '→ ${CurrencyRegistry.byCode(item.toAccount!.currencyCode).code}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }

  static Color _colorFor(AppThemeSpec s, TransactionType type) => switch (type) {
        TransactionType.income => s.income,
        TransactionType.expense => s.expense,
        TransactionType.transfer => s.transfer,
        TransactionType.exchange => s.warn,
      };

  static IconData _iconFor(TxWithRefs item) {
    if (item.tx.type == TransactionType.income ||
        item.tx.type == TransactionType.expense) {
      if (item.category != null) {
        return IconRegistry.forKey(item.category!.iconKey);
      }
      return IconRegistry.forTransactionType(item.tx.type);
    }
    return IconRegistry.forTransactionType(item.tx.type);
  }

  static String _titleFor(TxWithRefs item) {
    switch (item.tx.type) {
      case TransactionType.income:
        return item.category?.name ?? 'Income';
      case TransactionType.expense:
        return item.category?.name ?? 'Expense';
      case TransactionType.transfer:
        return 'Transfer · ${item.toAccount?.name ?? '—'}';
      case TransactionType.exchange:
        final toCur =
            item.toAccount != null ? CurrencyRegistry.byCode(item.toAccount!.currencyCode).code : '—';
        return 'Exchange → $toCur';
    }
  }

  static String _subtitleFor(TxWithRefs item) {
    final accountName = item.account?.name ?? '';
    final note = item.tx.note;
    if (note == null || note.isEmpty) return accountName;
    return '$accountName · $note';
  }

  static String _amountFor(TxWithRefs item) {
    final c = CurrencyRegistry.byCode(item.account?.currencyCode ?? 'XXX');
    switch (item.tx.type) {
      case TransactionType.income:
        return '+${AmountFormat.money(Money.fromMinor(item.tx.amountMinor, c))}';
      case TransactionType.expense:
        return '-${AmountFormat.money(Money.fromMinor(item.tx.amountMinor, c))}';
      case TransactionType.transfer:
        return AmountFormat.money(Money.fromMinor(item.tx.amountMinor, c));
      case TransactionType.exchange:
        return '-${AmountFormat.money(Money.fromMinor(item.tx.amountMinor + item.tx.feeMinor, c))}';
    }
  }
}
