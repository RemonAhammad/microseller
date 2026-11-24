import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:micro_seller/data/models/customer.dart';
import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/payment.dart';
import 'package:micro_seller/data/services/db_worker.dart';
import 'package:micro_seller/data/services/isar_service.dart';
import 'package:micro_seller/features/customers/presentation/customer_detail_screen.dart';
import 'package:micro_seller/features/customers/providers/customer_detail_providers.dart';
import 'package:micro_seller/features/customers/providers/dues_provider.dart';

import 'support/isar_core.dart';
import 'support/screen_harness.dart';

/// Issue #28: the customer detail screen loads only this customer's data,
/// a page at a time, and its numbers match the Due Book.
void main() {
  tearDown(closeTestIsars);

  group('customer detail data', skip: isarSkipReason, () {
    late Isar isar;
    late int rahim;
    late int karim;
    final now = DateTime.now();

    Order sale(int customerId, String no, DateTime at, double total,
            {double paid = 0, bool isReturn = false, OrderStatus status = OrderStatus.confirmed}) =>
        Order(
          orderNumber: no, customerId: customerId, customerName: 'x',
          subtotal: total, totalAmount: total, amountPaid: paid,
          orderStatus: status, isReturn: isReturn, createdAt: at,
        );

    Future<void> seed({int orders = 0, int payments = 0}) async {
      isar = await openTestIsar('customer_detail_${orders}_$payments');
      dbWorkerCoreLibrary = isarCoreLibrary();
      await isar.writeTxn(() async {
        rahim = await isar.customers.put(Customer(name: 'Rahim'));
        karim = await isar.customers.put(Customer(name: 'Karim'));
        for (var i = 0; i < orders; i++) {
          await isar.orders.put(sale(rahim, 'ORD-$i', DateTime(2025, 1, 1).add(Duration(days: i)), 10,
              paid: i.isEven ? 10 : 4));
        }
        for (var i = 0; i < payments; i++) {
          await isar.payments.put(Payment(
              customerId: rahim, orderId: 1, amount: 1, paidAt: DateTime(2025, 1, 1).add(Duration(hours: i))));
        }
      });
    }

    test('purchase history pages newest first and reloads only for this customer', () async {
      await seed(orders: 250);
      final first = customerOrdersWindowJob(rahim, 0, 100, null)(isar);
      expect(first.rows, hasLength(100));
      expect(first.rows.first.orderNumber, 'ORD-249');
      expect(first.hasMore, isTrue);

      final next = customerOrdersWindowJob(rahim, 100, 100, first.signature)(isar);
      expect(next.changed, isFalse);
      expect(next.rows.first.orderNumber, 'ORD-149');

      final last = customerOrdersWindowJob(rahim, 200, 100, first.signature)(isar);
      expect(last.rows, hasLength(50));
      expect(last.hasMore, isFalse);

      // Another customer's order: nothing to reload.
      await isar.writeTxn(() => isar.orders.put(sale(karim, 'ORD-K', now, 5)));
      final same = customerOrdersWindowJob(rahim, 0, 200, first.signature)(isar);
      expect(same.changed, isFalse);
      expect(same.rows, isEmpty);

      // One of this customer's orders edited: reload.
      final edited = (await isar.orders.filter().orderNumberEqualTo('ORD-3').findFirst())!
        ..updatedAt = now;
      await isar.writeTxn(() => isar.orders.put(edited));
      final again = customerOrdersWindowJob(rahim, 0, 200, first.signature)(isar);
      expect(again.changed, isTrue);
      expect(again.rows, hasLength(200));

      // A next page asked for after a change says so instead of mixing rows.
      final stale = customerOrdersWindowJob(rahim, 100, 100, first.signature)(isar);
      expect(stale.changed, isTrue);
      expect(stale.rows, isEmpty);
    });

    test('the notifier appends the next page and keeps the first', () async {
      await seed(orders: 150);
      final c = ProviderContainer(overrides: [isarProvider.overrideWith((ref) async => isar)]);
      addTearDown(c.dispose);
      final sub = c.listen(customerOrdersProvider(rahim), (_, _) {});
      addTearDown(sub.close);
      final page1 = await c.read(customerOrdersProvider(rahim).future);
      expect(page1.orders, hasLength(100));
      expect(page1.hasMore, isTrue);

      c.read(customerOrdersProvider(rahim).notifier).loadMore();
      final page2 = await _next<CustomerOrdersPage>(c, customerOrdersProvider(rahim), (p) => p.orders.length > 100);
      expect(page2.orders, hasLength(150));
      expect(page2.hasMore, isFalse);
      expect(identical(page2.orders.first, page1.orders.first), isTrue,
          reason: 'the first page is kept, not loaded again');
    });

    test("the customer's due equals the Due Book's", () async {
      await seed(orders: 40);
      final book = loadDuesSync(isar).singleWhere((d) => d.customer.id == rahim);
      final mine = customerDueJob(rahim)(isar)!;
      expect(mine.totalDue, book.totalDue);
      expect(mine.orderDues.map((d) => d.order.id), book.orderDues.map((d) => d.order.id));
      expect(customerDueJob(karim)(isar), isNull);
    });

    test('payments: the latest 10, then more on request', () async {
      await seed(payments: 25);
      final c = ProviderContainer(overrides: [isarProvider.overrideWith((ref) async => isar)]);
      addTearDown(c.dispose);
      final sub = c.listen(customerPaymentPagesProvider(rahim), (_, _) {});
      addTearDown(sub.close);
      final first = await c.read(customerPaymentPagesProvider(rahim).future);
      expect(first.payments, hasLength(10));
      expect(first.hasMore, isTrue);
      expect(first.payments.first.paidAt!.isAfter(first.payments.last.paidAt!), isTrue);

      c.read(customerPaymentPagesProvider(rahim).notifier).loadMore();
      final more = await _next<CustomerPaymentsPage>(c, customerPaymentPagesProvider(rahim), (p) => p.payments.length > 10);
      expect(more.payments, hasLength(25));
      expect(more.hasMore, isFalse);
    });

    test('the 6-month chart leaves out returns and cancelled orders', () async {
      await seed();
      final thisMonth = DateTime(now.year, now.month, 1);
      await isar.writeTxn(() async {
        await isar.orders.putAll([
          sale(rahim, 'ORD-1', thisMonth, 100),
          sale(rahim, 'RET-1', thisMonth, 40, isReturn: true),
          sale(rahim, 'ORD-2', thisMonth, 70, status: OrderStatus.cancelled),
          sale(rahim, 'ORD-OLD', DateTime(now.year - 2), 999),
        ]);
      });
      final c = ProviderContainer(overrides: [isarProvider.overrideWith((ref) async => isar)]);
      addTearDown(c.dispose);
      final sub = c.listen(customerMonthlySpendingProvider(rahim), (_, _) {});
      addTearDown(sub.close);
      final months = (await c.read(customerMonthlySpendingProvider(rahim).future))!;
      expect(months, hasLength(6));
      expect(months[thisMonth], 100);
      expect(months.values.fold<double>(0, (a, b) => a + b), 100);

      final none = c.listen(customerMonthlySpendingProvider(karim), (_, _) {});
      addTearDown(none.close);
      expect(await c.read(customerMonthlySpendingProvider(karim).future), isNull);
    });

    testWidgets('the screen pages payments and lists orders under a translated chart', (tester) async {
      await tester.runAsync(() => seed(orders: 3, payments: 12));
      await pumpScreen(tester, isar: isar, screen: CustomerDetailScreen(customerId: rahim));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.text('Purchase History (6 months)'), findsOneWidget);
      expect(find.text('Payment History'), findsOneWidget);
      expect(find.text('Show more'), findsOneWidget);
      await tester.dragUntilVisible(
          find.text('Show more'), find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pump();
      await tester.tap(find.text('Show more'));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.text('Show more'), findsNothing);
      expect(find.text('Orders'), findsWidgets);
      expect(find.text('ORD-2', skipOffstage: false), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<T> _next<T>(ProviderContainer c, dynamic provider, bool Function(T) ok) {
  final done = Completer<T>();
  final sub = c.listen<AsyncValue<T>>(provider, (_, next) {
    final v = next.value;
    if (v != null && ok(v) && !done.isCompleted) done.complete(v);
  });
  return done.future.timeout(const Duration(seconds: 10)).whenComplete(sub.close);
}
