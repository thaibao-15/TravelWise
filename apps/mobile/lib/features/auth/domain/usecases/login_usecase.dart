import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/auth_token.dart';
import '../repositories/auth_repository.dart';

/// Encapsulates the business logic for user login.
/// A use case class = one business action = one reason to change.
class LoginUseCase {
  final AuthRepository _repository;

  const LoginUseCase(this._repository);

  /// Executes login with [email] and [password].
  /// Returns [AuthToken] on success, [Failure] on error.
  Future<Either<Failure, AuthToken>> call({
    required String email,
    required String password,
  }) {
    return _repository.login(email: email, password: password);
  }
}
