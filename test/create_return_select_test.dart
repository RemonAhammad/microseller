import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/models/product.dart';
import 'package:micro_seller/core/constants/app_icons.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;
import 'package:micro_seller/features/returns/presentation/create_return_screen.dart';

import 'support/isar_core.dart';
import 'support/screen_harness.dart';

/// Create Return starts with nothing selected; Select All, 1 each and Clear
/// set every line at once.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(closeTestIsars);

  Future<(Isar, Order)> seed(WidgetTester tester) async {
    late Isar isar;
    late Order sale;
    await tester.runAsync(() async {
      isar = await openTestIsar('return_select');
      await isar.writeTxn(() async {
        final a = await isar.products.put(Product(name: 'Shirt', sellingPrice: 100, stockQty: 10));
        final b = await isar.products.put(Product(name: 'Cap', sellingPrice: 50, stockQty: 10));
        final id = await isar.orders.put(Order(
          orderNumber: 'ORD-001',
          items: [
            OrderItem(productId: a, productName: 'Shirt', qty: 3, unitPrice: 100, totalPrice: 300),
            OrderItem(productId: b, productName: 'Cap', qty: 2, unitPrice: 50, totalPrice: 100),
          ],
          subtotal: 400,
          totalAmount: 400,
          amountPaid: 400,
          paymentStatus: PaymentStatus.paid,
          orderStatus: OrderStatus.completed,
          createdAt: DateTime(2026, 11, 1),
        ));
        sale = (await isar.orders.get(id))!;
      });
    });
    return (isar, sale);
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed != null;

  testWidgets('starts at 0; Select All, 1 each and Clear', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    expect(find.text('0 of 2 selected'), findsOneWidget);
    expect(enabled(tester, 'returnClear'), isFalse);
    expect(enabled(tester, 'returnSelectAll'), isTrue);

    await tester.tap(find.byKey(const ValueKey('returnSelectAll')));
    await tester.pump();
    expect(find.text('2 of 2 selected'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(enabled(tester, 'returnSelectAll'), isFalse);

    await tester.tap(find.byKey(const ValueKey('returnOneEach')));
    await tester.pump();
    expect(find.text('1'), findsNWidgets(2));
    expect(enabled(tester, 'returnOneEach'), isFalse);

    await tester.tap(find.byKey(const ValueKey('returnClear')));
    await tester.pump();
    expect(find.text('0 of 2 selected'), findsOneWidget);
    expect(enabled(tester, 'returnClear'), isFalse);
  });

  testWidgets('nothing selected is refused; one line returns alone', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    final submit = find.text('Submit Return Request');
    await tester.scrollUntilVisible(submit, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Select at least one item to return'), findsOneWidget);
    expect(await tester.runAsync(() => isar.orders.filter().isReturnEqualTo(true).count()), 0);
    // The snackbar would cover the submit button on the next tap.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();

    // The Cap line's +.
    await tester.scrollUntilVisible(find.text('Cap'), -200, scrollable: find.byType(Scrollable).first);
    final capRow = find.ancestor(of: find.text('Cap'), matching: find.byType(Row)).first;
    final plus = find.descendant(
        of: capRow,
        matching: find.byWidgetPredicate((w) => w is ThinIcon && w.builder == tabler.Plus.new));
    await tester.tap(plus);
    await tester.pump();
    expect(find.descendant(of: capRow, matching: find.text('1')), findsOneWidget);

    await tester.scrollUntilVisible(submit, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await settleDb(tester);
    final ret = (await tester.runAsync(
        () => isar.orders.filter().isReturnEqualTo(true).findFirst()))!;
    expect(ret.items.single.productName, 'Cap');
    expect(ret.items.single.qty, 1);
  });
}
