import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/spacing.dart';
import '../../../../core/constants/text_styles.dart';
import '../../../../shared/widgets/main_shell.dart';
import '../models/trip_model.dart';
import '../models/mock_trips_list.dart';
import '../providers/trip_provider.dart';
import '../widgets/overview/trips_header.dart';
import '../widgets/overview/trip_search_filter.dart';
import '../widgets/overview/featured_trip_card.dart';
import '../widgets/overview/quick_create_section.dart';
import '../widgets/overview/trip_list_card.dart';
import '../widgets/create_trip_sheet.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  String _activeFilter = 'all';
  String _searchQuery = '';

  List<Trip> _filterTrips(List<Trip> source) {
    return source.where((trip) {
      if (_activeFilter != 'all') {
        final statusNorm = (trip.status ?? '').toLowerCase();
        if (_activeFilter == 'upcoming' &&
            statusNorm != 'upcoming' &&
            statusNorm != 'confirmed') {
          return false;
        }
        if (_activeFilter == 'planning' &&
            statusNorm != 'planning' &&
            statusNorm != 'generated') {
          return false;
        }
        if (_activeFilter == 'draft' && statusNorm != 'draft') {
          return false;
        }
        if (_activeFilter == 'completed' && statusNorm != 'completed') {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return trip.title.toLowerCase().contains(q) ||
            trip.destination.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }



  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(tripsListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            return ref.refresh(tripsListProvider.future);
          },
          child: tripsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, stack) => _buildErrorState(err.toString()),
            data: (apiTrips) {
              final effectiveTrips = apiTrips.isNotEmpty ? apiTrips : mockTripsList;
              final filtered = _filterTrips(effectiveTrips);
              final featuredTrip = effectiveTrips.firstWhere(
                (t) {
                  final s = (t.status ?? '').toLowerCase();
                  return s == 'upcoming' || s == 'confirmed';
                },
                orElse: () => effectiveTrips.first,
              );
              final isFiltering = _activeFilter != 'all' || _searchQuery.isNotEmpty;

              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TripsHeader(
                      onCreateTrip: () => CreateTripSheet.show(context),
                    ),
                    const SizedBox(height: 24),
                    TripSearchFilter(
                      activeFilter: _activeFilter,
                      trips: effectiveTrips,
                      onFilterChanged: (f) => setState(() => _activeFilter = f),
                      onSearchChanged: (q) => setState(() => _searchQuery = q),
                    ),
                    const SizedBox(height: 32),
                    if (!isFiltering && effectiveTrips.isNotEmpty) ...[
                      FeaturedTripCard(trip: featuredTrip),
                      const SizedBox(height: 32),
                      QuickCreateSection(
                        onManualCreate: () => CreateTripSheet.show(context),
                      ),
                      const SizedBox(height: 32),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Danh sách hành trình', style: AppTextStyles.h2),
                        Text(
                          '${filtered.length} chuyến đi',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (filtered.isEmpty)
                      _buildEmptyState()
                    else
                      ...filtered.map((trip) => TripListCard(trip: trip)),
                    if (!isFiltering) _buildBottomRecommendation(),
                    const SizedBox(height: 120),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton.extended(
          heroTag: 'trips_create_itinerary_fab',
          onPressed: () => CreateTripSheet.show(context),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.auto_awesome, size: 20),
          label: const Text(
            'Tạo lịch trình',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Không thể tải danh sách chuyến đi', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => ref.invalidate(tripsListProvider),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Thử lại', style: TextStyle(color: Colors.white)),
            ),
          ],
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
          Text(
            'Thử tìm kiếm với từ khóa khác hoặc thay đổi bộ lọc.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _activeFilter = 'all';
                _searchQuery = '';
              });
            },
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
            ),
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
          Text(
            'Nhập bất kỳ ý tưởng hoặc thành phố nào bạn muốn ghé thăm, trợ lý Voice AI sẽ lên lịch trình ngay.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Switch to AI Assistant Tab (index 2)
                MainShell.switchToTab(context, 2);
              },
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: const Text('Lên lịch trình với Voice AI'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        ],
      ),
    );
  }
}
