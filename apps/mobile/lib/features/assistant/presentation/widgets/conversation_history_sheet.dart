import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../auth/auth_di.dart';
import '../../services/conversation_api_service.dart';
import '../models/conversation_item.dart';
import '../providers/voice_assistant_provider.dart';

/// Bottom Sheet hiển thị danh sách các cuộc trò chuyện của User trong Voice Chat.
class ConversationHistorySheet extends ConsumerStatefulWidget {
  const ConversationHistorySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ConversationHistorySheet(),
    );
  }

  @override
  ConsumerState<ConversationHistorySheet> createState() =>
      _ConversationHistorySheetState();
}

class _ConversationHistorySheetState
    extends ConsumerState<ConversationHistorySheet> {
  late final ConversationApiService _apiService;
  List<ConversationItem> _conversations = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiService = ConversationApiService(ref.read(dioClientProvider));
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _apiService.fetchUserConversations();
      if (mounted) {
        setState(() {
          _conversations = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Không thể tải lịch sử cuộc trò chuyện';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteConversation(ConversationItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa cuộc trò chuyện?'),
        content: Text('Bạn có chắc muốn xóa "${item.title}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _apiService.deleteConversation(item.id);
      if (success && mounted) {
        setState(() {
          _conversations.removeWhere((c) => c.id == item.id);
        });

        // Nếu cuộc trò chuyện đang mở là cuộc trò chuyện bị xóa, clear active state
        final currentActiveId = ref.read(voiceAssistantProvider).conversationId;
        if (currentActiveId == item.id) {
          ref.read(voiceAssistantProvider.notifier).clearConversation();
        }
      }
    }
  }

  void _selectConversation(ConversationItem item) {
    ref.read(voiceAssistantProvider.notifier).loadConversation(item.id);
    Navigator.pop(context);
  }

  void _startNewConversation() {
    ref.read(voiceAssistantProvider.notifier).clearConversation();
    Navigator.pop(context);
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(
      voiceAssistantProvider.select((s) => s.conversationId),
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Handle Bar ───────────────────────────────────────────
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header Title & Actions ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lịch sử trò chuyện',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Xem lại các cuộc hội thoại cùng Linh AI',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Nút tạo đoạn chat mới
                ElevatedButton.icon(
                  onPressed: _startNewConversation,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Mới'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 16, color: AppColors.border),

          // ── Content List / Loading / Empty ───────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.error, size: 36),
                            const SizedBox(height: 8),
                            Text(_errorMessage!),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: _loadConversations,
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      )
                    : _conversations.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: AppColors.textSecondary,
                                      size: 30,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Chưa có cuộc trò chuyện nào',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Hãy bắt đầu trò chuyện bằng giọng nói hoặc tin nhắn với Linh AI!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                            itemCount: _conversations.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _conversations[index];
                              final isActive = activeId == item.id;

                              return InkWell(
                                onTap: () => _selectConversation(item),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppColors.primary.withValues(alpha: 0.08)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isActive
                                          ? AppColors.primary.withValues(alpha: 0.3)
                                          : AppColors.border,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Icon cuộc trò chuyện
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? AppColors.primary
                                              : Colors.grey.shade200,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isActive
                                              ? Icons.record_voice_over_rounded
                                              : Icons.forum_outlined,
                                          color: isActive
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Tiêu đề & thời gian
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: isActive
                                                          ? FontWeight.bold
                                                          : FontWeight.w600,
                                                      color: isActive
                                                          ? AppColors.primary
                                                          : AppColors.textPrimary,
                                                    ),
                                                  ),
                                                ),
                                                if (isActive)
                                                  Container(
                                                    margin: const EdgeInsets.only(
                                                        left: 6),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary,
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      'Đang mở',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDate(item.updatedAt),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Nút xóa
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 19,
                                          color: Colors.grey,
                                        ),
                                        splashRadius: 18,
                                        tooltip: 'Xóa hội thoại',
                                        onPressed: () =>
                                            _deleteConversation(item),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
