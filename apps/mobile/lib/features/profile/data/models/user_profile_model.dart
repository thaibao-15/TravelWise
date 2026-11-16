import 'package:equatable/equatable.dart';
import '../../domain/entities/profile_entity.dart';

/// Model representing backend UserProfileResponse from `/api/v1/users/me/profile`.
class UserProfileModel extends Equatable {
  final int? id;
  final int? userId;
  final String? phone;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? nationality;
  final String preferredLanguage;
  final String? travelStyle;
  final List<String> favoriteCategories;
  final List<String> interests;
  final double? budgetMin;
  final double? budgetMax;
  final String currency;
  final String? preferredTransport;
  final String? accommodationType;
  final List<String> dietaryPreferences;
  final List<String> accessibilityNeeds;
  final String? preferredTravelPace;
  final String? additionalPreferences;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfileModel({
    this.id,
    this.userId,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.nationality,
    this.preferredLanguage = 'vi',
    this.travelStyle,
    this.favoriteCategories = const [],
    this.interests = const [],
    this.budgetMin,
    this.budgetMax,
    this.currency = 'VND',
    this.preferredTransport,
    this.accommodationType,
    this.dietaryPreferences = const [],
    this.accessibilityNeeds = const [],
    this.preferredTravelPace,
    this.additionalPreferences,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is DateTime) return val;
      if (val is String && val.isNotEmpty) {
        return DateTime.tryParse(val);
      }
      return null;
    }

