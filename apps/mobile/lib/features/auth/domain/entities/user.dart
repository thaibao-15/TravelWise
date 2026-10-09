import 'package:equatable/equatable.dart';

/// Domain entity representing an authenticated user.
/// Pure business object — no JSON serialization, no framework dependencies.
class User extends Equatable {
  final int id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id, email, fullName, avatarUrl, role, isActive];
}
