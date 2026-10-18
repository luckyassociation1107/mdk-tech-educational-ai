import 'package:flutter/services.dart';

/// Bridge to the on-device Python engine (Chaquopy) via MainActivity.
/// The Android side owns: Python engine calls, Android TextToSpeech
/// (this is where a device Telugu voice is used when installed), and
/// PDFBox-Android extraction when PyMuPDF is unavailable on the device.
/// See docs/ANDROID_INTEGRATION.md — no server is involved.
class EngineGateway {
  static const _ch = MethodChannel('com.mdk.textbook_video/engine');

  Future<Map<String, dynamic>> createSession({
    required String pdfPath,
    required String language,
    int? grade,
    String brain = 'offline',
    String brainServerUrl = '',
  }) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('createSession', {
      'pdfPath': pdfPath,
      'language': language,
      'grade': grade,
      'brain': brain,
      'brainServerUrl': brainServerUrl,
    });
    if (r == null) throw StateError('Engine returned no session');
    return r;
  }

  Future<Map<String, dynamic>> generateVideo({
    required String sessionId,
    required String question,
    required String mode,
    required String resolution,
    required String theme,
    bool pageReading = false,
    List<int>? pageRange,
    String partLabel = '',
    String nextPartLabel = '',
    String brain = 'offline',
    String brainServerUrl = '',
  }) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('generateVideo', {
      'sessionId': sessionId,
      'question': question,
      'mode': mode,
      'resolution': resolution,
      'theme': theme,
      'pageReading': pageReading,
      'pageRange': pageRange,
      'partLabel': partLabel,
      'nextPartLabel': nextPartLabel,
      'brain': brain,
      'brainServerUrl': brainServerUrl,
    });
    if (r == null) throw StateError('Engine returned no video result');
    return r;
  }

  /// Chat with the textbook inside the SAME session — answer only, no video.
  Future<Map<String, dynamic>> askChat({
    required String sessionId,
    required String question,
    String brain = 'offline',
    String brainServerUrl = '',
  }) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('askChat', {
      'sessionId': sessionId,
      'question': question,
      'brain': brain,
      'brainServerUrl': brainServerUrl,
    });
    if (r == null) throw StateError('Engine returned no chat answer');
    return r;
  }

  Future<List<dynamic>> sessionVideos(String sessionId, {String brain = 'offline', String brainServerUrl = ''}) async {
    final r = await _ch.invokeListMethod<dynamic>('sessionVideos', {
      'sessionId': sessionId,
      'brain': brain,
      'brainServerUrl': brainServerUrl,
    });
    return r ?? const [];
  }

  /// Whole-chapter series: parts split by real pages, locked/unlocked.
  Future<Map<String, dynamic>> chapterSeries(String sessionId, {int pagesPerPart = 6, String brain = 'offline', String brainServerUrl = ''}) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('chapterSeries', {
      'sessionId': sessionId,
      'pagesPerPart': pagesPerPart,
      'brain': brain,
      'brainServerUrl': brainServerUrl,
    });
    return r ?? {'parts': []};
  }

  /// Finishing a part unlocks the next video in the series.
  Future<Map<String, dynamic>> completePart(String sessionId, int part, {String brain = 'offline', String brainServerUrl = ''}) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('completePart', {
      'sessionId': sessionId,
      'part': part,
      'brain': brain,
      'brainServerUrl': brainServerUrl,
    });
    return r ?? {'parts': []};
  }

  Future<Map<String, dynamic>> disconnect(String sessionId) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('disconnect', {'sessionId': sessionId});
    return r ?? {'cleanup': 'unknown'};
  }

  Future<List<dynamic>> listSessions({String brain = 'offline', String brainServerUrl = ''}) async {
    final r = await _ch.invokeListMethod<dynamic>('listSessions', {'brain': brain, 'brainServerUrl': brainServerUrl});
    return r ?? const [];
  }

  /// Check Android TTS voice availability, e.g. 'te-IN' / 'en-IN'.
  /// Returns e.g. {available: true} or {available: false, reason: ...}.
  Future<Map<String, dynamic>> checkTts(String languageCode) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('checkTts', {'language': languageCode});
    return r ?? {'available': false, 'reason': 'no response from Android TTS'};
  }
}

/// Generation modes from the spec (§8).
const kModes = {
  'quick_explanation': 'Quick Explanation',
  'detailed_teaching': 'Detailed Teaching',
  'complete_concept_mastery': 'Complete Concept Mastery',
};

const kExampleQuestions = [
  'Explain this topic in Telugu.',
  'Explain this formula step by step.',
  'Give real-life examples.',
  'Explain the diagram on this topic.',
  'Teach the complete concept from basics.',
  'Generate a revision video.',
];
