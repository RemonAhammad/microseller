// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(customers)
final customersProvider = CustomersProvider._();

final class CustomersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Customer>>,
          List<Customer>,
          Stream<List<Customer>>
        >
    with $FutureModifier<List<Customer>>, $StreamProvider<List<Customer>> {
  CustomersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'customersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$customersHash();

  @$internal
  @override
  $StreamProviderElement<List<Customer>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Customer>> create(Ref ref) {
    return customers(ref);
  }
}

String _$customersHash() => r'f5727a20a1e93e8cb2c21dd1e602514dde597f58';

@ProviderFor(CustomerNotifier)
final customerProvider = CustomerNotifierProvider._();

final class CustomerNotifierProvider
    extends $AsyncNotifierProvider<CustomerNotifier, void> {
  CustomerNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'customerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$customerNotifierHash();

  @$internal
  @override
  CustomerNotifier create() => CustomerNotifier();
}

String _$customerNotifierHash() => r'1cb86da23867e3ff938ceb749c864a90da40ec0f';

abstract class _$CustomerNotifier extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
