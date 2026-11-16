import 'package:dartz/dartz.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/error/failures.dart';
import '../../../auth/domain/entities/user.dart';
import '../../data/models/user_profile_model.dart';
import '../entities/profile_entity.dart';

/// Contract for Profile operations.
abstract class ProfileRepository {
  /// Fetches the consolidated profile data for the authenticated user.
  Future<Either<Failure, ProfileEntity>> getProfile();

  /// Updates personal profile info via real backend endpoint PATCH /api/v1/users/{userId}.
  Future<Either<Failure, User>> updateProfile({
    required int userId,
    String? fullName,
    String? avatarUrl,
  });

  /// Uploads avatar image and updates the user profile with the new URL.
  Future<Either<Failure, User>> uploadAvatar({
    required int userId,
    required XFile file,
  });

  /// Updates travel preferences (supporting both legacy preferences and backend travel profile).
  Future<Either<Failure, TravelPreferences>> updatePreferences(
    TravelPreferences preferences,
  );

  /// Saves the full travel profile to PUT/POST /api/v1/users/me/profile.
  Future<Either<Failure, UserProfileModel>> updateTravelProfile(
    UserProfileModel profile,
  );

  /// Deletes user account via DELETE /api/v1/users/{userId}.
  Future<Either<Failure, void>> deleteAccount(int userId);
}
