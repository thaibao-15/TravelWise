import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/user.dart';

part 'user_model.g.dart';

/// Data model that maps the API's user JSON response to the domain [User] entity.
/// Handles JSON serialization/deserialization at the data layer boundary.
@JsonSerializable()
class UserModel {
  final int id;
  final String email;
  @JsonKey(name: 'full_name')
  final String fullName;
  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;
  final String role;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserModelToJson(this);

  /// Converts this data model to a domain entity.
  User toEntity() {
    return User(
      id: id,
      email: email,
      fullName: fullName,
      avatarUrl: avatarUrl,
      role: role,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
