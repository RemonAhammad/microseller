// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mail_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mailComposer)
final mailComposerProvider = MailComposerProvider._();

final class MailComposerProvider
    extends $FunctionalProvider<MailComposer, MailComposer, MailComposer>
    with $Provider<MailComposer> {
  MailComposerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mailComposerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mailComposerHash();

  @$internal
  @override
  $ProviderElement<MailComposer> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MailComposer create(Ref ref) {
    return mailComposer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MailComposer value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MailComposer>(value),
    );
  }
}

String _$mailComposerHash() => r'b1d1c9ecb505bf7bb044d925e23525fa10b27c10';
