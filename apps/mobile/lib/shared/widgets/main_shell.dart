    import 'package:flutter/material.dart';

import '../widgets/bottom_nav_bar.dart';

import '../../features/home/screens/home_screen.dart';
import '../../features/explore/screens/explore_screen.dart';
import '../../features/assistant/presentation/screens/travel_assistant_screen.dart';
import '../../features/trips/screens/trips_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Global key used to access the MainShell state from external routes.
  static final GlobalKey<_MainShellState> shellKey =
      GlobalKey<_MainShellState>();

  /// Navigate back to MainShell and switch to the given tab index.
  /// Call this from pushed routes (e.g. MapScreen) to return to a tab.
  static void switchToTab(BuildContext context, int index) {
    // Pop all routes until we reach the MainShell route
    Navigator.of(context).popUntil((route) => route.isFirst);
    // Switch to the requested tab
    shellKey.currentState?._setTab(index);
  }

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  late final List<Widget> _pages = [
    const HomeScreen(),
    const ExploreScreen(),
    const TravelAssistantScreen(),

    const TripsScreen(),
    const ProfilePlaceholderScreen(),
  ];

  void _setTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onBottomNavTap(int index) {
    setState(() {
      _currentIndex = index;
    });
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