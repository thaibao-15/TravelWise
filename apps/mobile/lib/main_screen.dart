import 'package:flutter/material.dart';
import 'features/home/screens/home_screen.dart';
import 'features/explore/screens/explore_screen.dart';
import 'shared/widgets/bottom_nav_bar.dart';
import 'shared/widgets/floating_ai_bar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ExploreScreen(),
    const SizedBox(), // AI Placeholder
    const SizedBox(), // Trips
    const SizedBox(), // Profile
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FloatingAiBar(),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
