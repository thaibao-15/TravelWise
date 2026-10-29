import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../../home/models/category_model.dart';
import '../../home/models/place_model.dart';

class ExploreMapSection extends StatefulWidget {
  final List<Place> places;
  final List<Category> categories;
  final ValueChanged<Place> onPlaceTap;

  const ExploreMapSection({
    super.key,
    required this.places,
    required this.categories,
    required this.onPlaceTap,
  });

  @override
  State<ExploreMapSection> createState() => _ExploreMapSectionState();
}

class _ExploreMapSectionState extends State<ExploreMapSection> {
  Place? _selectedPlace;

  @override
  Widget build(BuildContext context) {
    final mappablePlaces = widget.places
        .where(
          (place) =>
              place.latitude != null &&
              place.longitude != null &&
              place.latitude! >= -90 &&
              place.latitude! <= 90 &&
              place.longitude! >= -180 &&
              place.longitude! <= 180 &&
              (place.latitude != 0 || place.longitude != 0),
        )
        .toList(growable: false);
    final mapPoints = mappablePlaces
        .map((place) => LatLng(place.latitude!, place.longitude!))
        .toList(growable: false);
    final initialCenter = mapPoints.isNotEmpty
        ? mapPoints.first
        : const LatLng(16.0544, 108.2022);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Khám phá trên bản đồ', style: AppTextStyles.h2),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: SizedBox(
              height: 340,
              child: Stack(
                children: [
                  FlutterMap(
                    key: ValueKey(
                      mappablePlaces.map((place) => place.id).join(','),
                    ),
                    options: MapOptions(
                      initialCenter: initialCenter,
                      initialZoom: mapPoints.length > 1 ? 12 : 14,
                      initialCameraFit: _cameraFit(mapPoints),
                      minZoom: 3,
                      maxZoom: 19,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onTap: (_, _) {
                        if (_selectedPlace != null) {
                          setState(() => _selectedPlace = null);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://server.arcgisonline.com/ArcGIS/rest/services/'
                            'World_Street_Map/MapServer/tile/{z}/{y}/{x}',
                        maxNativeZoom: 19,
                      ),
                      MarkerLayer(
                        markers: mappablePlaces
                            .map((place) {
                              final isSelected = _selectedPlace?.id == place.id;
                              return Marker(
                                point: LatLng(
                                  place.latitude!,
                                  place.longitude!,
                                ),
                                width: isSelected ? 52 : 44,
                                height: isSelected ? 56 : 48,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedPlace = place);
                                  },
                                  child: Icon(
                                    Icons.location_on,
                                    color: _colorForCategory(place.categoryId),
                                    size: isSelected ? 48 : 40,
                                    shadows: [
                                      Shadow(
                                        color: Colors.white,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.all(3),
                          color: Colors.white.withValues(alpha: 0.9),
                          child: const Text(
                            '© Tiles Esri',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedPlace != null)
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: _buildPlacePreview(_selectedPlace!),
                    )
                  else if (mappablePlaces.isEmpty)
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: Text(
                          widget.places.isEmpty
                              ? 'Không tìm thấy địa điểm trong danh mục này.'
                              : 'Các địa điểm này chưa có tọa độ để hiển thị trên bản đồ.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForCategory(int? categoryId) {
    if (categoryId == null) return AppColors.textSecondary;
    final categoryIndex = widget.categories.indexWhere(
      (category) => category.id == categoryId,
    );
    if (categoryIndex < 0) return AppColors.textSecondary;
    return HSVColor.fromAHSV(
      1,
      (categoryIndex * 137.508) % 360,
      0.78,
      0.82,
    ).toColor();
  }

  Widget _buildPlacePreview(Place place) {
    String? categoryName;
    for (final category in widget.categories) {
      if (category.id == place.categoryId) {
        categoryName = category.name;
        break;
      }
    }
    final subtitle = place.address?.trim().isNotEmpty == true
        ? place.address!.trim()
        : place.description.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onPlaceTap(place),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: place.imageUrl.isNotEmpty
                    ? Image.network(
                        place.imageUrl,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: kIsWeb
                            ? WebHtmlElementStrategy.prefer
                            : WebHtmlElementStrategy.never,
                        errorBuilder: (_, _, _) => _previewPlaceholder(),
                      )
                    : _previewPlaceholder(),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (categoryName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: _colorForCategory(place.categoryId),
                        ),
                      ),
                    ],
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption,
                      ),
                    ],
                    if (place.rating > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: AppColors.warning,
                            size: 16,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            place.rating.toStringAsFixed(1),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (place.reviewCount > 0)
                            Text(
                              ' · ${place.reviewCount} đánh giá',
                              style: AppTextStyles.caption,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Đóng',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _selectedPlace = null),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewPlaceholder() {
    return Container(
      width: 68,
      height: 68,
      color: AppColors.surfaceContainerHigh,
      alignment: Alignment.center,
      child: const Icon(Icons.location_on_outlined, color: AppColors.primary),
    );
  }

  CameraFit? _cameraFit(List<LatLng> points) {
    if (points.length < 2) return null;

    var minLatitude = points.first.latitude;
    var maxLatitude = points.first.latitude;
    var minLongitude = points.first.longitude;
    var maxLongitude = points.first.longitude;
    for (final point in points.skip(1)) {
      minLatitude = minLatitude < point.latitude ? minLatitude : point.latitude;
      maxLatitude = maxLatitude > point.latitude ? maxLatitude : point.latitude;
      minLongitude = minLongitude < point.longitude
          ? minLongitude
          : point.longitude;
      maxLongitude = maxLongitude > point.longitude
          ? maxLongitude
          : point.longitude;
    }

    if (minLatitude == maxLatitude) {
      minLatitude -= 0.005;
      maxLatitude += 0.005;
    }
    if (minLongitude == maxLongitude) {
      minLongitude -= 0.005;
      maxLongitude += 0.005;
    }

    return CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(minLatitude, minLongitude),
        LatLng(maxLatitude, maxLongitude),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
    );
  }
}
