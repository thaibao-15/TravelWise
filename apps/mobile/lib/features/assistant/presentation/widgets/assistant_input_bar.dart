import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../services/media_upload_service.dart';
import '../models/chat_media.dart';
import '../providers/voice_assistant_provider.dart';

class _PickedItem {
  final XFile file;
  final ChatMediaType type;
  final Uint8List? previewBytes;

  _PickedItem({
    required this.file,
    required this.type,
    this.previewBytes,
  });
}

/// Bottom bar: by default displays ONE SINGLE VOICE BUTTON for speaking with AI.
/// Provides keyboard mode with attachment button to send images, videos, and text.
class AssistantInputBar extends ConsumerStatefulWidget {
  final bool allowKeyboardToggle;
  final String? defaultPromptLabel;

  const AssistantInputBar({
    super.key,
    this.allowKeyboardToggle = true,
    this.defaultPromptLabel,
  });

  @override
  ConsumerState<AssistantInputBar> createState() => _AssistantInputBarState();
}

class _AssistantInputBarState extends ConsumerState<AssistantInputBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  late AnimationController _micPulse;
  late Animation<double> _micScale;
  bool _isKeyboardMode = false;

  final MediaUploadService _uploadService = MediaUploadService();
  final List<_PickedItem> _attachments = [];
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _micPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _micScale = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _micPulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _micPulse.dispose();
    super.dispose();
  }

  void _syncMicPulse(bool isRecording) {
    if (isRecording) {
      if (!_micPulse.isAnimating) {
        _micPulse.repeat(reverse: true);
      }
    } else if (_micPulse.isAnimating || _micPulse.value != 0) {
      _micPulse.stop();
      _micPulse.animateTo(0);
    }
  }

  Future<void> _pickAttachment(ChatMediaType type) async {
    try {
      final XFile? file = type == ChatMediaType.image
          ? await _uploadService.pickImage()
          : await _uploadService.pickVideo();

      if (file == null) return;

      Uint8List? previewBytes;
      if (type == ChatMediaType.image) {
        previewBytes = await file.readAsBytes();
      }

      setState(() {
        _attachments.add(_PickedItem(
          file: file,
          type: type,
          previewBytes: previewBytes,
        ));
        _isKeyboardMode = true; // Switch to composer to see attachments
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAttachmentBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Đính kèm tệp phương tiện',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                  ),
                  title: const Text('Chọn hình ảnh', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Tải ảnh từ thư viện thiết bị (tối đa 20 MB)', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAttachment(ChatMediaType.image);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.video_library_rounded, color: Color(0xFFEF4444)),
                  ),
                  title: const Text('Chọn video', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Tải video du lịch từ thiết bị (tối đa 100 MB)', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAttachment(ChatMediaType.video);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (_isUploading) return;

    List<ChatMedia> uploadedMedia = [];

    if (_attachments.isNotEmpty) {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.05;
      });

      try {
        final total = _attachments.length;
        for (int i = 0; i < total; i++) {
          final item = _attachments[i];
          final media = await _uploadService.uploadAttachment(
            item.file,
            item.type,
            onProgress: (ratio) {
              if (mounted) {
                setState(() {
                  _uploadProgress = (i + ratio) / total;
                });
              }
            },
          );
          uploadedMedia.add(media);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isUploading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }
    }

    _textCtrl.clear();
    setState(() {
      _attachments.clear();
      _isUploading = false;
      _uploadProgress = 0.0;
    });

    ref.read(voiceAssistantProvider.notifier).sendMessage(
      text,
      media: uploadedMedia,
    );
  }

  void _handleVoiceAction() {
    final state = ref.read(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);

    if (state.voiceState == VoiceState.speaking) {
      // 1-Tap Barge-in: interrupt AI speech and listen immediately
      notifier.bargeIn();
      return;
    }
    notifier.toggleRecording();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VoiceAssistantState>(voiceAssistantProvider, (previous, next) {
      final micActive = next.isRecording ||
          next.voiceState == VoiceState.listening ||
          next.voiceState == VoiceState.connecting;
      _syncMicPulse(micActive);
    });

    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);
    final isSpeaking = state.voiceState == VoiceState.speaking;
    final isThinking = state.voiceState == VoiceState.thinking;
    final micActive = state.isRecording ||
        state.voiceState == VoiceState.listening ||
        state.voiceState == VoiceState.connecting;

    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attachment Preview Tray above the input bar
          if (_attachments.isNotEmpty) _buildAttachmentPreviewTray(),

          // Upload Progress Bar
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _uploadProgress > 0 ? _uploadProgress : null,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đang tải tệp đính kèm lên máy chủ (${(_uploadProgress * 100).toInt()}%)...',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

          // Main Row: Voice Mode or Keyboard Mode
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isKeyboardMode
                ? _buildKeyboardInputRow(state, notifier)
                : _buildSingleVoiceButtonRow(state, isSpeaking, isThinking, micActive),
          ),
        ],
      ),
    );
  }

  /// Horizontal tray showing thumbnails of selected attachments before sending
  Widget _buildAttachmentPreviewTray() {
    return Container(
      height: 72,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _attachments[index];
          return Stack(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  color: const Color(0xFFF1F5F9),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: item.type == ChatMediaType.image && item.previewBytes != null
                      ? Image.memory(item.previewBytes!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.type == ChatMediaType.video
                                  ? Icons.videocam_rounded
                                  : Icons.image_rounded,
                              color: AppColors.primary,
                              size: 26,
                            ),
                            const SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                item.file.name,
                                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              // Remove 'X' button
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _isUploading
                      ? null
                      : () {
                          setState(() {
                            _attachments.removeAt(index);
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Mode 1 (DEFAULT): Single Voice Button for speaking with AI + attachment icon
  Widget _buildSingleVoiceButtonRow(
    VoiceAssistantState state,
    bool isSpeaking,
    bool isThinking,
    bool micActive,
  ) {
    return Row(
      key: const ValueKey('voice_mode'),
      children: [
        // Attachment Button
        GestureDetector(
          onTap: _isUploading ? null : _showAttachmentBottomSheet,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.attach_file_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(width: 8),

        // ── 1 nút duy nhất chỉ để nói ──────────────────────────────────────
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isThinking ? null : _handleVoiceAction,
              borderRadius: BorderRadius.circular(28),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 48,
                decoration: BoxDecoration(
                  gradient: isSpeaking || micActive
                      ? const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                        )
                      : (isThinking
                          ? const LinearGradient(
                              colors: [Color(0xFF94A3B8), Color(0xFF64748B)],
                            )
                          : const LinearGradient(
                              colors: [AppColors.primary, AppColors.secondary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (isSpeaking || micActive
                              ? const Color(0xFFEF4444)
                              : AppColors.primary)
                          .withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isThinking) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'AI đang suy nghĩ...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (isSpeaking) ...[
                      const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Dừng đọc AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (micActive) ...[
                      ScaleTransition(
                        scale: _micScale,
                        child: const Icon(Icons.mic, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Đang nghe... Chạm để gửi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        widget.defaultPromptLabel ?? 'Nhấn để nói chuyện với AI',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),

        // Optional keyboard toggle button on the side
        if (widget.allowKeyboardToggle) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _isKeyboardMode = true),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.keyboard_alt_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Mode 2: Nhập văn bản khi người dùng bấm vào icon bàn phím
  Widget _buildKeyboardInputRow(
    VoiceAssistantState state,
    VoiceAssistantNotifier notifier,
  ) {
    return Row(
      key: const ValueKey('keyboard_mode'),
      children: [
        // Button switch back to Voice Button
        GestureDetector(
          onTap: () => setState(() => _isKeyboardMode = false),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
        ),

        const SizedBox(width: 6),

        // Attachment Button
        GestureDetector(
          onTap: _isUploading ? null : _showAttachmentBottomSheet,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _attachments.isNotEmpty
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(
                color: _attachments.isNotEmpty ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Icon(
              Icons.attach_file_rounded,
              size: 20,
              color: _attachments.isNotEmpty ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(width: 6),

        // Text field
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: _textCtrl,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: _attachments.isNotEmpty ? 'Thêm ghi chú hoặc gửi ngay...' : 'Nhập câu hỏi cho AI...',
                hintStyle: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
        ),

        const SizedBox(width: 6),

        // Send button
        GestureDetector(
          onTap: (state.voiceState == VoiceState.thinking || _isUploading)
              ? null
              : _handleSend,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: (state.voiceState == VoiceState.thinking || _isUploading)
                  ? const LinearGradient(
                      colors: [Color(0xFFCBD5E1), Color(0xFFCBD5E1)])
                  : const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: (state.voiceState == VoiceState.thinking || _isUploading)
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: (state.voiceState == VoiceState.thinking || _isUploading)
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }
}
