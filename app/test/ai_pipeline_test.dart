import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:textbook_video_classroom/ai/ai_client.dart';
import 'package:textbook_video_classroom/ai/ai_config.dart';
import 'package:textbook_video_classroom/ai/json_utils.dart';
import 'package:textbook_video_classroom/ai/script_designer.dart';
import 'package:textbook_video_classroom/ai/textbook_extractor.dart';
import 'package:textbook_video_classroom/lesson_content.dart';

/// A fake transport: the request builders and response parsers are pure, so
/// the whole AI pipeline can be tested without a key or a network.
class FakeAi extends AiClient {
  FakeAi(this.reply);
  final String reply;
  final List<AiCall> seen = [];

  @override
  Future<String> generate(
    AiConfig cfg, {
    required List<AiPart> parts,
    bool json = false,
    int maxTokens = 4096,
    Duration timeout = const Duration(minutes: 4),
  }) async {
    seen.add(AiClient.build(cfg, parts: parts, json: json, maxTokens: maxTokens));
    return reply;
  }
}

AiConfig cfgFor(AiProvider p, {String key = 'test-key', String? script}) =>
    AiConfig(
        mode: AiMode.api,
        provider: p,
        apiKey: key,
        model: '',
        scriptPrompt: script);

final Uint8List fakePdf = Uint8List.fromList(utf8.encode('%PDF-1.4 fake'));

