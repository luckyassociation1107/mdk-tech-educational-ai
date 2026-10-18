import 'package:flutter_test/flutter_test.dart';
import 'package:textbook_video_classroom/main.dart';

void main() {
  testWidgets('App boots to splash', (tester) async {
    await tester.pumpWidget(const TextbookClassroomApp());
    expect(find.text('AI Textbook Classroom'), findsOneWidget);
  });
}
