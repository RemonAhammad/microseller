import '../models/order.dart';

/// What one line of an order can still be returned: earlier returns of the
/// order (any not rejected, pending ones included) use it up.
class Returnable {
  final double qty;
  final List<String> serials;
  final double alreadyReturned;
  const Returnable({required this.qty, required this.serials, required this.alreadyReturned});
}

/// Thrown by `createReturnOrder` when a return asks for more of a line than
/// is left of it.
class ReturnExceedsSold implements Exception {
  const ReturnExceedsSold();
  @override
  String toString() => 'ReturnExceedsSold';
}

String _lineKey(int productId, String combinationKey) => '$productId|$combinationKey';

/// One [Returnable] per line of [original], in order. Returned quantities
/// are matched by product + variant and used up line by line, so two lines
/// of the same item are each limited correctly.
List<Returnable> returnableFor(Order original, Iterable<Order> returns) {
  final returnedQty = <String, double>{};
  final returnedSerials = <String>{};
  for (final r in returns) {
    if (!r.isReturn || r.originalOrderId != original.id) continue;
    if (r.returnStatus == ReturnStatus.rejected) continue;
    for (final it in r.items) {
      final k = _lineKey(it.productId, it.variantCombinationKey);
      returnedQty[k] = (returnedQty[k] ?? 0) + it.qty;
      returnedSerials.addAll(it.serials);
    }
  }
  return [
    for (final item in original.items)
      () {
        final k = _lineKey(item.productId, item.variantCombinationKey);
        final used = (returnedQty[k] ?? 0).clamp(0.0, item.qty);
        returnedQty[k] = (returnedQty[k] ?? 0) - used;
        final serials = item.serials.where((s) => !returnedSerials.contains(s)).toList();
        final left = item.hasSerials ? serials.length.toDouble() : item.qty - used;
        return Returnable(
          qty: left < 1e-9 ? 0.0 : left,
          serials: serials,
          alreadyReturned: item.qty - (left < 1e-9 ? 0.0 : left),
        );
      }(),
  ];
}

/// Whether anything of [original] is left to return.
bool hasReturnable(Order original, Iterable<Order> returns) =>
    returnableFor(original, returns).any((r) => r.qty > 1e-9);
