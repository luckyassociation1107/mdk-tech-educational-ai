import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// One neural voice offered by the online reader.
class NeuralVoice {
  final String lang; // app language code (en, te, hi …)
  final String name; // exact engine voice name
  final String gender; // F | M
  const NeuralVoice(this.lang, this.name, this.gender);

  /// "Shruti (female)" — what the teacher sees in the list.
  String get label {
    final short = name.split('-').last.replaceAll('Neural', '');
    return '$short (${gender == 'F' ? 'female' : 'male'})';
  }
}

/// Every neural voice the reader can produce, generated from the engine's own
/// voice list. Two voices per language in most cases — the teacher picks the
/// one they like, and it is remembered.
const List<NeuralVoice> kNeuralVoices = [
  NeuralVoice('en', 'en-IN-NeerjaExpressiveNeural', 'F'),
  NeuralVoice('en', 'en-IN-PrabhatNeural', 'M'),
  NeuralVoice('te', 'te-IN-ShrutiNeural', 'F'),
  NeuralVoice('te', 'te-IN-MohanNeural', 'M'),
  NeuralVoice('hi', 'hi-IN-SwaraNeural', 'F'),
  NeuralVoice('hi', 'hi-IN-MadhurNeural', 'M'),
  NeuralVoice('ta', 'ta-IN-PallaviNeural', 'F'),
  NeuralVoice('ta', 'ta-IN-ValluvarNeural', 'M'),
  NeuralVoice('kn', 'kn-IN-SapnaNeural', 'F'),
  NeuralVoice('kn', 'kn-IN-GaganNeural', 'M'),
  NeuralVoice('ml', 'ml-IN-SobhanaNeural', 'F'),
  NeuralVoice('ml', 'ml-IN-MidhunNeural', 'M'),
  NeuralVoice('mr', 'mr-IN-AarohiNeural', 'F'),
  NeuralVoice('mr', 'mr-IN-ManoharNeural', 'M'),
  NeuralVoice('bn', 'bn-IN-TanishaaNeural', 'F'),
  NeuralVoice('bn', 'bn-IN-BashkarNeural', 'M'),
  NeuralVoice('gu', 'gu-IN-DhwaniNeural', 'F'),
  NeuralVoice('gu', 'gu-IN-NiranjanNeural', 'M'),
  NeuralVoice('ur', 'ur-IN-GulNeural', 'F'),
  NeuralVoice('ur', 'ur-IN-SalmanNeural', 'M'),
  NeuralVoice('ne', 'ne-NP-HemkalaNeural', 'F'),
  NeuralVoice('ne', 'ne-NP-SagarNeural', 'M'),
  NeuralVoice('si', 'si-LK-ThiliniNeural', 'F'),
  NeuralVoice('si', 'si-LK-SameeraNeural', 'M'),
  NeuralVoice('es', 'es-ES-ElviraNeural', 'F'),
  NeuralVoice('es', 'es-ES-AlvaroNeural', 'M'),
  NeuralVoice('fr', 'fr-FR-DeniseNeural', 'F'),
  NeuralVoice('fr', 'fr-FR-HenriNeural', 'M'),
  NeuralVoice('de', 'de-DE-KatjaNeural', 'F'),
  NeuralVoice('de', 'de-DE-ConradNeural', 'M'),
  NeuralVoice('pt', 'pt-BR-FranciscaNeural', 'F'),
  NeuralVoice('pt', 'pt-BR-AntonioNeural', 'M'),
  NeuralVoice('it', 'it-IT-ElsaNeural', 'F'),
  NeuralVoice('it', 'it-IT-DiegoNeural', 'M'),
  NeuralVoice('nl', 'nl-NL-FennaNeural', 'F'),
  NeuralVoice('nl', 'nl-NL-MaartenNeural', 'M'),
  NeuralVoice('ru', 'ru-RU-SvetlanaNeural', 'F'),
  NeuralVoice('ru', 'ru-RU-DmitryNeural', 'M'),
  NeuralVoice('uk', 'uk-UA-PolinaNeural', 'F'),
  NeuralVoice('uk', 'uk-UA-OstapNeural', 'M'),
  NeuralVoice('pl', 'pl-PL-ZofiaNeural', 'F'),
  NeuralVoice('pl', 'pl-PL-MarekNeural', 'M'),
  NeuralVoice('cs', 'cs-CZ-VlastaNeural', 'F'),
  NeuralVoice('cs', 'cs-CZ-AntoninNeural', 'M'),
  NeuralVoice('ro', 'ro-RO-AlinaNeural', 'F'),
  NeuralVoice('ro', 'ro-RO-EmilNeural', 'M'),
  NeuralVoice('hu', 'hu-HU-NoemiNeural', 'F'),
  NeuralVoice('hu', 'hu-HU-TamasNeural', 'M'),
  NeuralVoice('el', 'el-GR-AthinaNeural', 'F'),
  NeuralVoice('el', 'el-GR-NestorasNeural', 'M'),
  NeuralVoice('sv', 'sv-SE-SofieNeural', 'F'),
  NeuralVoice('sv', 'sv-SE-MattiasNeural', 'M'),
  NeuralVoice('da', 'da-DK-ChristelNeural', 'F'),
  NeuralVoice('da', 'da-DK-JeppeNeural', 'M'),
  NeuralVoice('nb', 'nb-NO-PernilleNeural', 'F'),
  NeuralVoice('nb', 'nb-NO-FinnNeural', 'M'),
  NeuralVoice('fi', 'fi-FI-NooraNeural', 'F'),
  NeuralVoice('fi', 'fi-FI-HarriNeural', 'M'),
  NeuralVoice('tr', 'tr-TR-EmelNeural', 'F'),
  NeuralVoice('tr', 'tr-TR-AhmetNeural', 'M'),
  NeuralVoice('ar', 'ar-SA-ZariyahNeural', 'F'),
  NeuralVoice('ar', 'ar-SA-HamedNeural', 'M'),
  NeuralVoice('fa', 'fa-IR-DilaraNeural', 'F'),
  NeuralVoice('fa', 'fa-IR-FaridNeural', 'M'),
  NeuralVoice('he', 'he-IL-HilaNeural', 'F'),
  NeuralVoice('he', 'he-IL-AvriNeural', 'M'),
  NeuralVoice('sw', 'sw-KE-ZuriNeural', 'F'),
  NeuralVoice('sw', 'sw-KE-RafikiNeural', 'M'),
  NeuralVoice('am', 'am-ET-MekdesNeural', 'F'),
  NeuralVoice('am', 'am-ET-AmehaNeural', 'M'),
  NeuralVoice('zh-CN', 'zh-CN-XiaoxiaoNeural', 'F'),
  NeuralVoice('zh-CN', 'zh-CN-YunxiNeural', 'M'),
  NeuralVoice('zh-TW', 'zh-TW-HsiaoChenNeural', 'F'),
  NeuralVoice('zh-TW', 'zh-TW-YunJheNeural', 'M'),
  NeuralVoice('ja', 'ja-JP-NanamiNeural', 'F'),
  NeuralVoice('ja', 'ja-JP-KeitaNeural', 'M'),
  NeuralVoice('ko', 'ko-KR-SunHiNeural', 'F'),
  NeuralVoice('ko', 'ko-KR-InJoonNeural', 'M'),
  NeuralVoice('vi', 'vi-VN-HoaiMyNeural', 'F'),
  NeuralVoice('vi', 'vi-VN-NamMinhNeural', 'M'),
  NeuralVoice('th', 'th-TH-PremwadeeNeural', 'F'),
  NeuralVoice('th', 'th-TH-NiwatNeural', 'M'),
  NeuralVoice('id', 'id-ID-GadisNeural', 'F'),
  NeuralVoice('id', 'id-ID-ArdiNeural', 'M'),
  NeuralVoice('ms', 'ms-MY-YasminNeural', 'F'),
  NeuralVoice('ms', 'ms-MY-OsmanNeural', 'M'),
];

