import '../../../map/presentation/screens/map_screen.dart';
import 'assistant_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../auth/presentation/providers/auth_notifier.dart';
import '../../../auth/presentation/providers/auth_state.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../../../trips/models/trip_model.dart';
import '../providers/voice_assistant_provider.dart';
import '../widgets/location_suggestions.dart';
import '../widgets/trip_preview_card.dart';
import '../widgets/voice_profile_bar.dart';

/// Màn hình Trợ lý du lịch TravelWise (Linh AI) - Thiết kế Compact không cần cuộn dọc.
/// Tối ưu trải nghiệm trò chuyện giọng nói, xem lộ trình và tương tác tức thì.
class TravelAssistantScreen extends ConsumerStatefulWidget {
  const TravelAssistantScreen({super.key});

  @override
  ConsumerState<TravelAssistantScreen> createState() => _TravelAssistantScreenState();
}

class _TravelAssistantScreenState extends ConsumerState<TravelAssistantScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Tự động kiểm tra và chào người dùng khi vào màn hình
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndGreetIfActive();
    });
  }

  void _checkAndGreetIfActive() {
    if (!mounted) return;
    final currentTab = ref.read(mainTabProvider);
    // Kích hoạt khi đang ở tab Assistant (tab 2) hoặc mở độc lập
    if (currentTab == 2 || MainShell.currentTab == -1 || MainShell.currentTab == 2) {
      final authState = ref.read(authProvider);
      String? userName;
      if (authState is AuthAuthenticated) {
        userName = authState.user.fullName;
      }
      ref.read(voiceAssistantProvider.notifier).greetUser(userName: userName);
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);

    // Lắng nghe thay đổi tab: Khi người dùng chuyển đến trang Assistant thì AI tự chào và giới thiệu
    ref.listen<int>(mainTabProvider, (prev, next) {
      if (next == 2) {
        _checkAndGreetIfActive();
      } else if (prev == 2 && next != 2) {
        // Dừng nghe và dừng phát audio nếu chuyển sang tab khác
        notifier.cancelListening();
        notifier.stopAudio();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // ── 1. Top Header Bar ───────────────────────────────────────────
            _buildTopAppBar(context, state, notifier),

            // ── 2. Nội dung chính: Tối ưu vừa vặn màn hình (Single-Screen) ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    // ── A. Nửa trên: AI Avatar Linh & Bong bóng thoại nổi ───
                    Expanded(
                      flex: 11,
                      child: _buildHeroPersonaSection(context, state, notifier),
                    ),

                    // ── B. Cụm điều khiển giọng nói trung tâm (Voice Cluster) ─
                    _buildVoiceActionCluster(context, state, notifier),

                    const SizedBox(height: 10),

                    // ── C. Nửa dưới: Thẻ thông minh (Lịch trình / Gợi ý) ────
                    Expanded(
                      flex: 9,
                      child: _buildSmartContentPanel(context, state, notifier),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. TOP APP BAR (Logo TravelWise, Menu, Notification)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildTopAppBar(
    BuildContext context,
    VoiceAssistantState state,
    VoiceAssistantNotifier notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Nút Menu bên trái
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.menu_rounded, size: 20, color: Color(0xFF1E293B)),
              padding: EdgeInsets.zero,
              onPressed: () {
                _openVoiceSettingsModal(context);
              },
            ),
          ),

          // Logo TravelWise & AI Tour Guide ở giữa
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D9488), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.explore_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'TravelWise',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'AI Tour Guide',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Nút Chuông thông báo / Đổi ngôn ngữ bên phải
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: notifier.toggleLanguage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    state.selectedLanguage,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      size: 21,
                      color: Color(0xFF1E293B),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. HERO PERSONA SECTION (Ảnh Linh AI & Thẻ thoại nổi)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildHeroPersonaSection(
    BuildContext context,
    VoiceAssistantState state,
    VoiceAssistantNotifier notifier,
  ) {
    // Lấy câu nói gần nhất của AI
    String latestAiSpeech = '';
    if (state.messages.isNotEmpty) {
      final aiMsgs = state.messages.where((m) => !m.isUser).toList();
      if (aiMsgs.isNotEmpty) {
        latestAiSpeech = aiMsgs.last.text;
      }
    }
    if (latestAiSpeech.isEmpty) {
      if (state.currentTranscript.isNotEmpty) {
        latestAiSpeech = state.currentTranscript;
      } else {
        latestAiSpeech = 'Xin chào bạn! Mình là Linh AI - trợ lý du lịch TravelWise với giọng Nữ Đà Nẵng ngọt ngào. Hôm nay bạn muốn lên lịch trình khám phá điểm đến nào?';
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Khung ảnh nền chân dung Linh AI
            Positioned(
              top: 0,
              bottom: 40,
              left: 12,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/linh_ai.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.2),
                      errorBuilder: (ctx, err, stack) => Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFE0F2FE), Color(0xFFBAE6FD)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.support_agent_rounded,
                            size: 90,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),

                    // Lớp Gradient mờ mềm mại ở chân ảnh
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              const Color(0xFFF6F8FB).withValues(alpha: 0.2),
                              const Color(0xFFF6F8FB).withValues(alpha: 0.85),
                            ],
                            stops: const [0.0, 0.6, 0.85, 1.0],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),

                    // Tag tên "Linh AI" đính trên áo
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Linh AI • Giọng Nữ Đà Nẵng',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bong bóng lời thoại nổi (Hiển thị văn bản khi User nói hoặc khi AI trả lời)
            Positioned(
              bottom: 0,
              left: 4,
              right: 4,
              child: Builder(
                builder: (context) {
                  final isUserSpeaking = (state.voiceState == VoiceState.listening || state.isRecording) &&
                      state.currentTranscript.trim().isNotEmpty;
                  final displayText = isUserSpeaking ? state.currentTranscript : latestAiSpeech;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUserSpeaking ? const Color(0xFFEFF6FF) : Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isUserSpeaking ? const Color(0xFF93C5FD) : Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isUserSpeaking
                              ? const Color(0xFF0284C7).withValues(alpha: 0.14)
                              : const Color(0xFF0F172A).withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon microphone hoặc sóng âm âm thanh
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: isUserSpeaking ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isUserSpeaking ? Icons.mic : Icons.graphic_eq_rounded,
                            color: const Color(0xFF0284C7),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Văn bản thoại (User nói hoặc AI nói)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isUserSpeaking) ...[
                                const Text(
                                  'Bạn đang nói...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0284C7),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                displayText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isUserSpeaking ? FontWeight.w700 : FontWeight.w600,
                                  color: isUserSpeaking ? const Color(0xFF1E3A8A) : const Color(0xFF1E293B),
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. VOICE ACTION CLUSTER (Nhắn tin - Mic Tròn Sóng Âm - Bản đồ)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildVoiceActionCluster(
    BuildContext context,
    VoiceAssistantState state,
    VoiceAssistantNotifier notifier,
  ) {
    final isListening = state.voiceState == VoiceState.listening ||
        state.voiceState == VoiceState.connecting;
    final isSpeaking = state.voiceState == VoiceState.speaking;

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Nút bên trái: Nhắn tin (Mở Chat Drawer & Bàn phím)
              _buildCircleActionButton(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Nhắn tin',
                onTap: () => _openChatModal(context),
              ),

              const SizedBox(width: 24),

              // Nút giữa: Voice Orb Mic lớn (Nhấn để nói / Dừng nghe / Dừng AI nói)
              GestureDetector(
                onTap: isSpeaking ? notifier.stopSpeaking : notifier.toggleRecording,
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Sóng âm tỏa ra khi đang nghe (Ripple Ring 1)
                      if (isListening || isSpeaking)
                        AnimatedBuilder(
                          animation: _rippleController,
                          builder: (context, child) {
                            final val = _rippleController.value;
                            return Container(
                              width: 70 + val * 26,
                              height: 70 + val * 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF0284C7).withValues(alpha: (1 - val) * 0.4),
                                  width: 2,
                                ),
                              ),
                            );
                          },
                        ),

                      // Sóng âm tỏa ra 2 (Offset)
                      if (isListening || isSpeaking)
                        AnimatedBuilder(
                          animation: _rippleController,
                          builder: (context, child) {
                            final val = (_rippleController.value + 0.5) % 1.0;
                            return Container(
                              width: 70 + val * 26,
                              height: 70 + val * 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF0284C7).withValues(alpha: (1 - val) * 0.25),
                                  width: 1.5,
                                ),
                              ),
                            );
                          },
                        ),

                      // Vòng viền Gradient xanh bóng bẩy
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE0F2FE),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),

                      // Nút chính giữa (Đỏ khi đang nói/dừng, Xanh khi bình thường)
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isSpeaking
                                ? const [Color(0xFFEF4444), Color(0xFFDC2626)]
                                : const [Color(0xFF0284C7), Color(0xFF0369A1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            (isSpeaking || isListening) ? Icons.stop_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 24),

              // Nút bên phải: Bản đồ
              _buildCircleActionButton(
                icon: Icons.location_on_outlined,
                label: 'Bản đồ',
                onTap: () => _openMapModal(context),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Hiển thị trực tiếp chữ khi người dùng nói hoặc dòng trạng thái
          if ((state.voiceState == VoiceState.listening || state.isRecording) &&
              state.currentTranscript.trim().isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF93C5FD), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.record_voice_over_rounded, size: 16, color: Color(0xFF0284C7)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state.currentTranscript,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E40AF),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isSpeaking) ...[
            const SizedBox(height: 2),
            _StopSpeakingButton(onPressed: notifier.stopSpeaking),
          ] else ...[
            Text(
              _resolveVoiceStateStatus(state),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isListening ? const Color(0xFF0284C7) : const Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. SMART CONTENT PANEL (Nửa dưới: Lịch trình tóm tắt / Quick Prompts)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSmartContentPanel(
    BuildContext context,
    VoiceAssistantState state,
    VoiceAssistantNotifier notifier,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "Lịch trình của bạn" | "Xem tất cả"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF0284C7)),
                  SizedBox(width: 7),
                  Text(
                    'Lịch trình của bạn',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  if (state.tripPreview != null) {
                    _openFullItineraryModal(context, state.tripPreview!);
                  } else {
                    _openQuickPromptsModal(context, notifier);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    'Xem tất cả',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Nội dung bên trong thẻ: Kiểm tra trạng thái planningState / tripPreview
          Expanded(
            child: _buildInnerItineraryContent(context, state, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildInnerItineraryContent(
    BuildContext context,
    VoiceAssistantState state,
    VoiceAssistantNotifier notifier,
  ) {
    // 1. Nếu đang tạo lịch trình (Generating)
    if (state.planningState == TripPlanningState.generating) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: const [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF0284C7)),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Đang đối chiếu dữ liệu điểm đến và tạo lịch trình từ địa điểm thực...',
                  style: TextStyle(
                    color: Color(0xFF0369A1),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 1b. Nếu đang chỉnh sửa lịch trình (Revising)
    if (state.planningState == TripPlanningState.revising) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: const [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Color(0xFFD97706)),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Đang phân tích yêu cầu và chỉnh sửa lịch trình của bạn...',
                  style: TextStyle(
                    color: Color(0xFFB45309),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Nếu đã có chuyến đi xem trước (tripPreview != null)
    if (state.tripPreview != null) {
      final trip = state.tripPreview!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tiêu đề chuyến đi + badge Nháp
          Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.destination} • ${trip.daysCount} ngày ${trip.daysCount > 1 ? trip.daysCount - 1 : 1} đêm',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Nháp',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Horizontal Carousel danh sách các ngày
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: trip.days.isNotEmpty ? trip.days.length : 3,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final day = trip.days.length > index ? trip.days[index] : null;
                final dayTitle = day?.title ?? (index == 0 ? 'Sơn Trà - Mỹ Khê' : index == 1 ? 'Hội An' : 'Bà Nà Hills');
                final fallbackImage = _getDayFallbackImage(index);

                return GestureDetector(
                  onTap: () => _openFullItineraryModal(context, trip),
                  child: Container(
                    width: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail ảnh của ngày
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                            child: Image.network(
                              fallbackImage,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Container(
                                color: const Color(0xFFE2E8F0),
                                child: const Icon(Icons.image, color: Colors.grey, size: 24),
                              ),
                            ),
                          ),
                        ),
                        // Thông tin ngày
                        Padding(
                          padding: const EdgeInsets.all(7.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ngày ${index + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    // 3. Nếu sẵn sàng tạo (Ready to generate)
    if (state.planningState == TripPlanningState.readyToGenerate) {
      final summaryText = state.planningContextSummary != null && state.planningContextSummary!.isNotEmpty
          ? state.planningContextSummary!
          : 'Đã đủ thông tin du lịch!';
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summaryText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'Nhấn để tạo lịch trình chi tiết từ địa điểm thực.',
                    style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => notifier.generateItinerary(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0284C7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Tạo ngay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // 4. Mặc định: Gợi ý tạo lịch trình du lịch nhanh (gọn gàng, loại bỏ các mục thời tiết thừa)
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => notifier.sendMessage('Tạo lịch trình du lịch Đà Nẵng 3 ngày 2 đêm'),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('🏖️', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Lên lịch trình Đà Nẵng 3 ngày 2 đêm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Chạm để Linh AI lên kế hoạch chi tiết',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPER WIDGETS
  // ──────────────────────────────────────────────────────────────────────────

  Widget _buildCircleActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF334155), size: 22),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  String _resolveVoiceStateStatus(VoiceAssistantState state) {
    switch (state.voiceState) {
      case VoiceState.listening:
        return 'Đang nghe... Bạn có thể nói bất cứ lúc nào';
      case VoiceState.thinking:
      case VoiceState.processing:
        return 'Đang suy nghĩ câu trả lời...';
      case VoiceState.speaking:
        return 'Linh AI đang nói...';
      case VoiceState.connecting:
        return 'Đang mở micro...';
      case VoiceState.error:
        return 'Đã có lỗi, chạm để thử lại';
      case VoiceState.idle:
        return 'Chạm micro hoặc bắt đầu trò chuyện';
    }
  }

  String _getDayFallbackImage(int index) {
    final images = [
      'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b', // Mỹ Khê
      'https://images.unsplash.com/photo-1582236968604-ee5ea861a4c9', // Hội An
      'https://images.unsplash.com/photo-1599707367072-cd6ada2bc375', // Bà Nà
    ];
    return images[index % images.length];
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MODAL BOTTOM SHEETS (Dành cho chức năng mở rộng không chiếm không gian)
  // ──────────────────────────────────────────────────────────────────────────

  void _openChatModal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AssistantChatScreen(),
      ),
    );
  }

  void _openMapModal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const MapScreen(),
      ),
    );
  }

  void _openFullItineraryModal(BuildContext context, Trip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: TripPreviewCard(trip: trip),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openVoiceSettingsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Cấu hình trợ lý giọng nói',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.record_voice_over_rounded, color: Color(0xFF16A34A), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Giọng đọc: Nữ Đà Nẵng (DaNang-Nu-1-BL)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF14532D),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Mô hình: Blaze AI 2.0-realtime • Tốc độ: 1.5x',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const VoiceProfileBar(),
            const SizedBox(height: 16),
            const LocationSuggestions(),
          ],
        ),
      ),
    );
  }

  void _openQuickPromptsModal(BuildContext context, VoiceAssistantNotifier notifier) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Gợi ý yêu cầu cho Linh AI',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.beach_access, color: Color(0xFF0284C7)),
              title: const Text('Lên lịch trình khám phá Đà Nẵng 3 ngày'),
              onTap: () {
                Navigator.pop(ctx);
                notifier.sendMessage('Tạo lịch trình du lịch Đà Nẵng 3 ngày 2 đêm');
              },
            ),
            ListTile(
              leading: const Icon(Icons.restaurant, color: Color(0xFFF59E0B)),
              title: const Text('Tìm các quán hải sản tươi ngon giá hợp lý'),
              onTap: () {
                Navigator.pop(ctx);
                notifier.sendMessage('Gợi ý cho mình các quán hải sản ngon rẻ ở Đà Nẵng');
              },
            ),
            ListTile(
              leading: const Icon(Icons.hotel, color: Color(0xFF10B981)),
              title: const Text('Gợi ý khách sạn view biển gần cầu Rồng'),
              onTap: () {
                Navigator.pop(ctx);
                notifier.sendMessage('Gợi ý khách sạn view đẹp gần cầu Rồng Đà Nẵng');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StopSpeakingButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _StopSpeakingButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Dừng đọc AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
