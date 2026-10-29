import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_di.dart';
import '../../map/presentation/providers/location_provider.dart';
import '../data/home_remote_data_source.dart';
import '../data/weather_remote_data_source.dart';
import '../models/category_model.dart';
import '../models/place_model.dart';
import '../models/weather_model.dart';

final homeRemoteDataSourceProvider = Provider<HomeRemoteDataSource>((ref) {
  return HomeRemoteDataSource(ref.watch(dioClientProvider).dio);
});

final weatherRemoteDataSourceProvider = Provider<WeatherRemoteDataSource>((
  ref,
) {
  return WeatherRemoteDataSource(ref.watch(dioClientProvider).dio);
});

final homeWeatherProvider = FutureProvider.autoDispose<WeatherResponse?>((ref) {
  final position = ref.watch(locationProvider).position;
  if (position == null) {
    return null;
  }

  return ref
      .watch(weatherRemoteDataSourceProvider)
      .getCurrentWeather(
        latitude: position.latitude,
        longitude: position.longitude,
      );
});

final homeCategoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(homeRemoteDataSourceProvider).getCategories();
});

final homePlacesProvider = FutureProvider.family<List<Place>, int?>((
  ref,
  categoryId,
) {
  return ref
      .watch(homeRemoteDataSourceProvider)
      .getPlaces(categoryId: categoryId);
});

final nearbyPlacesProvider = FutureProvider.autoDispose<List<Place>>((ref) {
  final position = ref.watch(locationProvider).position;
  if (position == null) {
    return const <Place>[];
  }

  return ref
      .watch(homeRemoteDataSourceProvider)
      .getNearbyPlaces(
        latitude: position.latitude,
        longitude: position.longitude,
      );
});

final exploreMapPlacesProvider = FutureProvider.autoDispose
    .family<List<Place>, int?>((ref, categoryId) {
      return ref
          .watch(homeRemoteDataSourceProvider)
          .getAllPlaces(categoryId: categoryId);
    });

final exploreMapFocusPlaceProvider = StateProvider<Place?>((ref) => null);

final placeRatingsRefreshProvider = StateProvider<int>((ref) => 0);

void invalidatePlaceRatingProviders(WidgetRef ref, int placeId) {
  ref.invalidate(placeDetailProvider(placeId));
  ref.invalidate(homePlacesProvider);
  ref.invalidate(exploreMapPlacesProvider);
  ref.invalidate(homeSearchPlacesProvider);
  ref.read(placeRatingsRefreshProvider.notifier).state++;
}

final homeSearchPlacesProvider = FutureProvider.family<List<Place>, String>((
  ref,
  query,
) {
  return ref.watch(homeRemoteDataSourceProvider).searchPlaces(query);
});

final placeDetailProvider = FutureProvider.family<Place, int>((ref, placeId) {
  return ref.watch(homeRemoteDataSourceProvider).getPlaceById(placeId);
});
