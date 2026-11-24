import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/core/l10n/app_localizations.dart';
import 'package:micro_seller/core/utils/validators.dart';
import 'package:micro_seller/data/models/customer.dart';
import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/models/payment.dart';
import 'package:micro_seller/data/services/isar_service.dart';
import 'package:micro_seller/data/services/local_backup_service.dart';
import 'package:micro_seller/data/services/mail_service.dart';
import 'package:micro_seller/data/services/pdf_service.dart';
import 'package:micro_seller/features/customers/presentation/customer_detail_screen.dart';
import 'package:micro_seller/features/customers/presentation/customer_form_screen.dart';
import 'package:micro_seller/features/customers/presentation/customer_list_screen.dart';
import 'package:micro_seller/features/orders/presentation/order_detail_screen.dart';
import 'package:micro_seller/shared/widgets/app_button.dart';
import 'package:micro_seller/shared/widgets/email_actions.dart';

import 'support/isar_core.dart';
import 'support/screen_harness.dart';

/// Issue #26: an optional customer email, and invoices, statements and
/// reminders sent through the phone's own mail app.
void main() {
  group('address rules', () {
    test('an empty email is always valid; a filled one must look like one', () {
      expect(Validators.email(null), isNull);
      expect(Validators.email('  '), isNull);
      expect(Validators.email('rahim@shop.com'), isNull);
      expect(Validators.email(' rahim.uddin+bd@mail.example.org '), isNull);
      expect(Validators.email('রহিম@দোকান.বাংলা'), isNull);
      for (final bad in ['rahim', 'rahim@', '@shop.com', 'rahim@shop', 'ra him@shop.com', 'a@b@c.com', 'a@b.']) {
        expect(Validators.email(bad, 'bad'), 'bad', reason: bad);
      }
    });

    test('mailto encodes spaces as %20, never +, and keeps any script and line breaks', () {
      final uri = mailtoUri('rahim@shop.com',
          subject: 'Invoice ORD-012 from রহিম স্টোর',
          body: 'مرحبًا،\nTotal: ৳1,250')!;
      final text = uri.toString();
      expect(text, startsWith('mailto:rahim@shop.com?'));
      expect(text, isNot(contains('+')));
      expect(text, contains('%20'));
      expect(text, contains('%0A'));
      final query = text.substring(text.indexOf('?') + 1).split('&');
      expect(Uri.decodeComponent(query[0].substring('subject='.length)),
          'Invoice ORD-012 from রহিম স্টোর');
      expect(Uri.decodeComponent(query[1].substring('body='.length)), 'مرحبًا،\nTotal: ৳1,250');
      expect(mailtoUri('not an email'), isNull);
    });

    test('a long address gets break points only after its separators', () {
      expect(breakableEmail('a.b@c.com'), 'a.​b@​c.​com');
      expect(breakableEmail('a.b@c.com').replaceAll('​', ''), 'a.b@c.com');
    });
  });

  group('the model', () {
    test('a customer saved before emails reads back with an empty one', () {
      final c = Customer.fromJson({'id': 3, 'name': 'Rahim', 'phone': '017', 'tag': 'regular'});
      expect(c.email, '');
      expect(c.hasEmail, isFalse);
    });

    test('toJson carries it and copyWith keeps it', () {
      final c = Customer(name: 'Rahim', email: 'r@s.com');
      expect(c.toJson()['email'], 'r@s.com');
      expect(c.copyWith(createdAt: DateTime(2026)).email, 'r@s.com');
      expect(c.copyWith(email: '').email, '');
    });
  });

  group('on a real database', skip: isarSkipReason, () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(closeTestIsars);

    late Isar isar;
    late int customerId;
    late int orderId;

    Future<void> seed({String email = 'rahim@shop.com'}) async {
      await loadPdfWatermarkIcon();
      isar = await openTestIsar('customer_email');
      await isar.writeTxn(() async {
        customerId = await isar.customers.put(Customer(
            name: 'Rahim', phone: '01700000000', email: email, totalOrders: 1, totalSpent: 20));
        orderId = await isar.orders.put(Order(
          orderNumber: 'ORD-001',
          customerId: customerId,
          customerName: 'Rahim',
          items: [OrderItem(productId: 1, productName: 'Eggs', qty: 2, unitPrice: 10, totalPrice: 20)],
          subtotal: 20,
          totalAmount: 20,
          amountPaid: 5,
          paymentStatus: PaymentStatus.partial,
          orderStatus: OrderStatus.confirmed,
          createdAt: DateTime(2026, 11, 1),
        ));
        await isar.payments.put(Payment(
            customerId: customerId, orderId: orderId, amount: 5, paidAt: DateTime(2026, 11, 1)));
      });
    }

    final shareCalls = <MethodCall>[];
    void mockShare(WidgetTester tester) {
      shareCalls.clear();
      final tmp = Directory.systemTemp.createTempSync('email');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
      messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async {
        shareCalls.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
        messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'), null);
      });
    }

    /// Pumps until [done] or the work (PDF render, isolate) gives up.
    Future<void> waitFor(WidgetTester tester, bool Function() done) async {
      // Up to 30 s of real time: CI runners are much slower than a Mac, and
      // the screen loads its data on a worker isolate. Fails loudly rather
      // than letting the next finder throw "No element".
      for (var i = 0; i < 600 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (!done()) fail('waitFor: condition not met after 30 s');
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('an edit keeps the email, and a backup round trip carries it', (tester) async {
      await tester.runAsync(seed);
      await pumpScreen(tester, isar: isar, screen: CustomerFormScreen(customerId: customerId));
      expect(find.text('rahim@shop.com'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Rahim'), 'Rahim Uddin');
      await tester.tap(find.byType(AppButton));
      await settleDb(tester);
      final edited = await tester.runAsync(() => isar.customers.get(customerId));
      expect(edited!.name, 'Rahim Uddin');
      expect(edited.email, 'rahim@shop.com');

      final service = LocalBackupService();
      final json = (await tester.runAsync(() => service.encodeAll(isar)))!;
      final restored = await tester.runAsync(() async {
        final other = await openTestIsar('customer_email_restore');
        await service.decodeAll(other, json);
        return other.customers.get(customerId);
      });
      expect(restored!.email, 'rahim@shop.com');

      // An older backup, without the field, restores with an empty email.
      final map = jsonDecode(json) as Map<String, dynamic>;
      for (final c in (map['customers'] as List).cast<Map<String, dynamic>>()) {
        c.remove('email');
      }
      final old = await tester.runAsync(() async {
        final other = await openTestIsar('customer_email_old');
        await service.decodeAll(other, jsonEncode(map));
        return other.customers.get(customerId);
      });
      expect(old!.email, '');
      expect(old.name, 'Rahim Uddin');
    });

    testWidgets('a bad email is refused on the form; empty is fine', (tester) async {
      await tester.runAsync(seed);
      await pumpScreen(tester, isar: isar, screen: CustomerFormScreen(customerId: customerId));
      await tester.enterText(find.widgetWithText(TextFormField, 'rahim@shop.com'), 'rahim@shop');
      await tester.tap(find.byType(AppButton));
      await settleDb(tester);
      expect(find.text('Please enter a valid email address'), findsOneWidget);
      expect(find.text(kBelowScreen), findsNothing);

      await tester.enterText(find.widgetWithText(TextFormField, 'rahim@shop'), '');
      await tester.tap(find.byType(AppButton));
      await settleDb(tester);
      final saved = await tester.runAsync(() => isar.customers.get(customerId));
      expect(saved!.email, '');
    });

    testWidgets('the customer list finds a customer by email', (tester) async {
      await tester.runAsync(seed);
      await tester.runAsync(() => isar.writeTxn(() => isar.customers.put(Customer(name: 'Karim'))));
      await pumpScreen(tester, isar: isar, screen: const CustomerListScreen());
      expect(find.text('Karim'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'RAHIM@SHOP');
      await tester.pump(const Duration(milliseconds: 500));
      await settleDb(tester);
      expect(find.text('Karim'), findsNothing);
      expect(find.text('Rahim'), findsWidgets);
    });

    testWidgets('customer detail shows the email; a tap writes to it, or offers Copy email', (tester) async {
      await tester.runAsync(seed);
      final mail = _FakeMail(addressOpens: false);
      await pumpScreen(tester,
          isar: isar,
          screen: CustomerDetailScreen(customerId: customerId),
          overrides: [mailComposerProvider.overrideWithValue(mail)]);
      final link = find.text(breakableEmail('rahim@shop.com'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(mail.addresses, ['rahim@shop.com']);
      expect(find.text('Copy email'), findsOneWidget);
    });

    Future<void> openMenuAction(WidgetTester tester, String label) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pump();
    }

    testWidgets('Email invoice fills in the customer, subject, summary and the PDF', (tester) async {
      await tester.runAsync(seed);
      final mail = _FakeMail();
      await pumpScreen(tester,
          isar: isar,
          screen: OrderDetailScreen(orderId: orderId),
          overrides: [mailComposerProvider.overrideWithValue(mail)]);
      await openMenuAction(tester, 'Email invoice');
      await waitFor(tester, () => mail.sent.isNotEmpty);
      expect(mail.sent, hasLength(1));
      final email = mail.sent.single;
      expect(email.to, 'rahim@shop.com');
      expect(email.subject, 'Invoice ORD-001 from My Shop');
      expect(email.body, contains('Hello Rahim,'));
      expect(email.body, contains('ORD-001'));
      expect(email.body, contains('Eggs'));
      expect(email.body, contains('Balance Due'));
      expect(email.attachment!.fileName, 'ORD-001.pdf');
      expect(latin1.decode(email.attachment!.bytes.sublist(0, 4)), '%PDF');
      expect(find.text('Opened in your mail app'), findsOneWidget);
      expect(find.textContaining('Sent'), findsNothing);
    });

    testWidgets('no email saved: it asks, checks the address and saves it to the customer', (tester) async {
      await tester.runAsync(() => seed(email: ''));
      final mail = _FakeMail();
      await pumpScreen(tester,
          isar: isar,
          screen: OrderDetailScreen(orderId: orderId),
          overrides: [mailComposerProvider.overrideWithValue(mail)]);
      await openMenuAction(tester, 'Email invoice');
      await settleDb(tester);
      expect(find.text('Rahim has no email saved.'), findsOneWidget);
      expect(find.text('Save it to Rahim'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'nope');
      await tester.tap(find.text('Open mail app'));
      await tester.pump();
      expect(find.text('Please enter a valid email address'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, ' rahim@new.com ');
      await tester.tap(find.text('Open mail app'));
      await waitFor(tester, () => mail.sent.isNotEmpty);
      expect(mail.sent.single.to, 'rahim@new.com');
      final saved = await tester.runAsync(() => isar.customers.get(customerId));
      expect(saved!.email, 'rahim@new.com');
    });

    testWidgets('cancelling the address renders nothing and opens nothing', (tester) async {
      await tester.runAsync(() => seed(email: ''));
      final mail = _FakeMail();
      await pumpScreen(tester,
          isar: isar,
          screen: OrderDetailScreen(orderId: orderId),
          overrides: [mailComposerProvider.overrideWithValue(mail)]);
      await openMenuAction(tester, 'Email invoice');
      await settleDb(tester);
      await tester.tap(find.text('Cancel'));
      await settleDb(tester);
      expect(mail.sent, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('no mail app: the share sheet gets the PDF and the subject', (tester) async {
      await tester.runAsync(seed);
      mockShare(tester);
      final mail = _FakeMail(outcome: MailOutcome.unavailable);
      await pumpScreen(tester,
          isar: isar,
          screen: OrderDetailScreen(orderId: orderId),
          overrides: [mailComposerProvider.overrideWithValue(mail)]);
      await openMenuAction(tester, 'Email invoice');
      await waitFor(tester, () => shareCalls.isNotEmpty);
      expect(mail.sent, hasLength(1));
      expect(shareCalls, hasLength(1));
      final args = shareCalls.single.arguments.toString();
      expect(args, contains('ORD-001.pdf'));
      expect(args, contains('Invoice ORD-001 from My Shop'));
      expect(find.text('No mail app is set up. Choose an app to send it.'), findsOneWidget);
    });

    testWidgets('Statement with an email asks Share or Email; Email sends the statement PDF', (tester) async {
      await tester.runAsync(seed);
      mockShare(tester);
      final mail = _FakeMail();
      await pumpScreen(tester,
          isar: isar,
          screen: CustomerDetailScreen(customerId: customerId),
          overrides: [mailComposerProvider.overrideWithValue(mail)]);
      final button = find.text('Statement');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Share PDF'), findsOneWidget);
      await tester.tap(find.text('Email statement'));
      await waitFor(tester, () => mail.sent.isNotEmpty);
      final email = mail.sent.single;
      expect(email.to, 'rahim@shop.com');
      expect(email.subject, 'Statement from My Shop');
      expect(email.attachment!.fileName, 'statement_Rahim.pdf');
      expect(shareCalls, isEmpty);
    });

    testWidgets('Remind with an email asks WhatsApp or Email; Email sends the reminder text', (tester) async {
      await tester.runAsync(seed);
      final mail = _FakeMail();
      await pumpScreen(tester,
          isar: isar,
          screen: CustomerDetailScreen(customerId: customerId),
          overrides: [mailComposerProvider.overrideWithValue(mail)]);
      await waitFor(tester, () => find.text('Remind').evaluate().isNotEmpty);
      await tester.ensureVisible(find.text('Remind'));
      await tester.tap(find.text('Remind'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email reminder'));
      await waitFor(tester, () => mail.sent.isNotEmpty);
      final email = mail.sent.single;
      expect(email.to, 'rahim@shop.com');
      expect(email.subject, 'Payment reminder from My Shop');
      expect(email.body, contains('ORD-001'));
      expect(email.attachment, isNull);
    });

    testWidgets('a very long email on customer detail wraps at 320 dp, 150% text, Arabic', (tester) async {
      await tester.runAsync(() => seed(
          email: 'mohammad.abdur.rahim.uddin.chowdhury@very-long-company-domain.example.com'));
      tester.view.physicalSize = const Size(320, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [isarProvider.overrideWith((ref) async => isar)],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: app!,
          ),
          home: CustomerDetailScreen(customerId: customerId),
        ),
      ));
      await settleDb(tester);
      expect(tester.takeException(), isNull);
      final link = tester.widget<Text>(find.text(breakableEmail(
          'mohammad.abdur.rahim.uddin.chowdhury@very-long-company-domain.example.com')));
      expect(link.textDirection, TextDirection.ltr);
    });

    testWidgets('Statement without an email shares straight away, as before', (tester) async {
      await tester.runAsync(() => seed(email: ''));
      mockShare(tester);
      await pumpScreen(tester, isar: isar, screen: CustomerDetailScreen(customerId: customerId));
      final button = find.text('Statement');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await waitFor(tester, () => shareCalls.isNotEmpty);
      expect(find.text('Email statement'), findsNothing);
      expect(shareCalls, hasLength(1));
    });
  });

  group('layout', () {
    Future<void> pumpAt(WidgetTester tester, Widget child,
        {required double width, required double scale, String locale = 'en'}) async {
      tester.view.physicalSize = Size(width, 700) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: app!,
          ),
          home: child,
        ),
      ));
      await tester.pump();
    }

    const longEmail = 'mohammad.abdur.rahim.uddin.chowdhury@very-long-company-domain.example.com';

    for (final locale in ['en', 'ar']) {
      for (final width in [320.0, 411.0]) {
        for (final scale in [1.0, 1.5]) {
          testWidgets('the ask dialog and Copy email sheet fit: $locale, $width dp, ×$scale', (tester) async {
            await pumpAt(
              tester,
              Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: Column(children: [
                    TextButton(
                      onPressed: () => emailRecipientFor(
                          context, ref, Customer(name: 'Mohammad Abdur Rahim Uddin Chowdhury')),
                      child: const Text('ask'),
                    ),
                    TextButton(
                      onPressed: () => writeEmail(context, ref, longEmail),
                      child: const Text('write'),
                    ),
                  ]),
                ),
              ),
              width: width,
              scale: scale,
              locale: locale,
            );
            await tester.tap(find.text('ask'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.enterText(find.byType(TextField), longEmail);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            Navigator.of(tester.element(find.byType(TextField))).pop();
            await tester.pumpAndSettle();

            await tester.tap(find.text('write'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}

class _Sent {
  _Sent(this.to, this.subject, this.body, this.attachment);
  final String to;
  final String subject;
  final String body;
  final MailAttachment? attachment;
}

class _FakeMail extends MailComposer {
  _FakeMail({this.outcome = MailOutcome.opened, this.addressOpens = true});

  final MailOutcome outcome;
  final bool addressOpens;
  final sent = <_Sent>[];
  final addresses = <String>[];

  @override
  Future<MailOutcome> compose({
    required String to,
    required String subject,
    required String body,
    MailAttachment? attachment,
  }) async {
    sent.add(_Sent(to, subject, body, attachment));
    return outcome;
  }

  @override
  Future<bool> openAddress(String address) async {
    addresses.add(address);
    return addressOpens;
  }
}
