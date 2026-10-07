class Trip {
  final String id;
  final String title;
  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final int travelers;
  final int totalStops;
  final double distanceKm;
  final String estimatedBudget;
  final bool optimized;
  final String coverImage;
  final List<TripDay> days;

  Trip({
    required this.id,
    required this.title,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.travelers,
    required this.totalStops,
    required this.distanceKm,
    required this.estimatedBudget,
    required this.optimized,
    required this.coverImage,
    required this.days,
  });
}

class TripDay {
  final int dayIndex;
  final DateTime date;
  final String title;
  final String subtitle;
  final List<ItineraryActivity> activities;

  TripDay({
    required this.dayIndex,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.activities,
  });
}

class ItineraryActivity {
  final String id;
  final String startTime;
  final String endTime;
  final String title;
  final String category;
  final String duration;
  final String description;
  final String? imageUrl;
  final String? icon;
  final double? rating;
  final String? aiSuggestion;
  final String? bookingStatus;
  final String? overlayText;
  final String? specialBadge;
  final bool isTransfer;

  ItineraryActivity({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.title,
    required this.category,
    required this.duration,
    required this.description,
    this.imageUrl,
    this.icon,
    this.rating,
    this.aiSuggestion,
    this.bookingStatus,
    this.overlayText,
    this.specialBadge,
    this.isTransfer = false,
  });
}
