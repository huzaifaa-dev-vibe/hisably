import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

// Row classes (Account, Category, TransactionEntry, AppMetaRow) are
// generated into the part file; re-export the table declarations (enums
// etc.) so a single import serves consumers.
export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Accounts,
  Categories,
  Transactions,
  AppMeta,
  Budgets,
  KhataPeople,
  KhataEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the production database from the app documents directory.
  static Future<AppDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'hisably.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  /// In-memory instance for tests.
  static AppDatabase memory() =>
      AppDatabase(NativeDatabase.memory(logStatements: false));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultCategories();
        },
        onUpgrade: (m, from, to) async {
          // Forward-only, additive migrations. Each version step is
          // documented here so the history is auditable.
          switch (from) {
            case 1:
              // v2: monthly budgets + personal khata (people & entries).
              await m.createTable(budgets);
              await m.createTable(khataPeople);
              await m.createTable(khataEntries);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA journal_mode = WAL');
        },
      );

  /// Seeds the system categories exactly once, inside a transaction so a
  /// crashed first launch cannot leave a half-seeded database.
  Future<void> _seedDefaultCategories() {
    return transaction(() async {
      final now = DateTime.now();
      var order = 0;
      final outCategories = [
        ('Food', 'food'),
        ('Groceries', 'groceries'),
        ('Transport', 'transport'),
        ('Bills', 'bills'),
        ('Shopping', 'shopping'),
        ('Health', 'health'),
        ('Entertainment', 'entertainment'),
        ('Education', 'education'),
        ('Travel', 'travel'),
        ('Rent', 'rent'),
        ('Other', 'other'),
      ];
      final inCategories = [
        ('Salary', 'salary'),
        ('Business', 'business'),
        ('Gifts', 'gift'),
        ('Interest', 'interest'),
        ('Other', 'other'),
      ];
      for (final (name, icon) in outCategories) {
        await into(categories).insert(CategoriesCompanion.insert(
          name: name,
          direction: CategoryDirection.outflow,
          iconKey: Value(icon),
          sortOrder: Value(order++),
          isSystem: const Value(true),
        ));
      }
      for (final (name, icon) in inCategories) {
        await into(categories).insert(CategoriesCompanion.insert(
          name: name,
          direction: CategoryDirection.inflow,
          iconKey: Value(icon),
          sortOrder: Value(order++),
          isSystem: const Value(true),
        ));
      }
      await into(appMeta).insert(AppMetaCompanion.insert(
        key: 'seeded_at',
        value: now.toIso8601String(),
      ));
    });
  }
}
