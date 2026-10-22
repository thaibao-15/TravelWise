
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:mobile/main.dart';
import 'package:mobile/shared/widgets/bottom_nav_bar.dart';

void main() {
  group('Bottom navigation bar tests', () {
    testWidgets(
      'Displays all tabs and handles Profile tap',
      (WidgetTester tester) async {
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

        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Explore'), findsOneWidget);
        expect(find.text('Trips'), findsOneWidget);
        expect(find.text('Profile'), findsOneWidget);
        expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

        await tester.tap(find.text('Profile'));
        await tester.pump();

        expect(tappedIndex, equals(4));
      },
    );
  });

  group('TravelWise app tests', () {
    testWidgets(
      'App starts and displays the login screen',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final originalOnError = FlutterError.onError;

        FlutterError.onError = (FlutterErrorDetails details) {
          if (details.exception is NetworkImageLoadException) {
            return;
          }

          originalOnError?.call(details);
        };

        addTearDown(() {
          FlutterError.onError = originalOnError;
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MyApp(),
          ),
        );

        await tester.pump();

        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );
  });
}
