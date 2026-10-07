import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/voice_assistant_provider.dart';

/// Horizontal scrollable suggestion chips with location emoji labels.
class LocationSuggestions extends ConsumerWidget {
  const LocationSuggestions({super.key});

  static const List<_Chip> _chips = [
    _Chip(emoji: '☕', label: 'Cà phê hoàng hôn',
        transcript: 'Gợi ý cho mình quán cà phê view biển đẹp gần Mỹ Khê để ngắm hoàng hôn chiều nay nhé?'),
    _Chip(emoji: '🐉', label: 'Cầu Rồng phun lửa',
        transcript: 'Cầu Rồng phun lửa mấy giờ? Mình muốn xem tối nay!'),
    _Chip(emoji: '🍜', label: 'Mì Quảng ếch ngon',
        transcript: 'Tìm quán mì Quảng ếch ngon, không gian thoáng gần trung tâm Đà Nẵng'),
    _Chip(emoji: '🏖️', label: 'Biển Mỹ Khê',
        transcript: 'Hôm nay biển Mỹ Khê có đông người không? Sóng thế nào?'),
    _Chip(emoji: '🌅', label: 'Ngắm bình minh',
        transcript: 'Địa điểm ngắm bình minh đẹp nhất ở Đà Nẵng là đâu?'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(voiceAssistantProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Gợi ý theo vị trí của bạn',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Đà Nẵng Live',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg),
            itemCount: _chips.length,
            itemBuilder: (context, index) {
              final chip = _chips[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SuggestionChip(
                  chip: chip,
                  onTap: () =>
                      notifier.setTranscript(chip.transcript),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Chip {
  final String emoji;
  final String label;
  final String transcript;
  const _Chip(
      {required this.emoji,
      required this.label,
      required this.transcript});
}

class _SuggestionChip extends StatefulWidget {
  final _Chip chip;
  final VoidCallback onTap;

  const _SuggestionChip({required this.chip, required this.onTap});

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleCtrl.forward(),
      onTapUp: (_) {
        _scaleCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleCtrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.chip.emoji,
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Text(
                widget.chip.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
