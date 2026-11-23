import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

typedef PagePixels = ({int width, int height});

Future<Uint8List> assemblePdf(
  List<Uint8List> pages, {
  PagePixels? jpegPages,
}) async {
  final encoded = <Uint8List>[];
  var converted = false;
  for (final png in pages) {
    final size = jpegPages == null ? null : _pngPixels(png);
    final page = size != null && size == jpegPages
        ? await _pngToJpeg(png, size)
        : png;
    converted |= !identical(page, png);
    encoded.add(page);
  }

  try {
    return await compute(_buildPdf, encoded, debugLabel: 'assemblePdf');
  } catch (e, st) {
    // A JPEG page the PDF can't embed shouldn't cost the whole document:
    // build it again from the original PNG pages.
    if (!converted) rethrow;
    developer.log('PDF with JPEG pages failed; retrying with PNG pages',
        name: 'assemblePdf', error: e, stackTrace: st);
    return compute(_buildPdf, pages, debugLabel: 'assemblePdf-png');
  }
}

Future<Uint8List> _buildPdf(List<Uint8List> pages) {
  final pdf = pw.Document();
  for (final bytes in pages) {
    final image = pw.MemoryImage(bytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(
          image,
          fit: pw.BoxFit.fitWidth,
          alignment: pw.Alignment.topCenter,
        ),
      ),
    );
  }
  return pdf.save();
}

PagePixels? _pngPixels(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}

const _jpegQuality = 75;

/// How long one page's JPEG encode may take before the page stays PNG, so a
/// native encoder that never answers can't hold a progress spinner forever.
@visibleForTesting
Duration jpegEncodeTimeout = const Duration(seconds: 20);

Future<Uint8List> _pngToJpeg(Uint8List png, PagePixels size) async {
  try {
    final jpeg = await FlutterImageCompress.compressWithList(
      png,
      format: CompressFormat.jpeg,
      quality: _jpegQuality,
      minWidth: size.width,
      minHeight: size.height,
      autoCorrectionAngle: false,
      keepExif: false,
    ).timeout(jpegEncodeTimeout);
    if (_isJpegOf(jpeg, size)) return jpeg;
    developer.log('JPEG page invalid; keeping PNG', name: 'assemblePdf');
  } catch (e, st) {
    developer.log('JPEG page encode failed; keeping PNG',
        name: 'assemblePdf', error: e, stackTrace: st);
  }
  return png;
}

/// A JPEG the PDF can embed: it starts like one and its frame header (read
/// the way the pdf package reads it) has the page's size.
bool _isJpegOf(Uint8List jpeg, PagePixels size) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return false;
  try {
    final info = PdfJpegInfo(jpeg);
    return info.width == size.width && info.height == size.height;
  } catch (_) {
    return false;
  }
}
