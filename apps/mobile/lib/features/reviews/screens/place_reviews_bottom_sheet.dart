import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../auth/presentation/providers/auth_notifier.dart';
import '../../auth/presentation/providers/auth_state.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import '../widgets/review_filter_chips.dart';
import '../widgets/review_item_card.dart';
import '../widgets/review_summary_card.dart';
import '../widgets/write_review_bottom_sheet.dart';

class PlaceReviewsBottomSheet extends ConsumerStatefulWidget {
  final int placeId;
  final String placeName;
  final double ratingAvg;
  final int totalReviews;

  const PlaceReviewsBottomSheet({
    super.key,
    required this.placeId,
    required this.placeName,
    required this.ratingAvg,
    required this.totalReviews,
  });

  static Future<void> show({
    required BuildContext context,
    required int placeId,
    required String placeName,
    required double ratingAvg,
    required int totalReviews,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlaceReviewsBottomSheet(
        placeId: placeId,
        placeName: placeName,
        ratingAvg: ratingAvg,
        totalReviews: totalReviews,
      ),
    );
  }

  @override
  ConsumerState<PlaceReviewsBottomSheet> createState() =>
      _PlaceReviewsBottomSheetState();
}

class _PlaceReviewsBottomSheetState
    extends ConsumerState<PlaceReviewsBottomSheet> {
  final ReviewService _reviewService = ReviewService();

  int? _selectedRating;
  String? _selectedTripType;
  String _sortBy = 'newest';

  bool _isLoading = true;
  String? _errorMessage;

  List<PlaceReview> _reviews = [];
  late double _ratingAvg;
  late int _totalReviews;
  Map<int, int> _ratingBreakdown = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

  @override
  void initState() {
    super.initState();
    _ratingAvg = widget.ratingAvg;
    _totalReviews = widget.totalReviews;
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _reviewService.getPlaceReviews(
        placeId: widget.placeId,
        rating: _selectedRating,
        tripType: _selectedTripType,
        sortBy: _sortBy,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _reviews = res.items;
        _totalReviews = res.total;
        _ratingAvg = res.total > 0 ? res.ratingAvg : widget.ratingAvg;
        _ratingBreakdown = res.ratingBreakdown;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Không thể tải đánh giá từ máy chủ: $e';
      });
    }
  }

  Future<void> _onHelpfulToggled(PlaceReview review) async {
    try {
      final res = await _reviewService.toggleHelpfulVote(reviewId: review.id);
      if (!mounted) return;

      final updatedVoted = res['voted'] as bool? ?? false;
      final updatedCount = res['helpful_count'] as int? ?? review.helpfulCount;

      setState(() {
        final idx = _reviews.indexWhere((r) => r.id == review.id);
        if (idx != -1) {
          _reviews[idx] = _reviews[idx].copyWith(
            isHelpfulVoted: updatedVoted,
            helpfulCount: updatedCount,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('401')
                ? 'Vui lòng đăng nhập để bình chọn hữu ích.'
                : 'Không thể cập nhật lượt bình chọn: $e',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _onWriteReviewTap() {
    WriteReviewBottomSheet.show(
      context: context,
      placeId: widget.placeId,
      placeName: widget.placeName,
      onReviewSubmitted: (newReview) {
        // Reload reviews directly from backend API
        _fetchReviews();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Đăng đánh giá thành công! Cảm ơn bạn.'),
            backgroundColor: AppColors.success,
          ),
        );
      },
    );
  }

  void _onEditReviewTap(PlaceReview review) {
    WriteReviewBottomSheet.show(
      context: context,
      placeId: widget.placeId,
      placeName: widget.placeName,
      reviewToEdit: review,
      onReviewSubmitted: (_) {
        _fetchReviews();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật đánh giá của bạn.'),
            backgroundColor: AppColors.success,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Modal Top Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Đánh giá & Trải nghiệm',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.placeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _onWriteReviewTap,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Viết đánh giá'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Scrollable Review Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchReviews,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // 1. Review Summary Card
                  ReviewSummaryCard(
                    ratingAvg: _ratingAvg,
                    totalReviews: _totalReviews,
                    ratingBreakdown: _ratingBreakdown,
                  ),

                  const SizedBox(height: 8),

                  // 2. Filter & Sort Chips
                  ReviewFilterChips(
                    selectedRating: _selectedRating,
                    selectedTripType: _selectedTripType,
                    sortBy: _sortBy,
                    onRatingSelected: (val) {
                      setState(() => _selectedRating = val);
                      _fetchReviews();
                    },
                    onTripTypeSelected: (val) {
                      setState(() => _selectedTripType = val);
                      _fetchReviews();
                    },
                    onSortChanged: (val) {
                      setState(() => _sortBy = val);
                      _fetchReviews();
                    },
                  ),

                  const SizedBox(height: 12),

                  // 3. Status handling: Loading, Error, or Items
                  if (_isLoading)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            'Đang tải đánh giá từ máy chủ...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_errorMessage != null)
                    Container(
                      margin: const EdgeInsets.all(AppSpacing.lg),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _fetchReviews,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    )
                  else if (_reviews.isEmpty)
                    Container(
                      margin: const EdgeInsets.all(AppSpacing.xxl),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.rate_review_outlined,
                            size: 48,
                            color: AppColors.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Chưa có bài đánh giá nào cho địa điểm này',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Hãy là người đầu tiên chia sẻ cảm nhận!',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: _onWriteReviewTap,
                            icon: const Icon(Icons.rate_review, size: 16),
                            label: const Text('Viết đánh giá ngay'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._reviews.map(
                      (review) {
                        final authState = ref.watch(authProvider);
                        final isOwner = authState is AuthAuthenticated &&
                            authState.user.id == review.userId;
                        return ReviewItemCard(
                          review: review,
                          onHelpfulToggled: _onHelpfulToggled,
                          onEdit: isOwner
                              ? () => _onEditReviewTap(review)
                              : null,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
