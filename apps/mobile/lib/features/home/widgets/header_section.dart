import 'package:flutter/material.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Legacy header section now standardized with CustomAppBar.
class HeaderSection extends StatelessWidget {
  const HeaderSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const CustomAppBar();
  }
}
