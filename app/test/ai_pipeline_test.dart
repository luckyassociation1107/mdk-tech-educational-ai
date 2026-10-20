import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:textbook_video_classroom/ai/ai_config.dart';
import 'package:textbook_video_classroom/ai/ai_exception.dart';
import 'package:textbook_video_classroom/ai/ai_service.dart';
import 'package:textbook_video_classroom/ai/json_utils.dart';
import 'package:textbook_video_classroom/ai/script_designer.dart';
import 'package:textbook_video_classroom/ai/web_ai_engine.dart';
import 'package:textbook_video_classroom/ai/textbook_extractor.dart';
import 'package:textbook_video_classroom/lesson_content.dart';

/// Stands in for the free website: the pipeline above [AiService] is pure, so
/// it can be tested end to end without a WebView, a network or a key.
class FakeFree {
  FakeFree(this.reply);
  final String reply;
  final List<String> prompts = [];
  final List<Uint8List?> pdfs = [];

  void install() => AiService.debugTransport = (
        String prompt,
        Uint8List? pdf,
        String name,
      ) async {
        prompts.add(prompt);
        pdfs.add(pdf);
        return reply;
      };

  String get lastPrompt => prompts.isEmpty ? '' : prompts.last;
}

AiConfig cfgFor({String? script}) => AiConfig(scriptPrompt: script);

final Uint8List fakePdf = Uint8List.fromList(utf8.encode('%PDF-1.4 fake'));

