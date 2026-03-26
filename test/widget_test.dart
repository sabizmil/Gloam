import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gloam/app/app.dart';

void main() {
  testWidgets('GloamApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: GloamApp()),
    );
    // Pump a few frames to allow async init to settle
    await tester.pump(const Duration(milliseconds: 100));
    // The app should render — find at least one text widget
    expect(find.byType(GloamApp), findsOneWidget);
  });
}
