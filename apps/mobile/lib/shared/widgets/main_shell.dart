import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/explore/screens/explore_screen.dart';
import '../../features/assistant/presentation/screens/travel_assistant_screen.dart';
import '../../features/trips/screens/trips_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Global key used to access the MainShell state from external routes.
  static final GlobalKey<MainShellState> shellKey = GlobalKey<MainShellState>();

  /// Fallback instance reference if MainShell wasn't given the shellKey.
  static MainShellState? instance;

  /// Navigate back to MainShell and switch to the given tab index.
  /// Call this from pushed routes (e.g. MapScreen) to return to a tab.
  static void switchToTab(BuildContext context, int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    (shellKey.currentState ?? instance)?.setTab(index);
  }

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  @override
  void initState() {
    super.initState();
    MainShell.instance = this;
  }

  @override
  void dispose() {
    if (MainShell.instance == this) {
      MainShell.instance = null;
    }
    super.dispose();
  }

  late final List<Widget> _pages = [
    const HomeScreen(),
    const ExploreScreen(),
    const TravelAssistantScreen(),
    const TripsScreen(),
    const ProfileScreen(),
  ];

  void setTab(int index) {
    if (index >= 0 && index < _pages.length) {
      if (_currentIndex != index) {
        setState(() {
          _currentIndex = index;
        });
      }
    }
  }

  void _onBottomNavTap(int index) {
    setTab(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onBottomNavTap,
      ),
    );
  }
}
