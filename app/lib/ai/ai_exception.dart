/// Anything that stopped the AI from answering — the site is down, the PDF was
/// refused, the free website changed, the device has no WebView. The message
/// is written for a teacher, not for a log.
class AiException implements Exception {
  final String message;
  AiException(this.message);

  @override
  String toString() => message;
}
