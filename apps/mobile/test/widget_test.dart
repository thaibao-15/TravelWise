import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/shared/widgets/bottom_nav_bar.dart';

void main() {
  testWidgets('Bottom navigation bar smoke test', (WidgetTester tester) async {
    int tappedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CustomBottomNavBar(
            currentIndex: 0,
            onTap: (index) {
              tappedIndex = index;
            },
          ),
        ),
      ),
    );

    // Verify all tabs exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

    // Tap Profile tab (index 4)
    await tester.tap(find.text('Profile'));
    await tester.pump();

    expect(tappedIndex, equals(4));
  });
}
