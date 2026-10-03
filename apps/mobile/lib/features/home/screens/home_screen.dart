import 'package:flutter/material.dart';
import '../../../core/constants/spacing.dart';
import '../widgets/ai_itinerary_card.dart';
import '../widgets/category_grid.dart';
import '../widgets/destination_card.dart';
import '../widgets/header_section.dart';
import '../widgets/nearby_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/suggestion_chips.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HeaderSection(),
                  const SizedBox(height: AppSpacing.md),
                  const HomeSearchBar(),
                  const SizedBox(height: AppSpacing.md),
                  const SuggestionChips(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionTitle('Điểm đến nổi bật', 'Xem tất cả'),
                  const SizedBox(height: AppSpacing.md),
                  _buildDestinations(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionTitle('Bạn muốn trải nghiệm gì?', '8 thể loại', isActionBold: false),
                  const SizedBox(height: AppSpacing.md),
                  const CategoryGrid(),
                  const SizedBox(height: AppSpacing.xl),
                  const AiItineraryCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionTitle('Gần bạn', 'Bán kính 5km', isActionBold: false),
                  const SizedBox(height: AppSpacing.md),
                  _buildNearbyList(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String action, {bool isActionBold = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Row(
            children: [
              Text(
                action, 
                style: TextStyle(
                  color: isActionBold ? const Color(0xFF2563EB) : const Color(0xFF6B7280), 
                  fontWeight: isActionBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                )
              ),
              if (isActionBold) ...[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF2563EB)),
              ] else if (action == 'Bán kính 5km') ...[
                const SizedBox(width: 8),
                const Icon(Icons.tune, size: 16, color: Color(0xFF2563EB)),
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDestinations() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: const [
          DestinationCard(
            title: 'Đà Nẵng',
            rating: 4.9,
            reviews: '24.8k',
            imageUrl: 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
            description: 'Thành phố của những cây cầu & bãi biển Mỹ Khê cát mịn thơ mộng.',
          ),
          SizedBox(width: AppSpacing.md),
          DestinationCard(
            title: 'Hội An',
            rating: 4.8,
            reviews: '31.2k',
            imageUrl: 'https://images.unsplash.com/photo-1555921015-5532091f6026',
            description: 'Phố cổ đèn lồng rực rỡ sắc màu được thế giới UNESCO công nhận.',
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: const [
          NearbyCard(
            title: 'Cầu Rồng',
            type: 'Điểm check-in nổi tiếng',
            distance: 1.2,
            rating: 4.8,
            imageUrl: 'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b',
          ),
          NearbyCard(
            title: 'Chợ Hàn',
            type: 'Ẩm thực & đặc sản địa phương',
            distance: 1.8,
            rating: 4.6,
            imageUrl: 'https://images.unsplash.com/photo-1555921015-5532091f6026',
          ),
          NearbyCard(
            title: 'Bãi biển Mỹ Khê',
            type: 'Bãi biển đẹp nhất hành tinh',
            distance: 2.4,
            rating: 4.9,
            imageUrl: 'https://images.unsplash.com/photo-1583417319070-4a69db38a482',
          ),
        ],
      ),
    );
  }
}
