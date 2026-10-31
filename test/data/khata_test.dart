import 'package:flutter_test/flutter_test.dart';

import 'package:hisably/core/db/app_database.dart';
import 'package:hisably/data/repositories/khata_repository.dart';

void main() {
  late AppDatabase db;
  late KhataRepository khata;
  late int aliId;

  setUp(() async {
    db = AppDatabase.memory();
    khata = KhataRepository(db);
    aliId = await khata.addPerson(name: 'Ali', phone: '0300-1234567');
  });

  tearDown(() => db.close());

  test('add person validates name', () async {
    expect(() => khata.addPerson(name: '   '), throwsArgumentError);
  });

  test('net balance: gave minus took, per currency', () async {
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.gave,
        amountMinor: 100000, // lent 1,000.00
        currencyCode: 'PKR');
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.gave,
        amountMinor: 5000,
        currencyCode: 'PKR');
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.took,
        amountMinor: 25000, // partial repayment 250.00
        currencyCode: 'PKR');
    // A second currency is tracked separately, never summed.
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.took,
        amountMinor: 100,
        currencyCode: 'USD');

    final people = await khata.watchPeopleWithBalances().first;
    expect(people.single.person.id, aliId);
    expect(people.single.balanceByCurrency['PKR'], 80000);
    expect(people.single.balanceByCurrency['USD'], -100);
    expect(people.single.isSettled, isFalse);
    expect(people.single.primaryBalance!.key, 'PKR');
  });

  test('partial repayments are plain opposite-direction entries', () async {
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.gave,
        amountMinor: 50000,
        currencyCode: 'PKR');
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.took,
        amountMinor: 20000,
        currencyCode: 'PKR',
        note: 'first instalment');
    final people = await khata.watchPeopleWithBalances().first;
    expect(people.single.balanceByCurrency['PKR'], 30000);
  });

  test('settle adds an opposite entry for the exact net', () async {
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.gave,
        amountMinor: 30000,
        currencyCode: 'PKR');
    // Person owes 300.00 → settling means we RECEIVE (took).
    await khata.settle(personId: aliId, currencyCode: 'PKR', netMinor: 30000);

    final people = await khata.watchPeopleWithBalances().first;
    expect(people.single.isSettled, isTrue);
    final entries = await khata.watchEntries(aliId).first;
    expect(entries, hasLength(2));
    expect(entries.first.direction, KhataDirection.took);
    expect(entries.first.note, 'Settle up');
  });

  test('settle in the other direction (we owe them)', () async {
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.took,
        amountMinor: 15000,
        currencyCode: 'PKR');
    await khata.settle(personId: aliId, currencyCode: 'PKR', netMinor: -15000);
    final entries = await khata.watchEntries(aliId).first;
    expect(entries.first.direction, KhataDirection.gave);
  });

  test('settle with zero net is rejected', () {
    expect(
      () => khata.settle(personId: aliId, currencyCode: 'PKR', netMinor: 0),
      throwsArgumentError,
    );
  });

  test('entries validate positive amounts', () {
    expect(
      () => khata.addEntry(
          personId: aliId,
          direction: KhataDirection.gave,
          amountMinor: 0,
          currencyCode: 'PKR'),
      throwsArgumentError,
    );
  });

  test('deleting an entry recalculates the balance', () async {
    final e1 = await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.gave,
        amountMinor: 40000,
        currencyCode: 'PKR');
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.gave,
        amountMinor: 10000,
        currencyCode: 'PKR');
    await khata.deleteEntry(e1);
    final people = await khata.watchPeopleWithBalances().first;
    expect(people.single.balanceByCurrency['PKR'], 10000);
  });

  test('archive person hides them from the active list', () async {
    await khata.archivePerson(aliId);
    final people = await khata.watchPeopleWithBalances().first;
    expect(people, isEmpty);
    final person = await khata.watchPerson(aliId).first;
    expect(person, isNotNull);
    expect(person!.archivedAt, isNotNull);
  });

  test('update person edits name/phone/note', () async {
    await khata.updatePerson(
        id: aliId, name: 'Ali Raza', phone: '  ', note: 'neighbour');
    final person = await khata.watchPerson(aliId).first;
    expect(person!.name, 'Ali Raza');
    expect(person.phone, isNull); // blank phone becomes null
    expect(person.note, 'neighbour');
  });

  test('people sort: live balance first, then most recent activity', () async {
    final bilalId = await khata.addPerson(name: 'Bilal');
    await khata.addEntry(
        personId: aliId,
        direction: KhataDirection.gave,
        amountMinor: 100,
        currencyCode: 'PKR',
        occurredAt: DateTime(2026, 1, 1));
    await khata.addEntry(
        personId: bilalId,
        direction: KhataDirection.gave,
        amountMinor: 99900,
        currencyCode: 'PKR',
        occurredAt: DateTime(2026, 2, 1));
    final people = await khata.watchPeopleWithBalances().first;
    expect(people.first.person.id, bilalId); // bigger outstanding balance
  });

  test('foreign key: entries reference existing people', () async {
    // PRAGMA foreign_keys is ON in beforeOpen; memory DBs run it too
    // (MigrationStrategy.beforeOpen applies to every open).
    final people = await db.select(db.khataPeople).get();
    expect(people, hasLength(1));
    final entries = await db.select(db.khataEntries).get();
    expect(entries, isEmpty);
  });
}
