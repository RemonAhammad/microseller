import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/core/l10n/app_localizations.dart';
import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/models/product.dart';
import 'package:micro_seller/data/services/isar_service.dart';
import 'package:micro_seller/features/orders/providers/order_provider.dart';
import 'package:micro_seller/features/returns/presentation/choose_return_order_screen.dart';
import 'package:micro_seller/features/returns/presentation/create_return_screen.dart';
import 'package:micro_seller/features/returns/presentation/returns_screen.dart';
import 'package:micro_seller/features/returns/providers/returnable_orders_provider.dart';

import 'support/isar_core.dart';

/// A return started from the Returns screen: + (or the empty state's button)
/// → choose the order → the usual Create Return screen. Only orders whose
/// goods were handed over and that still have something to return are
/// offered.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(closeTestIsars);

  OrderItem shirts(int productId, double qty) => OrderItem(
      productId: productId, productName: 'Shirt', qty: qty, unitPrice: 100, totalPrice: 100 * qty);

  Order sale(String number, int productId,
          {OrderStatus status = OrderStatus.completed,
          DateTime? at,
          String customer = 'Rahim',
          String phone = '01711000000'}) =>
      Order(
        orderNumber: number,
        customerName: customer,
        customerPhone: phone,
        items: [shirts(productId, 2)],
        subtotal: 200,
        totalAmount: 200,
        amountPaid: 200,
        paymentStatus: PaymentStatus.paid,
        orderStatus: status,
        createdAt: at ?? DateTime(2026, 11, 1),
      );

  Order returnOf(Order original, double qty, {ReturnStatus status = ReturnStatus.requested}) => Order(
        orderNumber: 'RET-${original.orderNumber}',
        items: [shirts(original.items.single.productId, qty)],
        subtotal: 100 * qty,
        totalAmount: 100 * qty,
        isReturn: true,
        originalOrderId: original.id,
        returnStatus: status,
        createdAt: DateTime(2026, 11, 10),
      );

  group('which orders are offered', skip: isarSkipReason, () {
    test('handed over, something left to return, newest first', () async {
      final isar = await openTestIsar('returnable-orders');
      late Order partly, fully, rejectedOnly;
      await isar.writeTxn(() async {
        final pid = await isar.products.put(Product(name: 'Shirt', sellingPrice: 100, stockQty: 50));
        Future<Order> put(Order o) async => o..id = await isar.orders.put(o);
        await put(sale('ORD-OLD', pid, at: DateTime(2026, 10, 1)));
        await put(sale('ORD-NEW', pid, at: DateTime(2026, 11, 5), status: OrderStatus.confirmed));
        await put(sale('ORD-SHIPPED', pid, at: DateTime(2026, 11, 3), status: OrderStatus.shipped));
        await put(sale('ORD-PENDING', pid, status: OrderStatus.pending));
        await put(sale('ORD-CANCELLED', pid, status: OrderStatus.cancelled));
        partly = await put(sale('ORD-PARTLY', pid, at: DateTime(2026, 11, 4)));
        fully = await put(sale('ORD-FULLY', pid));
        rejectedOnly = await put(sale('ORD-REJECTED', pid, at: DateTime(2026, 9, 1)));
        await isar.orders.putAll([
          returnOf(partly, 1),
          returnOf(fully, 2, status: ReturnStatus.received),
          returnOf(rejectedOnly, 2, status: ReturnStatus.rejected),
        ]);
      });

      final numbers = returnableOrdersJob(isar).map((o) => o.orderNumber).toList();
      expect(numbers, ['ORD-NEW', 'ORD-PARTLY', 'ORD-SHIPPED', 'ORD-OLD', 'ORD-REJECTED'],
          reason: 'no pending, cancelled, fully returned or return orders; a rejected return gives it all back');
    });
  });

  test('search: order number, customer, phone in any script', () {
    final o = sale('ORD-042', 1, customer: 'Karim Traders', phone: '01712345678');
    expect(returnOrderMatches(o, ''), isTrue);
    expect(returnOrderMatches(o, 'ord-042'), isTrue);
    expect(returnOrderMatches(o, 'karim'), isTrue);
    expect(returnOrderMatches(o, '2345'), isTrue);
    expect(returnOrderMatches(o, '২৩৪৫'), isTrue, reason: 'Bengali digits');
    expect(returnOrderMatches(o, 'rahim'), isFalse);
  });

  group('screens', skip: isarSkipReason, () {
    late Isar isar;
    late Order a, b;

    Future<void> pumpReturns(WidgetTester tester, {List<Order> returns = const []}) async {
      isar = await tester.runAsync(() => openTestIsar('returns-fab')) as Isar;
      await tester.runAsync(() => isar.writeTxn(() async {
            final pid = await isar.products.put(Product(name: 'Shirt', sellingPrice: 100, stockQty: 50));
            a = sale('ORD-001', pid, customer: 'Rahim');
            a.id = await isar.orders.put(a);
            b = sale('ORD-002', pid, customer: 'Karim', phone: '01899999999');
            b.id = await isar.orders.put(b);
          }));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isarProvider.overrideWith((ref) async => isar),
          returnOrdersProvider.overrideWith((ref) => Stream.value(returns)),
          returnableOrdersProvider.overrideWith((ref) => Stream.value([b, a])),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReturnsScreen(),
        ),
      ));
      await settle(tester);
    }

    testWidgets('+ opens the order picker; search narrows it; an order opens Create Return', (tester) async {
      await pumpReturns(tester);

      await tester.tap(find.byTooltip('Create Return'));
      await settle(tester);
      expect(find.byType(ChooseReturnOrderScreen), findsOneWidget);
      expect(find.text('ORD-001'), findsOneWidget);
      expect(find.text('ORD-002'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'karim');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('ORD-001'), findsNothing);
      expect(find.text('ORD-002'), findsOneWidget);

      await tester.tap(find.text('ORD-002'));
      await settle(tester);
      final create = tester.widget<CreateReturnScreen>(find.byType(CreateReturnScreen));
      expect(create.originalOrder.id, b.id);
    });

    testWidgets("the empty All tab's button opens the picker too", (tester) async {
      await pumpReturns(tester);
      expect(find.text('No returns'), findsOneWidget);

      await tester.tap(find.text('Create Return'));
      await settle(tester);
      expect(find.byType(ChooseReturnOrderScreen), findsOneWidget);
    });

    testWidgets('the picker lays out at 320–411 dp and up to 150% text, long names and amounts', (tester) async {
      final long = sale('ORD-1234567', 1,
          customer: 'Mohammad Abdur Rahman Chowdhury Enterprise Limited')
        ..totalAmount = 98765432.5;
      for (final width in [320.0, 360.0, 411.0]) {
        for (final scale in [1.0, 1.3, 1.5]) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(ProviderScope(
            key: UniqueKey(),
            overrides: [
              returnableOrdersProvider.overrideWith((ref) => Stream.value([long])),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const ChooseReturnOrderScreen(),
            ),
          ));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$width dp × $scale');
          expect(find.text('ORD-1234567'), findsOneWidget);
        }
      }
      addTearDown(tester.view.reset);
    });

    testWidgets('nothing to return says so', (tester) async {
      isar = await tester.runAsync(() => openTestIsar('returns-none')) as Isar;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isarProvider.overrideWith((ref) async => isar),
          returnableOrdersProvider.overrideWith((ref) => Stream.value(const <Order>[])),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChooseReturnOrderScreen(),
        ),
      ));
      await settle(tester);
      expect(find.text('No orders with items to return'), findsOneWidget);
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
