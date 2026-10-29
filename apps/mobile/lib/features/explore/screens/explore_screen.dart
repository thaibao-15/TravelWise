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
import '../../reviews/screens/place_reviews_bottom_sheet.dart';
import '../../reviews/services/review_service.dart';
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
  final ReviewService _reviewService = ReviewService();
  String? _activeFilter;
  int? _selectedCategoryId;
  String _searchQuery = '';
  bool _isSearchFocused = false;
  home_model.Place? _focusedMapPlace;

  final List<Place> _places = [
    Place(
      id: '1',
      name: 'Bán đảo Sơn Trà & Chùa Linh Ứng',
      description:
          'Tầm nhìn toàn cảnh vịnh Đà Nẵng, viếng tượng Phật Bà cao 67m và ngắm loài Voọc chà vá chân nâu quý hiếm.',
      rating: 4.9,
      reviews: 18200,
      distance: 8.5,
      imageUrl: 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
      price: 'Miễn phí',
      tags: ['Thiên nhiên & Văn hóa'],
      isOpen: true,
      topReviewSnippet:
          'Tầm nhìn vịnh biển tuyệt đẹp, không khí trong lành mát mẻ. Rất thích hợp đưa gia đình đi ngắm cảnh!',
      topReviewAuthor: 'Hoàng Nam (Gia đình)',
    ),
    Place(
      id: '2',
      name: 'Cà phê Trình - Bánh & Cà phê Muối',
      description:
          'Quán cà phê sân vườn yên tĩnh đặc trưng món cà phê muối béo ngậy và bánh sừng bò nướng thủ công thơm lừng.',
      rating: 4.7,
      reviews: 3500,
      distance: 1.1,
      imageUrl: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24',
      price: '30k - 55k',
      tags: ['Café & Check-in'],
      isOpen: true,
      topReviewSnippet:
          'Cà phê muối béo ngậy thơm ngon số một Đà Nẵng, view tầng 2 ngắm hoàng hôn rất chill.',
      topReviewAuthor: 'Ngọc Trinh (Cặp đôi)',
    ),
    Place(
      id: '3',
      name: 'Bún Chả Cá 109 Nguyễn Chí Thanh',
      description:
          'Món ăn truyền thống đậm đà hơn 40 năm với chả cá thu tươi dai giòn và nước dùng hầm rau củ thanh ngọt.',
      rating: 4.8,
      reviews: 6900,
      distance: 1.5,
      imageUrl: 'https://images.unsplash.com/photo-1585032226651-759b368d7246',
      price: '35k - 60k',
      tags: ['Ẩm thực địa phương'],
      isOpen: false,
      topReviewSnippet:
          'Nước dùng ngọt thanh đậm đà từ củ quả, chả cá dai giòn sần sật, ghé Đà Nẵng nhất định phải ăn.',
      topReviewAuthor: 'Quốc Bảo (Một mình)',
    ),
  ];

  // Community highlights for horizontal cards
  final List<Map<String, dynamic>> _communityReviews = [
    {
      'placeId': 1,
      'placeName': 'Bán đảo Sơn Trà',
      'author': 'Hoàng Nam',
      'avatar':
          'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
      'rating': 5,
      'tripType': '👨‍👩‍👦 Gia đình',
      'comment':
          'Cảnh hoàng hôn nhìn từ đỉnh Sơn Trà cực phẩm. Đưa bố mẹ và các bé đi trải nghiệm rất hài lòng.',
      'image':
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500',
    },
    {
      'placeId': 2,
      'placeName': 'Cà phê Trình',
      'author': 'Ngọc Trinh',
      'avatar':
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
      'rating': 5,
      'tripType': '💑 Cặp đôi',
      'comment':
          'Menu cà phê muối chuẩn vị, góc ban công nhiều cây xanh chụp ảnh xinh lung linh.',
      'image':
          'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=500',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchLatestReviewsForPlaces();
  }

  /// Gọi API review thực tế từ Backend để cập nhật thông tin đánh giá mới nhất
  Future<void> _fetchLatestReviewsForPlaces() async {
    for (int i = 0; i < _places.length; i++) {
      final place = _places[i];
      final placeId = int.tryParse(place.id);
      if (placeId == null) continue;

      try {
        final reviewList = await _reviewService.getPlaceReviews(
          placeId: placeId,
          limit: 1,
        );

        if (!mounted) return;

        if (reviewList.items.isNotEmpty) {
          final top = reviewList.items.first;
          setState(() {
            _places[i] = place.copyWith(
              rating: reviewList.ratingAvg > 0
                  ? reviewList.ratingAvg
                  : place.rating,
              reviews: reviewList.total > 0 ? reviewList.total : place.reviews,
              topReviewSnippet: top.comment ?? place.topReviewSnippet,
              topReviewAuthor:
                  top.user?.fullName ??
                  top.user?.email ??
                  place.topReviewAuthor,
            );
          });
        }
      } catch (_) {
        // Giữ fallback dữ liệu giao diện nếu backend chưa có dữ liệu cho place ID đó
      }
    }
  }

  List<Place> get _filteredPlaces {
    if (_activeFilter == 'rating') {
      return _places.where((p) => p.rating >= 4.8).toList();
    } else if (_activeFilter == 'open') {
      return _places.where((p) => p.isOpen).toList();
    }
    return _places;
  }

  @override
  Widget build(BuildContext context) {
    final places = _filteredPlaces;
    final categories = ref.watch(homeCategoriesProvider);
    final categoryItems = categories.when(
      data: (items) => items,
      loading: () => const <Category>[],
      error: (_, _) => const <Category>[],
    );
    final mapPlaces = ref.watch(exploreMapPlacesProvider(_selectedCategoryId));

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
                          });
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
                    // ─── COMMUNITY REVIEWS HIGHLIGHT SECTION ───────────────
                    const SizedBox(height: AppSpacing.xl),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Trải nghiệm cộng đồng',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Đánh giá thực tế từ du khách TravelWise',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.verified_user_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 140,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _communityReviews.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final item = _communityReviews[index];
                          return InkWell(
                            onTap: () {
                              PlaceReviewsBottomSheet.show(
                                context: context,
                                placeId: item['placeId'] as int,
                                placeName: item['placeName'] as String,
                                ratingAvg: 4.8,
                                totalReviews: 1240,
                              );
                            },
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            child: Container(
                              width: 280,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMd,
                                ),
                                border: Border.all(color: AppColors.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: SizedBox(
                                width: 256,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        item['image'] as String,
                                        width: 72,
                                        height: 116,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 10,
                                                backgroundImage: NetworkImage(
                                                  item['avatar'] as String,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text(
                                                  item['author'] as String,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        AppColors.textPrimary,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Text(
                                                '${item['rating']}★',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.warning,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            item['placeName'] as String,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Expanded(
                                            child: Text(
                                              '"${item['comment']}"',
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                height: 1.3,
                                                color: AppColors.textSecondary,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // ─── PLACES LIST SECTION ──────────────────────────────
                    const SizedBox(height: AppSpacing.xxl),
                    SectionHeader(
                      title: 'Khám phá quanh bạn',
                      subtitle: '${places.length} địa điểm nổi bật đang mở cửa',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: places.length,
                      itemBuilder: (context, index) {
                        return PlaceCard(place: places[index]);
                      },
                    ),
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
      data: (items) => ExploreMapSection(
        key: ValueKey(_selectedCategoryId),
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
                      },
                    );
                  },
                ),
        );
  }
}