/// Languages that have no neural voice at all, and the voice that reads their
/// script best (Sanskrit in Devanagari → Hindi voice, Sindhi → Urdu voice).
const Map<String, String> kNeuralVoiceFallback = {
  'sa': 'hi',
  'sd': 'ur',
};

/// Voices for [lang]. Empty when the language has no natural voice.
List<NeuralVoice> neuralVoicesFor(String lang) {
  final code = kNeuralVoiceFallback[lang] ?? lang;
  return kNeuralVoices.where((v) => v.lang == code).toList();
}

/// The default voice for a language: a warm female teacher, or the first one
/// available. Returns null for languages the reader cannot speak.
String? defaultNeuralVoice(String lang) {
  final list = neuralVoicesFor(lang);
  if (list.isEmpty) return null;
  final f = list.where((v) => v.gender == 'F');
  return (f.isNotEmpty ? f.first : list.first).name;
}

/// True when a natural voice exists for [lang].
bool languageHasNeuralVoice(String lang) => neuralVoicesFor(lang).isNotEmpty;

/// Talks to the free neural reader that powers the browser's Read Aloud.
///
/// The protocol is a WebSocket: one JSON config frame, one SSML frame, then
/// binary frames that carry MP3 audio. No key, no account, nothing paid.
/// A request that fails is reported as an error so the caller can fall back.
class NeuralTts {
  NeuralTts._();
  static final NeuralTts instance = NeuralTts._();

