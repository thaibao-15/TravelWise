import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/trip_repository.dart';
import '../models/trip_model.dart';
import '../models/mock_trips_list.dart';
import '../models/mock_trip_data.dart';

final selectedDayProvider = StateProvider<int>((ref) => 1);

/// Holds the currently generated unsaved trip preview (e.g. from Voice AI planning)
final currentTripPreviewProvider = StateProvider<Trip?>((ref) => null);

/// Holds the ID of the trip currently being viewed or edited
final currentEditingTripIdProvider = StateProvider<String?>((ref) => null);

/// Fetches saved trips from SQL Server via TripRepository (`GET /api/v1/trips`),
/// falling back gracefully if unauthenticated or offline.
final tripsListProvider = FutureProvider<List<Trip>>((ref) async {
  final repo = ref.watch(tripRepositoryProvider);
  final apiTrips = await repo.getTrips();
  return apiTrips;
});

/// Fetches single trip summary metadata (`GET /api/v1/trips/{tripId}`)
final tripSummaryProvider = FutureProvider.family<Trip?, String>((ref, tripId) async {
  final repo = ref.watch(tripRepositoryProvider);
  return await repo.getTripById(tripId);
});

/// Fetches full itinerary for a specific trip by its tripId
/// (`GET /api/v1/trips/{tripId}/itinerary` + `GET /api/v1/trips/{tripId}`)
final tripDetailProvider = FutureProvider.family<Trip?, String>((ref, tripId) async {
  final repo = ref.watch(tripRepositoryProvider);
  final trip = await repo.getTripItinerary(tripId);
  if (trip != null) {
    return trip;
  }
  // Fallback to mock item if viewing a mock trip id
  try {
    final mockItem = mockTripsList.firstWhere((t) => t.id == tripId);
    if (mockItem.days.isEmpty) {
      return mockItem.copyWith(days: mockTripDetail.days);
    }
    return mockItem;
  } catch (_) {
    return null;
  }
});
