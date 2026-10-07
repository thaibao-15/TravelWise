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
        Text('LÆ°u Ã½ cho chuyáº¿n Ä‘i', style: AppTextStyles.h2),
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
              _buildNoteItem('Mang theo kem chá»‘ng náº¯ng, mÅ© rÃ¢m.'),
              _buildNoteItem('NÃªn Ä‘áº·t bÃ n trÆ°á»›c vÃ o cuá»‘i tuáº§n.'),
              _buildNoteItem('Mang giÃ y thá»ƒ thao thoáº£i mÃ¡i Ä‘á»ƒ Ä‘i bá»™.'),
              _buildNoteItem('Kiá»ƒm tra thá»i tiáº¿t trÆ°á»›c khi ra ngoÃ i.'),
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
