import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'features/home/screens/home_screen.dart';
import 'features/explore/screens/explore_screen.dart';
import 'features/assistant/presentation/screens/travel_assistant_screen.dart';
import 'features/trips/screens/trips_screen.dart';
import 'features/profile/presentation/screens/profile_screen.dart';
import 'shared/widgets/bottom_nav_bar.dart';
import 'shared/widgets/floating_ai_bar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isNavBarVisible = true;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ExploreScreen(),
    const TravelAssistantScreen(),
    const TripsScreen(),
    const ProfileScreen(),
  ];

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (_currentIndex == 2) {
      if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
      return false;
    }

    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 50) {
      if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
      return false;
    }
    if (metrics.pixels <= 15) {
      if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
      return false;
    }
    if (metrics.pixels >= metrics.maxScrollExtent - 20) {
      if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final double delta = notification.scrollDelta ?? 0.0;
      if (delta > 2.5) {
        if (_isNavBarVisible) setState(() => _isNavBarVisible = false);
      } else if (delta < -2.5) {
        if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
      }
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse) {
        if (_isNavBarVisible) setState(() => _isNavBarVisible = false);
      } else if (notification.direction == ScrollDirection.forward) {
        if (!_isNavBarVisible) setState(() => _isNavBarVisible = true);
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            if (_currentIndex != 2)
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FloatingAiBar(),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        offset: _isNavBarVisible ? Offset.zero : const Offset(0, 1.5),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          opacity: _isNavBarVisible ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !_isNavBarVisible,
            child: CustomBottomNavBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                  _isNavBarVisible = true;
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}
