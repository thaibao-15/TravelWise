import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

/// Encapsulates the business logic for user registration.
class RegisterUseCase {
  final AuthRepository _repository;

  const RegisterUseCase(this._repository);

  /// Executes registration with [email], [password], and [fullName].
  /// Returns [User] on success, [Failure] on error.
  Future<Either<Failure, User>> call({
    required String email,
    required String password,
    required String fullName,
  }) {
    return _repository.register(
      email: email,
      password: password,
      fullName: fullName,
    );
  }
}
