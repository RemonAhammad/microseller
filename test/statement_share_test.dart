import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:micro_seller/data/models/customer.dart';
import 'package:micro_seller/data/models/order.dart';
import 'package:micro_seller/data/models/order_item.dart';
import 'package:micro_seller/data/models/payment.dart';
import 'package:micro_seller/data/services/pdf_assembly.dart';
import 'package:micro_seller/data/services/pdf_service.dart';
import 'package:micro_seller/features/customers/presentation/customer_detail_screen.dart';
import 'package:micro_seller/features/customers/presentation/widgets/due_actions.dart';

import 'package:micro_seller/data/services/db_worker.dart';

import 'support/isar_core.dart';
import 'support/screen_harness.dart';

/// The customer statement must always end in a shared PDF or a message that
/// says what failed — never in silence or a bare "Error".
void main() {
  group('statement file name', () {
    String name(String n, {int id = 7}) =>
        statementFileName(Customer(id: id, name: n));

    test('keeps the name in any script, marks included', () {
      expect(name('Rahim Uddin'), 'statement_Rahim_Uddin.pdf');
      expect(name('রহিম'), 'statement_রহিম.pdf'); // ি is a mark
      expect(name('محمد علي'), 'statement_محمد_علي.pdf');
    });

    test('symbols only, or nothing, falls back to the id', () {
      expect(name('***', id: 42), 'statement_42.pdf');
      expect(name('  ', id: 42), 'statement_42.pdf');
    });

    test('a very long name is cut to 40 characters', () {
      final file = name('A' * 300);
      expect(file, 'statement_${'A' * 40}.pdf');
    });
  });

  group('PDF pages that fail to become JPEG stay PNG', () {
    final original = FlutterImageCompressPlatform.instance;
    final originalTimeout = jpegEncodeTimeout;
    tearDown(() {
      FlutterImageCompressPlatform.instance = original;
      jpegEncodeTimeout = originalTimeout;
    });

    const size = (width: 20, height: 30);

    Future<Uint8List> page(WidgetTester tester) async {
      final png = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 20, 30), Paint()..color = Colors.white);
        final image = await recorder.endRecording().toImage(20, 30);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return png!;
    }

    Future<String> assemble(WidgetTester tester, Uint8List png) async {
      final pdf = await tester.runAsync(() => assemblePdf([png], jpegPages: size));
      final text = latin1.decode(pdf!);
      expect(text, startsWith('%PDF'));
      return text;
    }

    testWidgets('a valid JPEG of the page size is used', (tester) async {
      FlutterImageCompressPlatform.instance =
          _FakeCompress(() async => _jpeg(size.width, size.height));
      expect(await assemble(tester, await page(tester)), contains('/DCTDecode'));
    });

    testWidgets('a broken JPEG is refused', (tester) async {
      FlutterImageCompressPlatform.instance =
          _FakeCompress(() async => Uint8List.fromList([0xFF, 0xD8, 0, 0]));
      expect(await assemble(tester, await page(tester)), isNot(contains('/DCTDecode')));
    });

    testWidgets('a JPEG of another size is refused', (tester) async {
      FlutterImageCompressPlatform.instance =
          _FakeCompress(() async => _jpeg(size.width * 3, size.height * 3));
      expect(await assemble(tester, await page(tester)), isNot(contains('/DCTDecode')));
    });

    testWidgets('an encoder that throws keeps the PNG', (tester) async {
      FlutterImageCompressPlatform.instance =
          _FakeCompress(() async => throw PlatformException(code: 'encode_failed'));
      expect(await assemble(tester, await page(tester)), isNot(contains('/DCTDecode')));
    });

    testWidgets('an encoder that never answers keeps the PNG', (tester) async {
      jpegEncodeTimeout = const Duration(milliseconds: 50);
      FlutterImageCompressPlatform.instance =
          _FakeCompress(() => Completer<Uint8List>().future);
      expect(await assemble(tester, await page(tester)), isNot(contains('/DCTDecode')));
    });
  });

  group('Statement button', skip: isarSkipReason, () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(closeTestIsars);

    late Isar isar;
    late int customerId;
    final shareCalls = <MethodCall>[];

    Future<void> seed() async {
      // The watermark icon is cached for the whole run. Load it here, in a
      // real zone: a future first awaited inside one test's fake-async zone
      // never resumes in the next test.
      await loadPdfWatermarkIcon();
      isar = await openTestIsar('statement_share');
      dbWorkerCoreLibrary = isarCoreLibrary(); // the due loads on a worker
      await isar.writeTxn(() async {
        customerId = await isar.customers.put(Customer(name: 'Rahim', phone: '01700000000'));
        final orderId = await isar.orders.put(Order(
          orderNumber: 'ORD-001', customerId: customerId, customerName: 'Rahim',
          items: [OrderItem(productId: 1, productName: 'Eggs', qty: 2, unitPrice: 10, totalPrice: 20)],
          subtotal: 20, totalAmount: 20, amountPaid: 5,
          orderStatus: OrderStatus.confirmed, createdAt: DateTime(2026, 11, 1),
        ));
        await isar.payments.put(Payment(
          customerId: customerId, orderId: orderId, amount: 5, paidAt: DateTime(2026, 11, 1),
        ));
      });
    }

    void mockChannels(WidgetTester tester,
        {bool tempDirFails = false, bool shareFails = false}) {
      shareCalls.clear();
      final tmp = Directory.systemTemp.createTempSync('statement');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (tempDirFails) throw PlatformException(code: 'no_dir');
          return tmp.path;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          shareCalls.add(call);
          if (shareFails) throw PlatformException(code: 'share_failed');
          return 'dev.fluttercommunity.plus/share/unavailable';
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
        messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'), null);
      });
    }

    Future<void> tapStatement(WidgetTester tester) async {
      await pumpScreen(tester, isar: isar, screen: CustomerDetailScreen(customerId: customerId));
      final button = find.text('Statement');
      await tester.ensureVisible(button);
      await tester.tap(button);
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
        final snackBar = find.byType(SnackBar).evaluate().isNotEmpty;
        final shared = shareCalls.isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty;
        if (snackBar || shared) break;
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shares the statement PDF', (tester) async {
      await tester.runAsync(seed);
      mockChannels(tester);
      await tapStatement(tester);
      expect(shareCalls, hasLength(1));
      final args = shareCalls.single.arguments.toString();
      expect(args, contains('statement_Rahim.pdf'));
      expect(args, contains('application/pdf'));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a statement that cannot be made says so', (tester) async {
      await tester.runAsync(seed);
      mockChannels(tester, tempDirFails: true);
      await tapStatement(tester);
      expect(shareCalls, isEmpty);
      expect(find.text("Couldn't create the statement. Please try again."), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a share that fails says the statement was made but not shared', (tester) async {
      await tester.runAsync(seed);
      mockChannels(tester, shareFails: true);
      await tapStatement(tester);
      expect(shareCalls, hasLength(1));
      expect(
        find.text("The statement was created but couldn't be shared. Please try again."),
        findsOneWidget,
      );
    });
  });
}

/// The smallest baseline JPEG the pdf package embeds: SOI, a frame header
/// with the size, a scan header, one byte of scan data, EOI.
Uint8List _jpeg(int width, int height) => Uint8List.fromList([
      0xFF, 0xD8, //
      0xFF, 0xC0, 0x00, 0x11, 0x08, //
      height >> 8, height & 0xFF, width >> 8, width & 0xFF, //
      0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00, //
      0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, //
      0x00, 0x3F, 0x00, 0x00, //
      0xFF, 0xD9,
    ]);

class _FakeCompress extends UnsupportedFlutterImageCompress {
  _FakeCompress(this.answer);

  final Future<Uint8List> Function() answer;

  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) =>
      answer();
}
