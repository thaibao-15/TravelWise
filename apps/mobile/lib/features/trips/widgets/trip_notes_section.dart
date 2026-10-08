import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';

class TripNotesSection extends StatelessWidget {
  const TripNotesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text('Lưu ý cho chuyến đi', style: AppTextStyles.h2),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildNoteItem('Mang theo kem chống nắng, mũ râm.'),
              _buildNoteItem('Nên đặt bàn trước vào cuối tuần.'),
              _buildNoteItem('Mang giày thể thao thoải mái để đi bộ.'),
              _buildNoteItem('Kiểm tra thời tiết trước khi ra ngoài.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoteItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('â€¢ ', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: AppTextStyles.bodyMedium.copyWith(color: const Color(0xFF92400E)))),
        ],
      ),
    );
  }
}
