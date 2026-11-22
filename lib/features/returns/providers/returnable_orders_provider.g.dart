// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'returnable_orders_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The orders a new return can be made against, newest first: sales whose
/// goods were handed over (not pending, whose stock was never deducted, and
/// not cancelled) with something left to return. Loaded on a worker, since
/// it reads every order.

@ProviderFor(returnableOrders)
final returnableOrdersProvider = ReturnableOrdersProvider._();

/// The orders a new return can be made against, newest first: sales whose
/// goods were handed over (not pending, whose stock was never deducted, and
/// not cancelled) with something left to return. Loaded on a worker, since
/// it reads every order.

final class ReturnableOrdersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Order>>,
          List<Order>,
          Stream<List<Order>>
        >
    with $FutureModifier<List<Order>>, $StreamProvider<List<Order>> {
  /// The orders a new return can be made against, newest first: sales whose
  /// goods were handed over (not pending, whose stock was never deducted, and
  /// not cancelled) with something left to return. Loaded on a worker, since
  /// it reads every order.
  ReturnableOrdersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'returnableOrdersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$returnableOrdersHash();

  @$internal
  @override
  $StreamProviderElement<List<Order>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Order>> create(Ref ref) {
    return returnableOrders(ref);
  }
}

String _$returnableOrdersHash() => r'165a57f6c284114c43eadc04c18684fc926f921d';
