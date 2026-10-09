import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../error/exceptions.dart';

/// Service that wraps flutter_secure_storage for encrypted key-value persistence.
/// Used to securely store auth tokens on device.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  static const String _accessTokenKey = 'access_token';
  static const String _tokenTypeKey = 'token_type';

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Saves the access token securely.
  Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: _accessTokenKey, value: token);
    } catch (e) {
      throw CacheException(message: 'Không thể lưu token: ${e.toString()}');
    }
  }

  /// Saves the token type (e.g., "bearer").
  Future<void> saveTokenType(String tokenType) async {
    try {
      await _storage.write(key: _tokenTypeKey, value: tokenType);
    } catch (e) {
      throw CacheException(message: 'Không thể lưu token type: ${e.toString()}');
    }
  }

  /// Retrieves the stored access token, or null if not found.
  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _accessTokenKey);
    } catch (e) {
      throw CacheException(message: 'Không thể đọc token: ${e.toString()}');
    }
  }

  /// Retrieves the stored token type.
  Future<String?> getTokenType() async {
    try {
      return await _storage.read(key: _tokenTypeKey);
    } catch (e) {
      throw CacheException(message: 'Không thể đọc token type: ${e.toString()}');
    }
  }

  /// Deletes all auth-related stored data (used on logout).
  Future<void> clearAll() async {
    try {
      await _storage.delete(key: _accessTokenKey);
      await _storage.delete(key: _tokenTypeKey);
    } catch (e) {
      throw CacheException(message: 'Không thể xoá dữ liệu: ${e.toString()}');
    }
  }

  /// Checks if a token is currently stored.
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
