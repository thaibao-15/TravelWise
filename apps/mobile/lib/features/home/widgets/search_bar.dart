import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'dart:async';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';

class SearchBar extends StatelessWidget {
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFocus;
  final VoidCallback? onBack;
  final bool showBackButton;
  final String hintText;

  const SearchBar({
    super.key,
    this.onChanged,
    this.onFocus,
    this.onBack,
    this.showBackButton = false,
    this.hintText = 'Bạn muốn đi đâu hôm nay?',
  });

  @override
  Widget build(BuildContext context) {
    return _SearchField(
      onChanged: onChanged,
      onFocus: onFocus,
      onBack: onBack,
      showBackButton: showBackButton,
      hintText: hintText,
    );
  }
}

class _SearchField extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFocus;
  final VoidCallback? onBack;
  final bool showBackButton;
  final String hintText;

  const _SearchField({
    this.onChanged,
    this.onFocus,
    this.onBack,
    this.showBackButton = false,
    required this.hintText,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      widget.onChanged?.call(value.trim());
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _controller,
          onChanged: _handleChanged,
          onTap: widget.onFocus,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            prefixIcon: widget.showBackButton
                ? IconButton(
                    tooltip: 'Trở về',
                    icon: const Icon(Icons.arrow_back),
                    color: AppColors.textSecondary,
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged?.call('');
                      FocusScope.of(context).unfocus();
                      widget.onBack?.call();
                      setState(() {});
                    },
                  )
                : const Icon(
                    LucideIcons.search,
                    color: AppColors.textSecondary,
                  ),
            suffixIcon: _controller.text.isEmpty
                ? Container(
                    margin: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      LucideIcons.slidersHorizontal,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  )
                : IconButton(
                    tooltip: 'Xóa tìm kiếm',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged?.call('');
                      setState(() {});
                    },
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }
}