void main() {
  group('request builders', () {
    test('OpenAI uploads the PDF as input_file on /v1/responses', () {
      final call = AiClient.build(cfgFor(AiProvider.openai), parts: [
        AiPart.text('extract this'),
        AiPart.pdf(fakePdf, 'book.pdf'),
      ], json: true);
      expect(call.url.toString(), 'https://api.openai.com/v1/responses');
      expect(call.headers['authorization'], 'Bearer test-key');
      final content = (call.body['input'] as List).first['content'] as List;
      expect(content.first['type'], 'input_text');
      expect(content.last['type'], 'input_file');
      expect(content.last['file_data'],
          startsWith('data:application/pdf;base64,'));
      expect((call.body['text'] as Map)['format']['type'], 'json_object');
    });

    test('Gemini sends inline_data and the key in the query', () {
      final call = AiClient.build(cfgFor(AiProvider.gemini), parts: [
        AiPart.text('read'),
        AiPart.pdf(fakePdf, 'book.pdf'),
      ], json: true);
      expect(call.url.toString(),
          contains('/v1beta/models/gemini-2.5-flash:generateContent'));
      expect(call.url.queryParameters['key'], 'test-key');
      final parts = (call.body['contents'] as List).first['parts'] as List;
      expect(parts.first['text'], 'read');
      expect(parts.last['inline_data']['mime_type'], 'application/pdf');
      expect((call.body['generationConfig'] as Map)['responseMimeType'],
          'application/json');
    });

    test('Claude sends a base64 document block', () {
      final call = AiClient.build(cfgFor(AiProvider.anthropic), parts: [
        AiPart.text('read'),
        AiPart.pdf(fakePdf, 'book.pdf'),
      ]);
      expect(call.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(call.headers['x-api-key'], 'test-key');
      expect(call.headers['anthropic-version'], isNotEmpty);
      final content = (call.body['messages'] as List).first['content'] as List;
      expect(content.last['type'], 'document');
      expect(content.last['source']['media_type'], 'application/pdf');
    });

    test('a custom endpoint cannot receive a PDF', () {
      expect(
        () => AiClient.build(cfgFor(AiProvider.custom), parts: [
          AiPart.pdf(fakePdf, 'book.pdf'),
        ]),
        throwsA(isA<AiException>()),
      );
    });

    test('an oversized PDF is refused before the request', () {
      final big = Uint8List(AiClient.maxPdfBytes + 1);
      expect(
        () => AiClient.build(cfgFor(AiProvider.openai), parts: [
          AiPart.pdf(big, 'big.pdf'),
        ]),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('response parsing', () {
    test('OpenAI output_text', () {
      final body = jsonEncode({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'hello '},
              {'type': 'output_text', 'text': 'world'},
            ],
          }
        ],
      });
      expect(AiClient.parseResponse(AiProvider.openai, body), 'hello world');
    });

    test('Gemini candidates', () {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'hello '},
                {'text': 'gemini'},
              ]
            }
          }
        ]
      });
      expect(AiClient.parseResponse(AiProvider.gemini, body), 'hello gemini');
    });

    test('Claude content blocks', () {
      final body = jsonEncode({
        'content': [
          {'type': 'text', 'text': 'hello '},
          {'type': 'text', 'text': 'claude'},
        ]
      });
      expect(AiClient.parseResponse(AiProvider.anthropic, body), 'hello claude');
    });

    test('provider error messages are surfaced', () {
      final body = jsonEncode({
        'error': {'message': 'Incorrect API key provided'}
      });
      expect(
        () => AiClient.parseResponse(AiProvider.openai, body),
        throwsA(predicate((e) => '$e'.contains('Incorrect API key'))),
      );
    });
  });

  group('json repair', () {
    test('reads an object out of a fenced reply with prose around it', () {
      final raw = 'Sure!\n```json\n{"title":"Science","pages":[]}\n```\nHope that helps.';
      final obj = JsonUtils.object(raw);
      expect(obj?['title'], 'Science');
    });

    test('survives a trailing comma', () {
      final obj = JsonUtils.object('{"a":1,"b":[1,2,],}');
      expect(obj?['a'], 1);
    });

    test('returns null when there is no object at all', () {
      expect(JsonUtils.object('I cannot help with that.'), isNull);
    });
  });

  group('figure boxes', () {
    test('keeps a normal box', () {
      expect(JsonUtils.bbox([0.1, 0.2, 0.9, 0.7]), [0.1, 0.2, 0.9, 0.7]);
    });

    test('converts percentages to fractions', () {
      expect(JsonUtils.bbox([10, 20, 90, 70]), [0.1, 0.2, 0.9, 0.7]);
    });

    test('orders swapped corners', () {
      expect(JsonUtils.bbox([0.9, 0.7, 0.1, 0.2]), [0.1, 0.2, 0.9, 0.7]);
    });

    test('clamps values outside the page', () {
      final b = JsonUtils.bbox([-0.2, 0.2, 1.4, 0.7])!;
      expect(b, [0.0, 0.2, 1.0, 0.7]);
    });

    test('rejects a box too small to be a figure', () {
      expect(JsonUtils.bbox([0.5, 0.5, 0.51, 0.51]), isNull);
    });
  });

  group('extraction', () {
    test('batches big books', () {
      expect(TextbookExtractor.batchesFor(0), isEmpty);
      expect(TextbookExtractor.batchesFor(10), [
        [1, 10]
      ]);
      expect(TextbookExtractor.batchesFor(25), [
        [1, 12],
        [13, 24],
        [25, 25]
      ]);
      final big = TextbookExtractor.batchesFor(100);
      expect(big.first, [1, 40]);
      expect(big.last, [81, 100]);
    });

    test('merges pages from every batch with their figures', () async {
      final fake = FakeAi(jsonEncode({
        'title': 'Our Science',
        'subject': 'science',
        'pages': [
          {
            'page': 1,
            'text': 'Plants make food.',
            'figures': [
              {'caption': 'Leaf', 'bbox': [0.2, 0.3, 0.8, 0.6]}
            ]
          }
        ]
      }));
      final res = await TextbookExtractor.extract(
        pdfBytes: fakePdf,
        filename: 'science.pdf',
        pageCount: 1,
        cfg: cfgFor(AiProvider.gemini),
        client: fake,
      );
      expect(res.title, 'Our Science');
      expect(res.subject, 'science');
      expect(res.pages.single.text, 'Plants make food.');
      expect(res.pages.single.figures.single.bbox, [0.2, 0.3, 0.8, 0.6]);
      expect(res.allFigures.length, 1);
      expect(fake.seen.single.bodyJson, contains('inline_data'));
    });

    test('refuses to run without a key', () async {
      expect(
        () => TextbookExtractor.extract(
          pdfBytes: fakePdf,
          filename: 'x.pdf',
          pageCount: 3,
          cfg: cfgFor(AiProvider.gemini, key: ''),
          client: FakeAi('{}'),
        ),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('script designer', () {
    final pages = [
      const ExtractedPage(1, 'Photosynthesis is how plants make food.', [
        ExtractedFigure(1, 'Leaf cross section',
            where: 'middle', bbox: [0.1, 0.2, 0.9, 0.6])
      ]),
    ];

    test('maps AI scenes into playable scenes and crops figures', () async {
      final fake = FakeAi(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'Photosynthesis', 'narration': 'Today we learn how plants make their own food, step by step.'},
          {'kind': 'board', 'heading': 'Three things needed', 'boardText': 'Sunlight\nWater\nAir', 'narration': 'Plants need sunlight, water and air to prepare food.'},
          {'kind': 'figure', 'heading': 'The leaf', 'page': 1, 'bbox': [0.1, 0.2, 0.9, 0.6], 'caption': 'Leaf cross section', 'narration': 'Look at this leaf: the green part catches sunlight.'},
          {'kind': 'quick', 'heading': 'Quick check', 'question': 'What do plants need?', 'options': ['Sunlight', 'Diesel', 'Plastic'], 'answer': 'Sunlight', 'narration': 'Try this quick question before we continue the lesson.'},
          {'kind': 'summary', 'heading': 'What we learnt', 'boardText': 'Plants make food\nSunlight + water + air', 'narration': 'We finished photosynthesis. Revise these three lines tonight.'},
        ]
      }));
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(AiProvider.openai),
        title: 'Science',
        subject: 'science',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: 'Explain simply',
        client: fake,
        crop: (page, bbox, where) async =>
            '/tmp/f_${page}_${bbox == null ? where : bbox.first}.png',
      );
      expect(scenes, isNotNull);
      expect(scenes!.length, 5);
      expect(scenes.first.kind, 'title');
      final figure = scenes.firstWhere((s) => s.kind == 'figure');
      expect(figure.imagePath, '/tmp/f_1_0.1.png');
      expect(figure.zone, Rect.fromLTRB(0.1, 0.2, 0.9, 0.6));
      final quick = scenes.firstWhere((s) => s.kind == 'quick');
      expect(quick.options.length, 3);
      expect(quick.answer, 'Sunlight');
      // The figure catalogue must reach the model.
      expect(fake.seen.single.bodyJson, contains('Leaf cross section'));
    });

    test('drops scenes whose figure could not be cropped', () async {
      final fake = FakeAi(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'T', 'narration': 'A lesson that starts with a single short sentence.'},
          {'kind': 'figure', 'heading': 'F', 'page': 1, 'bbox': [0.1, 0.2, 0.9, 0.6], 'narration': 'This figure could not be cut out of the PDF.'},
          {'kind': 'board', 'heading': 'B', 'boardText': 'one\ntwo', 'narration': 'The board still teaches the idea without any picture.'},
          {'kind': 'daily', 'heading': 'D', 'narration': 'In daily life, leaves on every plant around us do this work.'},
          {'kind': 'summary', 'heading': 'S', 'narration': 'We reached the end of this very short test lesson.'},
        ]
      }));
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(AiProvider.openai),
        title: 'T',
        subject: 'general',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: '',
        client: fake,
        crop: (p, b, w) async => null,
      );
      expect(scenes, isNotNull);
      expect(scenes!.any((s) => s.kind == 'figure'), isFalse);
    });

    test('gives up (null) when the AI sends too little', () async {
      final fake = FakeAi(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'T', 'narration': 'Only one scene came back from the model.'},
        ]
      }));
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(AiProvider.openai),
        title: 'T',
        subject: 'general',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: '',
        client: fake,
      );
      expect(scenes, isNull);
    });
  });

  group('scene storage', () {
    test('a scene survives a json round-trip', () {
      final s = LessonScene('figure', 'The leaf', 'Look at the leaf.',
          labels: const ['Leaf'],
          page: 3,
          zone: const Rect.fromLTRB(0.1, 0.2, 0.9, 0.6),
          imagePath: '/tmp/f.png');
      final back = LessonScene.fromJson(s.toJson())!;
      expect(back.kind, 'figure');
      expect(back.page, 3);
      expect(back.zone, const Rect.fromLTRB(0.1, 0.2, 0.9, 0.6));
      expect(back.imagePath, '/tmp/f.png');
      expect(back.labels, ['Leaf']);
    });
  });
}
