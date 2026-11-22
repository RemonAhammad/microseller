import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/data/models/customer.dart';
import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/models/payment.dart';
import 'package:micro_seller/data/models/product.dart';
import 'package:micro_seller/data/models/stock_movement.dart';
import 'package:micro_seller/data/services/isar_service.dart';
import 'package:micro_seller/features/orders/providers/order_provider.dart';

import 'support/isar_core.dart';

/// Deleting a return on a real database. Only a requested return can go: it
/// has moved nothing yet, so deleting it only puts the original order's
/// return status back. A received or refunded return moved stock, the
/// customer's balance and the original's payments; the sale path used to
/// restock it again and leave the refund behind, so it's refused.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(closeTestIsars);

  group('delete a return', skip: isarSkipReason, () {
    late Isar isar;
    late ProviderContainer container;
    late OrderNotifier notifier;
    late int productId;
    late int customerId;

    Future<void> shop(String name) async {
      isar = await openTestIsar(name);
      await isar.writeTxn(() async {
        productId = await isar.products
            .put(Product(name: 'Shirt', sellingPrice: 500, costPrice: 300, stockQty: 10));
        customerId = await isar.customers.put(Customer(name: 'Rahim', phone: '01700000000'));
      });
      container = ProviderContainer(overrides: [isarProvider.overrideWith((ref) async => isar)]);
      addTearDown(container.dispose);
      notifier = container.read(orderProvider.notifier);
    }

    OrderItem shirts(double qty) => OrderItem(
          productId: productId,
          productName: 'Shirt',
          qty: qty,
          unitPrice: 500,
          costPrice: 300,
          totalPrice: 500 * qty,
        );

    Future<Order> sell() async {
      final id = await notifier.createOrder(Order(
        orderNumber: 'ORD-001',
        customerId: customerId,
        customerName: 'Rahim',
        items: [shirts(2)],
        subtotal: 1000,
        totalAmount: 1000,
        amountPaid: 1000,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.confirmed,
        createdAt: DateTime.now(),
      ));
      return (await isar.orders.get(id))!;
    }

    Future<Order> returnOne(Order original) async {
      await notifier.createReturnOrder(
        originalOrder: (await isar.orders.get(original.id))!,
        returnItems: [shirts(1)],
        reason: ReturnReason.defective,
        refundAmount: 500,
      );
      final returns = await isar.orders.filter().isReturnEqualTo(true).sortByCreatedAt().findAll();
      return returns.last;
    }

    /// Everything a delete must not touch, to compare before and after.
    Future<Map<String, Object?>> snapshot(int originalId) async {
      final p = (await isar.products.get(productId))!;
      final c = (await isar.customers.get(customerId))!;
      final o = (await isar.orders.get(originalId))!;
      return {
        'stock': p.stockQty,
        'movements': await isar.stockMovements.count(),
        'payments': await isar.payments.count(),
        'totalOrders': c.totalOrders,
        'totalSpent': c.totalSpent,
        'balance': c.outstandingBalance,
        'paid': o.amountPaid,
        'paymentStatus': o.paymentStatus,
      };
    }

    test('a requested return is deleted, and only the original order\'s return status changes', () async {
      await shop('del-ret-requested');
      final order = await sell();
      final ret = await returnOne(order);
      expect((await isar.orders.get(order.id))!.returnStatus, ReturnStatus.requested);
      final before = await snapshot(order.id);

      await notifier.deleteOrder(ret.id);

      expect(container.read(orderProvider).hasError, isFalse);
      expect(await isar.orders.get(ret.id), isNull);
      expect((await isar.orders.get(order.id))!.returnStatus, ReturnStatus.none);
      expect(await snapshot(order.id), before, reason: 'no stock, customer or payment change');
    });

    test('with another return still open, the original keeps that one\'s status', () async {
      await shop('del-ret-two');
      final order = await sell();
      final first = await returnOne(order);
      await notifier.approveReturn(first.id);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await returnOne(order);

      await notifier.deleteOrder(second.id);

      expect(await isar.orders.get(second.id), isNull);
      expect((await isar.orders.get(order.id))!.returnStatus, ReturnStatus.received);
    });

    test('a received return is refused, and nothing changes', () async {
      await shop('del-ret-received');
      final order = await sell();
      final ret = await returnOne(order);
      await notifier.approveReturn(ret.id);
      expect((await isar.products.get(productId))!.stockQty, 9, reason: '10 − 2 sold + 1 back');
      final before = await snapshot(order.id);

      await notifier.deleteOrder(ret.id);

      expect(container.read(orderProvider).hasError, isTrue);
      expect(await isar.orders.get(ret.id), isNotNull);
      expect((await isar.orders.get(order.id))!.returnStatus, ReturnStatus.received);
      expect(await snapshot(order.id), before);
    });

    test('a refunded return is refused: no second restock, the refund stays', () async {
      await shop('del-ret-refunded');
      final order = await sell();
      final ret = await returnOne(order);
      await notifier.approveReturn(ret.id);
      await notifier.processRefund(ret.id, amount: 500);
      final before = await snapshot(order.id);
      expect(before['stock'], 9);

      await notifier.deleteOrder(ret.id);

      expect(container.read(orderProvider).hasError, isTrue);
      expect(await isar.orders.get(ret.id), isNotNull);
      expect(await snapshot(order.id), before, reason: 'used to restock again and keep the refund row');
      expect(
        await isar.stockMovements.filter().reasonContains('Deleted order').count(),
        0,
      );
    });

    test('a rejected return is refused too', () async {
      await shop('del-ret-rejected');
      final order = await sell();
      final ret = await returnOne(order);
      await notifier.rejectReturn(ret.id);

      await notifier.deleteOrder(ret.id);

      expect(container.read(orderProvider).hasError, isTrue);
      expect(await isar.orders.get(ret.id), isNotNull);
    });

    test('deleting a sale still restores stock and the customer, as before', () async {
      await shop('del-ret-sale');
      final order = await sell();
      expect((await isar.products.get(productId))!.stockQty, 8);

      await notifier.deleteOrder(order.id);

      expect(container.read(orderProvider).hasError, isFalse);
      expect(await isar.orders.get(order.id), isNull);
      expect((await isar.products.get(productId))!.stockQty, 10);
      expect(await isar.payments.filter().orderIdEqualTo(order.id).count(), 0);
    });
  });
}