  static const String _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _version = '1-143.0.3650.75';
  static const String _sdk = '1.37.0';

  /// The security token the service expects: SHA-256 over the current
  /// five-minute window and its published client token.
  static String gecToken([DateTime? now]) {
    var secs = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
    secs += 11644473600; // Windows file-time epoch
    secs -= secs % 300;
    final raw = '${secs * 10000000}$_token';
    return _sha256Hex(utf8.encode(raw)).toUpperCase();
  }

  static String _sha256Hex(List<int> data) {
    // Small, dependency-free SHA-256 (the package `crypto` is already in the
    // project but keeping this local makes the class testable on its own).
    const k = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
      0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
      0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
      0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
      0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
      0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ];
    var h = [
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ];
    final msg = <int>[...data, 0x80];
    while (msg.length % 64 != 56) {
      msg.add(0);
    }
    final bitLen = data.length * 8;
    for (var i = 7; i >= 0; i--) {
      msg.add((bitLen >> (i * 8)) & 0xff);
    }
    int u32(int v) => v & 0xffffffff;
    int rotr(int x, int n) => u32((x >> n) | (x << (32 - n)));
    for (var off = 0; off < msg.length; off += 64) {
      final w = List<int>.filled(64, 0);
      for (var i = 0; i < 16; i++) {
        w[i] = (msg[off + i * 4] << 24) |
            (msg[off + i * 4 + 1] << 16) |
            (msg[off + i * 4 + 2] << 8) |
            msg[off + i * 4 + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = u32(w[i - 16] + s0 + w[i - 7] + s1);
      }
      var a = h[0], b = h[1], c = h[2], d = h[3];
      var e = h[4], f = h[5], g = h[6], hh = h[7];
      for (var i = 0; i < 64; i++) {
        final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final t1 = u32(hh + s1 + ch + k[i] + w[i]);
        final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = u32(s0 + maj);
        hh = g;
        g = f;
        f = e;
        e = u32(d + t1);
        d = c;
        c = b;
        b = a;
        a = u32(t1 + t2);
      }
      h = [
        u32(h[0] + a), u32(h[1] + b), u32(h[2] + c), u32(h[3] + d), //
        u32(h[4] + e), u32(h[5] + f), u32(h[6] + g), u32(h[7] + hh)
      ];
    }
    final sb = StringBuffer();
    for (final v in h) {
      sb.write(v.toRadixString(16).padLeft(8, '0'));
    }
    return sb.toString();
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// SSML for one utterance. Rate and pitch are percentages around 100.
  static String ssml(
    String text, {
    required String voice,
    double rate = 1.0,
    double pitch = 1.0,
  }) {
    final r = ((rate.clamp(0.5, 1.5) - 1) * 100).round();
    final p = ((pitch.clamp(0.5, 1.6) - 1) * 100).round();
    final rateStr = r >= 0 ? '+$r%' : '$r%';
    final pitchStr = p >= 0 ? '+$p%' : '$p%';
    return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' "
        "xml:lang='en-US'><voice name='$voice'>"
        "<prosody pitch='$pitchStr' rate='$rateStr' volume='+0%'>"
        '${_escape(text)}'
        '</prosody></voice></speak>';
  }

  /// The service wants a UUID with no dashes (32 hex characters).
  static String requestId([Random? rng]) {
    final r = rng ?? Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      sb.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// The exact timestamp shape the reader expects.
  static String stamp([DateTime? now]) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final t = (now ?? DateTime.now()).toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} ${months[t.month - 1]} ${t.day} ${t.year} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)} '
        'GMT+0000 (Coordinated Universal Time)';
  }

  static Uri endpoint() => Uri.parse(
      'wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1'
      '?Ocp-Apim-Subscription-Key=$_token'
      '&Sec-MS-GEC=${gecToken()}&Sec-MS-GEC-Version=$_version');

  /// Turns [text] into MP3 bytes. Throws on any failure.
  Future<Uint8List> synth(
    String text, {
    required String voice,
    double rate = 1.0,
    double pitch = 1.0,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return Uint8List(0);

    WebSocket? ws;
    try {
      ws = await WebSocket.connect(endpoint().toString(), headers: {
        'Pragma': 'no-cache',
        'Cache-Control': 'no-cache',
        'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 '
            'Safari/537.36 Edg/143.0.0.0',
      }).timeout(const Duration(seconds: 12));

      final ts = stamp();
      final config = jsonEncode({
        'context': {
          'synthesis': {
            'audio': {
              'metadataoptions': {
                'sentenceBoundaryEnabled': 'false',
                'wordBoundaryEnabled': 'false',
              },
              'outputFormat': 'audio-24khz-48kbitrate-mono-mp3',
            }
          }
        },
        'system': {
          'name': 'SpeechSDK',
          'version': _sdk,
          'build': 'JavaScript',
          'lang': 'en-US',
        }
      });
      ws.add('X-Timestamp:$ts\r\n'
          'Content-Type:application/json; charset=utf-8\r\n'
          'Path:speech.config\r\n\r\n$config');
      ws.add('X-RequestId:${requestId()}\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${ts}Z\r\n'
          'Path:ssml\r\n\r\n'
          '${ssml(clean, voice: voice, rate: rate, pitch: pitch)}');

      final bytes = BytesBuilder(copy: false);
      await for (final msg in ws.timeout(timeout)) {
        if (msg is String) {
          final head = msg.split('\r\n\r\n').first;
          if (head.contains('Path:turn.end')) break;
          continue;
        }
        final data = msg as List<int>;
        if (data.length < 2) continue;
        final headerLen = (data[0] << 8) | data[1];
        if (data.length < 2 + headerLen) continue;
        final header = utf8.decode(data.sublist(2, 2 + headerLen),
            allowMalformed: true);
        if (header.contains('Path:audio')) {
          bytes.add(data.sublist(2 + headerLen));
        }
      }
      final out = bytes.takeBytes();
      if (out.length < 1000) {
        throw const SocketException('neural voice returned no audio');
      }
      return out;
    } finally {
      try {
        await ws?.close();
      } catch (_) {}
    }
  }

  /// One retry, because a single dropped socket on school Wi-Fi is common.
  Future<Uint8List> synthRetried(
    String text, {
    required String voice,
    double rate = 1.0,
    double pitch = 1.0,
  }) async {
    try {
      return await synth(text, voice: voice, rate: rate, pitch: pitch);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return synth(text, voice: voice, rate: rate, pitch: pitch);
    }
  }
}
