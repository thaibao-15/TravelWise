import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants/colors.dart';
import '../../core/network/dio_client.dart';

/// Common network image widget with automatic CORS proxy resolution,
/// smooth loading shimmer/spinner, and elegant fallback placeholder on error.
class AppNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Alignment alignment;

  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.alignment = Alignment.center,
  });

  /// Resolves an image URL: automatically routes Wikimedia Commons / Special:FilePath
  /// through the FastAPI image proxy to bypass CORS restrictions on Flutter Web.
  static String resolveUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final trimmed = url.trim();

    // If already routed or a local file/asset/data uri, return as is
    if (trimmed.contains('/api/v1/media/image-proxy')) {
      return trimmed;
    }

    // Resolve Wikimedia Special:FilePath or any Wikimedia origin on web
    final isWikimedia = trimmed.contains('commons.wikimedia.org') ||
        trimmed.contains('upload.wikimedia.org') ||
        trimmed.contains('thumb.wikimedia.org');

    if (isWikimedia) {
      final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
      return '$base/api/v1/media/image-proxy?url=${Uri.encodeComponent(trimmed)}';
    }

    return trimmed;
  }

  /// Helper to get an [ImageProvider] for use in [DecorationImage] or [CircleAvatar]
  static ImageProvider provider(String? url, {String? fallbackAsset}) {
    final resolved = resolveUrl(url);
    if (resolved.isNotEmpty) {
      return NetworkImage(resolved);
    }
    return AssetImage(fallbackAsset ?? 'assets/images/placeholder.png');
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveUrl(imageUrl);

    Widget imageContent;

    if (resolved.isEmpty) {
      imageContent = _buildErrorPlaceholder();
    } else {
      imageContent = Image.network(
        resolved,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          if (placeholder != null) return placeholder!;

          return _buildLoadingPlaceholder(loadingProgress);
        },
        errorBuilder: (context, error, stackTrace) {
          if (errorWidget != null) return errorWidget!;
          return _buildErrorPlaceholder();
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageContent,
      );
    }

    return imageContent;
  }

  Widget _buildLoadingPlaceholder(ImageChunkEvent progress) {
    final total = progress.expectedTotalBytes;
    final loaded = progress.cumulativeBytesLoaded;
    final value = (total != null && total > 0) ? (loaded / total) : null;

    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: 2,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.landscape_rounded,
              color: Color(0xFF94A3B8),
              size: 26,
            ),
            SizedBox(height: 4),
            Text(
              'TravelWise',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

