import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/services/pdf_service.dart';
import 'package:micro_seller/data/services/pos_printer_service.dart';

/// A return's documents (Share / Download / Print, WhatsApp, POS) are a
/// return invoice: what came back, from which order, why, and the refund.
/// A return has no payments of its own, so the sales invoice's Paid /
/// Balance due / Unpaid would read as money the customer owes.
void main() {
  final shirt = OrderItem(productName: 'Blue Shirt', qty: 1, unitPrice: 500, totalPrice: 500);

  Order returnOrder({ReturnStatus status = ReturnStatus.requested, double refund = 450}) => Order(
        orderNumber: 'RET-003',
        customerName: 'Rahim',
        items: [shirt],
        subtotal: 500,
        discountAmount: 50,
        totalAmount: 450,
        refundAmount: refund,
        amountPaid: 0,
        paymentStatus: PaymentStatus.unpaid,
        isReturn: true,
        originalOrderId: 7,
        returnStatus: status,
        returnReason: ReturnReason.defective,
        returnNotes: 'Torn seam',
        notes: 'Return for ORD-007',
        createdAt: DateTime(2026, 11, 20),
      );

  final sale = Order(
    orderNumber: 'ORD-007',
    items: [shirt],
    subtotal: 500,
    totalAmount: 500,
    amountPaid: 200,
    paymentStatus: PaymentStatus.partial,
    createdAt: DateTime(2026, 11, 18),
  );

  Future<void> pumpReceipt(WidgetTester tester, Order order, {String? original}) async {
    tester.view.physicalSize = const Size(794, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: PdfService.receiptPage(order,
            shopName: 'Shop', sym: '\$', taxRate: 0, originalOrderNumber: original),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
  }

  group('PDF page', () {
    testWidgets('a return is a return invoice, with no payment rows', (tester) async {
      await pumpReceipt(tester, returnOrder(), original: 'ORD-007');

      expect(find.text('Return Invoice'), findsOneWidget);
      expect(find.text('Invoice'), findsNothing);
      expect(find.text('RET-003'), findsOneWidget);
      expect(find.text('Against order'), findsOneWidget);
      expect(find.text('ORD-007'), findsOneWidget);
      expect(find.text('Defective'), findsOneWidget);
      expect(find.text('Requested'), findsOneWidget);
      expect(find.text('Returned Items'), findsOneWidget);
      expect(find.text('Return Total'), findsOneWidget);
      expect(find.text('Refund (pending)'), findsOneWidget);
      expect(find.text('Torn seam'), findsOneWidget, reason: "the return's own notes");
      expect(find.text('Return for ORD-007'), findsNothing);
      expect(find.text('RETURN REQUESTED'), findsOneWidget);

      expect(find.text('Paid'), findsNothing);
      expect(find.text('Balance Due'), findsNothing);
      expect(find.text('UNPAID'), findsNothing);
      expect(find.text('Bill To:'), findsNothing);
    });

    testWidgets('a refunded return says the refund was paid', (tester) async {
      await pumpReceipt(tester, returnOrder(status: ReturnStatus.refunded), original: 'ORD-007');
      expect(find.text('Refund (paid)'), findsOneWidget);
      expect(find.text('RETURN REFUNDED'), findsOneWidget);
    });

    testWidgets('an exchange (no refund) and an unknown original order still lay out', (tester) async {
      await pumpReceipt(tester, returnOrder(refund: 0));
      expect(find.text('Refund'), findsOneWidget);
      expect(find.text('Against order'), findsNothing);
    });

    testWidgets('a sale keeps its sales invoice', (tester) async {
      await pumpReceipt(tester, sale);
      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Return Invoice'), findsNothing);
      expect(find.text('Bill To:'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Balance Due'), findsOneWidget);
      expect(find.text('PARTIALLY PAID'), findsOneWidget);
    });
  });

  test('WhatsApp text for a return describes the return', () {
    final text = PdfService().generateWhatsAppText(returnOrder(),
        currencySymbol: '\$', originalOrderNumber: 'ORD-007');
    expect(text, startsWith('↩️ Return RET-003 (order ORD-007)'));
    expect(text, contains('Returned items:'));
    expect(text, contains('*Return total: \$450*'));
    expect(text, contains('Refund: \$450 (pending)'));
    expect(text, contains('Reason: Defective'));
    expect(text, contains('Status: Requested'));
    expect(text, isNot(contains('Unpaid')));
    expect(text, isNot(contains('📦 Order')));
  });

  test('WhatsApp text for a sale is unchanged', () {
    final text = PdfService().generateWhatsAppText(sale, currencySymbol: '\$');
    expect(text, startsWith('📦 Order ORD-007'));
    expect(text, contains('Partially Paid'));
  });

  test('POS receipt for a return', () {
    final lines = PosPrinterService.instance
        .buildReceiptLinesForTest(order: returnOrder(), originalOrderNumber: 'ORD-007');
    final text = lines.join('\n');
    expect(text, contains('RETURN INVOICE'));
    expect(text, contains('Return: RET-003'));
    expect(text, contains('Order: ORD-007'));
    expect(text, contains('RETURN TOTAL:'));
    expect(text, contains('Refund (pending):'));
    expect(text, contains('Reason: Defective'));
    expect(text, isNot(contains('Paid:')));
    expect(text, isNot(contains('Due:')));
  });

  test('POS receipt for a sale keeps Paid and Due', () {
    final text = PosPrinterService.instance.buildReceiptLinesForTest(order: sale).join('\n');
    expect(text, contains('Order: ORD-007'));
    expect(text, contains('Paid:'));
    expect(text, contains('Due:'));
    expect(text, isNot(contains('RETURN')));
  });
}
