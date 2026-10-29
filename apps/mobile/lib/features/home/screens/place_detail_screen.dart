import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/spacing.dart';
import '../../../core/constants/text_styles.dart';
import '../models/place_model.dart';
import '../providers/home_provider.dart';

class PlaceDetailScreen extends ConsumerWidget {
  final int placeId;

  const PlaceDetailScreen({super.key, required this.placeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(placeDetailProvider(placeId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: place.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: 'Không thể tải thông tin địa điểm: $error',
          onRetry: () => ref.invalidate(placeDetailProvider(placeId)),
        ),
        data: (value) => _PlaceDetailContent(place: value),
      ),
    );
  }
}

class _PlaceDetailContent extends StatelessWidget {
  final Place place;

  const _PlaceDetailContent({required this.place});

  @override
  Widget build(BuildContext context) {
    final imageUrls = [
      place.imageUrl,
      if (place.secondaryImageUrl != null) place.secondaryImageUrl!,
    ].where((url) => url.isNotEmpty).toList();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 290,
          pinned: true,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          flexibleSpace: FlexibleSpaceBar(
            background: _ImageGallery(imageUrls: imageUrls),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              120,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(place.name, style: AppTextStyles.h2)),
                    const SizedBox(width: AppSpacing.sm),
                    _Rating(rating: place.rating, reviews: place.reviewCount),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (place.address?.trim().isNotEmpty == true)
                  _InfoTile(icon: LucideIcons.mapPin, text: place.address!),
                if (place.latitude != null && place.longitude != null)
                  _InfoTile(
                    icon: LucideIcons.navigation,
                    text:
                        '${place.latitude!.toStringAsFixed(5)}, ${place.longitude!.toStringAsFixed(5)}',
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text('Giới thiệu', style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  place.description.isEmpty
                      ? 'Chưa có thông tin giới thiệu cho địa điểm này.'
                      : place.description,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(LucideIcons.map),
                    label: const Text('Xem trên bản đồ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageGallery extends StatefulWidget {
  final List<String> imageUrls;

  const _ImageGallery({required this.imageUrls});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) {
      return _placeholder();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: widget.imageUrls.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemBuilder: (_, index) => Image.network(
            widget.imageUrls[index],
            fit: BoxFit.cover,
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  _placeholder(),
                  Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes == null
                          ? null
                          : progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              );
            },
            errorBuilder: (_, _, _) => _placeholder(),
          ),
        ),
        if (widget.imageUrls.length > 1)
          Positioned(
            bottom: AppSpacing.md,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.imageUrls.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentIndex == index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentIndex == index
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceContainerHigh,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_outlined,
        color: AppColors.textSecondary,
        size: 48,
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  final double rating;
  final int reviews;

  const _Rating({required this.rating, required this.reviews});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            const Icon(Icons.star, color: AppColors.warning, size: 18),
            const SizedBox(width: 4),
            Text(
              rating.toStringAsFixed(1),
              style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Text(
          '$reviews đánh giá',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoTile({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
