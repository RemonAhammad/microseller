import 'package:isar_community/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/utils/number_input.dart';
import '../../../data/models/order.dart';
import '../../../data/services/db_worker.dart';
import '../../../data/services/isar_reload.dart';
import '../../../data/services/isar_service.dart';
import '../../../data/services/returnable_service.dart';

part 'returnable_orders_provider.g.dart';

/// The orders a new return can be made against, newest first: sales whose
/// goods were handed over (not pending, whose stock was never deducted, and
/// not cancelled) with something left to return. Loaded on a worker, since
/// it reads every order.
@riverpod
Stream<List<Order>> returnableOrders(Ref ref) async* {
  final isar = await ref.watch(isarProvider.future);
  yield* reloadOn(
      isar.orders.watchLazy(), () => runDbJob(isar, returnableOrdersJob));
}

/// Worker job (top-level, see `runDbJob`).
List<Order> returnableOrdersJob(Isar db) {
  final sales = db.orders
      .filter()
      .isReturnEqualTo(false)
      .not()
      .orderStatusEqualTo(OrderStatus.pending)
      .not()
      .orderStatusEqualTo(OrderStatus.cancelled)
      .findAllSync();
  final returnsByOrder = <int, List<Order>>{};
  for (final r in db.orders.filter().isReturnEqualTo(true).findAllSync()) {
    (returnsByOrder[r.originalOrderId] ??= []).add(r);
  }
  return returnableAmong(sales, returnsByOrder);
}

/// [sales] with something left to return, newest first (ties: higher id
/// first; no date last).
List<Order> returnableAmong(
    List<Order> sales, Map<int, List<Order>> returnsByOrder) {
  final left = [
    for (final o in sales)
      if (hasReturnable(o, returnsByOrder[o.id] ?? const [])) o,
  ];
  left.sort((a, b) {
    final da = a.createdAt, db = b.createdAt;
    if (da != null && db != null && da != db) return db.compareTo(da);
    if (da == null && db != null) return 1;
    if (db == null && da != null) return -1;
    return b.id.compareTo(a.id);
  });
  return left;
}

/// Whether [order] matches a search: its number, the customer's name, or
/// their phone in any script's digits. [query] is lowercased.
bool returnOrderMatches(Order order, String query) {
  if (query.isEmpty) return true;
  return order.orderNumber.toLowerCase().contains(query) ||
      order.customerName.toLowerCase().contains(query) ||
      (order.customerPhone.isNotEmpty && NumberInput.phoneMatches(order.customerPhone, query));
}
