import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/data/models/category.dart';
import 'package:micro_seller/data/models/product.dart';
import 'package:micro_seller/data/models/trash_entry.dart';
import 'package:micro_seller/features/categories/presentation/category_screen.dart';

import 'support/isar_core.dart';
import 'support/screen_harness.dart';

/// Categories have a visible Delete button: it asks first, says how many
/// products still use the category, and the delete can be undone.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(closeTestIsars);

  Future<(Isar, int)> seed(WidgetTester tester) async {
    late Isar isar;
    late int id;
    await tester.runAsync(() async {
      isar = await openTestIsar('category_delete');
      await isar.writeTxn(() async {
        id = await isar.categories.put(Category(name: 'Snacks'));
        await isar.categories.put(Category(name: 'Clothes'));
        await isar.products.putAll([
          Product(name: 'Chips', category: 'Snacks', sellingPrice: 10),
          Product(name: 'Biscuits', category: 'Snacks', sellingPrice: 10),
          Product(name: 'Old crisps', category: 'Snacks', sellingPrice: 10, isActive: false),
        ]);
      });
    });
    return (isar, id);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('Delete asks, names the products using it, and goes to the bin',
      skip: isarSkipReason != null, (tester) async {
    final (isar, id) = await seed(tester);
    await pumpScreen(tester, isar: isar, screen: const CategoryScreen());

    await tester.tap(find.byKey(ValueKey('deleteCategory$id')));
    await settle(tester);
    expect(find.text('Delete Category'), findsOneWidget);
    // Only active products count: the soft-deleted one is left out.
    expect(find.textContaining('2 products use this category'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);

    expect(find.text('Snacks'), findsNothing);
    expect(find.text('Clothes'), findsOneWidget);
    expect(find.textContaining('Deleted: Snacks'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await isar.categories.get(id), isNull);
      expect(await isar.trashEntries.count(), 1);
    });
  });

  testWidgets('Cancel keeps the category', skip: isarSkipReason != null, (tester) async {
    final (isar, id) = await seed(tester);
    await pumpScreen(tester, isar: isar, screen: const CategoryScreen());

    await tester.tap(find.byKey(ValueKey('deleteCategory$id')));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(find.text('Snacks'), findsOneWidget);
    await tester.runAsync(() async => expect(await isar.categories.get(id), isNotNull));
  });
}
