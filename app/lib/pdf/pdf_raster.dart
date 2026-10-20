import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:pdfx/pdfx.dart';

import 'figure_finder.dart';

/// Page pictures and figure crops, rendered by the PDFium engine through
/// `pdfx`, which works on Android **and** Windows (the old build could only
/// render pages on Android, in Kotlin).
///
/// Nothing here reads the words on a page — text comes from the AI. This
/// class only turns a page (or a box on a page) into pixels.
class PdfRaster {
  /// Set when the platform plugin cannot be reached (unit tests, an
  /// unsupported build). The UI then says pages are unavailable instead of
  /// retrying on every frame.
  static bool unavailable = false;

  static Future<int> pageCount(String pdfPath) async {
    if (unavailable) return 0;
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      return doc.pagesCount;
    } catch (_) {
      return 0;
    } finally {
      await doc?.close();
    }
  }

  /// Full page as PNG. Returns the file path, or null when rendering is not
  /// available on this device.
  static Future<String?> renderPage({
    required String pdfPath,
    required int page,
    required String outPath,
    double targetWidth = 1400,
  }) async {
    if (unavailable) return null;
    PdfDocument? doc;
    PdfPage? pdfPage;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      if (page < 1 || page > doc.pagesCount) return null;
      pdfPage = await doc.getPage(page);
      final w = pdfPage.width;
      final h = pdfPage.height;
      if (w <= 0 || h <= 0) return null;
      final scale = (targetWidth / w).clamp(0.5, 4.0);
      final img = await pdfPage.render(
        width: w * scale,
        height: h * scale,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (img == null) return null;
      final file = File(outPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(img.bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      await pdfPage?.close();
      await doc?.close();
    }
  }

  /// Crop one figure out of a page. [bbox] is normalised (0..1, top-left
  /// origin) exactly as the AI returned it, so "cut this diagram" is just
  /// coordinates → pixels.
  static Future<String?> cropFigure({
    required String pdfPath,
    required int page,
    required List<double> bbox,
    required String outPath,
    double scale = 2.4,
  }) async {
    if (unavailable || bbox.length != 4) return null;
    PdfDocument? doc;
    PdfPage? pdfPage;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      if (page < 1 || page > doc.pagesCount) return null;
      pdfPage = await doc.getPage(page);
      final w = pdfPage.width;
      final h = pdfPage.height;
      final rect = Rect.fromLTRB(
        (bbox[0] * w).clamp(0.0, w),
        (bbox[1] * h).clamp(0.0, h),
        (bbox[2] * w).clamp(0.0, w),
        (bbox[3] * h).clamp(0.0, h),
      );
      if (rect.width < 8 || rect.height < 8) return null;
      final img = await pdfPage.render(
        width: rect.width * scale,
        height: rect.height * scale,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
        cropRect: rect,
        quality: 96,
      );
      if (img == null) return null;
      final file = File(outPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(img.bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    } finally {
      await pdfPage?.close();
      await doc?.close();
    }
  }

  /// Decode a rendered page (PNG) into raw RGBA + size for [FigureFinder].
  static Future<(Uint8List, int, int)?> decodeRgba(String pngPath) async {
    try {
      final bytes = await File(pngPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final out = data == null
          ? null
          : (data.buffer.asUint8List(), image.width, image.height);
      image.dispose();
      codec.dispose();
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Find the figure on a rendered page: the AI says *what* it is and
  /// roughly *where*; this measures the exact box from the pixels.
  static Future<List<double>?> findFigureBox(
    String pngPath, {
    String? where,
    List<double>? hint,
  }) async {
    final decoded = await decodeRgba(pngPath);
    if (decoded == null) return hint;
    final (rgba, w, h) = decoded;
    final boxes = FigureFinder.detect(rgba, w, h);
    final chosen = FigureFinder.choose(boxes, where: where, hint: hint);
    if (chosen == null) return hint;
    return FigureFinder.pad(chosen).bbox;
  }

  /// Convenience used by tests and callers that already hold bytes.
  static Future<String?> cropFromBytes({
    required Uint8List pdfBytes,
    required int page,
    required List<double> bbox,
    required String outPath,
  }) async {
    final tmp = File('$outPath.src.pdf');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsBytes(pdfBytes, flush: true);
    try {
      return await cropFigure(
          pdfPath: tmp.path, page: page, bbox: bbox, outPath: outPath);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }
}
