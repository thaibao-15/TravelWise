class ReviewAuthor {
  final int id;
  final String email;
  final String? fullName;
  final String? avatarUrl;

  const ReviewAuthor({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
  });

  factory ReviewAuthor.fromJson(Map<String, dynamic> json) {
    return ReviewAuthor(
      id: json['id'] as int? ?? 0,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'avatar_url': avatarUrl,
      };
}

class ReviewImage {
  final int id;
  final int reviewId;
  final String imageUrl;
  final String? caption;
  final int displayOrder;
  final DateTime createdAt;

  const ReviewImage({
    required this.id,
    required this.reviewId,
    required this.imageUrl,
    this.caption,
    this.displayOrder = 0,
    required this.createdAt,
  });

  factory ReviewImage.fromJson(Map<String, dynamic> json) {
    return ReviewImage(
      id: json['id'] as int? ?? 0,
      reviewId: json['review_id'] as int? ?? 0,
      imageUrl: json['image_url'] as String? ?? '',
      caption: json['caption'] as String?,
      displayOrder: json['display_order'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class PlaceReview {
  final int id;
  final int placeId;
  final int userId;
  final int rating;
  final String? title;
  final String? comment;
  final String? tripType; // solo, couple, family, friends, business
  final DateTime? visitedAt;
  final int helpfulCount;
  final String? ownerReply;
  final DateTime? ownerRepliedAt;
  final bool isVisible;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ReviewImage> images;
  final ReviewAuthor? user;
  final bool isHelpfulVoted;

  const PlaceReview({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.rating,
    this.title,
    this.comment,
    this.tripType,
    this.visitedAt,
    this.helpfulCount = 0,
    this.ownerReply,
    this.ownerRepliedAt,
    this.isVisible = true,
    required this.createdAt,
    required this.updatedAt,
    this.images = const [],
    this.user,
    this.isHelpfulVoted = false,
  });

  PlaceReview copyWith({
    int? helpfulCount,
    bool? isHelpfulVoted,
    String? ownerReply,
    DateTime? ownerRepliedAt,
  }) {
    return PlaceReview(
      id: id,
      placeId: placeId,
      userId: userId,
      rating: rating,
      title: title,
      comment: comment,
      tripType: tripType,
      visitedAt: visitedAt,
      helpfulCount: helpfulCount ?? this.helpfulCount,
      ownerReply: ownerReply ?? this.ownerReply,
      ownerRepliedAt: ownerRepliedAt ?? this.ownerRepliedAt,
      isVisible: isVisible,
      createdAt: createdAt,
      updatedAt: updatedAt,
      images: images,
      user: user,
      isHelpfulVoted: isHelpfulVoted ?? this.isHelpfulVoted,
    );
  }

  static String getTripTypeLabel(String? tripType) {
    switch (tripType?.toLowerCase()) {
      case 'solo':
        return '🎒 Một mình';
      case 'couple':
        return '💑 Cặp đôi';
      case 'family':
        return '👨‍👩‍👦 Gia đình';
      case 'friends':
        return '👥 Bạn bè';
      case 'business':
        return '💼 Công tác';
      default:
        return 'Trải nghiệm du lịch';
    }
  }

  factory PlaceReview.fromJson(Map<String, dynamic> json) {
    return PlaceReview(
      id: json['id'] as int? ?? 0,
      placeId: json['place_id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      rating: json['rating'] as int? ?? 5,
      title: json['title'] as String?,
      comment: json['comment'] as String?,
      tripType: json['trip_type'] as String?,
      visitedAt: json['visited_at'] != null
          ? DateTime.tryParse(json['visited_at'].toString())
          : null,
      helpfulCount: json['helpful_count'] as int? ?? 0,
      ownerReply: json['owner_reply'] as String?,
      ownerRepliedAt: json['owner_replied_at'] != null
          ? DateTime.tryParse(json['owner_replied_at'].toString())
          : null,
      isVisible: json['is_visible'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      images: (json['images'] as List<dynamic>? ?? [])
          .map((img) => ReviewImage.fromJson(img as Map<String, dynamic>))
          .toList(),
      user: json['user'] != null
          ? ReviewAuthor.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      isHelpfulVoted: json['is_helpful_voted'] as bool? ?? false,
    );
  }
}

class PlaceReviewList {
  final int total;
  final double ratingAvg;
  final Map<int, int> ratingBreakdown;
  final List<PlaceReview> items;

  const PlaceReviewList({
    required this.total,
    required this.ratingAvg,
    required this.ratingBreakdown,
    required this.items,
  });

  factory PlaceReviewList.fromJson(Map<String, dynamic> json) {
    final breakdownMap = <int, int>{};
    if (json['rating_breakdown'] is Map) {
      (json['rating_breakdown'] as Map).forEach((k, v) {
        final keyInt = int.tryParse(k.toString());
        if (keyInt != null) {
          breakdownMap[keyInt] = (v as num).toInt();
        }
      });
    }

    return PlaceReviewList(
      total: json['total'] as int? ?? 0,
      ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0.0,
      ratingBreakdown: breakdownMap,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => PlaceReview.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

