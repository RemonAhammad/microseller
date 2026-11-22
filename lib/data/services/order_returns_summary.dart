import '../models/order.dart';
import 'dues_service.dart';

/// One received return on an order's invoice.
class InvoiceReturnRow {
  final String number;
  final DateTime? date;
  final double qty;
  final double value;
  const InvoiceReturnRow({required this.number, this.date, required this.qty, required this.value});
}

/// An order's money as its invoices show it once returns are counted:
/// what was received, what came back as goods and as cash, what's left.
/// The same rule as the order detail screen and the Due Book.
class OrderReturnsSummary {
  final List<InvoiceReturnRow> returns;

  /// Cash given back for those returns.
  final double refunded;

  /// Every payment received for the order (its `amountPaid` was lowered by
  /// the refunds, so they're added back).
  final double received;

  final double due;
  final PaymentStatus status;

  const OrderReturnsSummary._(this.returns, this.refunded, this.received, this.due, this.status);

  bool get hasReturns => returns.isNotEmpty;

  /// From [order] and any orders in [allReturns]; only this order's returns
  /// whose goods are back count.
  factory OrderReturnsSummary.of(Order order, Iterable<Order> allReturns) {
    final mine = allReturns
        .where((r) => r.isCompletedReturn && r.originalOrderId == order.id && order.id > 0)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final rows = [
      for (final r in mine)
        InvoiceReturnRow(
          number: r.orderNumber,
          date: r.updatedAt ?? r.createdAt,
          qty: r.items.fold<double>(0, (s, i) => s + i.qty),
          value: r.totalAmount,
        ),
    ];
    final returned = rows.fold<double>(0, (s, r) => s + r.value);
    final refunded = mine
        .where((r) => r.returnStatus == ReturnStatus.refunded)
        .fold<double>(0, (s, r) => s + r.refundAmount);
    final due = order.isReturn ? 0.0 : order.balanceDue - returned;
    return OrderReturnsSummary._(
      rows,
      refunded,
      order.amountPaid + refunded,
      due > kDueEpsilon ? due : 0.0,
      mine.isEmpty
          ? order.paymentStatus
          : paymentStatusFor(total: order.totalAmount, paid: order.amountPaid, returned: returned),
    );
  }
}
