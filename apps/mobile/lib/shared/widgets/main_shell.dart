import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/bottom_nav_bar.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/explore/screens/explore_screen.dart';
import '../../features/assistant/presentation/screens/travel_assistant_screen.dart';
import '../../features/trips/screens/trips_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';

/// Provider lưu trữ tab index hiện tại của MainShell để các màn hình con nhận diện khi được kích hoạt.
final mainTabProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, this.pages, this.initialIndex = 0});

  /// Optional pages override for widget tests.
  final List<Widget>? pages;

  /// Initial selected tab.
  final int initialIndex;

  /// Global key for accessing the active shell.
  static final GlobalKey<MainShellState> shellKey =
      GlobalKey<MainShellState>();

  /// Fallback reference when the shell is mounted without shellKey.
  static MainShellState? _activeState;

  static MainShellState? get _effectiveState =>
      shellKey.currentState ?? _activeState;

  /// Currently selected tab, or -1 if the shell is not mounted.
  static int get currentTab => _effectiveState?._currentIndex ?? -1;

  static bool _isNavigating = false;

  /// Return to MainShell and select the requested tab.
  ///
  /// Use this from pushed screens such as MapScreen and TripDetailScreen.
  static void switchToTab(BuildContext context, int index) {
    if (_isNavigating || !context.mounted) return;

    final shellState = _effectiveState;
    final hasMountedShell =
        shellState != null && shellState.mounted;

    if (hasMountedShell && (index < 0 || index >= shellState._pages.length)) {
      debugPrint('Invalid tab index: $index');
      return;
    }

    _isNavigating = true;

    try {
      if (hasMountedShell) {
        final navigator = Navigator.of(shellState.context);
        final shellRoute = ModalRoute.of(shellState.context);

        if (navigator.canPop()) {
          navigator.popUntil((route) {
            if (shellRoute != null && route == shellRoute) {
              return true;
            }
            return route.isFirst;
          });
        }

        // Change tabs only after requesting the return navigation.
        shellState.setTab(index);
      } else {
        final navigator = Navigator.of(context);

        navigator.pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => MainShell(
              key: shellKey,
              initialIndex: index,
            ),
          ),
          (route) => false,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Navigation error in switchToTab: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isNavigating = false;
    }
  }

  @override
  ConsumerState<MainShell> createState() => MainShellState();
}

class MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;
  bool _isNavBarVisible = true;

  int get currentIndex => _currentIndex;

  late final List<Widget> _pages = widget.pages ??
      [
        const HomeScreen(),
        const ExploreScreen(),
        const TravelAssistantScreen(),
        const TripsScreen(),
        const ProfileScreen(),
      ];

  @override
  void initState() {
    super.initState();

    _currentIndex = _pages.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _pages.length - 1).toInt();

    MainShell._activeState = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(mainTabProvider.notifier).state = _currentIndex;
      }
    });
  }

  @override
  void dispose() {
    if (MainShell._activeState == this) {
      MainShell._activeState = null;
    }

    super.dispose();
  }

  /// Select a tab without pushing a new route.
  void setTab(int index) {
    if (!mounted || index < 0 || index >= _pages.length) {
      return;
    }

    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _currentIndex = index;
      _isNavBarVisible = true;
    });
    ref.read(mainTabProvider.notifier).state = index;
  }

  void _onBottomNavTap(int index) {
    setTab(index);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    // 1. Chỉ lắng nghe cuộn theo trục dọc (vertical). Bỏ qua hoàn toàn các cuộn ngang (horizontal carousels/chips)
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    // 2. Không ẩn khi đang ở tab Trợ lý AI (tab 2 - màn hình compact cố định)
    if (_currentIndex == 2) {
      if (!_isNavBarVisible) {
        setState(() => _isNavBarVisible = true);
      }
      return false;
    }

    final ScrollMetrics metrics = notification.metrics;

    // 3. Nếu trang có chiều dài cuộn quá ngắn (không đáng kể) -> luôn hiển thị
    if (metrics.maxScrollExtent <= 50) {
      if (!_isNavBarVisible) {
        setState(() => _isNavBarVisible = true);
      }
      return false;
    }

    // 4. Nếu đang ở gần đầu trang (offset <= 15) -> luôn luôn hiển thị
    if (metrics.pixels <= 15) {
      if (!_isNavBarVisible) {
        setState(() => _isNavBarVisible = true);
      }
      return false;
    }

    // 5. Nếu chạm tới gần cuối trang (chạm đáy) -> hiển thị lại thanh bar để người dùng điều hướng
    if (metrics.pixels >= metrics.maxScrollExtent - 20) {
      if (!_isNavBarVisible) {
        setState(() => _isNavBarVisible = true);
      }
      return false;
    }

    // 6. Xử lý cả Web chuột/trackpad lẫn Mobile cử chỉ vuốt
    // 6a. Chuột lăn / Trackpad (Web / Desktop) hoặc scroll update
    if (notification is ScrollUpdateNotification) {
      final double delta = notification.scrollDelta ?? 0.0;
      // Ngưỡng 2.5 để phân biệt hướng cuộn rõ ràng và tránh rung lắc
      if (delta > 2.5) {
        // Cuộn xuống (Scroll Down) -> Ẩn thanh bottom nav
        if (_isNavBarVisible) {
          setState(() => _isNavBarVisible = false);
        }
      } else if (delta < -2.5) {
        // Cuộn lên (Scroll Up) -> Hiện thanh bottom nav
        if (!_isNavBarVisible) {
          setState(() => _isNavBarVisible = true);
        }
      }
    }

    // 6b. Thao tác ngón tay kéo vuốt trên Mobile (UserScrollNotification)
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse) {
        // Vuốt lên kéo trang xuống -> Ẩn
        if (_isNavBarVisible) {
          setState(() => _isNavBarVisible = false);
        }
      } else if (notification.direction == ScrollDirection.forward) {
        // Vuốt xuống kéo trang lên -> Hiện
        if (!_isNavBarVisible) {
          setState(() => _isNavBarVisible = true);
        }
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _pages.isEmpty
          ? const Center(child: Text('No pages available'))
          : NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
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
              onTap: _onBottomNavTap,
            ),
          ),
        ),
      ),
    );
  }
}
