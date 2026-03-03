import 'package:flutter_test/flutter_test.dart';
import 'package:s_music/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SMusicApp());
    await tester.pump();

    expect(find.text('Trending'), findsOneWidget);
  });
}
