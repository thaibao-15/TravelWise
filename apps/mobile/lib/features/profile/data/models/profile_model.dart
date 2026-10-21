import 'package:mobile/features/profile/domain/entities/profile_entity.dart';

/// Data model for travel preferences supporting JSON serialization.
class TravelPreferencesModel extends TravelPreferences {
  const TravelPreferencesModel({
    required super.style,
    required super.styleEmoji,
    required super.budget,
    required super.budgetEmoji,
    required super.pace,
    required super.paceEmoji,
    required super.favoriteCategories,
  });

  factory TravelPreferencesModel.fromEntity(TravelPreferences entity) {
    return TravelPreferencesModel(
      style: entity.style,
      styleEmoji: entity.styleEmoji,
      budget: entity.budget,
      budgetEmoji: entity.budgetEmoji,
      pace: entity.pace,
      paceEmoji: entity.paceEmoji,
      favoriteCategories: List<String>.from(entity.favoriteCategories),
    );
  }

  factory TravelPreferencesModel.fromJson(Map<String, dynamic> json) {
    return TravelPreferencesModel(
      style: json['style'] as String? ?? 'Khám phá (Adventure)',
      styleEmoji: json['style_emoji'] as String? ?? '🎒',
      budget: json['budget'] as String? ?? 'Vừa phải (Mid-range)',
      budgetEmoji: json['budget_emoji'] as String? ?? '💳',
      pace: json['pace'] as String? ?? 'Cân bằng (Balanced)',
      paceEmoji: json['pace_emoji'] as String? ?? '⚖️',
      favoriteCategories:
          (json['favorite_categories'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['🏖️ Bãi biển', '🍜 Ẩm thực', '🏛️ Văn hóa', '🌿 Thiên nhiên'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'style': style,
      'style_emoji': styleEmoji,
      'budget': budget,
      'budget_emoji': budgetEmoji,
      'pace': pace,
      'pace_emoji': paceEmoji,
      'favorite_categories': favoriteCategories,
    };
  }
}
