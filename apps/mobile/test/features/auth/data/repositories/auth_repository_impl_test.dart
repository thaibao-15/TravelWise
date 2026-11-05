import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:mobile/features/auth/data/models/user_model.dart';
import 'package:mobile/features/auth/data/repositories/auth_repository_impl.dart';

class _FakeSecureStorageService extends SecureStorageService {
  _FakeSecureStorageService(this.tokenExists);

  final bool tokenExists;

  @override
  Future<bool> hasToken() async => tokenExists;
}

class _FakeAuthRemoteDataSource extends AuthRemoteDataSource {
  _FakeAuthRemoteDataSource() : super(Dio());

  bool getCurrentUserCalled = false;

  @override
  Future<UserModel> getCurrentUser() async {
    getCurrentUserCalled = true;
    return UserModel(
      id: 1,
      email: 'traveler@example.com',
      fullName: 'Traveler',
      role: 'USER',
      isActive: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }
}

void main() {
  test(
    'restoreSession skips profile request when no token is stored',
    () async {
      final remoteDataSource = _FakeAuthRemoteDataSource();
      final repository = AuthRepositoryImpl(
        remoteDataSource: remoteDataSource,
        storageService: _FakeSecureStorageService(false),
      );

      final result = await repository.restoreSession();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected an empty restored session.'),
        (user) => expect(user, isNull),
      );
      expect(remoteDataSource.getCurrentUserCalled, isFalse);
    },
  );

  test('restoreSession fetches the user when a token is stored', () async {
    final remoteDataSource = _FakeAuthRemoteDataSource();
    final repository = AuthRepositoryImpl(
      remoteDataSource: remoteDataSource,
      storageService: _FakeSecureStorageService(true),
    );

    final result = await repository.restoreSession();

    expect(result.isRight(), isTrue);
    result.fold((_) => fail('Expected the saved session to be restored.'), (
      user,
    ) {
      expect(user?.email, 'traveler@example.com');
      expect(user?.fullName, 'Traveler');
    });
    expect(remoteDataSource.getCurrentUserCalled, isTrue);
  });
}
