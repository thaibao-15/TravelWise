import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/constants/text_styles.dart';
import '../providers/auth_notifier.dart';
import '../providers/auth_state.dart';

/// Reusable text field widget matching the app's design system.
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final TextInputType keyboardType;

  const AuthTextField({
    Key? key,
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.obscureText = false,
    this.onToggleObscure,
    this.keyboardType = TextInputType.text,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: AppTextStyles.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: AppColors.textSecondary,
            size: 20,
          ),
          suffixIcon: onToggleObscure != null
              ? IconButton(
                  icon: Icon(
                    obscureText ? LucideIcons.eye : LucideIcons.eyeOff,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}

/// Primary gradient action button used across auth screens.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const AuthPrimaryButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: AppTextStyles.label.copyWith(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}
