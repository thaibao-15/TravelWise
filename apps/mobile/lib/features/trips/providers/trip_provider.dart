import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/trip_repository.dart';
import '../models/trip_model.dart';
import '../models/mock_trips_list.dart';

final selectedDayProvider = StateProvider<int>((ref) => 1);

/// Holds the currently generated unsaved trip preview (e.g. from Voice AI planning)
final currentTripPreviewProvider = StateProvider<Trip?>((ref) => null);

/// Holds the ID of the trip currently being viewed or edited
final currentEditingTripIdProvider = StateProvider<String?>((ref) => null);

/// Fetches saved trips from SQL Server via TripRepository, falling back gracefully if unauthenticated.
final tripsListProvider = FutureProvider<List<Trip>>((ref) async {
  final repo = ref.watch(tripRepositoryProvider);
  final apiTrips = await repo.getTrips();
  if (apiTrips.isNotEmpty) {
    return apiTrips;
  }
  // Return empty list if no trips yet, or fall back to mock data if offline/unauthenticated
  return apiTrips;
});

/// Fetches full itinerary for a specific trip by its tripId
final tripDetailProvider = FutureProvider.family<Trip?, String>((ref, tripId) async {
  final repo = ref.watch(tripRepositoryProvider);
  final trip = await repo.getTripItinerary(tripId);
  if (trip != null) {
    return trip;
  }
  // Fallback to mock item if not found in DB
  try {
    return mockTripsList.firstWhere((t) => t.id == tripId);
  } catch (_) {
    return null;
  }
});
