import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/constants/text_styles.dart';
import '../../../../shared/widgets/bottom_nav_bar.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../../assistant/presentation/providers/voice_assistant_provider.dart';
import '../../map/presentation/screens/map_screen.dart';
import '../data/repositories/trip_repository.dart';
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
  bool _isGeneratingItinerary = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedDayProvider.notifier).state = 1;
      }
    });
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _handleGenerateItinerary(Trip trip) async {
    if (_isGeneratingItinerary) return;
    setState(() => _isGeneratingItinerary = true);
    try {
      final repo = ref.read(tripRepositoryProvider);
      await repo.generateItineraryForTrip(trip.id);
      ref.invalidate(tripDetailProvider(trip.id));
      ref.invalidate(tripsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI đã tạo chi tiết lịch trình cho chuyến đi!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingItinerary = false);
      }
    }
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
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primary,
                          size: 20,
                        ),
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
                                color: AppColors.textSecondary.withValues(alpha: 0.8),
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text(
                          'Thêm quán ăn đặc sản buổi tối',
                          style: TextStyle(fontSize: 11.5, color: AppColors.primary),
                        ),
                        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onPressed: () {
                          _editController.text = 'Thêm quán ăn đặc sản buổi tối';
                        },
                      ),
                      ActionChip(
                        label: const Text(
                          'Đổi ngày 2 sang đi biển thư giãn',
                          style: TextStyle(fontSize: 11.5, color: AppColors.primary),
                        ),
                        backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onPressed: () {
                          _editController.text = 'Đổi ngày 2 sang đi biển thư giãn';
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _editController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Nhập yêu cầu điều chỉnh lịch trình của bạn...',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).popUntil((route) => route.isFirst);
                            MainShell.switchToTab(context, 2);
                            Future.delayed(const Duration(milliseconds: 300), () {
                              ref.read(voiceAssistantProvider.notifier).toggleRecording();
                            });
                          },
                          icon: const Icon(Icons.mic_rounded, size: 18),
                          label: const Text('Nói với AI'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
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
                                    final targetTripId = currentTrip.id.isNotEmpty
                                        ? currentTrip.id
                                        : ref.read(voiceAssistantProvider).savedTripId;
                                    if (targetTripId != null && targetTripId.isNotEmpty) {
                                      await notifier.editSavedTrip(
                                        tripId: targetTripId,
                                        instruction: text,
                                      );
                                    } else {
                                      await notifier.sendMessage(text);
                                    }
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
                                        SnackBar(
                                          content: Text('Lỗi: $e'),
                                          backgroundColor: AppColors.error,
                                        ),
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
                          label: Text(
                            _isEditing ? 'AI đang cập nhật...' : 'Cập nhật lịch trình',
                          ),
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

    final effectiveTripId = widget.tripId ?? widget.initialTrip?.id;
    final AsyncValue<Trip?>? tripAsync =
        (effectiveTripId != null && effectiveTripId.isNotEmpty)
            ? ref.watch(tripDetailProvider(effectiveTripId))
            : null;

    final bool isLoadingDetail = tripAsync?.isLoading ?? false;
    final Trip? resolvedFromApi = tripAsync?.valueOrNull;

    final Trip trip = resolvedFromApi ?? widget.initialTrip ?? mockTripDetail;

    final currentDayData = trip.days.isNotEmpty
        ? trip.days.firstWhere(
            (d) => d.dayIndex == selectedDay,
            orElse: () => trip.days.first,
          )
        : TripDay(
            dayIndex: 1,
            date: trip.startDate,
            title: trip.title,
            subtitle: '${trip.destination} · ${trip.daysCount} ngày',
            activities: [],
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () async {
          if (effectiveTripId != null && effectiveTripId.isNotEmpty) {
            return ref.refresh(tripDetailProvider(effectiveTripId).future);
          }
        },
        child: Stack(
          children: [
            CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                        const SizedBox(height: 44),
                        if (isLoadingDetail && trip.days.isEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Đang tải chi tiết lịch trình từ máy chủ...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (tripAsync?.hasError == true && trip.days.isEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Không thể tải chi tiết lịch trình: ${tripAsync?.error}',
                                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                                  ),
                                ),
                                if (effectiveTripId != null && effectiveTripId.isNotEmpty)
                                  TextButton(
                                    onPressed: () => ref.refresh(tripDetailProvider(effectiveTripId)),
                                    child: const Text('Thử lại'),
                                  ),
                              ],
                            ),
                          ),
                        if (trip.days.isNotEmpty) ...[
                          TripDaySelector(days: trip.days),
                          const SizedBox(height: AppSpacing.xl),
                        ],
                        TripDayHeader(day: currentDayData),
                        const SizedBox(height: AppSpacing.lg),
                        if (currentDayData.activities.isNotEmpty)
                          ItineraryTimeline(
                            activities: currentDayData.activities,
                            onActivityTap: (act) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MapScreen(
                                    trip: trip,
                                    initialDayIndex: selectedDay,
                                    originatingTabIndex: 3,
                                    initialSelectedActivity: act,
                                  ),
                                ),
                              );
                            },
                          )
                        else if (!isLoadingDetail)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 36,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Chưa có hoạt động chi tiết trong ngày này.',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  onPressed: _isGeneratingItinerary
                                      ? null
                                      : () => _handleGenerateItinerary(trip),
                                  icon: _isGeneratingItinerary
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Icon(Icons.auto_awesome, size: 16),
                                  label: Text(
                                    _isGeneratingItinerary
                                        ? 'AI đang tạo lịch trình...'
                                        : 'Tạo lịch trình chi tiết bằng AI',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
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
                      originatingTabIndex: 3,
                    ),
                  ),
                );
              },
              onAiEdit: () => _showAiEditModal(context, trip),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 3,
        onTap: (index) => MainShell.switchToTab(context, index),
      ),
    );
  }
}
