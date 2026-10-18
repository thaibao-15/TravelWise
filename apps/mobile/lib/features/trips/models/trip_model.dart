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
  final String? status;
  final String? category;
  final double? progress;
  final bool? aiPlanned;
  final Map<String, bool>? checklist;
  final int? conversationId;
  final Map<String, dynamic>? rawJson;

  Trip({
    required this.id,
    required this.title,
    required this.destination,
    required this.startDate,
    required this.endDate,
    this.travelers = 2,
    this.totalStops = 0,
    this.distanceKm = 0.0,
    this.estimatedBudget = '',
    this.optimized = true,
    this.coverImage = 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
    required this.days,
    this.status,
    this.category,
    this.progress,
    this.aiPlanned,
    this.checklist,
    this.conversationId,
    this.rawJson,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d, [DateTime? fallback]) {
      if (d == null) return fallback ?? DateTime.now();
      try {
        return DateTime.parse(d.toString());
      } catch (_) {
        return fallback ?? DateTime.now();
      }
    }

    final startDate = parseDate(
      json['start_date'] ?? json['startDate'],
      DateTime.now(),
    );
    final endDate = parseDate(
      json['end_date'] ?? json['endDate'],
      startDate.add(const Duration(days: 3)),
    );

    final rawDays = (json['days'] ?? json['itinerary_days'] ?? []) as List<dynamic>;
    int dayCount = 1;
    final parsedDays = rawDays.map((d) {
      final dayMap = d as Map<String, dynamic>;
      return TripDay.fromJson(dayMap, defaultIndex: dayCount++);
    }).toList();

    int totalStopsCount = 0;
    for (final day in parsedDays) {
      totalStopsCount += day.activities.where((a) => !a.isTransfer).length;
    }

    String dest = json['destination']?.toString() ??
        json['destination_city']?.toString() ??
        'Việt Nam';
    if (json['destination_country'] != null &&
        json['destination_city'] != null &&
        !dest.contains(json['destination_country'].toString())) {
      dest = '$dest, ${json['destination_country']}';
    }

    return Trip(
      id: (json['id'] ?? json['trip_id'] ?? '').toString(),
      title: json['title']?.toString() ?? 'Chuyến du lịch $dest',
      destination: dest,
      startDate: startDate,
      endDate: endDate,
      travelers: (json['travelers'] ?? json['traveler_count'] as num?)?.toInt() ?? 2,
      totalStops: totalStopsCount > 0 ? totalStopsCount : ((json['total_stops'] as num?)?.toInt() ?? 0),
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      estimatedBudget: json['estimated_budget']?.toString() ?? '',
      optimized: json['optimized'] as bool? ?? true,
      coverImage: json['cover_image']?.toString() ??
          json['cover_image_url']?.toString() ??
          json['image_url']?.toString() ??
          'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
      days: parsedDays,
      status: json['status']?.toString() ?? 'CONFIRMED',
      category: json['category']?.toString() ?? json['trip_type']?.toString(),
      progress: (json['progress'] as num?)?.toDouble(),
      aiPlanned: json['ai_planned'] as bool? ?? true,
      conversationId: (json['conversation_id'] as num?)?.toInt(),
      rawJson: json,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'destination': destination,
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'total_days': days.length,
      'status': status,
      'conversation_id': conversationId,
      'days': days.map((d) => d.toJson()).toList(),
    };
  }

  Trip copyWith({
    String? id,
    String? title,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
    int? travelers,
    int? totalStops,
    double? distanceKm,
    String? estimatedBudget,
    bool? optimized,
    String? coverImage,
    List<TripDay>? days,
    String? status,
    String? category,
    double? progress,
    bool? aiPlanned,
    Map<String, bool>? checklist,
    int? conversationId,
    Map<String, dynamic>? rawJson,
  }) {
    return Trip(
      id: id ?? this.id,
      title: title ?? this.title,
      destination: destination ?? this.destination,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      travelers: travelers ?? this.travelers,
      totalStops: totalStops ?? this.totalStops,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedBudget: estimatedBudget ?? this.estimatedBudget,
      optimized: optimized ?? this.optimized,
      coverImage: coverImage ?? this.coverImage,
      days: days ?? this.days,
      status: status ?? this.status,
      category: category ?? this.category,
      progress: progress ?? this.progress,
      aiPlanned: aiPlanned ?? this.aiPlanned,
      checklist: checklist ?? this.checklist,
      conversationId: conversationId ?? this.conversationId,
      rawJson: rawJson ?? this.rawJson,
    );
  }
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

  factory TripDay.fromJson(Map<String, dynamic> json, {int defaultIndex = 1}) {
    final idx = (json['day_number'] ?? json['day_index'] ?? json['day'] as num?)?.toInt() ?? defaultIndex;
    DateTime parsedDate;
    try {
      parsedDate = json['date'] != null ? DateTime.parse(json['date'].toString()) : DateTime.now().add(Duration(days: idx - 1));
    } catch (_) {
      parsedDate = DateTime.now().add(Duration(days: idx - 1));
    }

    final rawActs = (json['activities'] ?? json['itinerary_activities'] ?? []) as List<dynamic>;
    int actIdx = 1;
    final parsedActs = rawActs.map((a) {
      final actMap = a as Map<String, dynamic>;
      return ItineraryActivity.fromJson(actMap, defaultOrder: actIdx++);
    }).toList();

    return TripDay(
      dayIndex: idx,
      date: parsedDate,
      title: json['theme']?.toString() ?? json['title']?.toString() ?? 'Ngày $idx',
      subtitle: json['subtitle']?.toString() ?? 'Ngày $idx · ${parsedActs.length} hoạt động',
      activities: parsedActs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_number': dayIndex,
      'date': date.toIso8601String().split('T')[0],
      'theme': title,
      'activities': activities.map((a) => a.toJson()).toList(),
    };
  }
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

  // Real place and geolocation properties
  final int? placeId;
  final String? placeName;
  final String? placeAddress;
  final double? latitude;
  final double? longitude;
  final int? activityOrder;
  final double? estimatedCost;
  final String? activityType;

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
    this.placeId,
    this.placeName,
    this.placeAddress,
    this.latitude,
    this.longitude,
    this.activityOrder,
    this.estimatedCost,
    this.activityType,
  });

  bool get hasValidCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude! >= -90.0 &&
      latitude! <= 90.0 &&
      longitude! >= -180.0 &&
      longitude! <= 180.0 &&
      (latitude != 0.0 || longitude != 0.0);

  factory ItineraryActivity.fromJson(Map<String, dynamic> json, {int defaultOrder = 1}) {
    final placeMap = json['place'] is Map<String, dynamic> ? json['place'] as Map<String, dynamic> : null;

    final placeId = (json['place_id'] ?? placeMap?['id'] as num?)?.toInt();
    final pName = placeMap?['name']?.toString() ?? json['place_name']?.toString();
    final pAddress = placeMap?['address']?.toString() ?? json['address']?.toString();

    double? lat;
    if (placeMap?['latitude'] != null) {
      lat = (placeMap!['latitude'] as num).toDouble();
    } else if (json['latitude'] != null) {
      lat = (json['latitude'] as num).toDouble();
    }

    double? lng;
    if (placeMap?['longitude'] != null) {
      lng = (placeMap!['longitude'] as num).toDouble();
    } else if (json['longitude'] != null) {
      lng = (json['longitude'] as num).toDouble();
    }

    final title = json['title']?.toString() ??
        json['custom_title']?.toString() ??
        pName ??
        'Hoạt động tham quan';

    final category = json['category']?.toString() ??
        json['activity_type']?.toString() ??
        placeMap?['category']?.toString() ??
        'Địa điểm';

    final order = (json['activity_order'] ?? json['order'] as num?)?.toInt() ?? defaultOrder;

    return ItineraryActivity(
      id: (json['id'] ?? 'act_$order').toString(),
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      title: title,
      category: category,
      duration: json['duration']?.toString() ?? '',
      description: json['description']?.toString() ?? json['notes']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? json['imageUrl']?.toString() ?? placeMap?['image_url']?.toString(),
      icon: json['icon']?.toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? (placeMap?['rating'] as num?)?.toDouble(),
      aiSuggestion: json['ai_suggestion']?.toString() ?? json['aiSuggestion']?.toString(),
      bookingStatus: json['booking_status']?.toString() ?? json['bookingStatus']?.toString(),
      overlayText: json['overlay_text']?.toString() ?? json['overlayText']?.toString(),
      specialBadge: json['special_badge']?.toString() ?? json['specialBadge']?.toString(),
      isTransfer: json['is_transfer'] as bool? ?? json['isTransfer'] as bool? ?? false,
      placeId: placeId,
      placeName: pName,
      placeAddress: pAddress,
      latitude: lat,
      longitude: lng,
      activityOrder: order,
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble(),
      activityType: json['activity_type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'activity_order': activityOrder ?? 1,
      'place_id': placeId,
      'title': title,
      'description': description,
      'start_time': startTime,
      'end_time': endTime,
      'activity_type': activityType ?? category,
      'estimated_cost': estimatedCost,
      'place': placeId != null
          ? {
              'id': placeId,
              'name': placeName ?? title,
              'address': placeAddress,
              'latitude': latitude,
              'longitude': longitude,
              'category': category,
            }
          : null,
    };
  }
}
