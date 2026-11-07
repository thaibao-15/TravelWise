import 'package:flutter/material.dart';

/// A custom map pin (teardrop) marker widget that displays an optional order number or icon.
/// The bottom tip of the pin points precisely to the geographical coordinate.
class MapPinMarker extends StatelessWidget {
  final int order;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const MapPinMarker({
    super.key,
    required this.order,
    required this.color,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = isSelected ? 44.0 : 36.0;
    final height = isSelected ? 54.0 : 45.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // Shadow under the pin tip
            Positioned(
              bottom: 0,
              child: Container(
                width: isSelected ? 14 : 10,
                height: isSelected ? 6 : 4,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.all(Radius.elliptical(isSelected ? 14 : 10, isSelected ? 6 : 4)),
                ),
              ),
            ),
            // The Pin Body
            Positioned(
              top: 0,
              child: CustomPaint(
                size: Size(width, height - 3),
                painter: _PinPainter(
                  pinColor: isSelected ? const Color(0xFF0F172A) : color,
                  borderColor: Colors.white,
                  borderWidth: isSelected ? 2.5 : 2.0,
                  elevationColor: Colors.black.withValues(alpha: isSelected ? 0.35 : 0.22),
                ),
                child: SizedBox(
                  width: width,
                  height: width, // Pin head is circular
                  child: Center(
                    child: Container(
                      width: width * 0.62,
                      height: width * 0.62,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '$order',
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF0F172A) : color,
                            fontWeight: FontWeight.w800,
                            fontSize: isSelected ? 13 : 11.5,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  final Color pinColor;
  final Color borderColor;
  final double borderWidth;
  final Color elevationColor;

  _PinPainter({
    required this.pinColor,
    required this.borderColor,
    required this.borderWidth,
    required this.elevationColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w / 2.0;

    final path = Path();
    // Start at bottom tip
    final tipPoint = Offset(w / 2.0, h);

    // Angle from center down towards tangent
    path.moveTo(tipPoint.dx, tipPoint.dy);

    // Curve from tip to left side of circle
    path.cubicTo(
      w * 0.15,
      h * 0.65,
      0,
      radius * 1.3,
      0,
      radius,
    );

    // Arc around top of circle
    path.arcToPoint(
      Offset(w, radius),
      radius: Radius.circular(radius),
      clockwise: true,
    );

    // Curve from right side of circle back down to tip
    path.cubicTo(
      w,
      radius * 1.3,
      w * 0.85,
      h * 0.65,
      tipPoint.dx,
      tipPoint.dy,
    );

    path.close();

    // Draw shadow
    final shadowPaint = Paint()
      ..color = elevationColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.save();
    canvas.translate(0, 2);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    // Fill pin
    final fillPaint = Paint()
      ..color = pinColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Draw outer white border
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _PinPainter oldDelegate) {
    return oldDelegate.pinColor != pinColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.elevationColor != elevationColor;
  }
}
