// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_detail_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(customerById)
final customerByIdProvider = CustomerByIdFamily._();

final class CustomerByIdProvider
    extends
        $FunctionalProvider<AsyncValue<Customer?>, Customer?, Stream<Customer?>>
    with $FutureModifier<Customer?>, $StreamProvider<Customer?> {
  CustomerByIdProvider._({
    required CustomerByIdFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'customerByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$customerByIdHash();

  @override
  String toString() {
    return r'customerByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Customer?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Customer?> create(Ref ref) {
    final argument = this.argument as int;
    return customerById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CustomerByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customerByIdHash() => r'88c5288ddb993265d4e2390e6634e49f5f0869ba';

final class CustomerByIdFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Customer?>, int> {
  CustomerByIdFamily._()
    : super(
        retry: null,
        name: r'customerByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CustomerByIdProvider call(int id) =>
      CustomerByIdProvider._(argument: id, from: this);

  @override
  String toString() => r'customerByIdProvider';
}

/// The customer's purchase history, a page at a time. "Load more" fetches
/// only the next page; a change elsewhere in the shop reloads nothing unless
/// one of this customer's orders changed.

@ProviderFor(CustomerOrders)
final customerOrdersProvider = CustomerOrdersFamily._();

/// The customer's purchase history, a page at a time. "Load more" fetches
/// only the next page; a change elsewhere in the shop reloads nothing unless
/// one of this customer's orders changed.
final class CustomerOrdersProvider
    extends $StreamNotifierProvider<CustomerOrders, CustomerOrdersPage> {
  /// The customer's purchase history, a page at a time. "Load more" fetches
  /// only the next page; a change elsewhere in the shop reloads nothing unless
  /// one of this customer's orders changed.
  CustomerOrdersProvider._({
    required CustomerOrdersFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'customerOrdersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$customerOrdersHash();

  @override
  String toString() {
    return r'customerOrdersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CustomerOrders create() => CustomerOrders();

  @override
  bool operator ==(Object other) {
    return other is CustomerOrdersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customerOrdersHash() => r'87f36fd293a04989ad8d822fd5dea78dde2c52fb';

/// The customer's purchase history, a page at a time. "Load more" fetches
/// only the next page; a change elsewhere in the shop reloads nothing unless
/// one of this customer's orders changed.

final class CustomerOrdersFamily extends $Family
    with
        $ClassFamilyOverride<
          CustomerOrders,
          AsyncValue<CustomerOrdersPage>,
          CustomerOrdersPage,
          Stream<CustomerOrdersPage>,
          int
        > {
  CustomerOrdersFamily._()
    : super(
        retry: null,
        name: r'customerOrdersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The customer's purchase history, a page at a time. "Load more" fetches
  /// only the next page; a change elsewhere in the shop reloads nothing unless
  /// one of this customer's orders changed.

  CustomerOrdersProvider call(int customerId) =>
      CustomerOrdersProvider._(argument: customerId, from: this);

  @override
  String toString() => r'customerOrdersProvider';
}

/// The customer's purchase history, a page at a time. "Load more" fetches
/// only the next page; a change elsewhere in the shop reloads nothing unless
/// one of this customer's orders changed.

abstract class _$CustomerOrders extends $StreamNotifier<CustomerOrdersPage> {
  late final _$args = ref.$arg as int;
  int get customerId => _$args;

  Stream<CustomerOrdersPage> build(int customerId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<CustomerOrdersPage>, CustomerOrdersPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<CustomerOrdersPage>, CustomerOrdersPage>,
              AsyncValue<CustomerOrdersPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(customerDue)
final customerDueProvider = CustomerDueFamily._();

final class CustomerDueProvider
    extends
        $FunctionalProvider<
          AsyncValue<CustomerDue?>,
          CustomerDue?,
          Stream<CustomerDue?>
        >
    with $FutureModifier<CustomerDue?>, $StreamProvider<CustomerDue?> {
  CustomerDueProvider._({
    required CustomerDueFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'customerDueProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$customerDueHash();

  @override
  String toString() {
    return r'customerDueProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<CustomerDue?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<CustomerDue?> create(Ref ref) {
    final argument = this.argument as int;
    return customerDue(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CustomerDueProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customerDueHash() => r'8ca4721c4262b659c3b5f09b009782ff9e81a79b';

final class CustomerDueFamily extends $Family
    with $FunctionalFamilyOverride<Stream<CustomerDue?>, int> {
  CustomerDueFamily._()
    : super(
        retry: null,
        name: r'customerDueProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CustomerDueProvider call(int customerId) =>
      CustomerDueProvider._(argument: customerId, from: this);

  @override
  String toString() => r'customerDueProvider';
}

/// The customer's payments, newest first, the latest 10 and more on request.

@ProviderFor(CustomerPaymentPages)
final customerPaymentPagesProvider = CustomerPaymentPagesFamily._();

/// The customer's payments, newest first, the latest 10 and more on request.
final class CustomerPaymentPagesProvider
    extends
        $StreamNotifierProvider<CustomerPaymentPages, CustomerPaymentsPage> {
  /// The customer's payments, newest first, the latest 10 and more on request.
  CustomerPaymentPagesProvider._({
    required CustomerPaymentPagesFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'customerPaymentPagesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$customerPaymentPagesHash();

  @override
  String toString() {
    return r'customerPaymentPagesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CustomerPaymentPages create() => CustomerPaymentPages();

  @override
  bool operator ==(Object other) {
    return other is CustomerPaymentPagesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customerPaymentPagesHash() =>
    r'48b1356ef88438af846abab0498ee7de6b0f9d43';

/// The customer's payments, newest first, the latest 10 and more on request.

final class CustomerPaymentPagesFamily extends $Family
    with
        $ClassFamilyOverride<
          CustomerPaymentPages,
          AsyncValue<CustomerPaymentsPage>,
          CustomerPaymentsPage,
          Stream<CustomerPaymentsPage>,
          int
        > {
  CustomerPaymentPagesFamily._()
    : super(
        retry: null,
        name: r'customerPaymentPagesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The customer's payments, newest first, the latest 10 and more on request.

  CustomerPaymentPagesProvider call(int customerId) =>
      CustomerPaymentPagesProvider._(argument: customerId, from: this);

  @override
  String toString() => r'customerPaymentPagesProvider';
}

/// The customer's payments, newest first, the latest 10 and more on request.

abstract class _$CustomerPaymentPages
    extends $StreamNotifier<CustomerPaymentsPage> {
  late final _$args = ref.$arg as int;
  int get customerId => _$args;

  Stream<CustomerPaymentsPage> build(int customerId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<CustomerPaymentsPage>, CustomerPaymentsPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<CustomerPaymentsPage>,
                CustomerPaymentsPage
              >,
              AsyncValue<CustomerPaymentsPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The last six months of purchases, by month: sales only (no returns, no
/// cancelled orders), loaded through the customer index for those months.
/// Null when the customer has no orders at all.

@ProviderFor(customerMonthlySpending)
final customerMonthlySpendingProvider = CustomerMonthlySpendingFamily._();

/// The last six months of purchases, by month: sales only (no returns, no
/// cancelled orders), loaded through the customer index for those months.
/// Null when the customer has no orders at all.

final class CustomerMonthlySpendingProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<DateTime, double>?>,
          Map<DateTime, double>?,
          Stream<Map<DateTime, double>?>
        >
    with
        $FutureModifier<Map<DateTime, double>?>,
        $StreamProvider<Map<DateTime, double>?> {
  /// The last six months of purchases, by month: sales only (no returns, no
  /// cancelled orders), loaded through the customer index for those months.
  /// Null when the customer has no orders at all.
  CustomerMonthlySpendingProvider._({
    required CustomerMonthlySpendingFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'customerMonthlySpendingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$customerMonthlySpendingHash();

  @override
  String toString() {
    return r'customerMonthlySpendingProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Map<DateTime, double>?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<DateTime, double>?> create(Ref ref) {
    final argument = this.argument as int;
    return customerMonthlySpending(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CustomerMonthlySpendingProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$customerMonthlySpendingHash() =>
    r'1675657a84832beb7004facf008d6daf9327ed88';

/// The last six months of purchases, by month: sales only (no returns, no
/// cancelled orders), loaded through the customer index for those months.
/// Null when the customer has no orders at all.

final class CustomerMonthlySpendingFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Map<DateTime, double>?>, int> {
  CustomerMonthlySpendingFamily._()
    : super(
        retry: null,
        name: r'customerMonthlySpendingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The last six months of purchases, by month: sales only (no returns, no
  /// cancelled orders), loaded through the customer index for those months.
  /// Null when the customer has no orders at all.

  CustomerMonthlySpendingProvider call(int customerId) =>
      CustomerMonthlySpendingProvider._(argument: customerId, from: this);

  @override
  String toString() => r'customerMonthlySpendingProvider';
}
