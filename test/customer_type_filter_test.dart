import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/core/l10n/app_localizations.dart';
import 'package:micro_seller/data/models/customer.dart';
import 'package:micro_seller/features/customers/presentation/customer_list_screen.dart';
import 'package:micro_seller/features/customers/providers/customer_provider.dart';

/// Issue #27: the Customers screen filters by customer type.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'screen_guide_customers': true}));

  final customers = [
    Customer(name: 'Anika New', phone: '01711111111', tag: CustomerTag.newCustomer)..id = 1,
    Customer(name: 'Rahim Regular', phone: '01722222222', tag: CustomerTag.regular)..id = 2,
    Customer(name: 'Vera Vip', phone: '01733333333', tag: CustomerTag.vip)..id = 3,
    Customer(name: 'Victor Vip', phone: '01744444444', tag: CustomerTag.vip)..id = 4,
  ];

  Future<void> pump(WidgetTester tester, {double width = 411, double text = 1.0, List<Customer>? list}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [customersProvider.overrideWith((ref) => Stream.value(list ?? customers))],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text)),
          child: child!,
        ),
        home: const CustomerListScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
  }

  Finder chip(String t) => find.byKey(ValueKey('customerTypeChip-$t'));

  testWidgets('All by default; each chip shows only its type, with counts', (tester) async {
    await pump(tester);
    expect(find.text('All (4)'), findsOneWidget);
    expect(find.text('VIP (2)'), findsOneWidget);
    expect(find.text('Anika New'), findsOneWidget);

    await tester.ensureVisible(chip('vip'));
    await tester.tap(chip('vip'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Vera Vip'), findsOneWidget);
    expect(find.text('Victor Vip'), findsOneWidget);
    expect(find.text('Anika New'), findsNothing);
    expect(find.text('Rahim Regular'), findsNothing);

    // Search looks only within the type.
    await tester.enterText(find.byType(TextField), 'vera');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Vera Vip'), findsOneWidget);
    expect(find.text('Victor Vip'), findsNothing);
  });

  testWidgets('no match: No customers found with Clear filters', (tester) async {
    await pump(tester, list: customers.where((c) => c.tag != CustomerTag.regular).toList());
    await tester.ensureVisible(chip('regular'));
    await tester.tap(chip('regular'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No customers found'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Anika New'), findsOneWidget);
  });

  for (final w in [320.0, 360.0, 411.0]) {
    for (final t in [1.0, 1.3, 1.5]) {
      testWidgets('lays out cleanly at $w dp × $t text', (tester) async {
        await pump(tester, width: w, text: t);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
