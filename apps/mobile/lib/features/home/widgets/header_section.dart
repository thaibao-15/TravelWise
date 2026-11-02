import 'package:flutter/material.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Legacy header section now standardized with CustomAppBar.
class HeaderSection extends StatelessWidget {
  const HeaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomAppBar();
  }
}
