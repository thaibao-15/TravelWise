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

/// TravelSense Voice AI — full-screen demo.
/// All data is mock / local. No API calls.
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

                    // ── Voice Orb (tap to cycle state) ──────────────────────
                    VoiceOrb(
                      voiceState: state.voiceState,
                      onTap: notifier.cycleVoiceState,
                    ),

                    const SizedBox(height: AppSpacing.xxl),

                    // ── Location suggestions ────────────────────────────────
                    const LocationSuggestions(),

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
