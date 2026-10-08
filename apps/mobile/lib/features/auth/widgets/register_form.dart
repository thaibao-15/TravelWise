import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../../home/screens/home_screen.dart';

class RegisterForm extends StatefulWidget {
  const RegisterForm({Key? key}) : super(key: key);

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          // Name Field
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Họ và tên',
                hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                prefixIcon: const Icon(LucideIcons.user, color: AppColors.textSecondary, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Email Field
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                prefixIcon: const Icon(LucideIcons.mail, color: AppColors.textSecondary, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Password Field
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: 'Mật khẩu',
                hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                prefixIcon: const Icon(LucideIcons.lock, color: AppColors.textSecondary, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // Register Button
          Container(
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
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: Text(
                'Đăng ký',
                style: AppTextStyles.label.copyWith(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
