import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../home/models/category_model.dart';
import '../../home/models/place_model.dart' as home_model;
import '../../home/providers/home_provider.dart';
import '../../home/screens/place_detail_screen.dart';
import '../../home/widgets/search_bar.dart' as home_search;
import '../../map/presentation/providers/location_provider.dart';
import '../models/place_model.dart';
import '../widgets/category_chips.dart';
import '../widgets/filter_row.dart';
import '../widgets/floating_ai_button.dart';
import '../widgets/explore_map_section.dart';
import '../widgets/place_card.dart';
import '../widgets/section_header.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  String? _activeFilter;
  int? _selectedCategoryId;
  String _searchQuery = '';
  bool _isSearchFocused = false;
  home_model.Place? _focusedMapPlace;
  bool _pendingMapScroll = false;
  final GlobalKey _mapAnchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    ref.read(locationProvider.notifier).checkInitialStatus();
  }

  List<Place> _filteredPlaces(List<Place> places) {
    if (_activeFilter == 'rating') {
      return places.where((place) => place.rating >= 4.5).toList();
    } else if (_activeFilter == 'open') {
      return places.where((place) => place.isOpen == true).toList();
    }
    return places;
  }

  Place _toExplorePlace(home_model.Place place) {
    final description = place.description.trim().isNotEmpty
        ? place.description
        : place.address ?? '';
    return Place(
      id: place.id.toString(),
      name: place.name,
      description: description,
      rating: place.rating,
      reviews: place.reviewCount,
      distance: place.distanceKm ?? 0,
      imageUrl: place.imageUrl,
      price: '',
    );
  }

  Future<void> _requestNearbyLocation() async {
    final location = ref.read(locationProvider);
    final notifier = ref.read(locationProvider.notifier);
    if (location.isPermanentlyDenied) {
      await notifier.openAppSettings();
    } else if (location.isServiceDisabled) {
      await notifier.openLocationSettings();
    } else {
      await notifier.requestPermissionAndFetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(homeCategoriesProvider);
    final categoryItems = categories.when(
      data: (items) => items,
      loading: () => const <Category>[],
      error: (_, _) => const <Category>[],
    );
    final mapPlaces = ref.watch(exploreMapPlacesProvider(_selectedCategoryId));
    final nearbyPlaces = ref.watch(nearbyPlacesProvider);
    final locationState = ref.watch(locationProvider);

    ref.listen<int>(placeRatingsRefreshProvider, (_, _) {
      ref.invalidate(nearbyPlacesProvider);
    });

    ref.listen<home_model.Place?>(exploreMapFocusPlaceProvider, (
      previous,
      place,
    ) {
      if (place == null || !mounted) return;
      setState(() {
        _selectedCategoryId = place.categoryId;
        _focusedMapPlace = place;
        _isSearchFocused = false;
        _searchQuery = '';
        _pendingMapScroll = true;
      });
    });
    if (_pendingMapScroll && mapPlaces is AsyncData<List<home_model.Place>>) {
      _pendingMapScroll = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final mapContext = _mapAnchorKey.currentContext;
        if (mounted && mapContext != null) {
          Scrollable.ensureVisible(
            mapContext,
            duration: const Duration(milliseconds: 350),
            alignment: 0.1,
            curve: Curves.easeInOut,
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CustomAppBar(),
                  home_search.SearchBar(
                    hintText: 'Tìm địa điểm, món ăn, hoạt động...',
                    showBackButton: _isSearchFocused,
                    onFocus: () {
                      setState(() => _isSearchFocused = true);
                    },
                    onBack: () {
                      setState(() {
                        _isSearchFocused = false;
                        _searchQuery = '';
                        _focusedMapPlace = null;
                      });
                    },
                    onChanged: (query) {
                      setState(() => _searchQuery = query);
                    },
                  ),
                  if (_isSearchFocused)
                    _buildSearchResults()
                  else ...[
                    const SizedBox(height: AppSpacing.lg),
                    categories.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        child: Text('Đang tải danh mục...'),
                      ),
                      error: (error, _) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Không thể tải danh mục: $error',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  ref.invalidate(homeCategoriesProvider),
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      ),
                      data: (items) => CategoryChips(
                        categories: items,
                        selectedCategoryId: _selectedCategoryId,
                        onSelected: (categoryId) {
                          setState(() {
                            _selectedCategoryId = categoryId;
                            _focusedMapPlace = null;
                          });
                          ref
                                  .read(exploreMapFocusPlaceProvider.notifier)
                                  .state =
                              null;
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildExploreMap(mapPlaces, categoryItems),
                    const SizedBox(height: AppSpacing.lg),
                    FilterRow(
                      onFilterSelected: (filter) {
                        setState(() {
                          _activeFilter = _activeFilter == filter
                              ? null
                              : filter;
                        });
                      },
                    ),
                    // ─── PLACES LIST SECTION ──────────────────────────────
                    const SizedBox(height: AppSpacing.xxl),
                    _buildNearbyPlacesSection(nearbyPlaces, locationState),
                    const SizedBox(
                      height: 120,
                    ), // Spacing for floating ai button & nav
                  ],
                ],
              ),
            ),
            if (!_isSearchFocused)
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FloatingAiButton(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExploreMap(
    AsyncValue<List<home_model.Place>> mapPlaces,
    List<Category> categoryItems,
  ) {
    return mapPlaces.when(
      loading: () => const SizedBox(
        height: 340,
        child: Center(child: Text('Đang tải địa điểm trên bản đồ...')),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Không thể tải địa điểm trên bản đồ: $error',
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.invalidate(exploreMapPlacesProvider(_selectedCategoryId)),
              child: const Text('Thử lại'),
            ),
          ],
        ),
      ),
      data: (items) => KeyedSubtree(
        key: _mapAnchorKey,
        child: ExploreMapSection(
          key: ValueKey('${_selectedCategoryId}_${_focusedMapPlace?.id}'),
          places: items,
          categories: categoryItems,
          focusedPlace: _focusedMapPlace,
          onPlaceTap: (place) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlaceDetailScreen(placeId: place.id),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNearbyPlacesSection(
    AsyncValue<List<home_model.Place>> nearbyPlaces,
    LocationState location,
  ) {
    if (!location.hasLocation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Khám phá quanh bạn',
            subtitle: location.isLoading
                ? 'Đang xác định vị trí...'
                : 'Bật vị trí để tìm địa điểm gần bạn',
          ),
          const SizedBox(height: AppSpacing.md),
          if (location.isLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (location.errorMessage != null)
                    Text(
                      location.errorMessage!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _requestNearbyLocation,
                      icon: const Icon(Icons.my_location),
                      label: Text(
                        location.isPermanentlyDenied
                            ? 'Mở cài đặt vị trí'
                            : location.isServiceDisabled
                            ? 'Bật dịch vụ vị trí'
                            : 'Cho phép truy cập vị trí',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return nearbyPlaces.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Khám phá quanh bạn',
            subtitle: 'Đang tìm địa điểm gần vị trí hiện tại...',
          ),
          const SizedBox(height: AppSpacing.md),
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Khám phá quanh bạn',
            subtitle: 'Không thể tải địa điểm gần bạn',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$error',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(nearbyPlacesProvider),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ],
      ),
      data: (items) {
        final places = _filteredPlaces(items.map(_toExplorePlace).toList());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Khám phá quanh bạn',
              subtitle: '${places.length} địa điểm gần vị trí của bạn',
            ),
            const SizedBox(height: AppSpacing.md),
            if (places.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Text('Chưa tìm thấy địa điểm nào trong bán kính 10 km.'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: places.length,
                itemBuilder: (context, index) {
                  final place = places[index];
                  final placeId = int.tryParse(place.id);
                  return PlaceCard(
                    place: place,
                    onTap: placeId == null
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    PlaceDetailScreen(placeId: placeId),
                              ),
                            );
                          },
                  );
                },
              ),
          ],
        );
      },
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

    final provider = homeSearchPlacesProvider(_searchQuery);
    return ref
        .watch(provider)
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Không thể tìm kiếm địa điểm: $error',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
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
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: 100,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final place = items[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.1,
                        ),
                        backgroundImage: place.imageUrl.isNotEmpty
                            ? NetworkImage(place.imageUrl)
                            : null,
                        child: place.imageUrl.isEmpty
                            ? const Icon(
                                Icons.location_on_outlined,
                                color: AppColors.primary,
                              )
                            : null,
                      ),
                      title: Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        (place.address?.trim().isNotEmpty == true
                                    ? place.address
                                    : place.description)
                                ?.trim() ??
                            'Địa điểm du lịch',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.north_west,
                        color: AppColors.textSecondary,
                      ),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _selectedCategoryId = place.categoryId;
                          _focusedMapPlace = place;
                          _isSearchFocused = false;
                        });
                        ref.read(exploreMapFocusPlaceProvider.notifier).state =
                            null;
                      },
                    );
                  },
                ),
        );
  }
}