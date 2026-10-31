import 'package:flutter/material.dart';

import '../db/tables.dart';

/// Maps stable string keys (stored in the DB) to Material icons so data
/// stays presentation-independent.
abstract final class IconRegistry {
  static const Map<String, IconData> _map = {
    'category': Icons.category_outlined,
    'food': Icons.restaurant_outlined,
    'groceries': Icons.shopping_basket_outlined,
    'transport': Icons.directions_car_outlined,
    'bills': Icons.receipt_long_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'health': Icons.medical_services_outlined,
    'entertainment': Icons.movie_outlined,
    'education': Icons.school_outlined,
    'travel': Icons.flight_takeoff_outlined,
    'rent': Icons.home_outlined,
    'other': Icons.crop_square_outlined,
    'salary': Icons.payments_outlined,
    'business': Icons.work_outline,
    'gift': Icons.card_giftcard_outlined,
    'interest': Icons.savings_outlined,
    'cash': Icons.payments_outlined,
    'bank': Icons.account_balance_outlined,
    'savings': Icons.savings_outlined,
    'wallet': Icons.account_balance_wallet_outlined,
  };

  static IconData forKey(String key) => _map[key] ?? Icons.category_outlined;

  static IconData forAccountKind(AccountKind kind) => switch (kind) {
        AccountKind.cash => Icons.payments_outlined,
        AccountKind.bank => Icons.account_balance_outlined,
        AccountKind.savings => Icons.savings_outlined,
        AccountKind.wallet => Icons.account_balance_wallet_outlined,
      };

  static IconData forTransactionType(TransactionType type) => switch (type) {
        TransactionType.income => Icons.south_west,
        TransactionType.expense => Icons.north_east,
        TransactionType.transfer => Icons.swap_horiz,
        TransactionType.exchange => Icons.currency_exchange,
      };
}
