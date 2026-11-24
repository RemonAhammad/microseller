import 'dart:async';

import 'package:isar_community/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/models/customer.dart';
import '../../../data/models/order.dart';
import '../../../data/models/payment.dart';
import '../../../data/services/dues_service.dart';
import '../../../data/services/db_worker.dart';
import '../../../data/services/isar_reload.dart';
import '../../../data/services/isar_service.dart';
import 'dues_provider.dart';

part 'customer_detail_providers.g.dart';

@riverpod
Stream<Customer?> customerById(Ref ref, int id) async* {
  final isar = await ref.watch(isarProvider.future);
  yield isar.customers.getSync(id);

  yield* isar.customers.watchObject(id);
}

const kCustomerOrdersPageSize = 100;

class CustomerOrdersPage {
  const CustomerOrdersPage(this.orders, {required this.hasMore});

  final List<Order> orders;
  final bool hasMore;
}

/// What a window job found: the customer's orders' [signature] (ids and
/// dates), whether it differs from the one the caller knew, and — unless it
/// didn't — the requested slice of rows, newest first.
typedef CustomerOrdersWindow = ({
  int signature,
  bool changed,
  List<Order> rows,
  bool hasMore,
});

/// A stable fingerprint of the customer's orders (ids, created and updated
/// times). Plain arithmetic, so a worker isolate computes the same value.
int customerOrdersSignature(
    List<int> ids, List<DateTime?> created, List<DateTime?> updated) {
  var h = ids.length;
  void mix(int v) => h = (h * 31 + v) & 0x3fffffffffffffff;
  for (var i = 0; i < ids.length; i++) {
    mix(ids[i]);
    mix(created[i]?.microsecondsSinceEpoch ?? -1);
    mix(updated[i]?.microsecondsSinceEpoch ?? -1);
  }
  return h;
}

/// Loads [count] of the customer's orders starting at [from] (newest first,
/// undated last, ties by id). Only ids and dates are read for all orders; whole
/// rows only for the slice. When [known] equals the current signature and
/// [from] is 0, nothing is loaded (`changed: false`): no order of this
/// customer changed. When [known] is given with [from] > 0 and differs, no
/// rows are loaded either (`changed: true`) — the caller reloads its window.
CustomerOrdersWindow Function(Isar) customerOrdersWindowJob(
        int customerId, int from, int count, int? known) =>
    (db) => db.txnSync(() {
          final byCustomer = db.orders.where().customerIdEqualTo(customerId);
          final ids = byCustomer.idProperty().findAllSync();
          final created = byCustomer.createdAtProperty().findAllSync();
          final updated = byCustomer.updatedAtProperty().findAllSync();
          final signature = customerOrdersSignature(ids, created, updated);
          final changed = known != signature;
          if (known != null && (from == 0 ? !changed : changed)) {
            return (
              signature: signature,
              changed: changed,
              rows: const <Order>[],
              hasMore: false,
            );
          }
          final newestFirst = List.generate(ids.length, (i) => i)
            ..sort((a, b) {
              final x = created[a], y = created[b];
              final byDate = x == null
                  ? (y == null ? 0 : 1)
                  : (y == null ? -1 : y.compareTo(x));
              return byDate != 0 ? byDate : ids[a].compareTo(ids[b]);
            });
          final pageIds = [
            for (final i in newestFirst.skip(from).take(count)) ids[i],
          ];
          return (
            signature: signature,
            changed: changed,
            rows: [for (final o in db.orders.getAllSync(pageIds)) ?o],
            hasMore: newestFirst.length > from + count,
          );
        });

/// The customer's purchase history, a page at a time. "Load more" fetches
/// only the next page; a change elsewhere in the shop reloads nothing unless
/// one of this customer's orders changed.
@riverpod
class CustomerOrders extends _$CustomerOrders {
  var _orders = <Order>[];
  var _hasMore = false;
  int? _signature;
  int _wanted = kCustomerOrdersPageSize;
  StreamController<void>? _more;

  @override
  Stream<CustomerOrdersPage> build(int customerId) async* {
    final isar = await ref.watch(isarProvider.future);
    _orders = [];
    _hasMore = false;
    _signature = null;
    _wanted = kCustomerOrdersPageSize;
    final more = StreamController<void>();
    ref.onDispose(more.close);
    _more = more;

    Future<CustomerOrdersPage> reloadWindow() async {
      final w = await runDbJob(
          isar, customerOrdersWindowJob(customerId, 0, _wanted, null));
      _signature = w.signature;
      _orders = w.rows;
      _hasMore = w.hasMore;
      return CustomerOrdersPage(_orders, hasMore: _hasMore);
    }

    Future<CustomerOrdersPage> load() async {
      final known = _signature;
      if (known == null) return reloadWindow();
      if (_orders.length < _wanted && _hasMore) {
        final from = _orders.length;
        final w = await runDbJob(isar,
            customerOrdersWindowJob(customerId, from, _wanted - from, known));
        if (w.changed) return reloadWindow();
        _orders = [..._orders, ...w.rows];
        _hasMore = w.hasMore;
        return CustomerOrdersPage(_orders, hasMore: _hasMore);
      }
      final w = await runDbJob(
          isar, customerOrdersWindowJob(customerId, 0, _wanted, known));
      if (!w.changed) return CustomerOrdersPage(_orders, hasMore: _hasMore);
      _signature = w.signature;
      _orders = w.rows;
      _hasMore = w.hasMore;
      return CustomerOrdersPage(_orders, hasMore: _hasMore);
    }

    yield* reloadOn(
      mergeChanges([isar.orders.watchLazy(), more.stream]),
      load,
    );
  }

