import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/app_database.dart';

/// Result of an export/backup run — the UI shows the path and file size.
class ExportResult {
  const ExportResult({required this.path, required this.bytes, required this.summary});
  final String path;
  final int bytes;
  final String summary;
}

/// Offline CSV export and full backup/restore.
///
/// Files are written to the app's own documents directory — no permissions,
/// no network, nothing leaves the device. The user shares/moves them with
/// any file manager.
class ExportService {
  ExportService(this._db, {Future<Directory> Function()? exportDirFactory})
      : _exportDirFactory = exportDirFactory ?? _defaultExportDir;

  final AppDatabase _db;
  final Future<Directory> Function() _exportDirFactory;

  static Future<Directory> _defaultExportDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'hisably-exports'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ------------------------------------------------------------------ CSV

  /// Exports every transaction as CSV (RFC 4180 quoting). The file opens
  /// cleanly in Excel/Numbers/Sheets.
  Future<ExportResult> exportTransactionsCsv() async {
    final rows = await (_db.select(_db.transactions)
          ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
        .get();
    final accounts = {for (final a in await _db.select(_db.accounts).get()) a.id: a};
    final categories = {for (final c in await _db.select(_db.categories).get()) c.id: c};

    final buffer = StringBuffer()
      ..writeln(
          'id,type,date,account,to_account,amount_minor,currency,to_amount_minor,to_currency,fee_minor,category,note');
    for (final t in rows) {
      final acc = accounts[t.accountId]?.name ?? '';
      final toAcc = t.toAccountId != null ? (accounts[t.toAccountId!]?.name ?? '') : '';
      final cur = acc.isNotEmpty ? accounts[t.accountId]!.currencyCode : '';
      final toCur = t.toAccountId != null ? accounts[t.toAccountId!]?.currencyCode ?? '' : '';
      final cat = t.categoryId != null ? categories[t.categoryId!]?.name ?? '' : '';
      buffer.writeln(_csvLine([
        t.id.toString(),
        t.type.name,
        t.occurredAt.toIso8601String(),
        acc,
        toAcc,
        t.amountMinor.toString(),
        cur,
        t.toAmountMinor?.toString() ?? '',
        toCur,
        t.feeMinor.toString(),
        cat,
        t.note ?? '',
      ]));
    }

    final dir = await _exportDir();
    final stamp = DateTime.now();
    final name =
        'hisably-transactions-${stamp.year}${_p2(stamp.month)}${_p2(stamp.day)}-${_p2(stamp.hour)}${_p2(stamp.minute)}.csv';
    final file = File(p.join(dir, name));
    final bytes = utf8.encode(buffer.toString());
    await file.writeAsBytes(bytes, flush: true);
    return ExportResult(
      path: file.path,
      bytes: bytes.length,
      summary: '${rows.length} transactions',
    );
  }

  // --------------------------------------------------------------- backup

  /// Full, human-inspectable JSON backup of every table.
  Future<ExportResult> backup() async {
    final accounts = await _db.select(_db.accounts).get();
    final categories = await _db.select(_db.categories).get();
    final transactions = await _db.select(_db.transactions).get();
    final budgets = await _db.select(_db.budgets).get();
    final people = await _db.select(_db.khataPeople).get();
    final entries = await _db.select(_db.khataEntries).get();

    final payload = <String, dynamic>{
      'app': 'hisably',
      'backup_version': 1,
      'schema_version': _db.schemaVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'counts': {
        'accounts': accounts.length,
        'categories': categories.length,
        'transactions': transactions.length,
        'budgets': budgets.length,
        'khata_people': people.length,
        'khata_entries': entries.length,
      },
      'accounts': [for (final a in accounts) _accountJson(a)],
      'categories': [for (final c in categories) _categoryJson(c)],
      'transactions': [for (final t in transactions) _txJson(t)],
      'budgets': [for (final b in budgets) _budgetJson(b)],
      'khata_people': [for (final p in people) _personJson(p)],
      'khata_entries': [for (final e in entries) _entryJson(e)],
    };

    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await _exportDir();
    final stamp = DateTime.now();
    final name =
        'hisably-backup-${stamp.year}${_p2(stamp.month)}${_p2(stamp.day)}-${_p2(stamp.hour)}${_p2(stamp.minute)}.json';
    final file = File(p.join(dir, name));
    final bytes = utf8.encode(json);
    await file.writeAsBytes(bytes, flush: true);
    final c = payload['counts'] as Map;
    return ExportResult(
      path: file.path,
      bytes: bytes.length,
      summary:
          '${c['transactions']} transactions · ${c['accounts']} accounts · ${c['khata_entries']} khata entries',
    );
  }

  /// Restores a backup made by [backup]. VALIDATES the payload first, then
  /// replaces all data inside ONE transaction — a malformed or truncated
  /// file can never leave a half-destroyed database.
  Future<void> restoreFromJsonFile(String filePath) async {
    final raw = await File(filePath).readAsString();
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Not a valid Hisably backup file.');
    }
    if (json['app'] != 'hisably' || json['backup_version'] != 1) {
      throw const FormatException('Not a valid Hisably backup file.');
    }
    // Structural validation before touching a single row.
    final accounts = _jsonList(json['accounts']);
    final categories = _jsonList(json['categories']);
    final transactions = _jsonList(json['transactions']);
    final budgets = _jsonList(json['budgets']);
    final people = _jsonList(json['khata_people']);
    final entries = _jsonList(json['khata_entries']);

    await _db.transaction(() async {
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.budgets).go();
      await _db.delete(_db.khataEntries).go();
      await _db.delete(_db.khataPeople).go();
      await _db.delete(_db.accounts).go();
      await _db.delete(_db.categories).go();

      final categoryIdMap = <int, int>{};
      for (final c in categories) {
        final id = await _db.into(_db.categories).insert(CategoriesCompanion.insert(
              name: c['name'] as String,
              direction: CategoryDirection.values.byName(c['direction'] as String),
              iconKey: Value(c['iconKey'] as String? ?? 'category'),
              sortOrder: Value(c['sortOrder'] as int? ?? 100),
              isSystem: Value(c['isSystem'] as bool? ?? false),
            ));
        categoryIdMap[c['id'] as int] = id;
      }

      final accountIdMap = <int, int>{};
      for (final a in accounts) {
        final id = await _db.into(_db.accounts).insert(AccountsCompanion.insert(
              name: a['name'] as String,
              kind: AccountKind.values.byName(a['kind'] as String),
              currencyCode: a['currencyCode'] as String,
              openingBalanceMinor: a['openingBalanceMinor'] as int,
              colorKey: Value(a['colorKey'] as String? ?? 'blue'),
              note: Value(a['note'] as String?),
              createdAt: Value(_dt(a['createdAt'])),
              archivedAt: Value(a['archivedAt'] == null ? null : _dt(a['archivedAt'])),
            ));
        accountIdMap[a['id'] as int] = id;
      }

      for (final t in transactions) {
        await _db.into(_db.transactions).insert(TransactionsCompanion.insert(
              type: TransactionType.values.byName(t['type'] as String),
              accountId: accountIdMap[t['accountId'] as int] ??
                  (throw const FormatException('Backup references a missing account')),
              toAccountId: Value(t['toAccountId'] == null
                  ? null
                  : accountIdMap[t['toAccountId'] as int]),
              amountMinor: t['amountMinor'] as int,
              toAmountMinor: Value(t['toAmountMinor'] as int?),
              feeMinor: Value(t['feeMinor'] as int? ?? 0),
              categoryId: Value(t['categoryId'] == null
                  ? null
                  : categoryIdMap[t['categoryId'] as int]),
              note: Value(t['note'] as String?),
              occurredAt: _dt(t['occurredAt']),
              createdAt: Value(_dt(t['createdAt'])),
            ));
      }

      for (final b in budgets) {
        await _db.into(_db.budgets).insert(BudgetsCompanion.insert(
              categoryId: categoryIdMap[b['categoryId'] as int] ??
                  (throw const FormatException('Backup references a missing category')),
              currencyCode: b['currencyCode'] as String,
              monthlyLimitMinor: b['monthlyLimitMinor'] as int,
              createdAt: Value(_dt(b['createdAt'])),
            ));
      }

      final personIdMap = <int, int>{};
      for (final pe in people) {
        final id = await _db.into(_db.khataPeople).insert(KhataPeopleCompanion.insert(
              name: pe['name'] as String,
              phone: Value(pe['phone'] as String?),
              note: Value(pe['note'] as String?),
              colorKey: Value(pe['colorKey'] as String? ?? 'blue'),
              createdAt: Value(_dt(pe['createdAt'])),
              archivedAt: Value(pe['archivedAt'] == null ? null : _dt(pe['archivedAt'])),
            ));
        personIdMap[pe['id'] as int] = id;
      }

      for (final e in entries) {
        await _db.into(_db.khataEntries).insert(KhataEntriesCompanion.insert(
              personId: personIdMap[e['personId'] as int] ??
                  (throw const FormatException('Backup references a missing person')),
              direction: KhataDirection.values.byName(e['direction'] as String),
              amountMinor: e['amountMinor'] as int,
              currencyCode: e['currencyCode'] as String,
              note: Value(e['note'] as String?),
              occurredAt: _dt(e['occurredAt']),
              createdAt: Value(_dt(e['createdAt'])),
            ));
      }
    });
  }

  // --------------------------------------------------------------- helpers

  Future<String> _exportDir() async => (await _exportDirFactory()).path;

  String _csvLine(List<String> cells) => cells
      .map((c) =>
          (c.contains(',') || c.contains('"') || c.contains('\n'))
              ? '"${c.replaceAll('"', '""')}"'
              : c)
      .join(',');

  static String _p2(int v) => v.toString().padLeft(2, '0');

  static List<Map<String, dynamic>> _jsonList(Object? v) {
    if (v == null) return const [];
    if (v is! List) throw const FormatException('Malformed backup section.');
    return [for (final e in v) e as Map<String, dynamic>];
  }

  static DateTime _dt(Object? v) =>
      v == null ? DateTime.now() : DateTime.parse(v as String);

  // JSON encoders — explicit maps (no codegen, fully versioned shape).
  static Map<String, dynamic> _accountJson(Account a) => {
        'id': a.id,
        'name': a.name,
        'kind': a.kind.name,
        'currencyCode': a.currencyCode,
        'openingBalanceMinor': a.openingBalanceMinor,
        'colorKey': a.colorKey,
        'note': a.note,
        'createdAt': a.createdAt.toIso8601String(),
        'archivedAt': a.archivedAt?.toIso8601String(),
      };

  static Map<String, dynamic> _categoryJson(Category c) => {
        'id': c.id,
        'name': c.name,
        'direction': c.direction.name,
        'iconKey': c.iconKey,
        'sortOrder': c.sortOrder,
        'isSystem': c.isSystem,
      };

  static Map<String, dynamic> _txJson(TransactionEntry t) => {
        'id': t.id,
        'type': t.type.name,
        'accountId': t.accountId,
        'toAccountId': t.toAccountId,
        'amountMinor': t.amountMinor,
        'toAmountMinor': t.toAmountMinor,
        'feeMinor': t.feeMinor,
        'categoryId': t.categoryId,
        'note': t.note,
        'occurredAt': t.occurredAt.toIso8601String(),
        'createdAt': t.createdAt.toIso8601String(),
      };

  static Map<String, dynamic> _budgetJson(BudgetRow b) => {
        'id': b.id,
        'categoryId': b.categoryId,
        'currencyCode': b.currencyCode,
        'monthlyLimitMinor': b.monthlyLimitMinor,
        'createdAt': b.createdAt.toIso8601String(),
      };

  static Map<String, dynamic> _personJson(KhataPerson p) => {
        'id': p.id,
        'name': p.name,
        'phone': p.phone,
        'note': p.note,
        'colorKey': p.colorKey,
        'createdAt': p.createdAt.toIso8601String(),
        'archivedAt': p.archivedAt?.toIso8601String(),
      };

  static Map<String, dynamic> _entryJson(KhataEntry e) => {
        'id': e.id,
        'personId': e.personId,
        'direction': e.direction.name,
        'amountMinor': e.amountMinor,
        'currencyCode': e.currencyCode,
        'note': e.note,
        'occurredAt': e.occurredAt.toIso8601String(),
        'createdAt': e.createdAt.toIso8601String(),
      };
}
