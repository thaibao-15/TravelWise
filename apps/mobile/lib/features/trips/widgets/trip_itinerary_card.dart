import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:mobile/core/constants/colors.dart';
import 'package:mobile/features/assistant/presentation/providers/voice_assistant_provider.dart';
import 'package:mobile/features/map/presentation/screens/map_screen.dart';
import 'package:mobile/features/trips/models/trip_model.dart';
import 'package:mobile/features/trips/screens/trip_detail_screen.dart';

import 'package:mobile/features/assistant/presentation/models/chat_media.dart';
import 'package:mobile/features/assistant/presentation/widgets/fullscreen_media_viewer.dart';

/// Reusable Trip Itinerary Card displayed within Chat AI messages and assistant screens.
/// Conforms to TravelWise Design System and showcases real API response details.
class TripItineraryCard extends ConsumerWidget {
  final Trip trip;
  final bool isCompact;
  final VoidCallback? onSave;

  const TripItineraryCard({
    super.key,
    required this.trip,
    this.isCompact = false,
    this.onSave,
  });

  String? _resolveActivityImageUrl(ItineraryActivity act, String destination) {
    if (act.imageUrl != null && act.imageUrl!.isNotEmpty) {
      return act.imageUrl;
    }
    final title = (act.placeName ?? act.title).toLowerCase();
    if (title.contains('cầu vàng') || title.contains('golden bridge')) {
      return 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('bà nà') || title.contains('ba na')) {
      return 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('cầu rồng') || title.contains('dragon bridge')) {
      return 'https://images.unsplash.com/photo-1583417319070-4a69db38a482?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('mỹ khê') || title.contains('my khe') || title.contains('biển')) {
      return 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('ngũ hành sơn') || title.contains('non nước')) {
      return 'https://images.unsplash.com/photo-1621255855018-9366e6097fc0?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('linh ứng') || title.contains('sơn trà')) {
      return 'https://images.unsplash.com/photo-1628172911295-a0bc3c42845c?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('hội an') || title.contains('chùa cầu')) {
      return 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('phú quốc') || title.contains('bãi sao')) {
      return 'https://images.unsplash.com/photo-1588668214407-6ea9a6d8c272?auto=format&fit=crop&w=400&q=80';
    }
    if (title.contains('đà lạt') || title.contains('xuân hương')) {
      return 'https://images.unsplash.com/photo-1626587979672-0050e828d506?auto=format&fit=crop&w=400&q=80';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);
    final isSaving = state.planningState == TripPlanningState.saving;
    final isSaved = state.planningState == TripPlanningState.saved ||
        (trip.id.isNotEmpty && trip.status != 'DRAFT');

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Gradient Badge / Header ─────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isSaved
                      ? [const Color(0xFF059669), const Color(0xFF10B981)]
                      : [AppColors.primary, const Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSaved ? Icons.check_circle_rounded : Icons.auto_awesome,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isSaved ? 'LỊCH TRÌNH ĐÃ LƯU' : 'LỊCH TRÌNH AI TRAVELWISE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${trip.daysCount} ngày',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Card Content ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    trip.title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // Destination Row
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.mapPin,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          trip.destination,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Stats Pills Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildPill(
                        icon: LucideIcons.calendarDays,
                        label: '${trip.daysCount} ngày',
                        color: const Color(0xFF2563EB),
                      ),
                      if (trip.totalStops > 0)
                        _buildPill(
                          icon: LucideIcons.navigation,
                          label: '${trip.totalStops} điểm dừng',
                          color: const Color(0xFF0D9488),
                        ),
                      if (trip.estimatedBudget.isNotEmpty && trip.estimatedBudget != 'Chưa tính')
                        _buildPill(
                          icon: LucideIcons.wallet,
                          label: trip.estimatedBudget,
                          color: const Color(0xFFD97706),
                        ),
                    ],
                  ),

                  // Days / Activities Highlights
                  if (trip.days.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...trip.days.take(isCompact ? 2 : 3).map((day) {
                            final acts = day.activities.take(2).map((a) => a.title).join(' · ');
                            final actsWithImg = day.activities
                                .map((a) => (act: a, img: _resolveActivityImageUrl(a, trip.destination)))
                                .where((e) => e.img != null)
                                .take(2)
                                .toList();

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'N${day.dayIndex}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          acts.isNotEmpty ? acts : day.title,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textPrimary,
                                            height: 1.35,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Compact destination image pills for itinerary activities
                                  if (actsWithImg.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 32, top: 4),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: actsWithImg.map((item) {
                                          return GestureDetector(
                                            onTap: () {
                                              FullscreenMediaViewer.open(
                                                context,
                                                mediaList: [
                                                  ChatMedia(
                                                    id: 'itin_act_${item.act.id}',
                                                    type: ChatMediaType.image,
                                                    url: item.img!,
                                                    title: item.act.title,
                                                  ),
                                                ],
                                              );
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.only(right: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(color: AppColors.border),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(16),
                                                    child: Image.network(
                                                      item.img!,
                                                      width: 26,
                                                      height: 26,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    item.act.title,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),

                          if (trip.days.length > (isCompact ? 2 : 3))
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text(
                                '+ còn ${trip.days.length - (isCompact ? 2 : 3)} ngày trong lịch trình',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // ── Action Buttons ──────────────────────────────────────────
                  Row(
                    children: [
                      // "Xem lịch trình" button (Requirement 7)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TripDetailScreen(
                                  tripId: trip.id.isNotEmpty ? trip.id : null,
                                  initialTrip: trip,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(LucideIcons.calendarCheck, size: 15),
                          label: const Text(
                            'Xem lịch trình',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // "Bản đồ" button
                      IconButton.outlined(
                        tooltip: 'Xem trên bản đồ',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MapScreen(
                                trip: trip,
                                initialDayIndex: 1,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(LucideIcons.map, size: 16),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      // "Lưu chuyến đi" button (if not already saved)
                      if (!isSaved) ...[
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          tooltip: 'Lưu chuyến đi',
                          onPressed: isSaving
                              ? null
                              : (onSave ?? () => notifier.saveCurrentTrip()),
                          icon: isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(LucideIcons.bookmark, size: 16),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
