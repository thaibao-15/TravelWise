import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../../map/presentation/providers/location_provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/place_model.dart';
import '../providers/home_provider.dart';
import 'place_detail_screen.dart';
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
  String _searchQuery = '';
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider.notifier).requestPermissionAndFetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(homeCategoriesProvider);
    final places = ref.watch(homePlacesProvider(_selectedCategoryId));
    final weather = ref.watch(homeWeatherProvider);
    ref.listen(homeWeatherProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không thể tải thời tiết: $error')),
          );
        },
      );
    });

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
                  CustomAppBar(
                    weather: weather.when(
                      loading: () => '...',
                      error: (_, __) => null,
                      data: (value) => value == null
                          ? null
                          : '${value.current.temperature.round()}°C',
                    ),
                  ),
                  custom_search.SearchBar(
                    showBackButton: _isSearchFocused,
                    onFocus: () {
                      setState(() {
                        _isSearchFocused = true;
                      });
                    },
                    onBack: () {
                      setState(() {
                        _isSearchFocused = false;
                        _searchQuery = '';
                      });
                    },
                    onChanged: (query) {
                      setState(() {
                        _searchQuery = query;
                      });
                    },
                  ),
                  if (_isSearchFocused)
                    _buildSearchResults()
                  else ...[
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
                      child: Text(
                        'Gợi ý lịch trình AI',
                        style: AppTextStyles.h3,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: AiItineraryCard(),
                    ),
                  ],
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

  Widget _buildSearchResults() {
    if (_searchQuery.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          100,
        ),
        child: Text(
          'Nhập tên địa điểm để bắt đầu tìm kiếm',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return _buildSearchResultsState(
      ref.watch(homeSearchPlacesProvider(_searchQuery)),
    );
  }

  Widget _buildSearchResultsState(AsyncValue<List<Place>> results) {
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _buildError(
        'Không thể tìm kiếm địa điểm: $error',
        () => ref.invalidate(homeSearchPlacesProvider(_searchQuery)),
      ),
      data: (items) => items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Không tìm thấy địa điểm phù hợp.',
                style: AppTextStyles.bodyMedium,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 100),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final place = items[index];
                return _buildSearchResultTile(context, place);
              },
            ),
    );
  }

  Widget _buildSearchResultTile(BuildContext context, Place place) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withOpacity(0.1),
        backgroundImage: place.imageUrl.isNotEmpty
            ? NetworkImage(place.imageUrl)
            : null,
        child: place.imageUrl.isEmpty
            ? const Icon(Icons.location_on_outlined, color: AppColors.primary)
            : null,
      ),
      title: Text(
        place.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        (place.address?.trim().isNotEmpty == true
                    ? place.address
                    : place.description)
                ?.trim() ??
            'Địa điểm du lịch',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      ),
      trailing: const Icon(Icons.north_west, color: AppColors.textSecondary),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlaceDetailScreen(placeId: place.id),
          ),
        );
      },
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
        () => ref.invalidate(
          _searchQuery.isEmpty
              ? homePlacesProvider(_selectedCategoryId)
              : homeSearchPlacesProvider(_searchQuery),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text('Không tìm thấy địa điểm phù hợp.'),
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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlaceDetailScreen(placeId: place.id),
                      ),
                    );
                  },
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
