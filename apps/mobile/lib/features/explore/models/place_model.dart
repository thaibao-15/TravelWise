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
  });
}
