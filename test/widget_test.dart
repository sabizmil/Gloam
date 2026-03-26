import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gloam/app/app.dart';

void main() {
  testWidgets('GloamApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: GloamApp()),
    );
    expect(find.text('gloam'), findsOneWidget);
  });
}
