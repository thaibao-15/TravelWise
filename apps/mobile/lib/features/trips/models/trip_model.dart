class Trip {
  final String id;
  final String title;
  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final int daysCount;
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
    int? daysCount,
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
  }) : daysCount = daysCount ??
            (days.isNotEmpty
                ? days.length
                : (endDate.difference(startDate).inDays + 1).clamp(1, 365));

  static String _formatCost(double cost, [String currency = 'VND']) {
    if (cost <= 0) return 'Chưa tính';
    if (currency.toUpperCase() == 'VND' || cost >= 1000) {
      if (cost >= 1000000) {
        final millions = cost / 1000000.0;
        final str = millions == millions.roundToDouble()
            ? millions.toInt().toString()
            : millions.toStringAsFixed(1);
        return '${str}M đ';
      }
      if (cost >= 1000) {
        return '${(cost / 1000).round()}k đ';
      }
    }
    return '${cost.toStringAsFixed(0)} $currency';
  }

  static String _resolveCoverImage(Map<String, dynamic> json, String dest) {
    final explicit = json['cover_image']?.toString() ??
        json['cover_image_url']?.toString() ??
        json['image_url']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final lower = dest.toLowerCase();
    if (lower.contains('phú quốc') || lower.contains('phu quoc')) {
      return 'https://images.unsplash.com/photo-1588668214407-6ea9a6d8c272';
    }
    if (lower.contains('đà lạt') || lower.contains('da lat')) {
      return 'https://images.unsplash.com/photo-1626587979672-0050e828d506';
    }
    if (lower.contains('hội an') || lower.contains('hoi an')) {
      return 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1';
    }
    if (lower.contains('hà nội') || lower.contains('ha noi')) {
      return 'https://images.unsplash.com/photo-1509030450996-dd1a26dda07a';
    }
    if (lower.contains('sapa') || lower.contains('sa pa') || lower.contains('hà giang')) {
      return 'https://images.unsplash.com/photo-1528127269322-539801943592';
    }
    return 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b';
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d, [DateTime? fallback]) {
      if (d == null) return fallback ?? DateTime.now();
      try {
        return DateTime.parse(d.toString());
      } catch (_) {
        return fallback ?? DateTime.now();
      }
    }

    final rawDays = (json['days'] ?? json['itinerary_days'] ?? []) as List<dynamic>;
    int dayCount = 1;
    final parsedDays = rawDays.map((d) {
      final dayMap = d as Map<String, dynamic>;
      return TripDay.fromJson(dayMap, defaultIndex: dayCount++);
    }).toList();

    final parsedDaysCount = (json['days_count'] as num?)?.toInt() ??
        (json['duration_days'] as num?)?.toInt() ??
        (json['total_days'] as num?)?.toInt() ??
        (parsedDays.isNotEmpty ? parsedDays.length : null);

    DateTime startDate = parseDate(
      json['start_date'] ?? json['startDate'],
      parsedDays.isNotEmpty ? parsedDays.first.date : DateTime.now(),
    );

    DateTime endDate = parseDate(
      json['end_date'] ?? json['endDate'],
      parsedDays.isNotEmpty
          ? parsedDays.last.date
          : startDate.add(Duration(days: ((parsedDaysCount ?? 3) - 1).clamp(0, 365))),
    );

    final effectiveDaysCount = parsedDaysCount ??
        (parsedDays.isNotEmpty
            ? parsedDays.length
            : (endDate.difference(startDate).inDays + 1).clamp(1, 365));

    int totalStopsCount = 0;
    double summedDistanceKm = 0.0;
    double summedCost = 0.0;
    for (final day in parsedDays) {
      for (final act in day.activities) {
        if (!act.isTransfer) {
          totalStopsCount++;
        }
        if (act.travelDistanceKm != null) {
          summedDistanceKm += act.travelDistanceKm!;
        }
        if (act.estimatedCost != null) {
          summedCost += act.estimatedCost!;
        }
      }
    }

    final resolvedTotalStops = totalStopsCount > 0
        ? totalStopsCount
        : ((json['total_activities'] as num?)?.toInt() ??
            (json['total_stops'] as num?)?.toInt() ??
            0);

    final resolvedDistanceKm = (json['distance_km'] as num?)?.toDouble() ??
        (summedDistanceKm > 0
            ? double.parse(summedDistanceKm.toStringAsFixed(1))
            : (resolvedTotalStops > 0
                ? double.parse((resolvedTotalStops * 3.2).toStringAsFixed(1))
                : 0.0));

    final currency = json['currency']?.toString() ?? 'VND';
    String budgetStr = json['estimated_budget']?.toString() ?? '';
    if (budgetStr.isEmpty) {
      final totalCostNum = (json['estimated_total_cost'] as num?)?.toDouble() ??
          (json['budget'] is Map
              ? ((json['budget']['estimated_total'] ?? json['budget']['target_total']) as num?)?.toDouble()
              : null) ??
          (summedCost > 0 ? summedCost : null);
      if (totalCostNum != null && totalCostNum > 0) {
        budgetStr = _formatCost(totalCostNum, currency);
      } else {
        budgetStr = 'Tối ưu';
      }
    }

    String dest = json['destination']?.toString() ??
        json['destination_city']?.toString() ??
        'Việt Nam';
    if (json['destination_country'] != null &&
        json['destination_city'] != null &&
        !dest.contains(json['destination_country'].toString())) {
      dest = '$dest, ${json['destination_country']}';
    }

    final rawTitle = json['title']?.toString() ?? json['name']?.toString();
    final title = (rawTitle != null && rawTitle.trim().isNotEmpty)
        ? rawTitle.trim()
        : 'Chuyến du lịch $dest';

    final statusStr = json['status']?.toString() ?? 'CONFIRMED';
    final statusUpper = statusStr.toUpperCase();

    final double resolvedProgress = (json['progress'] as num?)?.toDouble() ??
        (statusUpper == 'COMPLETED'
            ? 1.0
            : (statusUpper == 'CONFIRMED' || statusUpper == 'UPCOMING'
                ? 0.85
                : (statusUpper == 'GENERATED' || statusUpper == 'PLANNING'
                    ? 0.6
                    : 0.25)));

    Map<String, bool>? parsedChecklist;
    if (json['checklist'] is Map) {
      parsedChecklist = (json['checklist'] as Map).map(
        (k, v) => MapEntry(k.toString(), v == true),
      );
    } else {
      parsedChecklist = {
        'Lịch trình AI': parsedDays.isNotEmpty || statusUpper == 'CONFIRMED' || statusUpper == 'GENERATED',
        'Điểm tham quan': resolvedTotalStops > 0 || statusUpper == 'CONFIRMED',
        'Lộ trình bản đồ': true,
        'Xác nhận': statusUpper == 'CONFIRMED' || statusUpper == 'COMPLETED',
      };
    }

    return Trip(
      id: (json['id'] ?? json['trip_id'] ?? '').toString(),
      title: title,
      destination: dest,
      startDate: startDate,
      endDate: endDate,
      daysCount: effectiveDaysCount,
      travelers: (json['travelers'] ?? json['traveler_count'] as num?)?.toInt() ?? 2,
      totalStops: resolvedTotalStops,
      distanceKm: resolvedDistanceKm,
      estimatedBudget: budgetStr,
      optimized: json['optimized'] as bool? ?? true,
      coverImage: _resolveCoverImage(json, dest),
      days: parsedDays,
      status: statusStr,
      category: json['category']?.toString() ??
          json['trip_type']?.toString() ??
          'Khám phá & Trải nghiệm',
      progress: resolvedProgress,
      aiPlanned: json['ai_planned'] as bool? ?? true,
      checklist: parsedChecklist,
      conversationId: (json['conversation_id'] as num?)?.toInt(),
      rawJson: json,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'name': title,
      'destination': destination,
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'duration_days': daysCount,
      'total_days': daysCount,
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
    int? daysCount,
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
      daysCount: daysCount ?? this.daysCount,
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
  final int? id;
  final int dayIndex;
  final DateTime date;
  final String title;
  final String subtitle;
  final List<ItineraryActivity> activities;

  TripDay({
    this.id,
    required this.dayIndex,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.activities,
  });

  factory TripDay.fromJson(Map<String, dynamic> json, {int defaultIndex = 1}) {
    final dayId = (json['id'] as num?)?.toInt();
    final idx = (json['day_number'] ?? json['day_index'] ?? json['day'] as num?)?.toInt() ?? defaultIndex;
    DateTime parsedDate;
    try {
      parsedDate = json['date'] != null
          ? DateTime.parse(json['date'].toString())
          : DateTime.now().add(Duration(days: idx - 1));
    } catch (_) {
      parsedDate = DateTime.now().add(Duration(days: idx - 1));
    }

    final rawActs = (json['activities'] ?? json['itinerary_activities'] ?? []) as List<dynamic>;
    int actIdx = 1;
    final parsedActs = rawActs.map((a) {
      final actMap = a as Map<String, dynamic>;
      return ItineraryActivity.fromJson(actMap, defaultOrder: actIdx++);
    }).toList();

    final dayTitle = json['title']?.toString() ??
        json['theme']?.toString() ??
        'Khám phá ngày $idx';
    final daySubtitle = json['subtitle']?.toString() ??
        json['description']?.toString() ??
        'Ngày $idx (${parsedDate.day}/${parsedDate.month}/${parsedDate.year}) · ${parsedActs.length} hoạt động';

    return TripDay(
      id: dayId,
      dayIndex: idx,
      date: parsedDate,
      title: dayTitle,
      subtitle: daySubtitle,
      activities: parsedActs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'day_number': dayIndex,
      'date': date.toIso8601String().split('T')[0],
      'title': title,
      'description': subtitle,
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
  final int? durationMinutes;
  final int? travelDurationMinutes;
  final double? travelDistanceKm;
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
    this.durationMinutes,
    this.travelDurationMinutes,
    this.travelDistanceKm,
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

  static String _localizeActivityCategory(String raw) {
    switch (raw.toUpperCase()) {
      case 'VISIT':
      case 'ATTRACTION':
      case 'SIGHTSEEING':
        return 'Tham quan';
      case 'MEAL':
      case 'RESTAURANT':
      case 'FOOD':
        return 'Ẩm thực';
      case 'CAFE':
        return 'Cà phê & Check-in';
      case 'REST':
      case 'HOTEL':
        return 'Nghỉ ngơi';
      case 'CHECKIN':
        return 'Check-in';
      case 'ENTERTAINMENT':
      case 'NIGHTLIFE':
        return 'Giải trí';
      case 'TRANSIT':
        return 'Di chuyển';
      case 'BEACH':
        return 'Biển & Thư giãn';
      case 'NATURE':
        return 'Thiên nhiên';
      case 'CULTURE':
        return 'Văn hóa & Lịch sử';
      default:
        return raw.isNotEmpty ? raw : 'Địa điểm';
    }
  }

  static String _formatMinutes(int mins) {
    if (mins <= 0) return '';
    if (mins < 60) return '$mins phút';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return '${h}h';
    return '${h}h${m}p';
  }

  factory ItineraryActivity.fromJson(Map<String, dynamic> json, {int defaultOrder = 1}) {
    final placeMap = json['place'] is Map<String, dynamic>
        ? json['place'] as Map<String, dynamic>
        : null;

    final placeId = (json['place_id'] ?? placeMap?['place_id'] ?? placeMap?['id'] as num?)?.toInt();
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

    final rawCategory = json['category']?.toString() ??
        placeMap?['category']?.toString() ??
        json['activity_type']?.toString() ??
        'VISIT';
    final category = _localizeActivityCategory(rawCategory);

    final order = (json['order_index'] ?? json['activity_order'] ?? json['order'] as num?)?.toInt() ?? defaultOrder;
    final durationMins = (json['duration_minutes'] as num?)?.toInt();
    final travelMins = (json['travel_duration_minutes'] as num?)?.toInt();
    final travelKm = (json['travel_distance_km'] as num?)?.toDouble();

    String durationStr = json['duration']?.toString() ?? '';
    if (durationStr.isEmpty && durationMins != null && durationMins > 0) {
      durationStr = _formatMinutes(durationMins);
    }

    final noteStr = json['note']?.toString() ?? json['notes']?.toString();
    final descStr = json['description']?.toString() ??
        placeMap?['description']?.toString() ??
        noteStr ??
        '';

    return ItineraryActivity(
      id: (json['id'] ?? 'act_${order}_${title.hashCode}').toString(),
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      title: title,
      category: category,
      duration: durationStr,
      description: descStr,
      imageUrl: json['image_url']?.toString() ??
          json['imageUrl']?.toString() ??
          placeMap?['image_url']?.toString(),
      icon: json['icon']?.toString(),
      rating: (json['rating'] as num?)?.toDouble() ??
          (placeMap?['rating'] as num?)?.toDouble(),
      aiSuggestion: json['ai_suggestion']?.toString() ??
          json['aiSuggestion']?.toString() ??
          noteStr,
      bookingStatus: json['booking_status']?.toString() ??
          json['bookingStatus']?.toString(),
      overlayText: json['overlay_text']?.toString() ??
          json['overlayText']?.toString() ??
          (travelKm != null && travelKm > 0
              ? 'Cách điểm trước ${travelKm.toStringAsFixed(1)} km'
              : null),
      specialBadge: json['special_badge']?.toString() ??
          json['specialBadge']?.toString(),
      isTransfer: json['is_transfer'] as bool? ??
          json['isTransfer'] as bool? ??
          false,
      placeId: placeId,
      placeName: pName,
      placeAddress: pAddress,
      latitude: lat,
      longitude: lng,
      activityOrder: order,
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble(),
      durationMinutes: durationMins,
      travelDurationMinutes: travelMins,
      travelDistanceKm: travelKm,
      activityType: json['activity_type']?.toString() ?? 'VISIT',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order_index': activityOrder ?? 1,
      'activity_order': activityOrder ?? 1,
      'place_id': placeId,
      'title': title,
      'description': description,
      'start_time': startTime.isNotEmpty ? startTime : null,
      'end_time': endTime.isNotEmpty ? endTime : null,
      'duration_minutes': durationMinutes,
      'travel_duration_minutes': travelDurationMinutes,
      'travel_distance_km': travelDistanceKm,
      'activity_type': activityType ?? 'VISIT',
      'estimated_cost': estimatedCost,
      'note': aiSuggestion,
      'place': placeId != null
          ? {
              'place_id': placeId,
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
