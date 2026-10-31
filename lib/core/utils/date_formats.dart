import 'package:intl/intl.dart';

/// Date/time helpers shared by UI features.
abstract final class DateFormats {
  static String friendlyDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return DateFormat('EEEE').format(d);
    return DateFormat('d MMM yyyy').format(d);
  }

  static String dayHeader(DateTime d) => DateFormat('d MMM yyyy').format(d);

  static String shortDate(DateTime d) => DateFormat('d MMM').format(d);

  static String time(DateTime d) => DateFormat('h:mm a').format(d);

  static String monthYear(DateTime d) => DateFormat('MMMM yyyy').format(d);

  /// Local midnight of [d]'s day.
  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// First instant of the month containing [d].
  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
}
