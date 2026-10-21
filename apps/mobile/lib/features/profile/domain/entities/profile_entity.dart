import 'package:equatable/equatable.dart';
import '../../../auth/domain/entities/user.dart';

/// Aggregated travel statistics entity for Section C.
class TravelStats extends Equatable {
  final int totalTrips;
  final int placesVisited;
  final int citiesExplored;
  final int savedPlaces;

  const TravelStats({
    required this.totalTrips,
    required this.placesVisited,
    required this.citiesExplored,
    required this.savedPlaces,
  });

  @override
  List<Object?> get props => [
    totalTrips,
    placesVisited,
    citiesExplored,
    savedPlaces,
  ];
}

/// Travel preferences entity for Section F.
class TravelPreferences extends Equatable {
  final String style;
  final String styleEmoji;
  final String budget;
  final String budgetEmoji;
  final String pace;
  final String paceEmoji;
  final List<String> favoriteCategories;

  const TravelPreferences({
    required this.style,
    required this.styleEmoji,
    required this.budget,
    required this.budgetEmoji,
    required this.pace,
    required this.paceEmoji,
    required this.favoriteCategories,
  });

  TravelPreferences copyWith({
    String? style,
    String? styleEmoji,
    String? budget,
    String? budgetEmoji,
    String? pace,
    String? paceEmoji,
    List<String>? favoriteCategories,
  }) {
    return TravelPreferences(
      style: style ?? this.style,
      styleEmoji: styleEmoji ?? this.styleEmoji,
      budget: budget ?? this.budget,
      budgetEmoji: budgetEmoji ?? this.budgetEmoji,
      pace: pace ?? this.pace,
      paceEmoji: paceEmoji ?? this.paceEmoji,
      favoriteCategories: favoriteCategories ?? this.favoriteCategories,
    );
  }

  @override
  List<Object?> get props => [
    style,
    styleEmoji,
    budget,
    budgetEmoji,
    pace,
    paceEmoji,
    favoriteCategories,
  ];
}

/// Travel badge entity for Section G.
class TravelBadge extends Equatable {
  final String id;
  final String title;
  final String countSubtitle;
  final String category;
  final String emoji;

  const TravelBadge({
    required this.id,
    required this.title,
    required this.countSubtitle,
    required this.category,
    required this.emoji,
  });

  @override
  List<Object?> get props => [id, title, countSubtitle, category, emoji];
}

/// Root domain entity for TravelSense Profile.
class ProfileEntity extends Equatable {
  final User user;
  final String membershipTier;
  final TravelStats stats;
  final TravelPreferences preferences;
  final List<TravelBadge> badges;
  final String locationPermissionLabel;
  final bool isLocationGranted;

  const ProfileEntity({
    required this.user,
    required this.membershipTier,
    required this.stats,
    required this.preferences,
    required this.badges,
    required this.locationPermissionLabel,
    required this.isLocationGranted,
  });

  ProfileEntity copyWith({
    User? user,
    String? membershipTier,
    TravelStats? stats,
    TravelPreferences? preferences,
    List<TravelBadge>? badges,
    String? locationPermissionLabel,
    bool? isLocationGranted,
  }) {
    return ProfileEntity(
      user: user ?? this.user,
      membershipTier: membershipTier ?? this.membershipTier,
      stats: stats ?? this.stats,
      preferences: preferences ?? this.preferences,
      badges: badges ?? this.badges,
      locationPermissionLabel:
          locationPermissionLabel ?? this.locationPermissionLabel,
      isLocationGranted: isLocationGranted ?? this.isLocationGranted,
    );
  }

  @override
  List<Object?> get props => [
    user,
    membershipTier,
    stats,
    preferences,
    badges,
    locationPermissionLabel,
    isLocationGranted,
  ];
}
