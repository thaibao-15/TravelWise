import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:mobile/features/home/screens/home_screen.dart';
import 'package:mobile/features/home/models/category_model.dart';
import 'package:mobile/features/home/models/place_model.dart';
import 'package:mobile/features/home/providers/home_provider.dart';
import 'package:mobile/features/explore/screens/explore_screen.dart';
import 'package:mobile/shared/widgets/custom_app_bar.dart';
import 'package:mobile/shared/widgets/main_shell.dart';

void main() {
  Widget testHome() {
    return ProviderScope(
      overrides: [
        homeCategoriesProvider.overrideWith((ref) async => <Category>[]),
        homePlacesProvider.overrideWith((ref, categoryId) async => <Place>[]),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  group('Unified Top Header (CustomAppBar) Tests', () {
    testWidgets(
      'CustomAppBar displays location, weather, bell, and profile avatar',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CustomAppBar())),
        );

        // Verify standardized location selector
        expect(find.text('Đà Nẵng, Việt Nam'), findsOneWidget);
        expect(find.byIcon(LucideIcons.mapPin), findsOneWidget);
        expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);

        // Verify weather status
        expect(find.text('28°C'), findsOneWidget);
        expect(find.byIcon(LucideIcons.sun), findsOneWidget);

        // Verify notification bell with unread badge
        expect(find.byIcon(LucideIcons.bell), findsOneWidget);

        // Verify profile avatar
        expect(find.byType(CircleAvatar), findsOneWidget);
      },
    );

    testWidgets('HomeScreen contains the unified CustomAppBar', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        testHome(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomAppBar), findsOneWidget);
      expect(find.text('Đà Nẵng, Việt Nam'), findsOneWidget);
      expect(find.byIcon(LucideIcons.bell), findsOneWidget);
    });

    testWidgets('ExploreScreen contains the unified CustomAppBar', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ExploreScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomAppBar), findsOneWidget);
      expect(find.text('Đà Nẵng, Việt Nam'), findsOneWidget);
      expect(find.byIcon(LucideIcons.bell), findsOneWidget);
    });

    testWidgets(
      'Tapping profile avatar in CustomAppBar switches to Profile tab',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: MainShell(
                key: MainShell.shellKey,
                initialIndex: 0,
                pages: [
                  testHome(),
                  const ExploreScreen(),
                  const Scaffold(body: Center(child: Text('Assistant'))),
                  const Scaffold(body: Center(child: Text('Trips'))),
                  const Scaffold(body: Center(child: Text('Profile Tab'))),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(MainShell.currentTab, equals(0));

        // Find the CircleAvatar in CustomAppBar and tap it
        final avatarFinder = find.descendant(
          of: find.byType(CustomAppBar),
          matching: find.byType(CircleAvatar),
        );
        expect(avatarFinder, findsOneWidget);

        await tester.tap(avatarFinder);
        await tester.pumpAndSettle();

        // Should have switched to tab 4 (Profile)
        expect(MainShell.currentTab, equals(4));
        expect(find.text('Profile Tab'), findsOneWidget);
      },
    );
  });

  group('RenderFlex Overflow Prevention Tests across screen sizes', () {
    final testSizes = [
      const Size(320, 600), // Very narrow phone
      const Size(360, 640), // Small Android
      const Size(375, 667), // iPhone SE
      const Size(390, 844), // iPhone 14
      const Size(412, 915), // Pixel 7
    ];

    for (final size in testSizes) {
      testWidgets(
        'HomeScreen renders without overflow at ${size.width}x${size.height}',
        (WidgetTester tester) async {
          tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);

          FlutterErrorDetails? errorCaught;
          final originalOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            if (details.toString().contains('overflowed')) {
              errorCaught = details;
            }
            originalOnError?.call(details);
          };

          await tester.pumpWidget(
            testHome(),
          );
          await tester.pumpAndSettle();

          FlutterError.onError = originalOnError;
          expect(
            errorCaught,
            isNull,
            reason:
                'RenderFlex overflow detected on HomeScreen at $size: ${errorCaught?.exception}',
          );
        },
      );

      testWidgets(
        'ExploreScreen renders without overflow at ${size.width}x${size.height}',
        (WidgetTester tester) async {
          tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);

          FlutterErrorDetails? errorCaught;
          final originalOnError = FlutterError.onError;
          FlutterError.onError = (details) {
            if (details.toString().contains('overflowed')) {
              errorCaught = details;
            }
            originalOnError?.call(details);
          };

          await tester.pumpWidget(
            const ProviderScope(child: MaterialApp(home: ExploreScreen())),
          );
          await tester.pumpAndSettle();

          FlutterError.onError = originalOnError;
          expect(
            errorCaught,
            isNull,
            reason:
                'RenderFlex overflow detected on ExploreScreen at $size: ${errorCaught?.exception}',
          );
        },
      );
    }
  });
}
