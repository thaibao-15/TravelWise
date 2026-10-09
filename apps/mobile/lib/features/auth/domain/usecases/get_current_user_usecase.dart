import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

/// Use case to fetch the currently authenticated user's profile.
class GetCurrentUserUseCase {
  final AuthRepository _repository;

  const GetCurrentUserUseCase(this._repository);

  Future<Either<Failure, User>> call() {
    return _repository.getCurrentUser();
  }
}
