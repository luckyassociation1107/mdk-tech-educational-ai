import 'dart_engine.dart';
import 'lesson_content.dart';

/// The app-facing engine API. Everything now runs in Dart on the device
/// (see dart_engine.dart): PDF parsing, chapter series, offline doubt
/// clearing and interactive lessons — no Python, no native engine.
/// The textbook is read by the teacher's own AI (Settings → AI & Prompts);
/// page pictures and figure crops are rendered locally with PDFium, so the
/// same build works on Android and Windows.
class EngineGateway {
  /// The online brain receives the student's actual PDF, so it must
  /// never be a plaintext endpoint out on the internet. Plain HTTP is
  /// tolerated only for localhost / LAN addresses.
  static void guardBrainUrl(String brain, String brainServerUrl) {
    if (brain != 'playwright') return;
    final url = brainServerUrl.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? '').toLowerCase();
    final isLan = host == 'localhost' ||
        host.endsWith('.local') ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host);
    if (uri == null ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && isLan))) {
      throw StateError(
          'The online brain needs an HTTPS server URL (plain HTTP is allowed only on your local network).');
    }
  }

  /// Uploads the PDF to the teacher's AI and builds the session.
  /// [onProgress] reports stages like "AI is reading pages 13–24".
  Future<Map<String, dynamic>> createSession({
    required String pdfPath,
    required String language,
    int? grade,
    String brain = 'offline',
    String brainServerUrl = '',
    void Function(int done, int total, String stage)? onProgress,
  }) {
    guardBrainUrl(brain, brainServerUrl);
    return DartEngine.createSession(
        pdfPath: pdfPath,
        language: language,
        grade: grade,
        brain: brain,
        brainServerUrl: brainServerUrl,
        onProgress: onProgress);
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
    String language = 'en',
    int? grade,
  }) =>
      DartEngine.generateLesson(
          sessionId: sessionId,
          question: question,
          pageRange: pageRange,
          partLabel: partLabel,
          language: language,
          grade: grade);

  /// Chat with the textbook inside the SAME session — answer only.
  Future<Map<String, dynamic>> askChat({
    required String sessionId,
    required String question,
    String brain = 'offline',
    String brainServerUrl = '',
  }) =>
      DartEngine.askChat(sessionId, question);

  Future<List<dynamic>> sessionVideos(String sessionId,
          {String brain = 'offline', String brainServerUrl = ''}) =>
      DartEngine.sessionLessons(sessionId);

  /// Whole-chapter series: parts split by real pages, locked/unlocked.
  Future<Map<String, dynamic>> chapterSeries(String sessionId,
          {int pagesPerPart = 6,
          String brain = 'offline',
          String brainServerUrl = ''}) =>
      DartEngine.chapterSeries(sessionId, pagesPerPart: pagesPerPart);

  /// Finishing a part unlocks the next part in the series.
  Future<Map<String, dynamic>> completePart(String sessionId, int part,
          {String brain = 'offline', String brainServerUrl = ''}) =>
      DartEngine.completePart(sessionId, part);

  Future<Map<String, dynamic>> disconnect(String sessionId) =>
      DartEngine.disconnect(sessionId);

  /// The AI-designed scene list for a part (empty when the on-device
  /// builder was used instead).
  Future<List<LessonScene>> loadScenes(String sessionId, int part) =>
      DartEngine.loadScenes(sessionId, part);

  /// Renders a page on demand (Android + Windows) and returns its file.
  Future<String?> ensurePageImage(String sessionId, int page) =>
      DartEngine.ensurePageImage(sessionId, page);

  /// Crops a figure using the AI's normalised box.
  Future<String?> figurePath(String sessionId, int page, List<double> bbox) =>
      DartEngine.figurePath(sessionId, page, bbox);

  // Website-brain results, stored locally per session (see DartEngine).
  Future<String> sessionPdfPath(String sessionId) =>
      DartEngine.sessionPdfPath(sessionId);
  Future<Map<String, dynamic>> loadBrainData(String sessionId) =>
      DartEngine.loadBrainData(sessionId);
  Future<void> saveBrainSummary(String sessionId, String summary, int level) =>
      DartEngine.saveBrainSummary(sessionId, summary, level);
  Future<void> addBrainQa(String sessionId, String question, String answer) =>
      DartEngine.addBrainQa(sessionId, question, answer);

  Future<List<dynamic>> listSessions(
          {String brain = 'offline', String brainServerUrl = ''}) =>
      DartEngine.listSessions();

  /// Check Android TTS voice availability, e.g. 'te-IN' / 'en-IN'.
  Future<Map<String, dynamic>> checkTts(String languageCode) =>
      DartEngine.checkTts(languageCode);
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
