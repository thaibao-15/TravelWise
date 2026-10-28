import 'package:flutter/material.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Legacy explore header bar now standardized with CustomAppBar.
class HeaderBar extends StatelessWidget {
  const HeaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomAppBar();
  }
}
