import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile/core/services/location_service.dart';
import 'package:mobile/features/map/presentation/providers/location_provider.dart';
import 'package:mobile/features/map/presentation/screens/map_screen.dart';
import 'package:mobile/shared/widgets/main_shell.dart';

/// Location service that never touches platform channels.
class _FakeLocationService extends LocationService {
  _FakeLocationService() : permission = LocationPermission.denied;

  final LocationPermission permission;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<LocationResult> getCurrentPosition() async =>
      const LocationResult.failure(errorMessage: 'fake');
}

class _TabPage extends StatelessWidget {
  const _TabPage(this.index);
  final int index;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Page $index'),
            ElevatedButton(
              key: Key('open-map-$index'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MapScreen()),
              ),
              child: const Text('Open map'),
            ),
          ],
        ),
      ),
    );
  }
}

void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

Future<void> _pumpShell(WidgetTester tester) async {
  _usePhoneSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(_FakeLocationService()),
      ],
      child: MaterialApp(
        home: MainShell(
          key: MainShell.shellKey,
          pages: List.generate(5, (i) => _TabPage(i)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _visiblePage(int i) => find.text('Page $i').hitTestable();
Finder get _mapTitle => find.text('Bản đồ khám phá');

Future<void> _tapShellTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).hitTestable().last);
  await tester.pumpAndSettle();
}

Future<void> _openMapFrom(WidgetTester tester, int tab) async {
  await tester.tap(find.byKey(Key('open-map-$tab')).hitTestable());
  await tester.pumpAndSettle();
  expect(_mapTitle, findsOneWidget);
}

void main() {
  testWidgets('Home → Map → Back → Home', (tester) async {
    await _pumpShell(tester);
    await _openMapFrom(tester, 0);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(_mapTitle, findsNothing);
    expect(_visiblePage(0), findsOneWidget);
    expect(MainShell.currentTab, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explore → Map → Back → Explore', (tester) async {
    await _pumpShell(tester);
    await _tapShellTab(tester, 'Explore');
    await _openMapFrom(tester, 1);
    // The originating tab stays highlighted on the map.
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(_mapTitle, findsNothing);
    expect(_visiblePage(1), findsOneWidget);
    expect(MainShell.currentTab, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home → Map → Trips via bottom nav', (tester) async {
    await _pumpShell(tester);
    await _openMapFrom(tester, 0);
    await tester.tap(find.text('Trips').hitTestable().last);
    await tester.pumpAndSettle();
    expect(_mapTitle, findsNothing);
    expect(_visiblePage(3), findsOneWidget);
    expect(MainShell.currentTab, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home → Map → Profile via bottom nav', (tester) async {
    await _pumpShell(tester);
    await _openMapFrom(tester, 0);
    await tester.tap(find.text('Profile').hitTestable().last);
    await tester.pumpAndSettle();
    expect(_mapTitle, findsNothing);
    expect(_visiblePage(4), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Map → Explore → Map again', (tester) async {
    await _pumpShell(tester);
    await _openMapFrom(tester, 0);
    await tester.tap(find.text('Explore').hitTestable().last);
    await tester.pumpAndSettle();
    expect(_visiblePage(1), findsOneWidget);
    await _openMapFrom(tester, 1);
    await tester.tap(find.text('Home').hitTestable().last);
    await tester.pumpAndSettle();
    expect(_visiblePage(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rapid repeated taps on map bottom nav do not crash',
      (tester) async {
    await _pumpShell(tester);
    await _openMapFrom(tester, 0);
    final tripsFinder = find.text('Trips');
    final profileFinder = find.text('Profile');
    if (tripsFinder.evaluate().isNotEmpty) {
      await tester.tap(tripsFinder.last, warnIfMissed: false);
    }
    // Further taps land while the map route is animating out.
    if (tripsFinder.evaluate().isNotEmpty) {
      await tester.tap(tripsFinder.last, warnIfMissed: false);
    }
    if (profileFinder.evaluate().isNotEmpty) {
      await tester.tap(profileFinder.last, warnIfMissed: false);
    }
    await tester.pump(const Duration(milliseconds: 50));
    if (profileFinder.evaluate().isNotEmpty) {
      await tester.tap(profileFinder.last, warnIfMissed: false);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_mapTitle, findsNothing);
    // Shell route must never be popped.
    expect(find.byType(MainShell), findsOneWidget);
  });

  testWidgets('Rapid double tap on map back arrow pops only the map',
      (tester) async {
    await _pumpShell(tester);
    await _tapShellTab(tester, 'Explore');
    await _openMapFrom(tester, 1);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.tap(find.byTooltip('Quay lại'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MainShell), findsOneWidget);
    expect(_visiblePage(1), findsOneWidget);
  });

  testWidgets('Android system back pops the map to the origin tab',
      (tester) async {
    await _pumpShell(tester);
    await _tapShellTab(tester, 'Explore');
    await _openMapFrom(tester, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_mapTitle, findsNothing);
    expect(_visiblePage(1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bottom nav tap while map is still loading', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('open-map-0')));
    // Only a couple of frames: push transition + post-frame GPS check pending.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Trips').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(MainShell), findsOneWidget);
  });

  testWidgets('Navigation after dismissing the GPS permission dialog',
      (tester) async {
    await _pumpShell(tester);
    await _openMapFrom(tester, 0);
    await tester.tap(find.byTooltip('Vị trí của tôi').first);
    await tester.pumpAndSettle();
    expect(find.text('Để sau'), findsOneWidget);
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(_mapTitle, findsOneWidget);
    await tester.tap(find.text('Trips').hitTestable().last);
    await tester.pumpAndSettle();
    expect(_visiblePage(3), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Map opened as the only route: back does not pop empty stack',
      (tester) async {
    _usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(_FakeLocationService()),
        ],
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_mapTitle, findsOneWidget);
  });
}