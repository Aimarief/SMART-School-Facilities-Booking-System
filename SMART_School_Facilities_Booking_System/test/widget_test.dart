import 'package:flutter_test/flutter_test.dart';
import 'package:smart_school_facilities_booking_system/main.dart';

void main() {
  testWidgets('App starts up without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.byType(MyApp), findsOneWidget);
  });
}
