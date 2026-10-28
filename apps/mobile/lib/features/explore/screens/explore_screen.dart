import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../reviews/screens/place_reviews_bottom_sheet.dart';
import '../../reviews/services/review_service.dart';
import '../models/place_model.dart';
import '../widgets/category_chips.dart';
import '../widgets/featured_card.dart';
import '../widgets/filter_row.dart';
import '../widgets/floating_ai_button.dart';
import '../widgets/place_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/section_header.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ReviewService _reviewService = ReviewService();
  String? _activeFilter;

  List<Place> _places = [
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
      imageUrl:
          'https://images.unsplash.com/photo-1585032226651-759b368d7246',
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
                  top.user?.fullName ?? top.user?.email ?? place.topReviewAuthor,
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
                  const ExploreSearchBar(),
                  const SizedBox(height: AppSpacing.lg),
                  const CategoryChips(),
                  const SizedBox(height: AppSpacing.md),
                  FilterRow(
                    onFilterSelected: (filter) {
                      setState(() {
                        _activeFilter = _activeFilter == filter ? null : filter;
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const FeaturedCard(),

                  // ─── COMMUNITY REVIEWS HIGHLIGHT SECTION ───────────────
                  const SizedBox(height: AppSpacing.xl),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                          child: Container(
                            width: 280,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
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
                                                item['avatar'] as String),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              item['author'] as String,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
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
              ),
            ),
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
}
