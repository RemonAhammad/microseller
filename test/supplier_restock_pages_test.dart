import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:micro_seller/data/models/stock_movement.dart';
import 'package:micro_seller/data/services/db_worker.dart';
import 'package:micro_seller/data/services/isar_service.dart';
import 'package:micro_seller/features/suppliers/providers/supplier_provider.dart';

import 'support/isar_core.dart';

/// Issue #30: a supplier's restock activity loads a page at a time, only
/// that supplier's restocks, newest first, with the true total.
void main() {
  tearDown(closeTestIsars);

  group('supplier restock pages', skip: isarSkipReason, () {
    late Isar isar;
    const a = 1, b = 2;
    final start = DateTime(2025, 1, 1);

    setUp(() async {
      isar = await openTestIsar('supplier_restock');
      dbWorkerCoreLibrary = isarCoreLibrary();
      await isar.writeTxn(() async {
        await isar.stockMovements.putAll([
          // 250 for supplier A, every fifth one a correction (qty <= 0).
          for (var i = 0; i < 250; i++)
            StockMovement(
              productId: 1,
              productName: 'Rice',
              type: i % 5 == 0 ? StockMovementType.adjustment : StockMovementType.restock,
              qty: i % 5 == 0 ? -1 : 2,
              supplierId: a,
              createdAt: start.add(Duration(hours: i)),
            ),
          for (var i = 0; i < 30; i++)
            StockMovement(
              productId: 2,
              productName: 'Oil',
              type: StockMovementType.restock,
              qty: 5,
              supplierId: b,
              createdAt: start.add(Duration(minutes: i)),
            ),
        ]);
      });
    });

    /// The query the screen used before paging.
    List<StockMovement> oldRestocks(int supplierId) => isar.stockMovements
        .filter()
        .supplierIdEqualTo(supplierId)
        .sortByCreatedAtDesc()
        .findAllSync()
        .where((m) => m.qty > 0)
        .toList();

    test('pages through exactly the old rows, with the true total', () async {
      final c = ProviderContainer(overrides: [isarProvider.overrideWith((ref) async => isar)]);
      addTearDown(c.dispose);
      final provider = supplierRestockPagesProvider(a);
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);

      final old = oldRestocks(a);
      expect(old, hasLength(200));

      final first = await c.read(provider.future);
      expect(first.movements, hasLength(100));
      expect(first.hasMore, isTrue);
      expect(first.total, 200);
      expect(first.movements.map((m) => m.id), old.take(100).map((m) => m.id));

      c.read(provider.notifier).loadMore();
      final second = await _next<SupplierRestockPage>(c, provider, (p) => p.movements.length > 100);
      expect(second.movements, hasLength(200));
      expect(second.hasMore, isFalse);
      expect(second.movements.map((m) => m.id), old.map((m) => m.id));
      expect(second.movements.every((m) => m.supplierId == a && m.qty > 0), isTrue);
    });

    test('another supplier sees only its own restocks', () async {
      final c = ProviderContainer(overrides: [isarProvider.overrideWith((ref) async => isar)]);
      addTearDown(c.dispose);
      final sub = c.listen(supplierRestockPagesProvider(b), (_, _) {});
      addTearDown(sub.close);
      final page = await c.read(supplierRestockPagesProvider(b).future);
      expect(page.movements, hasLength(30));
      expect(page.total, 30);
      expect(page.hasMore, isFalse);
      expect(page.movements.map((m) => m.id), oldRestocks(b).map((m) => m.id));
    });

    test('a new restock shows up without reopening', () async {
      final c = ProviderContainer(overrides: [isarProvider.overrideWith((ref) async => isar)]);
      addTearDown(c.dispose);
      final provider = supplierRestockPagesProvider(b);
      final sub = c.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await c.read(provider.future);

      await isar.writeTxn(() => isar.stockMovements.put(StockMovement(
            productId: 2,
            productName: 'Oil',
            type: StockMovementType.restock,
            qty: 7,
            supplierId: b,
            createdAt: DateTime(2026, 1, 1),
          )));
      final page = await _next<SupplierRestockPage>(c, provider, (p) => p.total == 31);
      expect(page.movements.first.qty, 7);
    });
  });
}

Future<T> _next<T>(ProviderContainer c, dynamic provider, bool Function(T) ok) {
  final done = Completer<T>();
  final sub = c.listen<AsyncValue<T>>(provider, (_, next) {
    final v = next.value;
    if (v != null && ok(v) && !done.isCompleted) done.complete(v);
  }, fireImmediately: true);
  return done.future.timeout(const Duration(seconds: 10)).whenComplete(sub.close);
}
