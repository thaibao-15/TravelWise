import 'package:equatable/equatable.dart';

/// Domain entity representing an authentication token pair.
class AuthToken extends Equatable {
  final String accessToken;
  final String tokenType;

  const AuthToken({
    required this.accessToken,
    required this.tokenType,
  });

  @override
  List<Object?> get props => [accessToken, tokenType];
}
