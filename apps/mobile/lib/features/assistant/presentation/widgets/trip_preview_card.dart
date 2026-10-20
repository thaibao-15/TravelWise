import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../map/presentation/screens/map_screen.dart';
import '../../../trips/models/trip_model.dart';
import '../providers/voice_assistant_provider.dart';

class TripPreviewCard extends ConsumerStatefulWidget {
  final Trip trip;

  const TripPreviewCard({super.key, required this.trip});

  @override
  ConsumerState<TripPreviewCard> createState() => _TripPreviewCardState();
}

class _TripPreviewCardState extends ConsumerState<TripPreviewCard> {
  int _selectedDayIndex = 1;

  TripDay get _currentDay {
    if (widget.trip.days.isEmpty) {
      return TripDay(
        dayIndex: 1,
        date: widget.trip.startDate,
        title: 'Lịch trình tổng quan',
        subtitle: '',
        activities: [],
      );
    }
    return widget.trip.days.firstWhere(
      (d) => d.dayIndex == _selectedDayIndex,
      orElse: () => widget.trip.days.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceAssistantProvider);
    final notifier = ref.read(voiceAssistantProvider.notifier);
    final isSaving = state.planningState == TripPlanningState.saving;
    final isSaved = state.planningState == TripPlanningState.saved;

    final trip = widget.trip;
    final validActivities = trip.days
        .expand((d) => d.activities)
        .where((a) => a.hasValidCoordinates)
        .toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Banner ──────────────────────────────────────────────────
          _buildHeader(trip, isSaved),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Trip Stats & Info ─────────────────────────────────────────
                _buildInfoRow(trip, validActivities.length),

                const SizedBox(height: 16),

                // ── Interactive Mini Map ──────────────────────────────────────
                _buildMiniMap(validActivities),

                const SizedBox(height: 16),

                // ── Day Selector Tabs ─────────────────────────────────────────
                if (trip.days.length > 1) _buildDaySelector(trip.days),

                const SizedBox(height: 12),

                // ── Day Title ─────────────────────────────────────────────────
                Text(
                  _currentDay.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Activity Timeline List ────────────────────────────────────
                ..._currentDay.activities.map((act) => _buildActivityItem(act)),

                const SizedBox(height: 16),

                // ── Actions: Save / View Map / Dismiss ────────────────────────
                _buildActionButtons(context, notifier, isSaving, isSaved),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Trip trip, bool isSaved) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSaved
              ? [const Color(0xFF059669), const Color(0xFF10B981)]
              : [AppColors.primary, const Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSaved ? Icons.check_circle_rounded : Icons.auto_awesome,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSaved ? 'ĐÃ LƯU VÀO CHUYẾN ĐI' : 'XEM TRƯỚC LỊCH TRÌNH AI',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trip.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${trip.days.length} ngày',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(Trip trip, int placesCount) {
    final startStr = '${trip.startDate.day}/${trip.startDate.month}';
    final endStr = '${trip.endDate.day}/${trip.endDate.month}/${trip.endDate.year}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.calendar, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                '$startStr - $endStr',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(LucideIcons.mapPin, size: 14, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                '$placesCount địa điểm thực',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMap(List<ItineraryActivity> validActivities) {
    if (validActivities.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstLoc = LatLng(
      validActivities.first.latitude!,
      validActivities.first.longitude!,
    );

    return Container(
      height: 140,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: firstLoc,
              initialZoom: 12.0,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/'
                    'World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                maxNativeZoom: 19,
              ),
              MarkerLayer(
                markers: validActivities.map((a) {
                  return Marker(
                    point: LatLng(a.latitude!, a.longitude!),
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${a.activityOrder ?? 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MapScreen(
                      trip: widget.trip,
                      initialDayIndex: _selectedDayIndex,
                    ),
                  ),
                );
              },
              icon: const Icon(LucideIcons.maximize2, size: 13),
              label: const Text('Xem toàn bản đồ', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySelector(List<TripDay> days) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: days.map((d) {
          final isSelected = d.dayIndex == _selectedDayIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedDayIndex = d.dayIndex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.background,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Colors.transparent : AppColors.border,
                  ),
                ),
                child: Text(
                  'Ngày ${d.dayIndex}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActivityItem(ItineraryActivity act) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MapScreen(
              trip: widget.trip,
              initialDayIndex: _selectedDayIndex,
              initialSelectedActivity: act,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withOpacity(0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${act.activityOrder ?? 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          act.placeName ?? act.title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (act.startTime.isNotEmpty)
                        Text(
                          act.startTime,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    act.category,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (act.placeAddress != null && act.placeAddress!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.navigation,
                          size: 11,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            act.placeAddress!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    VoiceAssistantNotifier notifier,
    bool isSaving,
    bool isSaved,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: isSaving || isSaved
                    ? null
                    : () => notifier.saveCurrentTrip(),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Icon(
                        isSaved ? Icons.check : LucideIcons.bookmark,
                        size: 16,
                      ),
                label: Text(
                  isSaving
                      ? 'Đang lưu...'
                      : (isSaved ? 'Đã lưu thành công' : 'Lưu chuyến đi'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSaved ? AppColors.success : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MapScreen(
                        trip: widget.trip,
                        initialDayIndex: _selectedDayIndex,
                      ),
                    ),
                  );
                },
                icon: const Icon(LucideIcons.map, size: 15),
                label: const Text('Bản đồ'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: notifier.dismissPreview,
            child: const Text(
              'Đóng xem trước',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