    double? parseDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String && val.isNotEmpty) {
        return double.tryParse(val);
      }
      return null;
    }

    List<String> parseList(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      return const [];
    }

    return UserProfileModel(
      id: json['id'] as int?,
      userId: json['user_id'] as int?,
      phone: json['phone'] as String?,
      dateOfBirth: parseDate(json['date_of_birth']),
      gender: json['gender'] as String?,
      nationality: json['nationality'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'vi',
      travelStyle: json['travel_style'] as String?,
      favoriteCategories: parseList(json['favorite_categories']),
      interests: parseList(json['interests']),
      budgetMin: parseDouble(json['budget_min']),
      budgetMax: parseDouble(json['budget_max']),
      currency: json['currency'] as String? ?? 'VND',
      preferredTransport: json['preferred_transport'] as String?,
      accommodationType: json['accommodation_type'] as String?,
      dietaryPreferences: parseList(json['dietary_preferences']),
      accessibilityNeeds: parseList(json['accessibility_needs']),
      preferredTravelPace: json['preferred_travel_pace'] as String?,
      additionalPreferences: json['additional_preferences'] as String?,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    String? formatDate(DateTime? date) {
      if (date == null) return null;
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final data = <String, dynamic>{
      'phone': phone,
      'date_of_birth': formatDate(dateOfBirth),
      'gender': gender,
      'nationality': nationality,
      'preferred_language': preferredLanguage,
      'travel_style': travelStyle,
      'favorite_categories': favoriteCategories.isNotEmpty ? favoriteCategories : null,
      'interests': interests.isNotEmpty ? interests : null,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      'currency': currency,
      'preferred_transport': preferredTransport,
      'accommodation_type': accommodationType,
      'dietary_preferences': dietaryPreferences.isNotEmpty ? dietaryPreferences : null,
      'accessibility_needs': accessibilityNeeds.isNotEmpty ? accessibilityNeeds : null,
      'preferred_travel_pace': preferredTravelPace,
      'additional_preferences': additionalPreferences,
    };

    // Remove null keys for partial update cleanliness
    data.removeWhere((_, value) => value == null);
    return data;
  }

  /// Converts this model into a [TravelPreferences] object for existing UI widgets.
  TravelPreferences toTravelPreferences() {
    String styleDisplay = travelStyle ?? 'Khám phá (Adventure)';
    String styleEmoji = '🎒';
    if (styleDisplay.contains('Nghỉ dưỡng') || styleDisplay.contains('Relax')) {
      styleEmoji = '🏖️';
    } else if (styleDisplay.contains('Văn hóa') || styleDisplay.contains('Di sản')) {
      styleEmoji = '🏛️';
    } else if (styleDisplay.contains('Ẩm thực')) {
      styleEmoji = '🍜';
    } else if (styleDisplay.contains('Thiên nhiên')) {
      styleEmoji = '🌿';
    }

    String budgetDisplay = 'Vừa phải (Mid-range)';
    String budgetEmoji = '💳';
    if (budgetMin != null || budgetMax != null) {
      if (budgetMin != null && budgetMax != null) {
        budgetDisplay = '${_formatMoney(budgetMin!)} - ${_formatMoney(budgetMax!)} $currency';
      } else if (budgetMin != null) {
        budgetDisplay = 'Từ ${_formatMoney(budgetMin!)} $currency';
      } else if (budgetMax != null) {
        budgetDisplay = 'Dưới ${_formatMoney(budgetMax!)} $currency';
      }
    }

    String paceDisplay = preferredTravelPace ?? 'Cân bằng (Balanced)';
    String paceEmoji = '⚖️';
    if (paceDisplay.contains('Năng động') || paceDisplay.contains('Fast')) {
      paceEmoji = '⚡';
    } else if (paceDisplay.contains('Thư thả') || paceDisplay.contains('Slow')) {
      paceEmoji = '☕';
    }

    final categories = favoriteCategories.isNotEmpty
        ? favoriteCategories
        : const ['🏖️ Bãi biển', '🍜 Ẩm thực', '🏛️ Văn hóa', '🌿 Thiên nhiên'];

    return TravelPreferences(
      style: styleDisplay,
      styleEmoji: styleEmoji,
      budget: budgetDisplay,
      budgetEmoji: budgetEmoji,
      pace: paceDisplay,
      paceEmoji: paceEmoji,
      favoriteCategories: categories,
    );
  }

  String _formatMoney(double amount) {
    if (amount >= 1000000) {
      final millions = amount / 1000000;
      return millions == millions.roundToDouble()
          ? '${millions.toInt()}tr'
          : '${millions.toStringAsFixed(1)}tr';
    } else if (amount >= 1000) {
      final thousands = amount / 1000;
      return '${thousands.toInt()}k';
    }
    return amount.toInt().toString();
  }

  UserProfileModel copyWith({
    int? id,
    int? userId,
    String? phone,
    DateTime? dateOfBirth,
    String? gender,
    String? nationality,
    String? preferredLanguage,
    String? travelStyle,
    List<String>? favoriteCategories,
    List<String>? interests,
    double? budgetMin,
    double? budgetMax,
    String? currency,
    String? preferredTransport,
    String? accommodationType,
    List<String>? dietaryPreferences,
    List<String>? accessibilityNeeds,
    String? preferredTravelPace,
    String? additionalPreferences,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfileModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      nationality: nationality ?? this.nationality,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      travelStyle: travelStyle ?? this.travelStyle,
      favoriteCategories: favoriteCategories ?? this.favoriteCategories,
      interests: interests ?? this.interests,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      currency: currency ?? this.currency,
      preferredTransport: preferredTransport ?? this.preferredTransport,
      accommodationType: accommodationType ?? this.accommodationType,
      dietaryPreferences: dietaryPreferences ?? this.dietaryPreferences,
      accessibilityNeeds: accessibilityNeeds ?? this.accessibilityNeeds,
      preferredTravelPace: preferredTravelPace ?? this.preferredTravelPace,
      additionalPreferences:
          additionalPreferences ?? this.additionalPreferences,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    phone,
    dateOfBirth,
    gender,
    nationality,
    preferredLanguage,
    travelStyle,
    favoriteCategories,
    interests,
    budgetMin,
    budgetMax,
    currency,
    preferredTransport,
    accommodationType,
    dietaryPreferences,
    accessibilityNeeds,
    preferredTravelPace,
    additionalPreferences,
    createdAt,
    updatedAt,
  ];
}
