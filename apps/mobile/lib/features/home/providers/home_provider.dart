import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_di.dart';
import '../data/home_remote_data_source.dart';
import '../models/category_model.dart';
import '../models/place_model.dart';

final homeRemoteDataSourceProvider = Provider<HomeRemoteDataSource>((ref) {
  return HomeRemoteDataSource(ref.watch(dioClientProvider).dio);
});

final homeCategoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(homeRemoteDataSourceProvider).getCategories();
});

final homePlacesProvider =
    FutureProvider.family<List<Place>, int?>((ref, categoryId) {
  return ref.watch(homeRemoteDataSourceProvider).getPlaces(
        categoryId: categoryId,
      );
});
