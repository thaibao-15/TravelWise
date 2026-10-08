import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/constants/text_styles.dart';
import '../models/trip_model.dart';
import '../models/mock_trips_list.dart';
import '../widgets/overview/trips_header.dart';
import '../widgets/overview/trip_search_filter.dart';
import '../widgets/overview/featured_trip_card.dart';
import '../widgets/overview/quick_create_section.dart';
import '../widgets/overview/trip_list_card.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  String _activeFilter = 'all';
  String _searchQuery = '';

  List<Trip> get filteredTrips {
    return mockTripsList.where((trip) {
      if (_activeFilter != 'all' && trip.status != _activeFilter) return false;
      if (_searchQuery.isNotEmpty) {
        return trip.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            trip.destination.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final trips = filteredTrips;
    final featuredTrip = mockTripsList.firstWhere((t) => t.status == 'upcoming', orElse: () => mockTripsList.first);
    final isFiltering = _activeFilter != 'all' || _searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TripsHeader(),
              const SizedBox(height: 24),
              TripSearchFilter(
                activeFilter: _activeFilter,
                onFilterChanged: (f) => setState(() => _activeFilter = f),
                onSearchChanged: (q) => setState(() => _searchQuery = q),
              ),
              const SizedBox(height: 32),
              if (!isFiltering) ...[
                FeaturedTripCard(trip: featuredTrip),
                const SizedBox(height: 32),
                const QuickCreateSection(),
                const SizedBox(height: 32),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Danh sách hành trình', style: AppTextStyles.h2),
                  Text('${trips.length} chuyến đi', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 16),
              if (trips.isEmpty)
                _buildEmptyState()
              else
                ...trips.map((trip) => TripListCard(trip: trip)),
              
              if (!isFiltering)
                _buildBottomRecommendation(),
              
              const SizedBox(height: 120), // Bottom padding for navigation
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text('Không tìm thấy hành trình', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Text('Thử tìm kiếm với từ khóa khác hoặc thay đổi bộ lọc.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _activeFilter = 'all';
                _searchQuery = '';
              });
            },
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999))),
            child: const Text('Xóa bộ lọc'),
          )
        ],
      ),
    );
  }

  Widget _buildBottomRecommendation() {
    return Container(
      margin: const EdgeInsets.only(top: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bạn đang ấp ủ chuyến đi mới?', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Text('Nhập bất kỳ ý tưởng hoặc thành phố nào bạn muốn ghé thăm, trợ lý sẽ phác thảo hành trình ngay.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Khám phá điểm đến mới'),
            ),
          )
        ],
      ),
    );
  }
}
