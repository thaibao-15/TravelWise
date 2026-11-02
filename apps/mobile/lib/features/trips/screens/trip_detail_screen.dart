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
  late final VoiceAssistantNotifier _voiceNotifier;
  bool _isEditing = false;
  bool _isGeneratingItinerary = false;
  bool _isAiModalOpen = false;
  BuildContext? _activeModalContext;
  bool _modalVoiceTriggered = false;

  @override
  void initState() {
    super.initState();
    _voiceNotifier = ref.read(voiceAssistantProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedDayProvider.notifier).state = 1;
      }
    });
  }

  @override
  void dispose() {
    _voiceNotifier.stopDirectTripVoiceSession(fromDispose: true);
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

  void _showAiEditModal(BuildContext context, Trip currentTrip, int selectedDay) {
    setState(() {
      _isAiModalOpen = true;
      _modalVoiceTriggered = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        _activeModalContext = ctx;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Consumer(
              builder: (ctx, modalRef, _) {
                final modalVoiceState = modalRef.watch(voiceAssistantProvider);
                final bool isModalListening = modalVoiceState.isRecording ||
                    modalVoiceState.voiceState == VoiceState.connecting ||
                    modalVoiceState.voiceState == VoiceState.listening;
                final bool isModalRevising = _isEditing ||
                    modalVoiceState.planningState == TripPlanningState.revising;
                final bool isModalSpeaking =
                    modalVoiceState.voiceState == VoiceState.speaking;

                // Đồng bộ trực tiếp giọng nói nhận diện được vào ô nhập văn bản trong modal
                if (isModalListening &&
                    modalVoiceState.currentTranscript.trim().isNotEmpty &&
                    _editController.text != modalVoiceState.currentTranscript) {
                  final liveText = modalVoiceState.currentTranscript;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (ctx.mounted && _editController.text != liveText) {
                      _editController.value = TextEditingValue(
                        text: liveText,
                        selection: TextSelection.collapsed(offset: liveText.length),
                      );
                    }
                  });
                }

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
                                Text(
                                  'Chỉnh sửa lịch trình bằng AI (Ngày $selectedDay)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Nói trực tiếp hoặc nhập yêu cầu ngay tại trang này',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              if (isModalListening) {
                                modalRef
                                    .read(voiceAssistantProvider.notifier)
                                    .cancelDirectTripVoiceEdit();
                              }
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                      if (isModalListening || isModalRevising || isModalSpeaking) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isModalListening
                                ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                                : AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isModalListening
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                                  : AppColors.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (isModalRevising)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                                  ),
                                )
                              else
                                Icon(
                                  isModalListening
                                      ? Icons.graphic_eq_rounded
                                      : Icons.volume_up_rounded,
                                  size: 18,
                                  color: isModalListening
                                      ? const Color(0xFFEF4444)
                                      : AppColors.primary,
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  isModalListening
                                      ? (modalVoiceState.currentTranscript.trim().isNotEmpty
                                          ? 'Đang nghe: "${modalVoiceState.currentTranscript}"'
                                          : 'Đang lắng nghe giọng nói của bạn... (tự động gửi khi bạn ngừng nói)')
                                      : isModalRevising
                                          ? 'Linh AI đang cập nhật lịch trình trực tiếp...'
                                          : 'Linh AI đang phản hồi...',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: isModalListening
                                        ? const Color(0xFFDC2626)
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                              if (isModalListening)
                                TextButton(
                                  onPressed: () {
                                    modalRef
                                        .read(voiceAssistantProvider.notifier)
                                        .cancelDirectTripVoiceEdit();
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    minimumSize: const Size(0, 28),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Huỷ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFDC2626),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
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
                          hintText:
                              'Nhập hoặc bấm "Nói trực tiếp" (VD: "Đổi buổi chiều sang Bà Nà Hills")...',
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
                              onPressed: isModalRevising
                                  ? null
                                  : () {
                                      _modalVoiceTriggered = true;
                                      modalRef
                                          .read(voiceAssistantProvider.notifier)
                                          .toggleDirectTripVoiceEdit(
                                            trip: currentTrip,
                                            targetDay: selectedDay,
                                          );
                                    },
                              icon: Icon(
                                isModalListening
                                    ? Icons.stop_circle_outlined
                                    : isModalSpeaking
                                        ? Icons.volume_off_rounded
                                        : Icons.mic_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isModalListening
                                    ? 'Chốt & Gửi'
                                    : isModalSpeaking
                                        ? 'Dừng đọc'
                                        : 'Nói trực tiếp',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isModalListening
                                    ? const Color(0xFFDC2626)
                                    : AppColors.primary,
                                backgroundColor: isModalListening
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                                    : null,
                                side: BorderSide(
                                  color: isModalListening
                                      ? const Color(0xFFDC2626)
                                      : AppColors.primary,
                                ),
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
                              onPressed: isModalRevising
                                  ? null
                                  : () async {
                                      if (isModalListening) {
                                        _modalVoiceTriggered = true;
                                        modalRef
                                            .read(voiceAssistantProvider.notifier)
                                            .toggleDirectTripVoiceEdit(
                                              trip: currentTrip,
                                              targetDay: selectedDay,
                                            );
                                        return;
                                      }
                                      final text = _editController.text.trim();
                                      if (text.isEmpty) return;
                                      _modalVoiceTriggered = false;
                                      setModalState(() => _isEditing = true);
                                      setState(() => _isEditing = true);
                                      try {
                                        final notifier =
                                            ref.read(voiceAssistantProvider.notifier);
                                        await notifier.editCurrentOrSavedTrip(
                                          instruction: text,
                                          targetDay: selectedDay,
                                          fallbackTrip: currentTrip,
                                          rethrowOnError: true,
                                        );
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Đã cập nhật lịch trình thành công!',
                                              ),
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
                              icon: isModalRevising
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded, size: 18),
                              label: Text(
                                isModalRevising
                                    ? 'AI đang cập nhật...'
                                    : 'Cập nhật lịch trình',
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
      },
    ).whenComplete(() {
      _activeModalContext = null;
      if (mounted) {
        setState(() {
          _isAiModalOpen = false;
          _modalVoiceTriggered = false;
        });
      }
    });
  }

  Widget _buildDirectVoiceBanner({
    required BuildContext context,
    required VoiceAssistantState voiceState,
    required Trip trip,
    required int selectedDay,
    required bool isListening,
    required bool isRevising,
    required bool isSpeaking,
  }) {
    final transcript = voiceState.currentTranscript.trim();

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 82,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isListening
                  ? const Color(0xFFEF4444).withValues(alpha: 0.45)
                  : AppColors.primary.withValues(alpha: 0.3),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isListening
                          ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: isRevising
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          )
                        : Icon(
                            isListening
                                ? Icons.graphic_eq_rounded
                                : Icons.volume_up_rounded,
                            size: 16,
                            color: isListening
                                ? const Color(0xFFEF4444)
                                : AppColors.primary,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isListening
                          ? 'Đang nghe yêu cầu chỉnh sửa (Ngày $selectedDay)...'
                          : isRevising
                              ? 'Linh AI đang cập nhật lịch trình...'
                              : 'Linh AI phản hồi trực tiếp',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isListening
                            ? const Color(0xFFDC2626)
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (isListening) ...[
                    TextButton(
                      onPressed: () {
                        ref
                            .read(voiceAssistantProvider.notifier)
                            .cancelDirectTripVoiceEdit();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Huỷ',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (transcript.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () {
                          ref
                              .read(voiceAssistantProvider.notifier)
                              .toggleDirectTripVoiceEdit(
                                trip: trip,
                                targetDay: selectedDay,
                              );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          'Gửi ngay',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ] else if (isSpeaking) ...[
                    TextButton.icon(
                      onPressed: () {
                        final notifier = ref.read(voiceAssistantProvider.notifier);
                        notifier.stopAudio();
                        Future.delayed(const Duration(milliseconds: 120), () {
                          if (mounted) {
                            notifier.toggleDirectTripVoiceEdit(
                              trip: trip,
                              targetDay: selectedDay,
                            );
                          }
                        });
                      },
                      icon: const Icon(Icons.mic_rounded, size: 15),
                      label: const Text(
                        'Nói tiếp',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () {
                        ref.read(voiceAssistantProvider.notifier).stopAudio();
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Đóng',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                transcript.isNotEmpty
                    ? (isListening ? '"$transcript"' : transcript)
                    : 'Hãy nói trực tiếp, ví dụ: "Đổi buổi tối đi ăn hải sản" hoặc "Ngày 2 đi Bà Nà Hills"...',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontStyle:
                      transcript.isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: transcript.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = ref.watch(selectedDayProvider);
    final voiceState = ref.watch(voiceAssistantProvider);

    ref.listen<VoiceAssistantState>(voiceAssistantProvider, (prev, next) {
      if (!mounted) return;

      // Thông báo khi hoàn tất chỉnh sửa bằng giọng nói trực tiếp
      if (prev?.planningState == TripPlanningState.revising &&
          next.planningState != TripPlanningState.revising &&
          !_isEditing) {
        if (next.error == null) {
          if (_isAiModalOpen &&
              _modalVoiceTriggered &&
              _activeModalContext != null &&
              _activeModalContext!.mounted) {
            _editController.clear();
            Navigator.of(_activeModalContext!).pop();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Linh AI đã cập nhật lịch trình ngay tại trang!'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.error!),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } else if (prev?.voiceState != VoiceState.error &&
          next.voiceState == VoiceState.error &&
          next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    final rawInitialId = widget.tripId ?? widget.initialTrip?.id;
    final effectiveTripId = (rawInitialId != null && rawInitialId.isNotEmpty)
        ? rawInitialId
        : voiceState.savedTripId;

    final AsyncValue<Trip?>? tripAsync =
        (effectiveTripId != null && effectiveTripId.isNotEmpty)
            ? ref.watch(tripDetailProvider(effectiveTripId))
            : null;

    final bool isLoadingDetail = tripAsync?.isLoading ?? false;
    final Trip? resolvedFromApi = tripAsync?.valueOrNull;

    final bool voicePreviewMatches = voiceState.tripPreview != null &&
        ((effectiveTripId != null &&
                effectiveTripId.isNotEmpty &&
                voiceState.tripPreview!.id == effectiveTripId) ||
            (rawInitialId == null || rawInitialId.isEmpty));

    // Ưu tiên bản vừa được cập nhật tức thì trong lúc provider đang tải lại dữ liệu từ API
    final Trip trip = (voicePreviewMatches &&
            (resolvedFromApi == null ||
                tripAsync?.isRefreshing == true ||
                tripAsync?.isReloading == true))
        ? voiceState.tripPreview!
        : (resolvedFromApi ??
            (voicePreviewMatches ? voiceState.tripPreview : null) ??
            widget.initialTrip ??
            mockTripDetail);

    // Đảm bảo ngày đang chọn luôn hợp lệ nếu tổng số ngày lịch trình vừa được rút gọn
    if (trip.days.isNotEmpty && !trip.days.any((d) => d.dayIndex == selectedDay)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(selectedDayProvider.notifier).state = trip.days.first.dayIndex;
        }
      });
    }

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

    final bool isListening = voiceState.isRecording ||
        voiceState.voiceState == VoiceState.connecting ||
        voiceState.voiceState == VoiceState.listening;
    final bool isRevising =
        _isEditing || voiceState.planningState == TripPlanningState.revising;
    final bool isSpeaking = voiceState.voiceState == VoiceState.speaking;
    final bool showDirectVoiceBanner =
        !_isAiModalOpen && (isListening || isRevising || isSpeaking);

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
                        SizedBox(height: showDirectVoiceBanner ? 210 : 140),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (showDirectVoiceBanner)
              _buildDirectVoiceBanner(
                context: context,
                voiceState: voiceState,
                trip: trip,
                selectedDay: selectedDay,
                isListening: isListening,
                isRevising: isRevising,
                isSpeaking: isSpeaking,
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
              onVoiceEdit: () {
                ref
                    .read(voiceAssistantProvider.notifier)
                    .toggleDirectTripVoiceEdit(
                      trip: trip,
                      targetDay: selectedDay,
                    );
              },
              onAiEdit: () => _showAiEditModal(context, trip, selectedDay),
              isListening: isListening,
              isRevising: isRevising,
              isSpeaking: isSpeaking,
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
