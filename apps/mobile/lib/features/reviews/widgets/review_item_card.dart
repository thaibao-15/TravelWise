import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../models/review_model.dart';

class ReviewItemCard extends StatefulWidget {
  final PlaceReview review;
  final ValueChanged<PlaceReview>? onHelpfulToggled;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ReviewItemCard({
    super.key,
    required this.review,
    this.onHelpfulToggled,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<ReviewItemCard> createState() => _ReviewItemCardState();
}

class _ReviewItemCardState extends State<ReviewItemCard> {
  late bool _isHelpful;
  late int _helpfulCount;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isHelpful = widget.review.isHelpfulVoted;
    _helpfulCount = widget.review.helpfulCount;
  }

  void _toggleHelpful() {
    setState(() {
      _isHelpful = !_isHelpful;
      _helpfulCount += _isHelpful ? 1 : -1;
      if (_helpfulCount < 0) _helpfulCount = 0;
    });

    final updated = widget.review.copyWith(
      isHelpfulVoted: _isHelpful,
      helpfulCount: _helpfulCount,
    );
    widget.onHelpfulToggled?.call(updated);
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.review.user;
    final authorName = author?.fullName?.isNotEmpty == true
        ? author!.fullName!
        : (author?.email.split('@').first ?? 'Du khách TravelWise');

    final dateStr =
        '${widget.review.createdAt.day}/${widget.review.createdAt.month}/${widget.review.createdAt.year}';

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header Row
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryFixed,
                backgroundImage: author?.avatarUrl != null
                    ? NetworkImage(author!.avatarUrl!)
                    : null,
                child: author?.avatarUrl == null
                    ? Text(
                        authorName.isNotEmpty
                            ? authorName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (widget.review.visitedAt != null) ...[
                          const Text(
                            ' • ',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Đi T${widget.review.visitedAt!.month}/${widget.review.visitedAt!.year}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Rating stars
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < widget.review.rating
                        ? Icons.star
                        : Icons.star_border,
                    size: 14,
                    color: AppColors.warning,
                  );
                }),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Trip Type Badge (if any)
          if (widget.review.tripType != null &&
              widget.review.tripType!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                PlaceReview.getTripTypeLabel(widget.review.tripType),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

          // Review Title
          if (widget.review.title != null &&
              widget.review.title!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.review.title!,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

          // Review Comment Content
          if (widget.review.comment != null &&
              widget.review.comment!.trim().isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.review.comment!,
                  maxLines: _isExpanded ? null : 3,
                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                if ((widget.review.comment?.length ?? 0) > 120)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _isExpanded ? 'Thu gọn' : 'Xem thêm',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

          // Photos gallery
          if (widget.review.images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.review.images.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final img = widget.review.images[idx];
                  return GestureDetector(
                    onTap: () => _showImageDialog(context, img.imageUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        img.imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 72,
                          height: 72,
                          color: AppColors.surfaceContainerHigh,
                          child: const Icon(
                            Icons.broken_image,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // Official Owner Reply (if present)
          if (widget.review.ownerReply != null &&
              widget.review.ownerReply!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryFixedDim),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.verified, size: 14, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Phản hồi từ Quản lý địa điểm',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.review.ownerReply!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Helpful Action Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _toggleHelpful,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _isHelpful
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isHelpful ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isHelpful ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 13,
                        color: _isHelpful
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Hữu ích ($_helpfulCount)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _isHelpful
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: _isHelpful
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onEdit != null || widget.onDelete != null)
                PopupMenuButton<String>(
                  tooltip: 'Tùy chọn đánh giá',
                  onSelected: (action) {
                    if (action == 'edit') widget.onEdit?.call();
                    if (action == 'delete') widget.onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (widget.onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Sửa đánh giá'),
                        ),
                      ),
                    if (widget.onDelete != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                          title: Text(
                            'Xóa đánh giá',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ),
                  ],
                ),
              if (widget.onEdit == null && widget.onDelete == null)
                IconButton(
                  icon: const Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã nhận phản ánh về đánh giá này'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}