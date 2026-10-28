import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../auth/domain/entities/user.dart';
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

  /// Updates travel preferences.
  Future<Either<Failure, TravelPreferences>> updatePreferences(
    TravelPreferences preferences,
  );
}
