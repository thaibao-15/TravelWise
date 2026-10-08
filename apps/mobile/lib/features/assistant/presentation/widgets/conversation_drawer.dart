import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/voice_assistant_provider.dart';
import 'chat_message_bubble.dart';

/// Collapsible conversation drawer with animated expand/collapse.
class ConversationDrawer extends ConsumerWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);
    final isExpanded = state.isConversationExpanded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header / drag handle ─────────────────────────────────────────
          GestureDetector(
            onTap: notifier.toggleConversation,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // Drag handle pill
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.chat_bubble_outline,
                            color: AppColors.primary, size: 16),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Hội thoại trực tiếp',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Message count badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${state.messages.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 250),
                        turns: isExpanded ? 0.5 : 0,
                        child: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.textSecondary, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Expandable message list ──────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            child: isExpanded
                ? ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) => ChatMessageBubble(
                        message: state.messages[index],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
