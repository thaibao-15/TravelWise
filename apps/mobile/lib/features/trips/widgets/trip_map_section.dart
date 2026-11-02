import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/text_styles.dart';
import '../../map/presentation/screens/map_screen.dart';
import '../models/trip_model.dart';

class TripMapSection extends StatelessWidget {
  final Trip? trip;
  final int? selectedDayIndex;

  const TripMapSection({
    super.key,
    this.trip,
    this.selectedDayIndex,
  });

  @override
  Widget build(BuildContext context) {
    final validActivities = trip?.days
            .expand((d) => d.activities)
            .where((a) => a.hasValidCoordinates)
            .toList() ??
        [];

    final LatLng center = validActivities.isNotEmpty
        ? LatLng(validActivities.first.latitude!, validActivities.first.longitude!)
        : const LatLng(16.0544, 108.2022); // Default Da Nang

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Lộ trình bản đồ', style: AppTextStyles.h2),
            if (validActivities.isNotEmpty)
              Text(
                '${validActivities.length} điểm dừng thực',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 190,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 12.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/'
                        'World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                    maxNativeZoom: 19,
                  ),
                  if (validActivities.isNotEmpty)
                    MarkerLayer(
                      markers: validActivities.map((act) {
                        return Marker(
                          point: LatLng(act.latitude!, act.longitude!),
                          width: 28,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '${act.activityOrder ?? 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MapScreen(
                          trip: trip,
                          initialDayIndex: selectedDayIndex ?? 0,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(LucideIcons.map, size: 18),
                  label: const Text('Xem toàn bộ lộ trình'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    elevation: 5,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
