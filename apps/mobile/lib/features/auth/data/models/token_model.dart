import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/auth_token.dart';

part 'token_model.g.dart';

/// Data model that maps the API's login JSON response to the domain [AuthToken] entity.
@JsonSerializable()
class TokenModel {
  @JsonKey(name: 'access_token')
  final String accessToken;
  @JsonKey(name: 'token_type')
  final String tokenType;

  const TokenModel({
    required this.accessToken,
    required this.tokenType,
  });

  factory TokenModel.fromJson(Map<String, dynamic> json) =>
      _$TokenModelFromJson(json);

  Map<String, dynamic> toJson() => _$TokenModelToJson(this);

  /// Converts this data model to a domain entity.
  AuthToken toEntity() {
    return AuthToken(
      accessToken: accessToken,
      tokenType: tokenType,
    );
  }
}