  void loadMore() {
    final page = state.value;
    if (page == null || !page.hasMore || page.orders.length < _wanted) return;
    _wanted += kCustomerOrdersPageSize;
    _more?.add(null);
  }
}

/// The customer's due, by the Due Book's rules, for this customer only:
/// their orders in id order, as the Due Book groups them.
CustomerDue? Function(Isar) customerDueJob(int customerId) =>
    (db) => db.txnSync(() {
          final orders = db.orders
              .where()
              .customerIdEqualTo(customerId)
              .findAllSync()
            ..sort((a, b) => a.id.compareTo(b.id));
          final totalDue = computeNetDue(orders);
          if (totalDue <= 0) return null;
          final customer = db.customers.getSync(customerId);
          if (customer == null) return null;
          return CustomerDue(
            customer: customer,
            orderDues: computeOrderDues(orders),
            totalDue: totalDue,
          );
        });

@riverpod
Stream<CustomerDue?> customerDue(Ref ref, int customerId) async* {
  final isar = await ref.watch(isarProvider.future);
  yield* reloadOn(
    isar.orders.watchLazy(),
    () => runDbJob(isar, customerDueJob(customerId)),
  );
}

const kCustomerPaymentsFirstPage = 10;
const kCustomerPaymentsPageSize = 20;

class CustomerPaymentsPage {
  const CustomerPaymentsPage(this.payments, {required this.hasMore});

  final List<Payment> payments;
  final bool hasMore;
}

/// The customer's payments, newest first, the latest 10 and more on request.
@riverpod
class CustomerPaymentPages extends _$CustomerPaymentPages {
  int _limit = kCustomerPaymentsFirstPage;
  StreamController<void>? _more;

  @override
  Stream<CustomerPaymentsPage> build(int customerId) async* {
    final isar = await ref.watch(isarProvider.future);
    _limit = kCustomerPaymentsFirstPage;
    final more = StreamController<void>();
    ref.onDispose(more.close);
    _more = more;
    yield* reloadOn(
      mergeChanges([isar.payments.watchLazy(), more.stream]),
      () => isar.txn(() async {
        // Isar can't sort by id, so order the ids and dates here (newest
        // first, ties by id) and load whole rows only for the page.
        final byCustomer = isar.payments.where().customerIdEqualTo(customerId);
        final ids = await byCustomer.idProperty().findAll();
        final paidAt = await byCustomer.paidAtProperty().findAll();
        final order = List.generate(ids.length, (i) => i)
          ..sort((a, b) {
            final x = paidAt[a], y = paidAt[b];
            final byDate = x == null
                ? (y == null ? 0 : 1)
                : (y == null ? -1 : y.compareTo(x));
            return byDate != 0 ? byDate : ids[a].compareTo(ids[b]);
          });
        final page = [for (final i in order.take(_limit)) ids[i]];
        return CustomerPaymentsPage(
          [for (final p in await isar.payments.getAll(page)) ?p],
          hasMore: order.length > _limit,
        );
      }),
    );
  }

  void loadMore() {
    final page = state.value;
    if (page == null || !page.hasMore) return;
    _limit += kCustomerPaymentsPageSize;
    _more?.add(null);
  }
}

/// The last six months of purchases, by month: sales only (no returns, no
/// cancelled orders), loaded through the customer index for those months.
/// Null when the customer has no orders at all.
@riverpod
Stream<Map<DateTime, double>?> customerMonthlySpending(
    Ref ref, int customerId) async* {
  final isar = await ref.watch(isarProvider.future);

  yield* reloadOn(
    isar.orders.watchLazy(),
    () => isar.txn(() async {
      final now = DateTime.now();
      final byCustomer = isar.orders.where().customerIdEqualTo(customerId);
      if (await byCustomer.count() == 0) return null;
      final query = byCustomer
          .filter()
          .createdAtGreaterThan(DateTime(now.year, now.month - 5, 1),
              include: true)
          .isReturnEqualTo(false)
          .not()
          .orderStatusEqualTo(OrderStatus.cancelled);
      final dates = await query.createdAtProperty().findAll();
      final totals = await query.totalAmountProperty().findAll();
      return spendingByMonth(dates, totals, now);
    }),
  );
}

Map<DateTime, double> spendingByMonth(
    List<DateTime?> dates, List<double> totals, DateTime now) {
  final spending = <DateTime, double>{
    for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1): 0,
  };
  for (var i = 0; i < dates.length; i++) {
    final at = dates[i];
    if (at == null) continue;
    final key = DateTime(at.year, at.month, 1);
    final sum = spending[key];
    if (sum != null) spending[key] = sum + totals[i];
  }
  return spending;
}
