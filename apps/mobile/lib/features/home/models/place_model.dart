class Place {
  final int id;
  final String name;
  final String description;
  final double rating;
  final int reviewCount;
  final String imageUrl;
  final String? secondaryImageUrl;

  const Place({
    required this.id,
    required this.name,
    required this.description,
    required this.rating,
    required this.reviewCount,
    required this.imageUrl,
    this.secondaryImageUrl,
  });

  factory Place.fromJson(
    Map<String, dynamic> json, {
    required String imageBaseUrl,
  }) {
    final images = json['images'];
    final imageUrls = <String>[];
    if (images is List) {
      for (final image in images) {
        if (image is Map) {
          final url = image['url'] as String?;
          if (url != null && url.trim().isNotEmpty) {
            imageUrls.add(_resolveImageUrl(url, imageBaseUrl));
          }
        }
        if (imageUrls.length == 2) {
          break;
        }
      }
    }

    return Place(
      id: (json['id'] as num).toInt(),
      name: (json['name'] as String?) ?? 'Địa điểm chưa đặt tên',
      description: (json['description'] as String?)?.trim() ?? '',
      rating: (json['rating_avg'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      imageUrl: imageUrls.isEmpty ? '' : imageUrls.first,
      secondaryImageUrl: imageUrls.length > 1 ? imageUrls[1] : null,
    );
  }

  static String _resolveImageUrl(String url, String imageBaseUrl) {
    return url.startsWith('/') ? '$imageBaseUrl$url' : url;
  }
}
