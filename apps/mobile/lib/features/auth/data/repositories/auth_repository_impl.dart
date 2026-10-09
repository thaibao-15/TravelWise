import 'package:dartz/dartz.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../domain/entities/auth_token.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

/// Concrete implementation of [AuthRepository].
/// Orchestrates between the remote data source and local storage.
/// Catches data-layer exceptions and converts them to domain-layer Failures.
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final SecureStorageService _storageService;

  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required SecureStorageService storageService,
  })  : _remoteDataSource = remoteDataSource,
        _storageService = storageService;

  @override
  Future<Either<Failure, AuthToken>> login({
    required String email,
    required String password,
  }) async {
    try {
      final tokenModel = await _remoteDataSource.login(
        email: email,
        password: password,
      );

      // Persist token immediately after successful login
      await _storageService.saveToken(tokenModel.accessToken);
      await _storageService.saveTokenType(tokenModel.tokenType);

      return Right(tokenModel.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, statusCode: e.statusCode));
    } on CacheException catch (e) {
      return Left(CacheFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Lỗi không xác định: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, User>> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final userModel = await _remoteDataSource.register(
        email: email,
        password: password,
        fullName: fullName,
      );
      return Right(userModel.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, statusCode: e.statusCode));
    } catch (e) {
      return Left(ServerFailure(message: 'Lỗi không xác định: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, User>> getCurrentUser() async {
    try {
      final userModel = await _remoteDataSource.getCurrentUser();
      return Right(userModel.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message, statusCode: e.statusCode));
    } catch (e) {
      return Left(ServerFailure(message: 'Lỗi không xác định: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> logout() async {
    try {
      await _storageService.clearAll();
      return const Right(null);
    } on CacheException catch (e) {
      return Left(CacheFailure(message: e.message));
    } catch (e) {
      return Left(CacheFailure(message: 'Lỗi khi đăng xuất: ${e.toString()}'));
    }
  }
}
