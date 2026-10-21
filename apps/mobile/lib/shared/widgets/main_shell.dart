import 'package:flutter/material.dart';

import '../widgets/bottom_nav_bar.dart';

import '../../features/home/screens/home_screen.dart';
import '../../features/explore/screens/explore_screen.dart';
import '../../features/assistant/presentation/screens/travel_assistant_screen.dart';
import '../../features/trips/screens/trips_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.pages, this.initialIndex = 0});

  /// Optional tab pages override (used by widget tests).
  final List<Widget>? pages;

  /// Initial tab index when MainShell is first built.
  final int initialIndex;

  /// Global key used to access the MainShell state from external routes.
  static final GlobalKey<MainShellState> shellKey =
      GlobalKey<MainShellState>();

  /// Track the active MainShellState even if MainShell was instantiated without shellKey.
  static MainShellState? _activeState;

  static MainShellState? get _effectiveState =>
      shellKey.currentState ?? _activeState;

  /// Currently selected tab, or -1 when the shell is not mounted.
  static int get currentTab => _effectiveState?._currentIndex ?? -1;

  static bool _isNavigating = false;

  /// Navigate back to MainShell and switch to the given tab index.
  /// Call this from pushed routes (e.g. MapScreen, TripDetailScreen) to return to a tab.
  static void switchToTab(BuildContext context, int index) {
    if (_isNavigating) return;
    if (!context.mounted) return;

    _isNavigating = true;

    try {
      final shellState = _effectiveState;
      final navigator = (shellState != null && shellState.mounted)
          ? Navigator.of(shellState.context)
          : Navigator.of(context);
      final mainShellRoute = shellState != null && shellState.mounted
          ? ModalRoute.of(shellState.context)
          : null;

      if (shellState != null && shellState.mounted) {
        if (navigator.canPop()) {
          navigator.popUntil((route) {
            if (mainShellRoute != null && route == mainShellRoute) return true;
            return route.isFirst;
          });
        }
        shellState.setTab(index);
      } else {
        // Fallback if MainShell was not in the route stack (e.g. direct pushReplacement)
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => MainShell(
              key: shellKey,
              initialIndex: index,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Navigation error in switchToTab: $e');
    } finally {
      _isNavigating = false;
    }
  }

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  late int _currentIndex;
  int get currentIndex => _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    MainShell._activeState = this;
  }

  @override
  void dispose() {
    if (MainShell._activeState == this) {
      MainShell._activeState = null;
    }
    super.dispose();
  }

  late final List<Widget> _pages = widget.pages ??
      [
        const HomeScreen(),
        const ExploreScreen(),
        const TravelAssistantScreen(),
        const TripsScreen(),
        const ProfilePlaceholderScreen(),
      ];

  void setTab(int index) {
    if (!mounted) return;
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
    });
  }

  void _onBottomNavTap(int index) {
    setTab(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onBottomNavTap,
      ),
    );
  }
}

class TripsPlaceholderScreen extends StatelessWidget {
  const TripsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Trips',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class ProfilePlaceholderScreen extends StatelessWidget {
  const ProfilePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Profile',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
