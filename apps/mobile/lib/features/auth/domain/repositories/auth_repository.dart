import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/auth_token.dart';
import '../entities/user.dart';

/// Domain-layer contract for authentication operations.
/// The data layer provides the implementation; the domain layer only
/// knows about this interface + domain entities.
abstract class AuthRepository {
  /// Authenticates a user and returns an [AuthToken] on success.
  Future<Either<Failure, AuthToken>> login({
    required String email,
    required String password,
  });

  /// Registers a new user and returns the created [User] on success.
  Future<Either<Failure, User>> register({
    required String email,
    required String password,
    required String fullName,
  });

  /// Fetches the currently authenticated user's profile.
  Future<Either<Failure, User>> getCurrentUser();

  /// Logs out the user by clearing stored tokens.
  Future<Either<Failure, void>> logout();
}
