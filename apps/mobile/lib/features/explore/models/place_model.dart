class Place {
  final String id;
  final String name;
  final String description;
  final double rating;
  final int reviews;
  final double distance;
  final String imageUrl;
  final String price;
  final bool isOpen;
  final List<String> tags;
  final String? topReviewSnippet;
  final String? topReviewAuthor;

  Place({
    required this.id,
    required this.name,
    required this.description,
    required this.rating,
    required this.reviews,
    required this.distance,
    required this.imageUrl,
    required this.price,
    this.isOpen = true,
    this.tags = const [],
    this.topReviewSnippet,
    this.topReviewAuthor,
  });

  Place copyWith({
    String? id,
    String? name,
    String? description,
    double? rating,
    int? reviews,
    double? distance,
    String? imageUrl,
    String? price,
    bool? isOpen,
    List<String>? tags,
    String? topReviewSnippet,
    String? topReviewAuthor,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      reviews: reviews ?? this.reviews,
      distance: distance ?? this.distance,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      isOpen: isOpen ?? this.isOpen,
      tags: tags ?? this.tags,
      topReviewSnippet: topReviewSnippet ?? this.topReviewSnippet,
      topReviewAuthor: topReviewAuthor ?? this.topReviewAuthor,
    );
  }
}
