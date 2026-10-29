import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';

class TripFloatingActions extends StatelessWidget {
  final VoidCallback? onOpenMap;
  final VoidCallback? onVoiceEdit;
  final VoidCallback? onAiEdit;
  final bool isListening;
  final bool isRevising;
  final bool isSpeaking;

  const TripFloatingActions({
    super.key,
    this.onOpenMap,
    this.onVoiceEdit,
    this.onAiEdit,
    this.isListening = false,
    this.isRevising = false,
    this.isSpeaking = false,
  });

  @override
  Widget build(BuildContext context) {
    final List<Color> micGradient = isListening
        ? const [Color(0xFFEF4444), Color(0xFFF97316)]
        : isSpeaking
            ? const [Color(0xFFF59E0B), Color(0xFFEF4444)]
            : const [Color(0xFF0EA5E9), AppColors.primary];

    final String micTooltip = isListening
        ? 'Chạm để gửi yêu cầu giọng nói'
        : isRevising
            ? 'Linh AI đang cập nhật lịch trình...'
            : isSpeaking
                ? 'Dừng giọng đọc AI'
                : 'Nói trực tiếp để chỉnh sửa lịch trình';

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: ElevatedButton.icon(
              onPressed: onOpenMap,
              icon: const Icon(LucideIcons.map, size: 19),
              label: const Text(
                'Xem lộ trình bản đồ',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                elevation: 4,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),
          ),
          if (onVoiceEdit != null) ...[
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: micGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isListening ? const Color(0xFFEF4444) : AppColors.primary)
                        .withValues(alpha: isListening ? 0.5 : 0.35),
                    blurRadius: isListening ? 16 : 12,
                    spreadRadius: isListening ? 2 : 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: isRevising ? null : onVoiceEdit,
                tooltip: micTooltip,
                icon: isRevising
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        isListening
                            ? Icons.graphic_eq_rounded
                            : isSpeaking
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.38),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              onPressed: isRevising ? null : onAiEdit,
              icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
              tooltip: 'Nhập hoặc chọn gợi ý chỉnh sửa bằng AI',
            ),
          ),
        ],
      ),
    );
  }
}
