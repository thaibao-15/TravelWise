import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/usecases/get_current_user_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_usecase.dart';
import '../../auth_di.dart';
import 'auth_state.dart';

/// Riverpod StateNotifier that drives all auth UI state transitions.
/// Depends only on use cases — never touches the data layer directly.
class AuthNotifier extends StateNotifier<AuthState> {
  final LoginUseCase _loginUseCase;
  final RegisterUseCase _registerUseCase;
  final GetCurrentUserUseCase _getCurrentUserUseCase;

  AuthNotifier({
    required LoginUseCase loginUseCase,
    required RegisterUseCase registerUseCase,
    required GetCurrentUserUseCase getCurrentUserUseCase,
  })  : _loginUseCase = loginUseCase,
        _registerUseCase = registerUseCase,
        _getCurrentUserUseCase = getCurrentUserUseCase,
        super(const AuthInitial());

  /// Performs login, saves token (handled by repo), then fetches user profile.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();

    final result = await _loginUseCase(email: email, password: password);

    await result.fold(
      (failure) async {
        state = AuthError(failure.message);
      },
      (token) async {
        // Token saved by repository — now fetch user profile
        final userResult = await _getCurrentUserUseCase();
        userResult.fold(
          (failure) => state = AuthError(failure.message),
          (user) => state = AuthAuthenticated(user),
        );
      },
    );
  }

  /// Performs registration. On success, transitions to AuthRegistered
  /// so the UI can navigate to the login tab.
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = const AuthLoading();

    final result = await _registerUseCase(
      email: email,
      password: password,
      fullName: fullName,
    );

    result.fold(
      (failure) => state = AuthError(failure.message),
      (user) => state = const AuthRegistered(),
    );
  }

  /// Resets state to initial (e.g., after showing an error snackbar).
  void resetState() {
    state = const AuthInitial();
  }
}

/// The main auth provider — single source of truth for auth state.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    loginUseCase: ref.watch(loginUseCaseProvider),
    registerUseCase: ref.watch(registerUseCaseProvider),
    getCurrentUserUseCase: ref.watch(getCurrentUserUseCaseProvider),
  );
});
