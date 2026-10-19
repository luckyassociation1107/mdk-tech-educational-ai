import 'dart_engine.dart';

/// The app-facing engine API. Everything now runs in Dart on the device
/// (see dart_engine.dart): PDF parsing, chapter series, offline doubt
/// clearing and interactive lessons — no Python, no native engine.
/// (The online "playwright" brain label is accepted for compatibility;
/// lesson content is composed locally from the extracted textbook, and
/// page pictures come from Android PdfRenderer.)
class EngineGateway {
  Future<Map<String, dynamic>> createSession({
    required String pdfPath,
    required String language,
    int? grade,
    String brain = 'offline',
    String brainServerUrl = '',
  }) =>
      DartEngine.createSession(pdfPath: pdfPath, language: language, grade: grade, brain: brain, brainServerUrl: brainServerUrl);

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
  }) =>
      DartEngine.generateLesson(sessionId: sessionId, question: question, pageRange: pageRange, partLabel: partLabel);

  /// Chat with the textbook inside the SAME session — answer only.
  Future<Map<String, dynamic>> askChat({
    required String sessionId,
    required String question,
    String brain = 'offline',
    String brainServerUrl = '',
  }) =>
      DartEngine.askChat(sessionId, question);

  Future<List<dynamic>> sessionVideos(String sessionId, {String brain = 'offline', String brainServerUrl = ''}) =>
      DartEngine.sessionLessons(sessionId);

  /// Whole-chapter series: parts split by real pages, locked/unlocked.
  Future<Map<String, dynamic>> chapterSeries(String sessionId, {int pagesPerPart = 6, String brain = 'offline', String brainServerUrl = ''}) =>
      DartEngine.chapterSeries(sessionId, pagesPerPart: pagesPerPart);

  /// Finishing a part unlocks the next part in the series.
  Future<Map<String, dynamic>> completePart(String sessionId, int part, {String brain = 'offline', String brainServerUrl = ''}) =>
      DartEngine.completePart(sessionId, part);

  Future<Map<String, dynamic>> disconnect(String sessionId) => DartEngine.disconnect(sessionId);

  Future<List<dynamic>> listSessions({String brain = 'offline', String brainServerUrl = ''}) => DartEngine.listSessions();

  /// Check Android TTS voice availability, e.g. 'te-IN' / 'en-IN'.
  Future<Map<String, dynamic>> checkTts(String languageCode) => DartEngine.checkTts(languageCode);
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
