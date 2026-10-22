import 'package:flutter/material.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../widgets/search_bar.dart' as custom_search;
import '../widgets/suggestion_chips.dart';
import '../widgets/destination_card.dart';
import '../widgets/category_grid.dart';
import '../widgets/ai_itinerary_card.dart';
import '../widgets/nearby_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionHeader('Thịnh hành'),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      itemCount: 3,
                      itemBuilder: (context, index) {
                        return const Padding(
                          padding: EdgeInsets.only(right: AppSpacing.md),
                          child: DestinationCard(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const CategoryGrid(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionHeader('Gợi ý lịch trình AI'),
                  const SizedBox(height: AppSpacing.md),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: AiItineraryCard(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionHeader('Gần bạn'),
                  const SizedBox(height: AppSpacing.md),
                  ListView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: 3,
                    itemBuilder: (context, index) {
                      return const NearbyCard();
                    },
                  ),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.h3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'Xem tất cả',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
