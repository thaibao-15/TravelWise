import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/place_model.dart';
import '../providers/home_provider.dart';
import '../widgets/search_bar.dart' as custom_search;
import '../widgets/suggestion_chips.dart';
import '../widgets/destination_card.dart';
import '../widgets/category_grid.dart';
import '../widgets/ai_itinerary_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(homeCategoriesProvider);
    final places = ref.watch(homePlacesProvider(_selectedCategoryId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CustomAppBar(),
                  const custom_search.SearchBar(),
                  const SuggestionChips(),
                  const SizedBox(height: AppSpacing.md),
                  categories.when(
                    loading: () => const SizedBox(
                      height: 52,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => _buildError(
                      'Không thể tải danh mục: $error',
                      () => ref.invalidate(homeCategoriesProvider),
                    ),
                    data: (items) => items.isEmpty
                        ? const SizedBox.shrink()
                        : CategoryGrid(
                            categories: items,
                            selectedCategoryId: _selectedCategoryId,
                            onCategorySelected: (categoryId) {
                              setState(() {
                                _selectedCategoryId = categoryId;
                              });
                            },
                          ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildPlacesSection(places),
                  const SizedBox(height: AppSpacing.xl),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Text('Gợi ý lịch trình AI', style: AppTextStyles.h3),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: AiItineraryCard(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SizedBox(
                    height: 100,
                  ), // Spacing for bottom nav & floating bar
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlacesSection(AsyncValue<List<Place>> places) {
    return places.when(
      loading: () => const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _buildError(
        'Không thể tải địa điểm: $error',
        () => ref.invalidate(homePlacesProvider(_selectedCategoryId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text('Chưa có địa điểm trong danh mục này.'),
          );
        }

        return SizedBox(
          height: 300,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final place = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: DestinationCard(
                  title: place.name,
                  rating: place.rating.toStringAsFixed(1),
                  subtitle: place.description.isEmpty
                      ? 'Khám phá địa điểm này'
                      : place.description,
                  imageUrl: place.imageUrl,
                  secondaryImageUrl: place.secondaryImageUrl,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildError(String message, VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}
