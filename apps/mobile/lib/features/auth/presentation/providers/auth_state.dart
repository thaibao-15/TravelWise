import 'package:equatable/equatable.dart';
import '../../domain/entities/user.dart';

/// Sealed-style auth state hierarchy using Equatable for
/// value-based equality in Riverpod state comparisons.
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any auth action.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Loading state while an auth operation is in progress.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// State after successful login — holds the authenticated user.
class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated(this.user);

  @override
  List<Object?> get props => [user];
}

/// State after successful registration.
class AuthRegistered extends AuthState {
  final String message;

  const AuthRegistered({this.message = 'Đăng ký thành công!'});

  @override
  List<Object?> get props => [message];
}

/// State when an auth operation fails.
class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when the user is not authenticated (logged out).
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}
