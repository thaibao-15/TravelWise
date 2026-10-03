import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../models/place_model.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/category_chips.dart';
import '../widgets/featured_card.dart';
import '../widgets/filter_row.dart';
import '../widgets/floating_ai_button.dart';
import '../widgets/header_bar.dart';
import '../widgets/place_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/section_header.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Dummy Data to render exactly like design
    final places = [
      Place(
        id: '1',
        name: 'Bán đảo Sơn Trà & Chùa Linh...',
        description: 'Tầm nhìn toàn cảnh vịnh Đà Nẵng, viếng tượng Phật Bà cao 67m và ngắm loài Voọc chà vá chân nâu quý hiếm.',
        rating: 4.9,
        reviews: 18200,
        distance: 8.5,
        imageUrl: 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
        price: 'Miễn phí',
        tags: ['Thiên nhiên & Văn hóa'],
        isOpen: true,
      ),
      Place(
        id: '2',
        name: 'Cà phê Trình - Bánh & Cà ph...',
        description: 'Quán cà phê sân vườn yên tĩnh đặc trưng món cà phê muối béo ngậy và bánh sừng bò nướng thủ công thơm...',
        rating: 4.7,
        reviews: 3500,
        distance: 1.1,
        imageUrl: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24',
        price: '30k - 55k',
        tags: ['Café & Check-in'],
        isOpen: true,
      ),
      Place(
        id: '3',
        name: 'Bún Chả Cá 109 Nguyễn Chí...',
        description: 'Món ăn truyền thống đậm đà hơn 40 năm với chả cá thu tươi dai giòn và nước dùng hầm rau củ thanh ngọt.',
        rating: 4.8,
        reviews: 6900,
        distance: 1.5,
        imageUrl: 'https://images.unsplash.com/photo-1585032226651-759b368d7246',
        price: '35k - 60k',
        tags: ['Ẩm thực địa phương'],
        isOpen: false,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HeaderBar(),
                  const ExploreSearchBar(),
                  const SizedBox(height: AppSpacing.lg),
                  const CategoryChips(),
                  const SizedBox(height: AppSpacing.md),
                  const FilterRow(),
                  const SizedBox(height: AppSpacing.lg),
                  const FeaturedCard(),
                  const SizedBox(height: AppSpacing.xxl),
                  const SectionHeader(
                    title: 'Khám phá quanh bạn',
                    subtitle: '42 địa điểm nổi bật đang mở cửa',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: places.length,
                    itemBuilder: (context, index) {
                      return PlaceCard(place: places[index]);
                    },
                  ),
                  const SizedBox(height: 100), // Spacing for floating ai button
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
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}
