import 'package:equatable/equatable.dart';

/// Base failure class for domain-level error representation.
/// Uses Equatable for value equality in tests and state comparisons.
abstract class Failure extends Equatable {
  final String message;
  final int? statusCode;

  const Failure({required this.message, this.statusCode});

  @override
  List<Object?> get props => [message, statusCode];
}

/// Represents failures from remote API calls.
class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.statusCode});
}

/// Represents failures from local storage operations.
class CacheFailure extends Failure {
  const CacheFailure({required super.message});
}

/// Represents network connectivity failures.
class NetworkFailure extends Failure {
  const NetworkFailure({super.message = 'Không có kết nối mạng'});
}
