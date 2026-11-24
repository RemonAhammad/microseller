import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/core/constants/app_icons.dart';
import 'package:micro_seller/core/utils/currency_formatter.dart';
import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/models/product.dart';
import 'package:micro_seller/features/returns/presentation/create_return_screen.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;

import 'support/isar_core.dart';
import 'support/screen_harness.dart';

/// Create Return explains the refund when the order had a discount: each
/// line's price after the discount, and list price − discount share =
/// return value, with what's still owed paid off before cash goes back.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(closeTestIsars);

  String money(double v) => CurrencyFormatter.format(v);

  /// [lines]: (name, qty, unit price). The order is completed.
  Future<(Isar, Order)> seed(WidgetTester tester,
      {required List<(String, double, double)> lines,
      required double discount,
      required double paid,
      double tax = 0,
      List<(int, double)> earlierReturns = const []}) async {
    late Isar isar;
    late Order sale;
    await tester.runAsync(() async {
      isar = await openTestIsar('return_discount');
      await isar.writeTxn(() async {
        final items = <OrderItem>[];
        for (final (name, qty, price) in lines) {
          final id = await isar.products.put(Product(name: name, sellingPrice: price, stockQty: 50));
          items.add(OrderItem(
              productId: id, productName: name, qty: qty, unitPrice: price, totalPrice: qty * price));
        }
        final subtotal = items.fold(0.0, (a, i) => a + i.totalPrice);
        final total = subtotal - discount + tax;
        final id = await isar.orders.put(Order(
          orderNumber: 'ORD-001',
          items: items,
          subtotal: subtotal,
          discountAmount: discount,
          taxAmount: tax,
          totalAmount: total,
          amountPaid: paid,
          paymentStatus: paid >= total ? PaymentStatus.paid : PaymentStatus.partial,
          orderStatus: OrderStatus.completed,
          createdAt: DateTime(2026, 11, 1),
        ));
        sale = (await isar.orders.get(id))!;
        // Earlier returns of the first line whose goods are back: (qty, value).
        for (final (qty, value) in earlierReturns) {
          final first = items.first;
          await isar.orders.put(Order(
            orderNumber: 'RET-00${earlierReturns.indexOf((qty, value)) + 1}',
            items: [first.copyWith(qty: qty.toDouble(), totalPrice: qty * first.unitPrice)],
            subtotal: qty * first.unitPrice,
            totalAmount: value,
            amountPaid: value,
            isReturn: true,
            originalOrderId: id,
            returnStatus: ReturnStatus.refunded,
            orderStatus: OrderStatus.completed,
            createdAt: DateTime(2026, 11, 2),
          ));
        }
      });
    });
    return (isar, sale);
  }

  Future<void> add(WidgetTester tester, String name, int times) async {
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(name), -200, scrollable: scrollable);
    final row = find.ancestor(of: find.text(name), matching: find.byType(Row)).first;
    final plus = find.descendant(
        of: row, matching: find.byWidgetPredicate((w) => w is ThinIcon && w.builder == tabler.Plus.new));
    for (var i = 0; i < times; i++) {
      await tester.ensureVisible(plus);
      await tester.pumpAndSettle();
      await tester.tap(plus);
      await tester.pump();
    }
  }

  final calc = find.byKey(const ValueKey('returnCalculation'));

  Future<void> showCalc(WidgetTester tester) async {
    await tester.scrollUntilVisible(calc, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  Finder inCalc(String text) => find.descendant(of: calc, matching: find.text(text));

  testWidgets('eggs: 2 of 10 at \$10 with \$10 off is worth \$18', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 10, paid: 90);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    expect(find.text('After discount: ${money(9)} each'), findsOneWidget);
    expect(calc, findsNothing); // nothing selected yet

    await add(tester, 'Egg', 2);
    await showCalc(tester);
    expect(inCalc('How the refund is calculated'), findsOneWidget);
    expect(inCalc(money(20)), findsOneWidget);
    expect(inCalc('Order discount (10%)'), findsOneWidget);
    expect(inCalc('−${money(2)}'), findsOneWidget);
    expect(inCalc(money(18)), findsNWidgets(2)); // return value, max cash refund
    expect(inCalc('Paid off from due'), findsNothing);
    expect(inCalc('Tax share'), findsNothing);
  });

  testWidgets('several items: 2 eggs + 1 rice of a \$400 order with \$40 off is \$63', skip: isarSkipReason != null,
      (tester) async {
    final (isar, sale) = await seed(tester,
        lines: [('Egg', 10, 10), ('Rice', 2, 50), ('Oil', 1, 200)], discount: 40, paid: 360);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'Egg', 2);
    await add(tester, 'Rice', 1);
    await showCalc(tester);
    expect(inCalc(money(70)), findsOneWidget);
    expect(inCalc('−${money(7)}'), findsOneWidget);
    expect(inCalc(money(63)), findsNWidgets(2));
  });

  testWidgets('what is still owed is paid off first', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 10, paid: 80);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'Egg', 2);
    await showCalc(tester);
    expect(inCalc(money(18)), findsOneWidget);
    expect(inCalc('Paid off from due'), findsOneWidget);
    expect(inCalc('−${money(10)}'), findsOneWidget);
    expect(inCalc(money(8)), findsOneWidget);
  });

  testWidgets('no discount: no calculation and no after-discount price', skip: isarSkipReason != null,
      (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 0, paid: 100);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'Egg', 2);
    await tester.pumpAndSettle();
    expect(find.textContaining('After discount'), findsNothing);
    expect(calc, findsNothing);
  });

  testWidgets('fits a 320 dp phone at 150% text', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester,
        lines: [('Organic free-range brown eggs, large', 10, 1234567), ('Rice', 2, 50)],
        discount: 1234567,
        paid: 0);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));
    tester.view.physicalSize = const Size(640, 1600);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    await add(tester, 'Organic free-range brown eggs, large', 3);
    await showCalc(tester);
    expect(tester.takeException(), isNull);
    expect(inCalc('Paid off from due'), findsOneWidget);
  });

  testWidgets('tax: its share of the returned goods is added', skip: isarSkipReason != null, (tester) async {
    // 10 × $10, $10 off, 10% tax on $90 = $9; paid in full.
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 10, tax: 9, paid: 99);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'Egg', 2);
    await showCalc(tester);
    expect(inCalc('Tax share'), findsOneWidget);
    expect(inCalc('+${money(1.8)}'), findsOneWidget);
    expect(inCalc(money(19.8)), findsNWidgets(2));
  });

  testWidgets('a second return uses the same discount and is not capped by the first',
      skip: isarSkipReason != null, (tester) async {
    // 2 eggs already returned and refunded $18: the order's paid drops to $72.
    final (isar, sale) =
        await seed(tester, lines: [('Egg', 10, 10)], discount: 10, paid: 72, earlierReturns: [(2, 18)]);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'Egg', 3);
    await showCalc(tester);
    expect(inCalc(money(30)), findsOneWidget);
    expect(inCalc('Order discount (10%)'), findsOneWidget);
    expect(inCalc(money(27)), findsNWidgets(2));
    expect(inCalc('Paid off from due'), findsNothing);
  });

  testWidgets('rounded rows still add up', skip: isarSkipReason != null, (tester) async {
    // 3 × $10 with $10 off: one is worth 6.666…, the discount 3.333….
    final (isar, sale) = await seed(tester, lines: [('Egg', 3, 10)], discount: 10, paid: 20);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'Egg', 1);
    await showCalc(tester);
    expect(inCalc(money(10)), findsOneWidget);
    expect(inCalc('Order discount (33.33%)'), findsOneWidget);
    expect(inCalc('−${money(3.33)}'), findsOneWidget);
    expect(inCalc(money(6.67)), findsNWidgets(2));
  });

  testWidgets('a discount of everything: worth nothing, no cash back', skip: isarSkipReason != null,
      (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 2, 10)], discount: 20, paid: 0);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'Egg', 1);
    await showCalc(tester);
    expect(tester.takeException(), isNull);
    expect(inCalc('Order discount (100%)'), findsOneWidget);
    expect(inCalc('Paid off from due'), findsNothing);
    expect(inCalc(money(0)), findsNWidgets(2));
  });

  testWidgets('a tiny discount on a big order never reads 0%', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('TV', 1, 100000)], discount: 1, paid: 99999);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    await add(tester, 'TV', 1);
    await showCalc(tester);
    expect(inCalc('Order discount (<0.01%)'), findsOneWidget);
    expect(inCalc('Order discount (0%)'), findsNothing);
  });

  testWidgets('Arabic, right to left, 320 dp at 150% text', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 1234567)], discount: 1234567, paid: 0);
    await pumpScreen(tester,
        isar: isar, screen: CreateReturnScreen(originalOrder: sale), locale: const Locale('ar'));
    tester.view.physicalSize = const Size(640, 1600);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    await add(tester, 'Egg', 2);
    await showCalc(tester);
    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(calc)), TextDirection.rtl);
  });

  Future<void> toggleDiscount(WidgetTester tester) async {
    final sw = find.byKey(const ValueKey('applyDiscountSwitch'));
    await tester.scrollUntilVisible(sw, -200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(sw);
    await tester.pumpAndSettle();
    await tester.tap(sw);
    await tester.pumpAndSettle();
  }

  /// The refund field's text; the list builds lazily, so scroll to it first.
  Future<String> refundText(WidgetTester tester) async {
    final field = find.descendant(
        of: find.widgetWithText(TextField, 'Refund'), matching: find.byType(EditableText));
    await tester.scrollUntilVisible(find.text('Submit Return Request'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    return tester.widget<EditableText>(field).controller.text;
  }

  test('returnValueFor without the discount: list price, tax at the order rate', () {
    final order = Order(
      orderNumber: 'ORD-001',
      items: [OrderItem(productId: 1, productName: 'Egg', qty: 10, unitPrice: 10, totalPrice: 100)],
      subtotal: 100,
      discountAmount: 10,
      taxAmount: 9, // 10% of 90
      totalAmount: 99,
    );
    final two = [OrderItem(productId: 1, productName: 'Egg', qty: 2, unitPrice: 10, totalPrice: 20)];
    final on = returnValueFor(order, two);
    expect(on.total, closeTo(19.8, 1e-9));
    final off = returnValueFor(order, two, applyDiscount: false);
    expect(off.discount, 0);
    expect(off.tax, closeTo(2, 1e-9));
    expect(off.total, closeTo(22, 1e-9));
  });

  testWidgets('discount switch: on by default, off refunds list price, back on again',
      skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 10, paid: 90);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));

    final sw = find.byKey(const ValueKey('applyDiscountSwitch'));
    expect(sw, findsOneWidget);
    expect(tester.widget<SwitchListTile>(sw).value, isTrue);

    await add(tester, 'Egg', 2);
    expect(await refundText(tester), '18.00');

    await toggleDiscount(tester);
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    expect(find.textContaining('After discount'), findsNothing);
    expect(await refundText(tester), '20.00');
    await showCalc(tester);
    expect(inCalc('Order discount (10%)'), findsNothing);
    expect(inCalc(money(20)), findsNWidgets(3)); // items, value, max refund

    await toggleDiscount(tester);
    expect(await refundText(tester), '18.00');
    await showCalc(tester);
    expect(inCalc(money(18)), findsNWidgets(2));
  });

  testWidgets('discount off is what gets saved', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 10, paid: 90);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));
    await add(tester, 'Egg', 2);
    await toggleDiscount(tester);

    final submit = find.text('Submit Return Request');
    await tester.scrollUntilVisible(submit, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await settleDb(tester);
    final ret = (await tester.runAsync(() => isar.orders.filter().isReturnEqualTo(true).findFirst()))!;
    expect(ret.totalAmount, 20);
    expect(ret.discountAmount, 0);
    expect(ret.subtotal, 20);
  });

  testWidgets('no discount: no switch', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 0, paid: 100);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));
    expect(find.byKey(const ValueKey('applyDiscountSwitch')), findsNothing);
  });

  testWidgets('switch fits 320 dp at 150% text in Arabic', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 10, paid: 90);
    await pumpScreen(tester,
        isar: isar, screen: CreateReturnScreen(originalOrder: sale), locale: const Locale('ar'));
    tester.view.physicalSize = const Size(640, 1600);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await add(tester, 'Egg', 2);
    await toggleDiscount(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('amounts line up at the end of the card', skip: isarSkipReason != null, (tester) async {
    final (isar, sale) = await seed(tester, lines: [('Egg', 10, 10)], discount: 10, paid: 80);
    await pumpScreen(tester, isar: isar, screen: CreateReturnScreen(originalOrder: sale));
    await add(tester, 'Egg', 2);
    await showCalc(tester);
    final cardEnd = tester.getRect(calc).right - 12; // the card's padding
    for (final t in [money(20), '−${money(2)}', '−${money(10)}', money(8)]) {
      expect(tester.getRect(inCalc(t)).right, moreOrLessEquals(cardEnd, epsilon: 1.5), reason: t);
    }
  });
}