void main() {
  tearDown(() => AiService.debugTransport = null);

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
      final fake = FakeFree(jsonEncode({
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
      fake.install();
      final res = await TextbookExtractor.extract(
        pdfBytes: fakePdf,
        filename: 'science.pdf',
        pageCount: 1,
        cfg: cfgFor(),
      );
      expect(res.title, 'Our Science');
      expect(res.subject, 'science');
      expect(res.pages.single.text, 'Plants make food.');
      expect(res.pages.single.figures.single.bbox, [0.2, 0.3, 0.8, 0.6]);
      expect(res.allFigures.length, 1);
      expect(fake.pdfs.single, isNotNull);
      expect(fake.lastPrompt, contains('Pages to return: 1 to 1 of 1'));
    });

    test('a reply that is not JSON is reported as a readable error', () async {
      FakeFree('I could not read that book, sorry.').install();
      expect(
        () => TextbookExtractor.extract(
          pdfBytes: fakePdf,
          filename: 'x.pdf',
          pageCount: 3,
          cfg: cfgFor(),
        ),
        throwsA(predicate((e) =>
            e is AiException && e.message.contains('not JSON'))),
      );
    });

    test('reads a big book in batches and asks for every range', () async {
      final fake = FakeFree(jsonEncode({
        'title': 'Big',
        'pages': [
          {'page': 1, 'text': 'first', 'figures': <dynamic>[]}
        ]
      }));
      fake.install();
      await TextbookExtractor.extract(
        pdfBytes: fakePdf,
        filename: 'big.pdf',
        pageCount: 25,
        cfg: cfgFor(),
      );
      expect(fake.prompts.length, 3);
      expect(fake.lastPrompt, contains('Pages to return: 25 to 25 of 25'));
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
      final fake = FakeFree(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'Photosynthesis', 'narration': 'Today we learn how plants make their own food, step by step.'},
          {'kind': 'board', 'heading': 'Three things needed', 'boardText': 'Sunlight\nWater\nAir', 'narration': 'Plants need sunlight, water and air to prepare food.'},
          {'kind': 'figure', 'heading': 'The leaf', 'page': 1, 'bbox': [0.1, 0.2, 0.9, 0.6], 'caption': 'Leaf cross section', 'narration': 'Look at this leaf: the green part catches sunlight.'},
          {'kind': 'quick', 'heading': 'Quick check', 'question': 'What do plants need?', 'options': ['Sunlight', 'Diesel', 'Plastic'], 'answer': 'Sunlight', 'narration': 'Try this quick question before we continue the lesson.'},
          {'kind': 'summary', 'heading': 'What we learnt', 'boardText': 'Plants make food\nSunlight + water + air', 'narration': 'We finished photosynthesis. Revise these three lines tonight.'},
        ]
      }));
      fake.install();
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(),
        title: 'Science',
        subject: 'science',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: 'Explain simply',
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
      expect(fake.lastPrompt, contains('Leaf cross section'));
    });

    test('takes a board given as a list of lines, as free models do', () async {
      final fake = FakeFree(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'Photosynthesis', 'narration': 'Today we learn how plants make their own food, step by step.'},
          {'kind': 'board', 'heading': 'What is it?', 'boardText': ['Plants make food.', 'They need sunlight.', 'Chlorophyll helps.'], 'narration': 'Photosynthesis is how a plant makes its own food from light.'},
          {'kind': 'daily', 'heading': 'In daily life', 'narration': 'Every tree outside your window is doing this right now, all day long.'},
          {'kind': 'summary', 'heading': 'What we learnt', 'boardText': ['Plants make food.', 'Sunlight + water + air'], 'narration': 'We finished photosynthesis. Revise these lines tonight.'},
        ]
      }));
      fake.install();
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(),
        title: 'Science',
        subject: 'science',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: '',
      );
      expect(scenes, isNotNull);
      final board = scenes!.firstWhere((s) => s.kind == 'board');
      expect(board.boardText, 'Plants make food.\nThey need sunlight.\nChlorophyll helps.');
      expect(board.boardText, isNot(contains('[')));
    });

    test('lettered options lose their letter and the right one stays right', () async {
      final fake = FakeFree(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'Light', 'narration': 'Today we learn how plants use light to make their own food.'},
          {'kind': 'quick', 'heading': 'Quick check', 'question': 'What do plants need?', 'options': ['a) Sunlight', 'b) Moonlight', 'c) Starlight'], 'answer': 'a', 'narration': 'Try this quick question before we continue the lesson.'},
          {'kind': 'board', 'heading': 'Light', 'boardText': 'Plants need light', 'narration': 'Light is the fuel. Without it the plant cannot make its food.'},
          {'kind': 'summary', 'heading': 'What we learnt', 'boardText': 'Plants need light', 'narration': 'We finished the lesson. Revise the board once before the test.'},
        ]
      }));
      fake.install();
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(),
        title: 'Science',
        subject: 'science',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: '',
      );
      final quick = scenes!.firstWhere((s) => s.kind == 'quick');
      expect(quick.options, ['Sunlight', 'Moonlight', 'Starlight']);
      expect(quick.answer, 'Sunlight');
    });

    test('drops scenes whose figure could not be cropped', () async {
      final fake = FakeFree(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'T', 'narration': 'A lesson that starts with a single short sentence.'},
          {'kind': 'figure', 'heading': 'F', 'page': 1, 'bbox': [0.1, 0.2, 0.9, 0.6], 'narration': 'This figure could not be cut out of the PDF.'},
          {'kind': 'board', 'heading': 'B', 'boardText': 'one\ntwo', 'narration': 'The board still teaches the idea without any picture.'},
          {'kind': 'daily', 'heading': 'D', 'narration': 'In daily life, leaves on every plant around us do this work.'},
          {'kind': 'summary', 'heading': 'S', 'narration': 'We reached the end of this very short test lesson.'},
        ]
      }));
      fake.install();
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(),
        title: 'T',
        subject: 'general',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: '',
        crop: (p, b, w) async => null,
      );
      expect(scenes, isNotNull);
      expect(scenes!.any((s) => s.kind == 'figure'), isFalse);
    });

    test('gives up (null) when the AI sends too little', () async {
      final fake = FakeFree(jsonEncode({
        'scenes': [
          {'kind': 'title', 'heading': 'T', 'narration': 'Only one scene came back from the model.'},
        ]
      }));
      fake.install();
      final scenes = await ScriptDesigner.design(
        cfg: cfgFor(),
        title: 'T',
        subject: 'general',
        language: 'en',
        partNumber: 1,
        pages: [1],
        indexPages: pages,
        teacherNote: '',
      );
      expect(scenes, isNull);
    });
  });

  group('free AI site errors', () {
    test('a scan says so in plain words', () {
      final m = WebAiEngine.friendlySiteError(
          'Errors Your file appears to be a scan, image-based, or has no text. '
          'Please try a different file. OK Close');
      expect(m, contains('photos of pages'));
      expect(m, contains('real text'));
      expect(m.toLowerCase(), isNot(contains('errors your file')));
    });

    test('a huge PDF asks for smaller chapters', () {
      final m = WebAiEngine.friendlySiteError(
          'Errors File is too large. OK Close');
      expect(m, contains('too large'));
      expect(m, contains('smaller'));
    });

    test('an unknown message keeps the site\'s own words', () {
      final m = WebAiEngine.friendlySiteError(
          'Errors Something odd happened. OK Close');
      expect(m, contains('Something odd happened.'));
      expect(m.startsWith('Errors'), isFalse);
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
