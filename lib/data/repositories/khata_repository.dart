import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';

/// A khata person with their derived per-currency net balance.
///
/// Net = Σ(gave) − Σ(took). Positive → the person owes the user; negative →
/// the user owes the person. Multi-currency people keep one bucket per
/// currency (never summed together).
class PersonWithBalance {
  const PersonWithBalance({
    required this.person,
    required this.balanceByCurrency,
    required this.lastActivity,
  });

  final KhataPerson person;

  /// currency code → signed minor units.
  final Map<String, int> balanceByCurrency;
  final DateTime? lastActivity;

  bool get isSettled =>
      balanceByCurrency.values.every((v) => v == 0);

  /// Primary (largest absolute) balance for list rows.
  MapEntry<String, int>? get primaryBalance {
    MapEntry<String, int>? best;
    for (final e in balanceByCurrency.entries) {
      if (e.value == 0) continue;
      if (best == null || e.value.abs() > best.value.abs()) best = e;
    }
    return best;
  }
}

/// The personal khata — informal debts between the user and people they
/// know. Entries are immutable facts; balances are always re-derived.
class KhataRepository {
  KhataRepository(this._db);

  final AppDatabase _db;

  /// All active people with live net balances, most recent activity first.
  Stream<List<PersonWithBalance>> watchPeopleWithBalances() {
    final people$ = (_db.select(_db.khataPeople)
          ..where((p) => p.archivedAt.isNull())
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .watch();
    final entries$ = _db.select(_db.khataEntries).watch();

    return _combine(people$, entries$, (people, entries) {
      final balances = <int, Map<String, int>>{};
      final lastAt = <int, DateTime>{};
      for (final e in entries) {
        final bucket = balances.putIfAbsent(e.personId, () => {});
        final signed = e.direction == KhataDirection.gave
            ? e.amountMinor
            : -e.amountMinor;
        bucket[e.currencyCode] = (bucket[e.currencyCode] ?? 0) + signed;
        final prev = lastAt[e.personId];
        if (prev == null || e.occurredAt.isAfter(prev)) {
          lastAt[e.personId] = e.occurredAt;
        }
      }
      final rows = [
        for (final p in people)
          PersonWithBalance(
            person: p,
            balanceByCurrency: balances[p.id] ?? const {},
            lastActivity: lastAt[p.id],
          ),
      ];
      // People with a live balance first, then by recent activity.
      rows.sort((a, b) {
        final av = a.primaryBalance?.value.abs() ?? 0;
        final bv = b.primaryBalance?.value.abs() ?? 0;
        if (av != bv) return bv.compareTo(av);
        final aa = a.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
        final ba = b.lastActivity ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ba.compareTo(aa);
      });
      return rows;
    });
  }

  /// Entries of one person, newest first.
  Stream<List<KhataEntry>> watchEntries(int personId) {
    return (_db.select(_db.khataEntries)
          ..where((e) => e.personId.equals(personId))
          ..orderBy([(e) => OrderingTerm.desc(e.occurredAt), (e) => OrderingTerm.desc(e.id)]))
        .watch();
  }

  Stream<KhataPerson?> watchPerson(int id) {
    return (_db.select(_db.khataPeople)..where((p) => p.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<int> addPerson({
    required String name,
    String? phone,
    String? note,
    String colorKey = 'blue',
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Person name must not be empty');
    }
    return _db.into(_db.khataPeople).insert(KhataPeopleCompanion.insert(
          name: name.trim(),
          phone: Value(phone?.trim().isEmpty == true ? null : phone?.trim()),
          note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
          colorKey: Value(colorKey),
        ));
  }

  Future<void> updatePerson({
    required int id,
    required String name,
    String? phone,
    String? note,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Person name must not be empty');
    }
    return (_db.update(_db.khataPeople)..where((p) => p.id.equals(id))).write(
      KhataPeopleCompanion(
        name: Value(name.trim()),
        phone: Value(phone?.trim().isEmpty == true ? null : phone?.trim()),
        note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
      ),
    );
  }

  Future<void> archivePerson(int id) {
    return (_db.update(_db.khataPeople)..where((p) => p.id.equals(id)))
        .write(KhataPeopleCompanion(archivedAt: Value(DateTime.now())));
  }

  /// Adds an entry. [amountMinor] must be positive — direction encodes the
  /// sign, so the stored magnitude is always clean.
  Future<int> addEntry({
    required int personId,
    required KhataDirection direction,
    required int amountMinor,
    required String currencyCode,
    String? note,
    DateTime? occurredAt,
  }) {
    if (amountMinor <= 0) {
      throw ArgumentError.value(
          amountMinor, 'amountMinor', 'Khata amount must be positive');
    }
    return _db.into(_db.khataEntries).insert(KhataEntriesCompanion.insert(
          personId: personId,
          direction: direction,
          amountMinor: amountMinor,
          currencyCode: currencyCode,
          note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
          occurredAt: occurredAt ?? DateTime.now(),
        ));
  }

  Future<void> deleteEntry(int id) =>
      (_db.delete(_db.khataEntries)..where((e) => e.id.equals(id))).go();

  /// Settle up in one currency: adds an opposite entry for the exact net
  /// amount so history stays honest (no edits of past facts).
  Future<int> settle({
    required int personId,
    required String currencyCode,
    required int netMinor,
    DateTime? occurredAt,
  }) {
    if (netMinor == 0) {
      throw ArgumentError.value(netMinor, 'netMinor', 'Nothing to settle');
    }
    // Positive net = person owes user → user receives money (`took`).
    final direction =
        netMinor > 0 ? KhataDirection.took : KhataDirection.gave;
    return addEntry(
      personId: personId,
      direction: direction,
      amountMinor: netMinor.abs(),
      currencyCode: currencyCode,
      note: 'Settle up',
      occurredAt: occurredAt ?? DateTime.now(),
    );
  }

  // --------------------------------------------------------------- helpers

  /// Same semantics as combine2 in stream_utils.dart, local copy to keep
  /// this file dependency-light.
  static Stream<R> _combine<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) fn,
  ) {
    late StreamController<R> controller;
    A? lastA;
    B? lastB;
    var hasA = false;
    var hasB = false;

    void emit() {
      if (hasA && hasB) controller.add(fn(lastA as A, lastB as B));
    }

    controller = StreamController<R>(
      onListen: () {
        a.listen((v) {
          lastA = v;
          hasA = true;
          emit();
        }, onError: controller.addError);
        b.listen((v) {
          lastB = v;
          hasB = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () {},
    );
    return controller.stream;
  }
}
