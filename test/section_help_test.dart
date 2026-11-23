import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:micro_seller/core/constants/sidebar_items.dart';
import 'package:micro_seller/core/l10n/app_localizations.dart';
import 'package:micro_seller/core/l10n/translations_ar.dart';
import 'package:micro_seller/core/l10n/translations_bn.dart';
import 'package:micro_seller/core/l10n/translations_en.dart';
import 'package:micro_seller/core/l10n/translations_es.dart';
import 'package:micro_seller/core/l10n/translations_fr.dart';
import 'package:micro_seller/core/l10n/translations_id.dart';
import 'package:micro_seller/core/l10n/translations_ms.dart';
import 'package:micro_seller/core/l10n/translations_pt.dart';
import 'package:micro_seller/core/l10n/translations_th.dart';
import 'package:micro_seller/core/l10n/translations_tr.dart';
import 'package:micro_seller/core/l10n/translations_ur.dart';
import 'package:micro_seller/core/l10n/translations_vi.dart';
import 'package:micro_seller/shared/widgets/section_help.dart';

/// Issue #25: every screen's ? opens help that names its controls, explains
/// its numbers and gives tips, in every language, and lays out cleanly.
void main() {
  const locales = {
    'en': translationsEn,
    'bn': translationsBn,
    'ar': translationsAr,
    'es': translationsEs,
    'fr': translationsFr,
    'pt': translationsPt,
    'tr': translationsTr,
    'id': translationsId,
    'th': translationsTh,
    'vi': translationsVi,
    'ur': translationsUr,
    'ms': translationsMs,
  };

  /// The sub-screens issue #25 asked a ? for.
  const subScreens = [
    'product_detail', 'product_form', 'catalog_share',
    'order_detail', 'order_form',
    'create_return', 'choose_return_order',
    'customer_detail', 'customer_form',
    'supplier_detail', 'supplier_form', 'purchase_list', 'purchase_form', 'purchase_detail',
    'expense_form', 'stock_adjustment',
    'sidebar_order', 'recycle_bin', 'color_theme', 'color_theme_editor',
  ];

  group('help texts', () {
    test('every sidebar section has help naming its controls', () {
      for (final item in sidebarItems) {
        final help = kSectionHelp[item.key];
        expect(help, isNotNull, reason: '${item.key} has no help');
        expect(help!.hasTitle, isFalse, reason: '${item.key} is titled by its sidebar label');
        expect(help.controls, isNotEmpty, reason: '${item.key} names no controls');
        expect(kSectionRoutes, contains(item.key));
      }
    });

    test('the Dashboard, Reports, Due Book and Cash Register explain their numbers', () {
      for (final key in ['dashboard', 'reports', 'dues', 'cash_register']) {
        expect(kSectionHelp[key]!.numbers, isNotEmpty, reason: key);
      }
    });

    test('every sub-screen the issue lists has titled help', () {
      for (final id in subScreens) {
        final help = kSectionHelp[id];
        expect(help, isNotNull, reason: '$id has no help');
        expect(help!.hasTitle, isTrue, reason: '$id needs its own title');
        expect(help.controls, isNotEmpty, reason: '$id names no controls');
      }
    });

    test('every key is translated, non-empty, in all 12 languages', () {
      final missing = <String>[];
      for (final MapEntry(key: id, value: help) in kSectionHelp.entries) {
        for (final key in [...help.keys, 'helpOnThisScreen', 'helpNumbersMean', 'helpTips']) {
          for (final MapEntry(key: code, value: map) in locales.entries) {
            final text = map[key];
            if (text == null || text.trim().isEmpty) missing.add('$code:$key ($id)');
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('placeholders and brand names survive translation', () {
      final odd = <String>[];
      for (final help in kSectionHelp.values) {
        for (final key in help.keys) {
          final en = translationsEn[key]!;
          for (final MapEntry(key: code, value: map) in locales.entries) {
            for (final word in ['WhatsApp', 'IMEI', 'SKU', 'PDF', 'CSV']) {
              if (en.contains(word) && !map[key]!.contains(word)) odd.add('$code:$key lost $word');
            }
          }
        }
      }
      expect(odd, isEmpty);
    });
  });

  group('? buttons in the source', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('section_help.dart'))
        .map((f) => (f.path, f.readAsStringSync()))
        .toList();
    final used = <String, String>{};
    for (final (path, src) in sources) {
      for (final m in RegExp(r"SectionHelpButton\(\s*'([a-z_]+)'").allMatches(src)) {
        used[m.group(1)!] = path;
      }
    }

    test('every ? opens help that exists', () {
      for (final MapEntry(key: id, value: path) in used.entries) {
        expect(kSectionHelp, contains(id), reason: '$path asks for help "$id"');
      }
    });

    test('every help is reachable from a ? button', () {
      for (final id in kSectionHelp.keys) {
        expect(used, contains(id), reason: 'no screen shows help "$id"');
      }
    });
  });

  group('the sheet', () {
    Future<void> pumpHelp(
      WidgetTester tester, {
      required String locale,
      required Size size,
      required double textScale,
      required Widget child,
    }) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: child,
      ));
      await tester.pump();
    }

    // Every help body, padded as in the sheet, one under the other.
    final allBodies = Scaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final help in kSectionHelp.values) ...[
            SectionHelpBody(help: help),
            const Divider(height: 32),
          ],
        ],
      ),
    );

    for (final locale in ['en', 'ar', 'bn']) {
      for (final width in [320.0, 360.0, 411.0]) {
        for (final scale in [1.0, 1.3, 1.5]) {
          testWidgets('lays out cleanly: $locale, $width dp, text ×$scale', (tester) async {
            await pumpHelp(tester,
                locale: locale, size: Size(width, 800), textScale: scale, child: allBodies);
            expect(tester.takeException(), isNull);
            // Scroll through everything, so every row is built and laid out.
            final list = find.byType(Scrollable).first;
            for (var i = 0; i < 400; i++) {
              final pos = tester.state<ScrollableState>(list).position;
              if (pos.pixels >= pos.maxScrollExtent) break;
              await tester.drag(list, const Offset(0, -600));
              await tester.pump();
              expect(tester.takeException(), isNull);
            }
          });
        }
      }
    }

    for (final size in [const Size(820, 1180), const Size(1180, 820)]) {
      testWidgets('lays out cleanly on a tablet ${size.width}×${size.height}', (tester) async {
        await pumpHelp(tester, locale: 'ar', size: size, textScale: 1.5, child: allBodies);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a ? button opens its screen\'s sheet with all sections', (tester) async {
      await pumpHelp(
        tester,
        locale: 'en',
        size: const Size(411, 900),
        textScale: 1.0,
        child: Scaffold(appBar: AppBar(actions: const [SectionHelpButton('order_detail')])),
      );
      await tester.tap(find.byType(SectionHelpButton));
      await tester.pumpAndSettle();
      expect(find.text('Order details'), findsOneWidget);
      expect(find.text('When to use it'), findsOneWidget);
      expect(find.text('On this screen'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
      expect(find.text('What the numbers mean'), findsOneWidget);
      expect(find.text('Tips'), findsOneWidget);
    });

    testWidgets('a sidebar section\'s sheet keeps its title and Works with', (tester) async {
      await pumpHelp(
        tester,
        locale: 'en',
        size: const Size(411, 900),
        textScale: 1.0,
        child: Scaffold(appBar: AppBar(actions: const [SectionHelpButton('dues')])),
      );
      await tester.tap(find.byType(SectionHelpButton));
      await tester.pumpAndSettle();
      expect(find.text('Due Book'), findsWidgets);
      expect(find.text('Recalculate balances'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Works with'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Works with'), findsOneWidget);
    });
  });
}
