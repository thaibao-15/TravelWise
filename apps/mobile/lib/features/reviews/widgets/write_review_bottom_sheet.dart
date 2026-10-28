import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';

class WriteReviewBottomSheet extends StatefulWidget {
  final int placeId;
  final String placeName;
  final ValueChanged<PlaceReview> onReviewSubmitted;
  final PlaceReview? reviewToEdit;

  const WriteReviewBottomSheet({
    super.key,
    required this.placeId,
    required this.placeName,
    required this.onReviewSubmitted,
    this.reviewToEdit,
  });

  static Future<void> show({
    required BuildContext context,
    required int placeId,
    required String placeName,
    required ValueChanged<PlaceReview> onReviewSubmitted,
    PlaceReview? reviewToEdit,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => WriteReviewBottomSheet(
        placeId: placeId,
        placeName: placeName,
        onReviewSubmitted: onReviewSubmitted,
        reviewToEdit: reviewToEdit,
      ),
    );
  }

  @override
  State<WriteReviewBottomSheet> createState() => _WriteReviewBottomSheetState();
}

class _WriteReviewBottomSheetState extends State<WriteReviewBottomSheet> {
  late int _rating;
  String? _selectedTripType = 'couple';
  late DateTime _visitedAt;
  final _titleController = TextEditingController();
  final _commentController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final List<String> _attachedImages = [];

  bool _isSubmitting = false;

  final List<Map<String, String>> _tripTypes = [
    {'key': 'solo', 'label': '🎒 Một mình'},
    {'key': 'couple', 'label': '💑 Cặp đôi'},
    {'key': 'family', 'label': '👨‍👩‍👦 Gia đình'},
    {'key': 'friends', 'label': '👥 Bạn bè'},
    {'key': 'business', 'label': '💼 Công tác'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _commentController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final review = widget.reviewToEdit;
    _rating = review?.rating ?? 5;
    _selectedTripType = review?.tripType ?? 'couple';
    _visitedAt = review?.visitedAt ?? DateTime.now();
    _titleController.text = review?.title ?? '';
    _commentController.text = review?.comment ?? '';
  }

  Future<void> _submit() async {
    if (_commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập nội dung đánh giá của bạn')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final service = ReviewService();
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : null;
      final comment = _commentController.text.trim();
      final newReview = widget.reviewToEdit == null
          ? await service.createReview(
              placeId: widget.placeId,
              rating: _rating,
              title: title,
              comment: comment,
              tripType: _selectedTripType,
              visitedAt: _visitedAt,
              imageUrls: _attachedImages,
            )
          : await service.updateReview(
              reviewId: widget.reviewToEdit!.id,
              rating: _rating,
              title: title,
              comment: comment,
              tripType: _selectedTripType,
              visitedAt: _visitedAt,
            );

      if (!mounted) return;
      widget.onReviewSubmitted(newReview);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final errorMsg = e.toString().contains('401')
          ? 'Vui lòng đăng nhập để gửi bài đánh giá.'
          : 'Không thể gửi đánh giá: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _addSampleImage() {
    setState(() {
      _attachedImages.add(
        'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 16,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.reviewToEdit == null
                            ? 'Viết đánh giá trải nghiệm'
                            : 'Sửa đánh giá của bạn',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.placeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Star Rating Picker
            Center(
              child: Column(
                children: [
                  const Text(
                    'Bạn chấm điểm địa điểm này thế nào?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      return IconButton(
                        iconSize: 36,
                        icon: Icon(
                          starValue <= _rating ? Icons.star : Icons.star_border,
                          color: AppColors.warning,
                        ),
                        onPressed: () => setState(() => _rating = starValue),
                      );
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Trip Type Selection
            const Text(
              'Chuyến đi này của bạn cùng với ai?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _tripTypes.map((type) {
                  final isSelected = _selectedTripType == type['key'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(type['label']!),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : AppColors.textPrimary,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedTripType = selected ? type['key'] : null;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 14),

            // Title input
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Tiêu đề ngắn (Ví dụ: Trải nghiệm tuyệt vời!)',
                labelStyle: const TextStyle(fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 12),

            // Comment input
            TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Chia sẻ chi tiết cảm nhận của bạn...',
                alignLabelWithHint: true,
                labelStyle: const TextStyle(fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),

            const SizedBox(height: 12),

            // Photos attachment
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _addSampleImage,
                  icon: const Icon(Icons.add_photo_alternate, size: 16),
                  label: const Text('Thêm ảnh', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _attachedImages
                          .map(
                            (img) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      img,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => setState(() =>
                                          _attachedImages.remove(img)),
                                      child: Container(
                                        color: Colors.black54,
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Đăng đánh giá',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
