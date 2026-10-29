import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../auth/presentation/providers/auth_notifier.dart';
import '../../auth/presentation/providers/auth_state.dart';
import '../../home/providers/home_provider.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'review_item_card.dart';
import 'review_summary_card.dart';
import 'write_review_bottom_sheet.dart';

class PlaceReviewsSection extends ConsumerStatefulWidget {
  final int placeId;
  final String placeName;
  final double initialRating;
  final int initialReviewCount;

  const PlaceReviewsSection({
    super.key,
    required this.placeId,
    required this.placeName,
    required this.initialRating,
    required this.initialReviewCount,
  });

  @override
  ConsumerState<PlaceReviewsSection> createState() =>
      _PlaceReviewsSectionState();
}

class _PlaceReviewsSectionState extends ConsumerState<PlaceReviewsSection> {
  static const int _pageSize = 10;

  final ReviewService _reviewService = ReviewService();
  List<PlaceReview> _reviews = [];
  PlaceReview? _myReview;
  Map<int, int> _ratingBreakdown = const {};
  double _ratingAvg = 0;
  int _totalReviews = 0;
  bool _isLoading = true;
  bool _isLoadingMyReview = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  String? _myReviewError;

  @override
  void initState() {
    super.initState();
    _ratingAvg = widget.initialRating;
    _totalReviews = widget.initialReviewCount;
    _loadReviews();
    _loadMyReview();
  }

  Future<void> _loadMyReview() async {
    try {
      final review = await _reviewService.getMyPlaceReview(
        placeId: widget.placeId,
      );
      if (!mounted) return;
      setState(() {
        _myReview = review;
        _myReviewError = null;
        _isLoadingMyReview = false;
      });
    } catch (error) {
      if (!mounted) return;
      final isUnauthenticated =
          error is DioException &&
          (error.response?.statusCode == 401 ||
              error.response?.statusCode == 403);
      setState(() {
        _myReview = null;
        _myReviewError = isUnauthenticated
            ? null
            : 'Không thể kiểm tra đánh giá của bạn: $error';
        _isLoadingMyReview = false;
      });
    }
  }

  Future<void> _loadReviews({bool loadMore = false}) async {
    if (loadMore) {
      setState(() {
        _isLoadingMore = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _myReviewError = null;
      });
    }

    try {
      final result = await _reviewService.getPlaceReviews(
        placeId: widget.placeId,
        skip: loadMore ? _reviews.length : 0,
        limit: _pageSize,
      );
      if (!mounted) return;

      setState(() {
        _reviews = loadMore ? [..._reviews, ...result.items] : result.items;
        _totalReviews = result.total;
        _ratingAvg = result.total > 0 ? result.ratingAvg : widget.initialRating;
        _ratingBreakdown = result.ratingBreakdown;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = 'Không thể tải đánh giá: $error';
      });
    }
  }

  void _openReviewForm({PlaceReview? review}) {
    WriteReviewBottomSheet.show(
      context: context,
      placeId: widget.placeId,
      placeName: widget.placeName,
      reviewToEdit: review,
      onReviewSubmitted: (submittedReview) {
        setState(() {
          _myReview = submittedReview;
          _isLoadingMyReview = false;
          _myReviewError = null;
        });
        invalidatePlaceRatingProviders(ref, widget.placeId);
        _loadReviews();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              review == null
                  ? 'Đăng đánh giá thành công. Cảm ơn bạn!'
                  : 'Đã cập nhật đánh giá của bạn.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      },
    );
  }

  Future<void> _deleteReview(PlaceReview review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa đánh giá?'),
        content: const Text('Đánh giá này sẽ bị xóa và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _reviewService.deleteReview(reviewId: review.id);
      if (!mounted) return;
      setState(() {
        _myReview = null;
        _isLoadingMyReview = false;
      });
      invalidatePlaceRatingProviders(ref, widget.placeId);
      await _loadReviews();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã xóa đánh giá.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xóa đánh giá: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _toggleHelpful(PlaceReview review) async {
    try {
      final result = await _reviewService.toggleHelpfulVote(
        reviewId: review.id,
      );
      if (!mounted) return;
      final voted = result['voted'] as bool? ?? false;
      final count = result['helpful_count'] as int? ?? review.helpfulCount;
      setState(() {
        _reviews = _reviews
            .map(
              (item) => item.id == review.id
                  ? item.copyWith(isHelpfulVoted: voted, helpfulCount: count)
                  : item,
            )
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể cập nhật lượt hữu ích: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final currentUserId = authState is AuthAuthenticated
        ? authState.user.id
        : null;
    final visibleReviews = List<PlaceReview>.of(_reviews);
    final myReview = _myReview;
    if (myReview != null) {
      visibleReviews.removeWhere((review) => review.id == myReview.id);
      visibleReviews.insert(0, myReview);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Đánh giá & trải nghiệm',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _isLoadingMyReview
                  ? null
                  : _myReviewError != null
                  ? _loadMyReview
                  : _isLoading
                  ? null
                  : () => _openReviewForm(review: _myReview),
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: Text(
                _myReviewError != null
                    ? 'Thử tải lại'
                    : _isLoadingMyReview
                    ? 'Đang kiểm tra...'
                    : _myReview == null
                    ? 'Viết đánh giá'
                    : 'Sửa đánh giá',
              ),
            ),
          ],
        ),
        if (_myReviewError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              _myReviewError!,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        ReviewSummaryCard(
          ratingAvg: _ratingAvg,
          totalReviews: _totalReviews,
          ratingBreakdown: _ratingBreakdown,
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_errorMessage != null && _reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
                TextButton(
                  onPressed: _loadReviews,
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          )
        else if (visibleReviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.rate_review_outlined,
                    color: AppColors.textSecondary,
                    size: 36,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Chưa có đánh giá nào cho địa điểm này.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => _openReviewForm(),
                    child: const Text('Hãy là người đầu tiên đánh giá'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          for (final review in visibleReviews)
            ReviewItemCard(
              key: ValueKey(review.id),
              review: review,
              onHelpfulToggled: (_) => _toggleHelpful(review),
              onEdit: review.userId == currentUserId
                  ? () => _openReviewForm(review: review)
                  : null,
              onDelete: review.userId == currentUserId
                  ? () => _deleteReview(review)
                  : null,
            ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          if (_reviews.length < _totalReviews)
            Center(
              child: TextButton(
                onPressed: _isLoadingMore
                    ? null
                    : () => _loadReviews(loadMore: true),
                child: _isLoadingMore
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Xem thêm đánh giá'),
              ),
            ),
        ],
      ],
    );
  }
}
