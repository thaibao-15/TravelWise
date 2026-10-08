import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage_service.dart';
import 'data/datasources/auth_remote_datasource.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/usecases/get_current_user_usecase.dart';
import 'domain/usecases/login_usecase.dart';
import 'domain/usecases/register_usecase.dart';

// ─── Core Providers ───────────────────────────────────────────────

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final dioClientProvider = Provider<DioClient>((ref) {
  final storageService = ref.watch(secureStorageProvider);
  return DioClient(storageService: storageService);
});

// ─── Data Layer Providers ─────────────────────────────────────────

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  return AuthRemoteDataSource(dioClient.dio);
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final remoteDataSource = ref.watch(authRemoteDataSourceProvider);
  final storageService = ref.watch(secureStorageProvider);
  return AuthRepositoryImpl(
    remoteDataSource: remoteDataSource,
    storageService: storageService,
  );
});

// ─── Use Case Providers ───────────────────────────────────────────

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(ref.watch(authRepositoryProvider));
});

final registerUseCaseProvider = Provider<RegisterUseCase>((ref) {
  return RegisterUseCase(ref.watch(authRepositoryProvider));
});

final getCurrentUserUseCaseProvider = Provider<GetCurrentUserUseCase>((ref) {
  return GetCurrentUserUseCase(ref.watch(authRepositoryProvider));
});
