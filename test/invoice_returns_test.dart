import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/services/order_returns_summary.dart';
import 'package:micro_seller/data/services/pdf_service.dart';

/// Egg at 10, 5 sold (50), paid 35; two 1-egg returns, the second refunded 5.
void main() {
  OrderItem egg(double q) =>
      OrderItem(productId: 1, productName: 'Egg', qty: q, unitPrice: 10, totalPrice: 10 * q);
  final order = Order(
    orderNumber: 'ORD-001',
    items: [egg(5)],
    subtotal: 50,
    totalAmount: 50,
    amountPaid: 30, // 35 minus the 5 refund
    paymentStatus: PaymentStatus.partial,
  )..id = 7;
  Order ret(int id, ReturnStatus st, double refund) => Order(
        orderNumber: 'RET-00$id',
        items: [egg(1)],
        subtotal: 10,
        totalAmount: 10,
        refundAmount: refund,
        isReturn: true,
        originalOrderId: 7,
        returnStatus: st,
      )..id = id;
  final returns = [
    ret(8, ReturnStatus.received, 0),
    ret(9, ReturnStatus.refunded, 5),
    ret(10, ReturnStatus.requested, 0), // goods not back: not shown
  ];

  test('summary counts received returns and refunds', () {
    final s = OrderReturnsSummary.of(order, returns);
    expect(s.returns.map((r) => r.number), ['RET-008', 'RET-009']);
    expect(s.received, 35);
    expect(s.refunded, 5);
    expect(s.due, 0);
    expect(s.status, PaymentStatus.paid);
  });

  test('no returns: as before', () {
    final s = OrderReturnsSummary.of(order, const []);
    expect(s.hasReturns, isFalse);
    expect(s.status, PaymentStatus.partial);
  });

  test('WhatsApp text shows the returns and a 0 due', () {
    final text = PdfService().generateWhatsAppText(order, currencySymbol: '\$', returns: returns);
    expect(text, contains('Paid: \$35'));
    expect(text, contains('Returned RET-008 (1): -\$10'));
    expect(text, contains('Refunded: \$5'));
    expect(text, contains('Balance Due: \$0'));
    expect(text, contains('✅ Paid'));
    expect(text, isNot(contains('RET-0010')));
  });

  testWidgets('the receipt page lists the returns and the real due', (tester) async {
    tester.view.physicalSize = const Size(794, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: PdfService.receiptPage(order,
            shopName: 'Shop', sym: '\$', taxRate: 0, returns: returns),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Returned RET-008 (1)'), findsOneWidget);
    expect(find.textContaining('RET-0010'), findsNothing);
    expect(find.text('Refunded'), findsOneWidget);
    expect(find.text('PAID'), findsOneWidget);
  });
}
