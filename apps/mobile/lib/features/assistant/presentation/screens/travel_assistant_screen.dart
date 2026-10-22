import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../providers/voice_assistant_provider.dart';
import '../widgets/assistant_header.dart';
import '../widgets/voice_profile_bar.dart';
import '../widgets/voice_state_selector.dart';
import '../widgets/transcript_view.dart';
import '../widgets/voice_orb.dart';
import '../widgets/location_suggestions.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/place_recommendation_card.dart';
import '../widgets/assistant_input_bar.dart';
import '../widgets/map_gps_card.dart';
import '../widgets/trip_preview_card.dart';

/// TravelSense Voice AI — connected to FastAPI + SQL Server backend.
class TravelAssistantScreen extends ConsumerWidget {
  const TravelAssistantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            const AssistantHeader(),

            // ── Scrollable body ─────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.sm),

                    // ── Voice profile pill ──────────────────────────────────
                    const VoiceProfileBar(),

                    const SizedBox(height: AppSpacing.lg),

                    // ── State selector ──────────────────────────────────────
                    const VoiceStateSelector(),

                    const SizedBox(height: AppSpacing.xl),

                    // ── Transcript ──────────────────────────────────────────
                    const TranscriptView(),

                    const SizedBox(height: AppSpacing.xl),

                    // ── Voice Orb ───────────────────────────────────────────
                    VoiceOrb(
                      voiceState: state.voiceState,
                      onTap: notifier.toggleRecording,
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // ── AI Planning: Generating / Revising Status Banner ──────
                    if (state.planningState == TripPlanningState.generating ||
                        state.planningState == TripPlanningState.revising) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                state.planningState == TripPlanningState.revising
                                    ? 'AI đang tối ưu và cập nhật lại lịch trình theo yêu cầu của bạn...'
                                    : 'Đang đối chiếu dữ liệu điểm đến và tạo lịch trình từ địa điểm thực...',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // ── AI Planning: Ready to Generate Prompt ───────────────
                    if (state.planningState == TripPlanningState.readyToGenerate &&
                        state.tripPreview == null) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Đã đủ thông tin du lịch!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Bấm để AI tạo lịch trình xem trước ngay.',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => notifier.requestGenerateItinerary(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                              child: const Text(
                                'Tạo ngay',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // ── Generated Trip Preview Card ─────────────────────────
                    if (state.tripPreview != null) ...[
                      TripPreviewCard(trip: state.tripPreview!),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // ── Location suggestions ────────────────────────────────
                    const LocationSuggestions(),

                    const SizedBox(height: AppSpacing.lg),

                    // ── Map & GPS action card ────────────────────────────────
                    const MapGpsCard(),

                    const SizedBox(height: AppSpacing.lg),

                    // ── Conversation drawer ─────────────────────────────────
                    const ConversationDrawer(),

                    const SizedBox(height: AppSpacing.lg),

                    // ── Place recommendation ────────────────────────────────
                    const PlaceRecommendationCard(),

                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),

            // ── Bottom input bar (pinned) ────────────────────────────────────
            const AssistantInputBar(),
          ],
        ),
      ),
    );
  }
}
