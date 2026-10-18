import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/constants/text_styles.dart';
import '../../assistant/presentation/providers/voice_assistant_provider.dart';
import '../../map/presentation/screens/map_screen.dart';
import '../models/trip_model.dart';
import '../models/mock_trip_data.dart';
import '../providers/trip_provider.dart';
import '../widgets/trip_hero_header.dart';
import '../widgets/trip_day_selector.dart';
import '../widgets/trip_day_header.dart';
import '../widgets/itinerary_timeline.dart';
import '../widgets/trip_map_section.dart';
import '../widgets/trip_floating_actions.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  final String? tripId;
  final Trip? initialTrip;

  const TripDetailScreen({
    super.key,
    this.tripId,
    this.initialTrip,
  });

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  final TextEditingController _editController = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _showAiEditModal(BuildContext context, Trip currentTrip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Chỉnh sửa lịch trình bằng AI',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Ví dụ: "Ngày thứ 2 đổi Bà Nà sang đi biển Mỹ Khê"',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _editController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Nhập yêu cầu điều chỉnh lịch trình của bạn...',
                      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isEditing
                          ? null
                          : () async {
                              final text = _editController.text.trim();
                              if (text.isEmpty) return;
                              setModalState(() => _isEditing = true);
                              setState(() => _isEditing = true);
                              try {
                                final notifier = ref.read(voiceAssistantProvider.notifier);
                                await notifier.editSavedTrip(
                                  tripId: currentTrip.id,
                                  instruction: text,
                                );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã cập nhật lịch trình thành công!'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _isEditing = false);
                                  _editController.clear();
                                }
                              }
                            },
                      icon: _isEditing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_isEditing ? 'AI đang cập nhật...' : 'Gửi yêu cầu chỉnh sửa'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = ref.watch(selectedDayProvider);

    Trip? currentTrip = widget.initialTrip;

    if (widget.tripId != null && widget.tripId!.isNotEmpty) {
      final tripAsync = ref.watch(tripDetailProvider(widget.tripId!));
      tripAsync.whenData((data) {
        if (data != null) {
          currentTrip = data;
        }
      });
    }

    // Fallback to mockTripDetail if no trip is loaded
    final trip = currentTrip ?? mockTripDetail;

    final currentDayData = trip.days.isNotEmpty
        ? trip.days.firstWhere(
            (d) => d.dayIndex == selectedDay,
            orElse: () => trip.days.first,
          )
        : TripDay(
            dayIndex: 1,
            date: trip.startDate,
            title: trip.title,
            subtitle: trip.destination,
            activities: [],
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: TripHeroHeader(trip: trip),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.xl),
                      if (trip.days.isNotEmpty)
                        TripDaySelector(days: trip.days),
                      const SizedBox(height: AppSpacing.xl),
                      TripDayHeader(day: currentDayData),
                      const SizedBox(height: AppSpacing.lg),
                      if (currentDayData.activities.isNotEmpty)
                        ItineraryTimeline(activities: currentDayData.activities)
                      else
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Center(
                            child: Text(
                              'Không có hoạt động nào trong ngày này.',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      TripMapSection(
                        trip: trip,
                        selectedDayIndex: selectedDay,
                      ),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ),
            ],
          ),
          TripFloatingActions(
            onOpenMap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MapScreen(
                    trip: trip,
                    initialDayIndex: selectedDay,
                  ),
                ),
              );
            },
            onAiEdit: () => _showAiEditModal(context, trip),
          ),
        ],
      ),
    );
  }
}
